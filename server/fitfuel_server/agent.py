"""AI 对话代理：LLM（OpenAI 兼容接口）+ fitfuel 工具集。

用户说"今天体重77.9体脂21.4"、"午饭吃了150g鸡胸肉200g米饭"，LLM 通过
工具调用完成记录/查询；工具直接复用 fitfuel 包的领域函数与食物消歧策略。
"""

from __future__ import annotations

import json
import sqlite3
from datetime import date as date_mod
from typing import Any, Callable

import httpx

from fitfuel.body import (
    add_goal,
    add_measurements,
    add_metric,
    get_profile,
    list_goals,
    list_measurements,
    list_metrics,
    set_profile,
)
from fitfuel.exercises import exercise_detail, search_exercises
from fitfuel.nutrition import (
    add_meal,
    compute_targets,
    day_summary,
    food_detail,
    list_meals,
    search_foods,
)
from fitfuel.report import weekly_report
from fitfuel.strength import add_log, list_logs, pr_table
from fitfuel.util import FitFuelError
from fitfuel.workouts import add_workout, list_workouts

from .config import llm_config

MAX_TOOL_ROUNDS = 6

SYSTEM_PROMPT = """你是 FitFuel，用户的私人健身与饮食记录助手。今天是 {today}。

你的能力通过工具实现，用户的所有记录/查询请求都应通过工具完成，不要编造数据：
- 记录：record_weight / record_measurements / record_meal / record_strength / record_workout / set_goal / update_profile
- 查询：get_today / get_status / get_targets / get_report / list_goals / query_food / search_exercises / list_workouts / list_strength

行为准则：
1. 记录类请求：解析出数值后直接调用工具，不需要反复确认；工具返回错误时把原因和 hints 转告用户。
2. 食物匹配有歧义时（query_food 返回 ambiguous），把候选列给用户让 TA 选，不要擅自决定。
3. 用户口述含糊（"吃了点米饭"）时按常见份量估算并在回复中注明估算假设。
4. 查询类请求优先用 get_today / get_status / get_report。
5. 回复用简体中文，简洁：先结论/数字，再一句要点；不要堆砌建议，不做医疗诊断。
6. 单位：体重 kg，围度 cm，食物 g，热量 kcal。
"""

# ---------------------------------------------------------------- 工具实现


def _today() -> str:
    return date_mod.today().isoformat()


def make_tool_executor(con: sqlite3.Connection) -> Callable[[str, dict], Any]:
    """把工具名映射到 fitfuel 领域函数；返回 executor(name, args)。"""

    def executor(name: str, args: dict) -> Any:
        d = args.get("date") or _today()
        if name == "record_weight":
            return add_metric(
                con, d,
                weight_kg=args.get("weight"),
                body_fat_pct=args.get("body_fat"),
                skeletal_muscle_kg=args.get("muscle"),
            )
        if name == "record_measurements":
            values = args.get("values") or {}
            return add_measurements(con, d, values)
        if name == "record_meal":
            return add_meal(
                con, args.get("meal_type") or "lunch",
                item_specs=[f"{i['query']}:{i['grams']}" for i in args.get("items", [])],
                custom_specs=[
                    "{name}:{grams}:{kcal}:{protein}:{fat}:{carbs}".format(**c)
                    for c in args.get("custom", [])
                ],
                date_str=d, note=args.get("note"),
            )
        if name == "record_strength":
            return add_log(
                con, args["lift"], args["weight"], args["reps"],
                date_str=d, rpe=args.get("rpe"),
            )
        if name == "record_workout":
            sets = [
                f"{s['name']} {s['weight']} {s['reps']}" +
                (f" @{s['rpe']}" if s.get("rpe") else "")
                for s in args.get("sets", [])
            ]
            return add_workout(con, sets, name=args.get("name"), date_str=d)
        if name == "set_goal":
            return add_goal(con, args["kind"], args["target"],
                            target_date=args.get("date"))
        if name == "update_profile":
            return {"profile": set_profile(
                con,
                sex=args.get("sex"), birth_date=args.get("birth"),
                height_cm=args.get("height"), activity_level=args.get("activity"),
                goal_type=args.get("goal"),
            )}
        if name == "get_today":
            return day_summary(con, d)
        if name == "get_status":
            from fitfuel.report import status as build_status
            return build_status(con)
        if name == "get_targets":
            return compute_targets(con)
        if name == "get_report":
            return weekly_report(con, days=int(args.get("days") or 7))
        if name == "list_goals":
            return {"goals": list_goals(con)}
        if name == "query_food":
            q = args["query"]
            hits = search_foods(con, q, limit=5)
            top = hits[0] if hits else None
            ambiguous = not (
                top and (top["match_score"] >= 850
                         and top["match_score"] - (hits[1]["match_score"] if len(hits) > 1 else 0) >= 15
                         or top["match_score"] >= 700
                         and top["match_score"] - (hits[1]["match_score"] if len(hits) > 1 else 0) >= 40)
            )
            if ambiguous:
                near = [m for m in hits if top and top["match_score"] - m["match_score"] <= 2]
                reps = [m for m in near if "代表值" in (m["name"] or "")]
                if len(reps) == 1:
                    return {"status": "resolved", "food": reps[0]}
                return {"status": "ambiguous", "candidates": hits[:5]}
            return {"status": "resolved", "food": food_detail(con, q)}
        if name == "search_exercises":
            return {"exercises": search_exercises(con, args["query"], limit=8)}
        if name == "exercise_detail":
            return {"exercise": exercise_detail(con, args["query"])}
        if name == "list_workouts":
            return {"workouts": list_workouts(con, days=int(args.get("days") or 30), limit=10)}
        if name == "list_strength":
            return {"logs": list_logs(con, days=int(args.get("days") or 90))}
        if name == "list_measurements":
            return {"measurements": list_measurements(con, days=int(args.get("days") or 180))}
        if name == "list_meals":
            return {"meals": list_meals(con, days=int(args.get("days") or 7))}
        raise ValueError(f"unknown tool {name}")

    return executor


# ---------------------------------------------------------------- 工具 Schema

TOOLS_SPEC = [
    {"type": "function", "function": {
        "name": "record_weight",
        "description": "记录体重/体脂率/骨骼肌量（至少一项）",
        "parameters": {"type": "object", "properties": {
            "weight": {"type": "number"}, "body_fat": {"type": "number"},
            "muscle": {"type": "number"}, "date": {"type": "string"}},
            "description": "date 缺省为今天"}},
    },
    {"type": "function", "function": {
        "name": "record_measurements",
        "description": "记录身体围度 cm。values 键：chest胸/waist腰/hip臀/neck颈/shoulder肩/"
                       "arm上臂/forearm前臂/thigh大腿/calf小腿/wrist腕",
        "parameters": {"type": "object", "properties": {
            "values": {"type": "object"},
            "date": {"type": "string"}},
            "required": ["values"]}},
    },
    {"type": "function", "function": {
        "name": "record_meal",
        "description": "记录一餐。items 为食物库条目（先 query_food 确认名称与编码再填）；"
                       "custom 为食物库没有的包装/自制食品",
        "parameters": {"type": "object", "properties": {
            "meal_type": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
            "items": {"type": "array", "items": {"type": "object", "properties": {
                "query": {"type": "string"}, "grams": {"type": "number"}},
                "required": ["query", "grams"]}},
            "custom": {"type": "array", "items": {"type": "object", "properties": {
                "name": {"type": "string"}, "grams": {"type": "number"},
                "kcal": {"type": "number"}, "protein": {"type": "number"},
                "fat": {"type": "number"}, "carbs": {"type": "number"}},
                "required": ["name", "grams", "kcal", "protein", "fat", "carbs"]}},
            "date": {"type": "string"}, "note": {"type": "string"}},
            "required": ["meal_type"]}},
    },
    {"type": "function", "function": {
        "name": "record_strength",
        "description": "记录力量数据组并估算 1RM。lift：bench/squat/deadlift/ohp/row 或其他动作名",
        "parameters": {"type": "object", "properties": {
            "lift": {"type": "string"}, "weight": {"type": "number"},
            "reps": {"type": "integer"}, "rpe": {"type": "number"},
            "date": {"type": "string"}},
            "required": ["lift", "weight", "reps"]}},
    },
    {"type": "function", "function": {
        "name": "record_workout",
        "description": "记录一次完整训练（多组）。sets 每项含动作名/重量/次数/可选RPE",
        "parameters": {"type": "object", "properties": {
            "name": {"type": "string"},
            "sets": {"type": "array", "items": {"type": "object", "properties": {
                "name": {"type": "string"}, "weight": {"type": "number"},
                "reps": {"type": "integer"}, "rpe": {"type": "number"}},
                "required": ["name", "weight", "reps"]}},
            "date": {"type": "string"}, "note": {"type": "string"}},
            "required": ["sets"]}},
    },
    {"type": "function", "function": {
        "name": "set_goal",
        "description": "设置目标。kind：weight/body_fat/muscle/measure:waist 等/strength:bench 等",
        "parameters": {"type": "object", "properties": {
            "kind": {"type": "string"}, "target": {"type": "number"},
            "date": {"type": "string"}},
            "required": ["kind", "target"]}},
    },
    {"type": "function", "function": {
        "name": "update_profile",
        "description": "更新个人档案：性别/生日/身高/活动水平/目标类型",
        "parameters": {"type": "object", "properties": {
            "sex": {"type": "string"}, "birth": {"type": "string"},
            "height": {"type": "number"},
            "activity": {"type": "string", "enum": ["sedentary", "light", "moderate", "active", "very_active"]},
            "goal": {"type": "string", "enum": ["cut", "maintain", "bulk"]}}}},
    },
    {"type": "function", "function": {
        "name": "get_today", "description": "获取某天（默认今天）的饮食汇总：各餐、总量、目标、剩余",
        "parameters": {"type": "object", "properties": {"date": {"type": "string"}}}},
    },
    {"type": "function", "function": {
        "name": "get_status", "description": "当前状态总览：档案、最新体重/围度、今日饮食、目标进度、PR、最近训练"}},
    {"type": "function", "function": {
        "name": "get_targets", "description": "计算每日热量与宏量目标（BMR/TDEE）"}},
    {"type": "function", "function": {
        "name": "get_report", "description": "近 N 天复盘：饮食均值、体重/围度变化、训练量、新 PR",
        "parameters": {"type": "object", "properties": {"days": {"type": "integer"}}}},
    },
    {"type": "function", "function": {
        "name": "list_goals", "description": "查看目标与进度"}},
    {"type": "function", "function": {
        "name": "query_food",
        "description": "查询食物营养（每100g）。可能返回 resolved 或 ambiguous（candidates 供用户选择）",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}},
                       "required": ["query"]}},
    },
    {"type": "function", "function": {
        "name": "search_exercises", "description": "搜索动作库（中英文/肌群/器械）",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}},
                       "required": ["query"]}},
    },
    {"type": "function", "function": {
        "name": "exercise_detail", "description": "动作详情：步骤/动画GIF路径/肌群",
        "parameters": {"type": "object", "properties": {"query": {"type": "string"}},
                       "required": ["query"]}},
    },
    {"type": "function", "function": {
        "name": "list_workouts", "description": "最近训练列表",
        "parameters": {"type": "object", "properties": {"days": {"type": "integer"}}}},
    },
    {"type": "function", "function": {
        "name": "list_strength", "description": "最近力量记录列表",
        "parameters": {"type": "object", "properties": {"days": {"type": "integer"}}}},
    },
    {"type": "function", "function": {
        "name": "list_measurements", "description": "最近围度记录",
        "parameters": {"type": "object", "properties": {"days": {"type": "integer"}}}},
    },
    {"type": "function", "function": {
        "name": "list_meals", "description": "最近饮食记录",
        "parameters": {"type": "object", "properties": {"days": {"type": "integer"}}}},
    },
]


# ---------------------------------------------------------------- LLM 调用

def call_llm(cfg: dict, messages: list[dict]) -> dict:
    """OpenAI 兼容 /chat/completions。可被测试替换（monkeypatch）。"""
    r = httpx.post(
        f"{cfg['base_url'].rstrip('/')}/chat/completions",
        headers={"Authorization": f"Bearer {cfg['api_key']}"},
        json={
            "model": cfg["model"],
            "messages": messages,
            "tools": TOOLS_SPEC,
            "temperature": 0.3,
        },
        timeout=90,
    )
    if r.status_code != 200:
        raise RuntimeError(f"LLM HTTP {r.status_code}: {r.text[:200]}")
    return r.json()["choices"][0]["message"]


def run_agent(con: sqlite3.Connection, message: str,
              history: list[dict] | None = None,
              llm_call: Callable[[dict, list[dict]], dict] | None = None) -> dict:
    """一轮对话：LLM + 工具循环，返回最终回复与已执行动作。"""
    cfg = llm_config()
    if not cfg.get("configured"):
        return {
            "reply": "还没有配置 AI 模型。请在服务端设置 server/data/llm_config.json"
                     "（base_url / api_key / model，OpenAI 兼容接口），或设置环境变量 "
                     "FITFUEL_LLM_BASE_URL / FITFUEL_LLM_API_KEY / FITFUEL_LLM_MODEL 后重启服务。",
            "actions": [],
        }
    call = llm_call or call_llm
    executor = make_tool_executor(con)

    profile = get_profile(con)
    system = SYSTEM_PROMPT.format(today=_today())
    messages: list[dict] = [{"role": "system", "content": system}]
    for h in (history or [])[-8:]:
        if h.get("role") in ("user", "assistant") and h.get("content"):
            messages.append({"role": h["role"], "content": h["content"]})
    messages.append({"role": "user", "content": message})

    actions: list[dict] = []
    reply = ""
    for _ in range(MAX_TOOL_ROUNDS):
        msg = call(cfg, messages)
        tool_calls = msg.get("tool_calls") or []
        if not tool_calls:
            reply = msg.get("content") or ""
            break
        messages.append({
            "role": "assistant",
            "content": msg.get("content") or "",
            "tool_calls": tool_calls,
        })
        for tc in tool_calls:
            fn = tc.get("function", {})
            name = fn.get("name", "")
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            try:
                result = executor(name, args)
                actions.append({"tool": name, "args": args, "ok": True})
            except FitFuelError as exc:
                result = {"ok": False, "error": exc.message, "hints": exc.hints}
                actions.append({"tool": name, "args": args, "ok": False,
                                "error": exc.message})
            except (KeyError, ValueError, TypeError) as exc:
                result = {"ok": False, "error": f"参数问题：{exc}"}
                actions.append({"tool": name, "args": args, "ok": False,
                                "error": str(exc)})
            messages.append({
                "role": "tool",
                "tool_call_id": tc.get("id", ""),
                "content": json.dumps(result, ensure_ascii=False, default=str)[:4000],
            })
    else:
        reply = "这个请求有点复杂，我处理到一半超时了，请拆成几句话再说一次。"

    return {"reply": reply or "（无回复）", "actions": actions}
