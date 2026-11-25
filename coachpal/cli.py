"""coachpal 命令行入口。"""

from __future__ import annotations

import argparse
import webbrowser
from pathlib import Path
from typing import Any

from . import __version__
from .body import (
    SITES,
    add_goal,
    add_measurements,
    add_metric,
    get_profile,
    latest_metric,
    latest_measurements,
    list_goals,
    list_measurements,
    list_metrics,
    set_profile,
)
from .dashboard import generate_dashboard
from .db import connect
from .exercises import exercise_detail, search_exercises
from .nutrition import (
    add_meal,
    compute_targets,
    day_summary,
    delete_meal,
    food_detail,
    list_meals,
    search_foods,
    seed_foods,
)
from .paths import dashboard_path, db_path, default_sources
from .report import status as build_status
from .report import weekly_report
from .strength import (
    add_log,
    estimate_1rm,
    list_logs,
    percentage_table,
    percentages_for_lift,
    pr_table,
)
from .util import (
    ACTIVITY_LABELS,
    CoachPalError,
    MEAL_LABELS,
    dumps_zh,
    normalize_activity,
    normalize_goal,
    print_table,
    r1,
)
from .workouts import add_workout, delete_workout, list_workouts, workout_detail


# ---------------------------------------------------------------- 人类可读输出


def kv(label: str, value: Any, unit: str = "") -> str:
    if value is None or value == "":
        value = "—"
    return f"{label}: {value}{(' ' + unit) if unit else ''}"


def show_profile(profile: dict) -> None:
    print(kv("性别", {"male": "男", "female": "女", "other": "其他"}.get(profile.get("sex"), profile.get("sex"))))
    print(kv("年龄", profile.get("age"), "岁"))
    print(kv("身高", profile.get("height_cm"), "cm"))
    print(kv("活动水平", ACTIVITY_LABELS.get(profile.get("activity_level"), profile.get("activity_level"))))
    print(kv("目标", {"cut": "减脂", "maintain": "维持", "bulk": "增肌"}.get(profile.get("goal_type"), profile.get("goal_type"))))
    print(kv("当前体重", profile.get("latest_weight_kg"), "kg"))
    print(kv("BMI", profile.get("bmi")))


def show_day(data: dict) -> None:
    print(f"{data['date']} 饮食")
    if not data["meals"]:
        print("  （今天还没有记录）")
    for meal in data["meals"]:
        print(f"\n[{meal['meal_label']}] 合计 {meal['totals']['kcal']} kcal · P{meal['totals']['protein']} F{meal['totals']['fat']} C{meal['totals']['carbs']}")
        for item in meal["items"]:
            print(
                f"  - {item['food_name']} {item['grams']}g · {item['kcal']} kcal "
                f"(P{item['protein']} F{item['fat']} C{item['carbs']})"
            )
    totals = data["totals"]
    print(f"\n总计: {totals['kcal']} kcal · 蛋白 {totals['protein']}g · 脂肪 {totals['fat']}g · 碳水 {totals['carbs']}g · 纤维 {totals['fiber']}g")
    if data.get("targets"):
        t = data["targets"]
        rem = data.get("remaining") or {}
        print(f"目标: {t['kcal']} kcal · 蛋白 {t['protein']}g · 脂肪 {t['fat']}g · 碳水 {t['carbs']}g")
        print(f"剩余: {rem.get('kcal')} kcal · 蛋白 {rem.get('protein')}g · 脂肪 {rem.get('fat')}g · 碳水 {rem.get('carbs')}g")
    elif data.get("target_note"):
        print(f"目标: 未计算（{data['target_note']}）")


def show_targets(data: dict) -> None:
    if not data.get("available"):
        print("无法计算目标：" + data.get("reason", "资料不足"))
        return
    t = data["targets"]
    print(kv("目标类型", data["goal_label"]))
    print(kv("BMR", data["bmr"], "kcal"))
    print(kv("TDEE", data["tdee"], "kcal"))
    print(kv("每日热量", t["kcal"], "kcal"))
    print(kv("蛋白质", t["protein"], "g"))
    print(kv("脂肪", t["fat"], "g"))
    print(kv("碳水", t["carbs"], "g"))
    print(kv("纤维", t["fiber"], "g"))
    for note in data.get("assumptions") or []:
        print("注意: " + note)
    print(f"\n算法: {data['method']}")


def show_meal(meal: dict) -> None:
    print(f"#{meal['id']} {meal['date']} {meal['meal_label']}")
    print_table(
        ["食物", "克数", "kcal", "蛋白", "脂肪", "碳水"],
        [
            [i["food_name"], i["grams"], i["kcal"], i["protein"], i["fat"], i["carbs"]]
            for i in meal["items"]
        ],
    )
    t = meal["totals"]
    print(f"合计: {t['kcal']} kcal · 蛋白 {t['protein']}g · 脂肪 {t['fat']}g · 碳水 {t['carbs']}g")


def show_workout(w: dict) -> None:
    print(f"#{w['id']} {w['date']} {w['name'] or '未命名训练'}")
    print_table(
        ["动作", "组", "重量", "次数", "RPE", "训练量"],
        [
            [s["exercise_name"], s["set_no"], s["weight_kg"], s["reps"], s["rpe"] or "—", s["volume_kg"]]
            for s in w["sets"]
        ],
    )
    print(f"动作 {w['exercise_count']} 个 · {w['set_count']} 组 · 总训练量 {w['volume_kg']} kg")
    for warning in w.get("warnings") or []:
        print("注意: " + warning)


def human_output(args, result: dict) -> None:
    cmd = args.command
    action = getattr(args, "action", None)

    if cmd == "init":
        print(f"数据库已就绪：{result['db']}")
        print(f"食物 {result['foods']} 条 · 动作 {result['exercises']} 条 · 记录 {result['records']} 条")
        if result["foods"] == 0 or result["exercises"] == 0:
            print("下一步：python3 -m coachpal seed")
        return
    if cmd == "seed":
        if result.get("foods"):
            f = result["foods"]
            print(f"食物库：{f['foods_total']} 条（{f['with_gi']} 条有 GI），来源 {f['food_dir']}")
        if result.get("exercises"):
            e = result["exercises"]
            print(f"动作库：{e['exercises_total']} 个动作，其中 {e['with_chinese_name']} 个有中文名")
        for warning in result.get("warnings") or []:
            print("注意: " + warning)
        return
    if cmd == "profile":
        if action == "set":
            print("个人档案已更新")
        show_profile(result["profile"])
        return
    if cmd == "weight":
        if action == "add":
            m = result["metric"]
            print(f"已记录 {m['date']}：体重 {m['weight_kg']} kg" + (f" · 体脂 {m['body_fat_pct']}%" if m.get("body_fat_pct") is not None else "") + (f" · 骨骼肌 {m['skeletal_muscle_kg']} kg" if m.get("skeletal_muscle_kg") is not None else ""))
            if m.get("bmi"):
                print(f"BMI: {m['bmi']}")
            return
        rows = result["metrics"]
        print_table(
            ["日期", "体重", "体脂%", "骨骼肌", "BMI"],
            [[m["date"], m["weight_kg"], m["body_fat_pct"], m["skeletal_muscle_kg"], m["bmi"]] for m in rows],
        )
        return
    if cmd == "measure":
        if action == "add":
            print(f"已记录 {result['date']} 围度")
            print_table(["部位", "数值 (cm)"], [[m["label"], m["value_cm"]] for m in result["measurements"]])
            return
        print_table(["日期", "部位", "数值 (cm)"], [[m["date"], m["label"], m["value_cm"]] for m in result["measurements"]])
        return
    if cmd == "goal":
        if action == "set":
            goal = result["goal"]
            print(f"已设置目标：{goal['label']} → {goal['target_value']} {goal['unit']}")
            if goal.get("baseline_value") is not None:
                print(f"起点：{goal['baseline_value']} {goal['unit']} · 当前：{goal.get('current_value')} {goal['unit']}")
            return
        goals = result["goals"]
        print_table(
            ["#", "目标", "当前", "目标值", "进度", "目标日期", "状态"],
            [
                [
                    g["id"],
                    g["label"],
                    g["current_value"],
                    f"{g['target_value']} {g['unit']}",
                    f"{round((g.get('progress') or 0) * 100)}%" if g.get("progress") is not None else "—",
                    g.get("target_date") or "—",
                    "达成" if g.get("achieved") else "进行中",
                ]
                for g in goals
            ],
        )
        return
    if cmd == "strength":
        if action == "add":
            log = result["log"]
            print(
                f"已记录 {log['date']} {log['lift_label']} {log['weight_kg']}kg × {log['reps']}"
                f" → 估算 1RM {log['estimated_1rm']} kg"
            )
            if log.get("is_pr"):
                print("新 PR！")
            if log.get("high_rep_warning"):
                print("注意: 次数超过 12，1RM 估算误差较大")
            return
        if action == "list":
            print_table(
                ["日期", "动作", "重量", "次数", "RPE", "估算 1RM"],
                [[l["date"], l["lift_label"], l["weight_kg"], l["reps"], l["rpe"] or "—", l["estimated_1rm"]] for l in result["logs"]],
            )
            return
        if action == "pr":
            print_table(
                ["动作", "估算 1RM", "来源", "日期"],
                [[p["label"], p["estimated_1rm"], f"{p['weight_kg']}kg × {p['reps']}", p["date"]] for p in result["prs"]],
            )
            return
        if action == "calc":
            print(f"估算 1RM: {result['estimated_1rm']} kg（{result['weight_kg']} kg × {result['reps']}）")
            print_table(
                ["%1RM", "重量", "参考次数"],
                [[f"{row['pct']}%", row["weight_kg"], row["reps_guide"]] for row in result["table"]],
            )
            return
        if action == "percentages":
            print(f"{result['label']} 估算 1RM：{result['estimated_1rm']} kg（{result['source']['weight_kg']}kg × {result['source']['reps']}，{result['source']['date']}）")
            print_table(
                ["%1RM", "重量", "参考次数"],
                [[f"{row['pct']}%", row["weight_kg"], row["reps_guide"]] for row in result["table"]],
            )
            return
    if cmd == "food":
        if action == "search":
            print_table(
                ["编码", "名称", "kcal/100g", "蛋白", "脂肪", "碳水", "GI"],
                [[m["code"] or m["id"], m["name"], m["kcal_per_100g"], m["protein_g"], m["fat_g"], m["carbs_g"], m["gi"]] for m in result["foods"]],
            )
            return
        f = result["food"]
        print(f"{f['name']}" + (f"（{f['name_en']}）" if f.get("name_en") else ""))
        print(kv("编码", f.get("code")))
        print(kv("分类", f.get("category")))
        print(kv("热量", f.get("kcal"), "kcal/100g"))
        print(kv("蛋白质", f.get("protein"), "g/100g"))
        print(kv("脂肪", f.get("fat"), "g/100g"))
        print(kv("碳水", f.get("carbs"), "g/100g"))
        print(kv("膳食纤维", f.get("fiber"), "g/100g"))
        print(kv("钠", f.get("sodium_mg"), "mg/100g"))
        print(kv("GI", f.get("gi")))
        return
    if cmd == "exercise":
        if action == "search":
            print_table(
                ["名称", "中文名", "器械", "难度", "主要肌群", "分类"],
                [[m["name"], m["name_zh"] or "—", m["equipment_zh"] or "—", m["level_zh"] or "—", "、".join(m["primary_muscles_zh"]), m["category_zh"]] for m in result["exercises"]],
            )
            return
        e = result["exercise"]
        print(f"{e['name']}（{e['name_zh'] or '无中文名'}）")
        print(kv("动作 ID", e["ext_id"]))
        print(kv("器械", e["equipment_zh"]))
        print(kv("难度", e["level_zh"]))
        print(kv("类型", e["category_zh"]))
        print(kv("主要肌群", "、".join(e["primary_muscles_zh"])))
        print(kv("辅助肌群", "、".join(e["secondary_muscles_zh"]) or "—"))
        if e.get("images"):
            print("示意图:")
            style_label = {"gif": "动画GIF", "thumb": "缩略图", "photo": "照片", "cartoon": "卡通"}
            for img in e["images"]:
                if isinstance(img, dict):
                    path = img["path"]
                    style = style_label.get(img.get("style"), "图片")
                    exists = "✓" if Path(path).exists() else "✗"
                    print(f"  [{exists}] {path}（{style}）")
                else:
                    print(f"  [✗] {img}")
        if e.get("steps_zh"):
            print("\n步骤（中文）:")
            for i, step in enumerate(e["steps_zh"], 1):
                print(f"  {i}. {step}")
        print("\n步骤:")
        for i, step in enumerate(e["instructions"], 1):
            print(f"  {i}. {step}")
        return
    if cmd == "meal":
        if action == "add":
            show_meal(result["meal"])
            return
        if action == "delete":
            print(f"已删除饮食记录 #{result['deleted']}（{result['date']} {MEAL_LABELS.get(result['meal_type'], result['meal_type'])}）")
            return
        meals = result["meals"]
        if not meals:
            print("（没有饮食记录）")
            return
        for meal in meals:
            show_meal(meal)
            print()
        return
    if cmd == "day":
        show_day(result)
        return
    if cmd == "targets":
        show_targets(result["targets"])
        return
    if cmd == "workout":
        if action == "add":
            show_workout(result["workout"])
            return
        if action == "show":
            show_workout(result["workout"])
            return
        if action == "delete":
            print(f"已删除训练记录 #{result['deleted']}")
            return
        workouts = result["workouts"]
        if not workouts:
            print("（没有训练记录）")
            return
        print_table(
            ["#", "日期", "训练", "动作", "组数", "训练量"],
            [[w["id"], w["date"], w["name"] or "—", w["exercise_count"], w["set_count"], w["volume_kg"]] for w in workouts],
        )
        return
    if cmd == "status":
        p = result["profile"]
        print("== 个人 ==")
        print(kv("身高", p.get("height_cm"), "cm"))
        print(kv("BMI", p.get("bmi")))
        print(kv("目标", {"cut": "减脂", "maintain": "维持", "bulk": "增肌"}.get(p.get("goal_type"), p.get("goal_type"))))
        latest = result.get("latest_weight")
        if latest:
            print(kv("最新体重", latest.get("weight_kg"), "kg") + (f"（{latest['date']}）"))
        if result.get("latest_measurements"):
            print("最新围度: " + " · ".join(f"{m['label']} {m['value_cm']}cm" for m in result["latest_measurements"]))
        print("\n== 今日饮食 ==")
        t = result["today"]["totals"]
        print(f"{t['kcal']} kcal · 蛋白 {t['protein']}g · 脂肪 {t['fat']}g · 碳水 {t['carbs']}g")
        if result["today"].get("targets"):
            tt = result["today"]["targets"]
            print(f"目标 {tt['kcal']} kcal · 蛋白 {tt['protein']}g")
        print("\n== 目标 ==")
        if result.get("goals"):
            for g in result["goals"]:
                progress = f"{round((g.get('progress') or 0) * 100)}%" if g.get("progress") is not None else "—"
                print(f"- {g['label']}: {g.get('current_value')} → {g['target_value']} {g['unit']}（{progress}{'，已达成' if g.get('achieved') else ''}）")
        else:
            print("（未设置）")
        print("\n== PR ==")
        if result.get("prs"):
            for pr in result["prs"]:
                print(f"- {pr['label']}: {pr['estimated_1rm']} kg（{pr['weight_kg']}kg × {pr['reps']}，{pr['date']}）")
        else:
            print("（暂无）")
        if result.get("recent_workouts"):
            print("\n== 最近训练 ==")
            for w in result["recent_workouts"]:
                print(f"- {w['date']} {w['name'] or '未命名'} · {w['set_count']} 组 · {w['volume_kg']} kg")
        return
    if cmd == "report":
        period = result["period"]
        print(f"周期：{period['start']} → {period['end']}（{period['days']} 天）")
        avg = result.get("nutrition_average")
        if avg:
            print(f"饮食（{avg['days_logged']} 天有记录）：平均 {avg['kcal']} kcal · 蛋白 {avg['protein']}g · 脂肪 {avg['fat']}g · 碳水 {avg['carbs']}g")
        else:
            print("饮食：没有记录")
        wc = result.get("weight_change")
        if wc:
            print(f"体重：{wc['from']} → {wc['to']} kg（{wc['delta']:+} kg）")
        if result.get("measurement_changes"):
            print("围度变化: " + " · ".join(f"{m['label']} {m['delta']:+}cm" for m in result["measurement_changes"]))
        w = result["workouts"]
        print(f"训练：{w['sessions']} 次 · {w['total_sets']} 组 · 总训练量 {w['total_volume_kg']} kg")
        if result.get("new_prs"):
            print("新 PR: " + " · ".join(f"{p['label']} {p['estimated_1rm']}kg" for p in result["new_prs"]))
        return
    if cmd == "dashboard":
        print(f"看板已生成：{result['path']}")
        print(f"数据范围：最近 {result['days']} 天（可在页面切换）")
        return
    # 兜底：打印 JSON
    print(dumps_zh(result))


# ---------------------------------------------------------------- 参数解析


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="coachpal",
        description="本地优先的健身与饮食记录工具（SQLite + 网页看板）",
    )
    parser.add_argument("--json", action="store_true", help="以 JSON 输出，便于程序/skill 使用")
    parser.add_argument("--db", help="指定数据库路径（默认 data/coachpal.db）")
    parser.add_argument("--version", action="version", version=f"coachpal {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("init", help="初始化数据库")

    p_seed = sub.add_parser("seed", help="导入食物库与动作库")
    p_seed.add_argument("--foods-dir", help="china-food-composition-data 仓库目录")
    p_seed.add_argument("--exercises-dir", help="exercises-dataset 目录（含 data/exercises.json）")
    p_seed.add_argument("--gi", help="GI JSON 路径")
    p_seed.add_argument("--skip-foods", action="store_true")
    p_seed.add_argument("--skip-exercises", action="store_true")

    p_profile = sub.add_parser("profile", help="个人档案")
    profile_sub = p_profile.add_subparsers(dest="action", required=True)
    profile_sub.add_parser("show", help="查看档案")
    p_pset = profile_sub.add_parser("set", help="更新档案")
    p_pset.add_argument("--sex", help="male/female/other 或 男/女")
    p_pset.add_argument("--birth", help="出生日期 YYYY-MM-DD")
    p_pset.add_argument("--height", type=float, help="身高 cm")
    p_pset.add_argument("--activity", help="活动水平 sedentary/light/moderate/active/very_active")
    p_pset.add_argument("--goal", help="目标 cut/maintain/bulk 或 减脂/维持/增肌")

    p_weight = sub.add_parser("weight", help="体重与体成分")
    weight_sub = p_weight.add_subparsers(dest="action", required=True)
    p_wadd = weight_sub.add_parser("add", help="记录体重")
    p_wadd.add_argument("weight", type=float, help="体重 kg")
    p_wadd.add_argument("--date", help="日期，默认今天")
    p_wadd.add_argument("--body-fat", type=float, help="体脂率 %%")
    p_wadd.add_argument("--muscle", type=float, help="骨骼肌量 kg")
    p_wadd.add_argument("--note")
    p_wlist = weight_sub.add_parser("list", help="查看历史")
    p_wlist.add_argument("--days", type=int, default=90)
    p_wlist.add_argument("--limit", type=int)

    p_measure = sub.add_parser("measure", help="围度记录")
    measure_sub = p_measure.add_subparsers(dest="action", required=True)
    p_madd = measure_sub.add_parser("add", help="记录围度")
    p_madd.add_argument("--date")
    p_madd.add_argument("--note")
    for key, (label, _aliases) in SITES.items():
        p_madd.add_argument(f"--{key}", type=float, help=f"{label} cm")
    p_madd.add_argument("--set", dest="set_values", action="append", default=[], metavar="部位=数值", help="自定义围度，可重复")
    p_mlist = measure_sub.add_parser("list", help="查看围度历史")
    p_mlist.add_argument("--days", type=int, default=180)
    p_mlist.add_argument("--site")

    p_goal = sub.add_parser("goal", help="目标管理")
    goal_sub = p_goal.add_subparsers(dest="action", required=True)
    p_gset = goal_sub.add_parser("set", help="设置目标")
    p_gset.add_argument("kind", help="weight/body_fat/muscle/围度/力量动作")
    p_gset.add_argument("target", type=float, help="目标值")
    p_gset.add_argument("--date", help="目标日期")
    p_gset.add_argument("--note")
    p_glist = goal_sub.add_parser("list", help="查看目标")
    p_glist.add_argument("--all", action="store_true", help="包含已归档目标")

    p_strength = sub.add_parser("strength", help="力量与 1RM")
    strength_sub = p_strength.add_subparsers(dest="action", required=True)
    p_sadd = strength_sub.add_parser("add", help="记录一组力量数据")
    p_sadd.add_argument("lift", help="bench/squat/deadlift/ohp/row 或中文")
    p_sadd.add_argument("weight", type=float, help="重量 kg")
    p_sadd.add_argument("reps", type=int, help="次数")
    p_sadd.add_argument("--date")
    p_sadd.add_argument("--rpe", type=float)
    p_sadd.add_argument("--note")
    p_slist = strength_sub.add_parser("list", help="查看力量记录")
    p_slist.add_argument("--days", type=int, default=180)
    p_slist.add_argument("--lift")
    strength_sub.add_parser("pr", help="查看各动作 PR")
    p_scalc = strength_sub.add_parser("calc", help="计算估算 1RM")
    p_scalc.add_argument("weight", type=float)
    p_scalc.add_argument("reps", type=int)
    p_spct = strength_sub.add_parser("percentages", help="按 1RM 生成百分比重量表")
    p_spct.add_argument("lift")
    p_spct.add_argument("--step", type=float, help="取整步长 kg")

    p_food = sub.add_parser("food", help="食物库")
    food_sub = p_food.add_subparsers(dest="action", required=True)
    p_fsearch = food_sub.add_parser("search", help="搜索食物")
    p_fsearch.add_argument("query")
    p_fsearch.add_argument("--limit", type=int, default=15)
    p_fshow = food_sub.add_parser("show", help="查看食物详情")
    p_fshow.add_argument("query")

    p_ex = sub.add_parser("exercise", help="动作库")
    ex_sub = p_ex.add_subparsers(dest="action", required=True)
    p_esearch = ex_sub.add_parser("search", help="搜索动作")
    p_esearch.add_argument("query")
    p_esearch.add_argument("--limit", type=int, default=15)
    p_eshow = ex_sub.add_parser("show", help="查看动作详情")
    p_eshow.add_argument("query")
    p_eshow.add_argument("--open", action="store_true", help="打开第一个示意图/动画")

    p_meal = sub.add_parser("meal", help="饮食记录")
    meal_sub = p_meal.add_subparsers(dest="action", required=True)
    p_maddm = meal_sub.add_parser("add", help="记录一餐")
    p_maddm.add_argument("--type", required=True, help="早餐/午餐/晚餐/加餐 或 breakfast/lunch/dinner/snack")
    p_maddm.add_argument("--item", action="append", default=[], metavar="食物:克数", help="来自食物库，可重复")
    p_maddm.add_argument("--custom", action="append", default=[], metavar="名称:克数:热量:蛋白:脂肪:碳水[:纤维]", help="手动录入，可重复")
    p_maddm.add_argument("--date")
    p_maddm.add_argument("--note")
    p_mlistm = meal_sub.add_parser("list", help="查看饮食记录")
    p_mlistm.add_argument("--date", help="指定日期，默认今天")
    p_mlistm.add_argument("--days", type=int, help="改为查看最近 N 天")
    p_mdel = meal_sub.add_parser("delete", help="删除饮食记录")
    p_mdel.add_argument("id", type=int)

    p_day = sub.add_parser("day", help="某天的饮食汇总")
    p_day.add_argument("--date")

    sub.add_parser("targets", help="查看热量与宏量目标")

    p_workout = sub.add_parser("workout", help="训练记录")
    workout_sub = p_workout.add_subparsers(dest="action", required=True)
    p_waddw = workout_sub.add_parser("add", help="记录一次训练")
    p_waddw.add_argument("--name", help="训练名称，例如 推日")
    p_waddw.add_argument("--set", dest="sets", action="append", default=[], metavar="动作 重量 次数 [@RPE]", help="可重复")
    p_waddw.add_argument("--date")
    p_waddw.add_argument("--note")
    p_wlistw = workout_sub.add_parser("list", help="查看训练历史")
    p_wlistw.add_argument("--days", type=int, default=30)
    p_wlistw.add_argument("--limit", type=int)
    p_wshow = workout_sub.add_parser("show", help="查看训练详情")
    p_wshow.add_argument("id", type=int)
    p_wdel = workout_sub.add_parser("delete", help="删除训练记录")
    p_wdel.add_argument("id", type=int)

    sub.add_parser("status", help="一眼看当前状态")

    p_report = sub.add_parser("report", help="阶段复盘")
    p_report.add_argument("--days", type=int, default=7)

    p_dash = sub.add_parser("dashboard", help="生成网页看板")
    p_dash.add_argument("--days", type=int, default=90, help="默认展示范围")
    p_dash.add_argument("--open", action="store_true", help="生成后自动打开浏览器")

    return parser


def _measure_values(args) -> dict[str, float]:
    values: dict[str, float] = {}
    for key in SITES:
        value = getattr(args, key, None)
        if value is not None:
            values[key] = value
    for spec in getattr(args, "set_values", []) or []:
        raw = spec.replace("：", ":").replace("=", ":")
        if ":" not in raw:
            raise CoachPalError(f"围度格式不对：{spec}", ["格式：部位=数值，例如 waist=82"])
        site, value = raw.split(":", 1)
        try:
            values[site.strip()] = float(value)
        except ValueError as exc:
            raise CoachPalError(
                f"围度数值不是数字：{spec}", ["格式：部位=数值，例如 waist=82"]
            ) from exc
    return values


def dispatch(args, con) -> dict[str, Any]:
    cmd = args.command
    action = getattr(args, "action", None)

    if cmd == "init":
        counts = {
            "foods": con.execute("SELECT COUNT(*) AS n FROM foods").fetchone()["n"],
            "exercises": con.execute("SELECT COUNT(*) AS n FROM exercises").fetchone()["n"],
            "records": con.execute(
                "SELECT (SELECT COUNT(*) FROM body_metrics) + (SELECT COUNT(*) FROM measurements) "
                "+ (SELECT COUNT(*) FROM strength_logs) + (SELECT COUNT(*) FROM meals) "
                "+ (SELECT COUNT(*) FROM workouts) AS n"
            ).fetchone()["n"],
        }
        db_file = str(Path(args.db).expanduser().resolve()) if args.db else str(db_path())
        return {"db": db_file, **counts}

    if cmd == "seed":
        defaults = default_sources()
        result: dict[str, Any] = {"warnings": []}
        if not args.skip_foods:
            foods_dir = Path(args.foods_dir) if args.foods_dir else defaults["foods"]
            gi_path = Path(args.gi) if args.gi else defaults["gi"]
            if not foods_dir.exists():
                result["warnings"].append(f"食物数据目录不存在，已跳过：{foods_dir}")
            else:
                result["foods"] = seed_foods(con, foods_dir, gi_path=gi_path if gi_path.exists() else None)
        if not args.skip_exercises:
            from .exercises import seed_exercises

            result["exercises"] = seed_exercises(con, args.exercises_dir)
        if not result.get("foods") and not result.get("exercises"):
            raise CoachPalError(
                "没有导入任何数据",
                ["指定 --foods-dir 和 --exercises-dir，或先把数据集放在项目同级目录"],
            )
        return result

    if cmd == "profile":
        if action == "show":
            return {"profile": get_profile(con)}
        profile = set_profile(
            con,
            sex=args.sex,
            birth_date=args.birth,
            height_cm=args.height,
            activity_level=args.activity,
            goal_type=args.goal,
        )
        return {"profile": profile}

    if cmd == "weight":
        if action == "add":
            return {
                "metric": add_metric(
                    con,
                    args.date,
                    weight_kg=args.weight,
                    body_fat_pct=args.body_fat,
                    skeletal_muscle_kg=args.muscle,
                    note=args.note,
                )
            }
        return {"metrics": list_metrics(con, days=args.days, limit=args.limit)}

    if cmd == "measure":
        if action == "add":
            return add_measurements(con, args.date, _measure_values(args), note=args.note)
        return {"measurements": list_measurements(con, days=args.days, site=args.site)}

    if cmd == "goal":
        if action == "set":
            return {
                "goal": add_goal(
                    con, args.kind, args.target, target_date=args.date, note=args.note
                )
            }
        return {"goals": list_goals(con, status=None if args.all else "active")}

    if cmd == "strength":
        if action == "add":
            return {
                "log": add_log(
                    con,
                    args.lift,
                    args.weight,
                    args.reps,
                    date_str=args.date,
                    rpe=args.rpe,
                    note=args.note,
                )
            }
        if action == "list":
            return {"logs": list_logs(con, days=args.days, lift=args.lift)}
        if action == "pr":
            return {"prs": pr_table(con)}
        if action == "calc":
            estimated = estimate_1rm(args.weight, args.reps)
            return {
                "weight_kg": args.weight,
                "reps": args.reps,
                "estimated_1rm": estimated,
                "high_rep_warning": args.reps > 12,
                "table": percentage_table(estimated),
            }
        if action == "percentages":
            return percentages_for_lift(con, args.lift, step=args.step)

    if cmd == "food":
        if action == "search":
            return {"foods": search_foods(con, args.query, limit=args.limit)}
        return {"food": food_detail(con, args.query)}

    if cmd == "exercise":
        if action == "search":
            return {"exercises": search_exercises(con, args.query, limit=args.limit)}
        detail = exercise_detail(con, args.query)
        if getattr(args, "open", False) and detail.get("images"):
            first = detail["images"][0]
            path = first["path"] if isinstance(first, dict) else None
            if path and Path(path).exists():
                webbrowser.open(Path(path).as_uri())
                detail["opened"] = path
        return {"exercise": detail}

    if cmd == "meal":
        if action == "add":
            return {
                "meal": add_meal(
                    con,
                    args.type,
                    item_specs=args.item,
                    custom_specs=args.custom,
                    date_str=args.date,
                    note=args.note,
                )
            }
        if action == "delete":
            return delete_meal(con, args.id)
        if args.days:
            return {"meals": list_meals(con, days=args.days)}
        return {"meals": list_meals(con, date_str=args.date or "today")}

    if cmd == "day":
        return day_summary(con, args.date)

    if cmd == "targets":
        return {"targets": compute_targets(con)}

    if cmd == "workout":
        if action == "add":
            return {
                "workout": add_workout(
                    con, args.sets, name=args.name, date_str=args.date, note=args.note
                )
            }
        if action == "show":
            return {"workout": workout_detail(con, args.id)}
        if action == "delete":
            return delete_workout(con, args.id)
        return {"workouts": list_workouts(con, days=args.days, limit=args.limit)}

    if cmd == "status":
        return build_status(con)

    if cmd == "report":
        return weekly_report(con, days=args.days)

    if cmd == "dashboard":
        out = (Path(args.db).expanduser().resolve().parent / "dashboard.html") if args.db else None
        path = generate_dashboard(con, days=args.days, out_path=out)
        if args.open:
            webbrowser.open(path.as_uri())
        return {"path": str(path), "days": args.days}

    raise CoachPalError(f"未知命令：{cmd}")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    con = None
    try:
        con = connect(args.db)
        result = dispatch(args, con)
        if args.json:
            print(dumps_zh({"ok": True, **result}))
        else:
            human_output(args, result)
        return 0
    except CoachPalError as exc:
        if args.json:
            print(dumps_zh({"ok": False, "error": exc.message, "hints": exc.hints}))
        else:
            print(f"错误：{exc.message}")
            for hint in exc.hints:
                print(f"  · {hint}")
        return 2
    except BrokenPipeError:
        return 0
    finally:
        if con is not None:
            con.close()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
