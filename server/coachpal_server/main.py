"""CoachPal 同步服务：领域 API（复用 coachpal 包计算）+ 同步 pull/push。"""

from __future__ import annotations

import sqlite3

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from coachpal.body import (
    add_goal,
    add_measurements,
    add_metric,
    get_profile,
    list_goals,
    list_measurements,
    list_metrics,
    set_profile,
)
from coachpal.exercises import exercise_detail, search_exercises
from coachpal.nutrition import (
    add_meal,
    compute_targets,
    day_summary,
    delete_meal,
    food_detail,
    list_meals,
    search_foods,
    seed_foods,
)
from coachpal.paths import PROJECT_ROOT
from coachpal.util import CoachPalError
from coachpal.report import status as build_status
from coachpal.report import weekly_report
from coachpal.strength import (
    add_log,
    list_logs,
    percentages_for_lift,
    pr_table,
)
from coachpal.workouts import add_workout, delete_workout, list_workouts, workout_detail

from . import auth as auth_mod
from . import stamp
from .agent import run_agent
from .config import bootstrap_password, llm_config, media_dir, port
from .db import connect, stamp_missing, utcnow
from .deps import get_con, require_token
from .routers import sync as sync_router

app = FastAPI(title="CoachPal Sync Server", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(CoachPalError)
def coachpal_error_handler(_req, exc: CoachPalError):
    return JSONResponse(
        status_code=400,
        content={"ok": False, "error": exc.message, "hints": exc.hints},
    )


con_dep = Depends(get_con)
guard = Depends(require_token)


@app.on_event("startup")
def startup() -> None:
    bootstrap_password()
    con = get_con()
    stamp_missing(con)
    foods_dir = PROJECT_ROOT / "vendor" / "foods"
    gi = PROJECT_ROOT / "vendor" / "foods" / "glycemic_index_of_foods.json"
    if any(foods_dir.glob("merged_*.json")):
        seed_foods(con, foods_dir, gi_path=gi if gi.exists() else None)
    from coachpal.exercises import seed_exercises

    try:
        seed_exercises(con)
    except Exception as exc:  # 数据集缺失时动作 API 不可用，但不阻塞服务
        print(f"[startup] 动作库导入跳过：{exc}")


media = media_dir()
if media:
    app.mount("/media", StaticFiles(directory=str(media)), name="media")


# ---------------------------------------------------------------- auth/meta


class LoginBody(BaseModel):
    password: str


@app.post("/api/auth/login")
def login(body: LoginBody, con: sqlite3.Connection = Depends(get_con)):
    token = auth_mod.login(con, body.password)
    if not token:
        raise HTTPException(status_code=401, detail="密码错误")
    return {"ok": True, "token": token}


@app.get("/api/meta", dependencies=[guard])
def meta(con: sqlite3.Connection = Depends(get_con)):
    return {
        "server_time": utcnow(),
        "foods": con.execute("SELECT COUNT(*) AS n FROM foods").fetchone()["n"],
        "exercises": con.execute("SELECT COUNT(*) AS n FROM exercises").fetchone()["n"],
        "protocol": 1,
    }


@app.get("/api/health")
def health():
    return {"ok": True}


# ---------------------------------------------------------------- profile


class ProfileBody(BaseModel):
    sex: str | None = None
    birth: str | None = None
    height: float | None = None
    activity: str | None = None
    goal: str | None = None


@app.get("/api/profile", dependencies=[guard])
def profile(con: sqlite3.Connection = Depends(get_con)):
    return get_profile(con)


@app.put("/api/profile", dependencies=[guard])
def update_profile(body: ProfileBody, con: sqlite3.Connection = Depends(get_con)):
    p = set_profile(
        con,
        sex=body.sex,
        birth_date=body.birth,
        height_cm=body.height,
        activity_level=body.activity,
        goal_type=body.goal,
    )
    return {"ok": True, "profile": p}


# ---------------------------------------------------------------- 体重 / 围度


class WeightBody(BaseModel):
    weight: float
    body_fat: float | None = None
    muscle: float | None = None
    date: str | None = None
    note: str | None = None


@app.post("/api/weight", dependencies=[guard])
def add_weight(body: WeightBody, con: sqlite3.Connection = Depends(get_con)):
    return {"metric": add_metric(
        con, body.date,
        weight_kg=body.weight, body_fat_pct=body.body_fat,
        skeletal_muscle_kg=body.muscle, note=body.note,
    )}


@app.get("/api/weight", dependencies=[guard])
def list_weight(days: int = 90, limit: int | None = None,
                con: sqlite3.Connection = Depends(get_con)):
    return {"metrics": list_metrics(con, days=days, limit=limit)}


@app.get("/api/measurements", dependencies=[guard])
def measurements(days: int = 180, site: str | None = None,
                 con: sqlite3.Connection = Depends(get_con)):
    return {"measurements": list_measurements(con, days=days, site=site)}


class MeasureBody(BaseModel):
    model_config = {"extra": "allow"}
    date: str | None = None
    note: str | None = None


@app.post("/api/measurements", dependencies=[guard])
def add_meas(body: MeasureBody, con: sqlite3.Connection = Depends(get_con)):
    extra = {k: v for k, v in (body.model_extra or {}).items()}
    return add_measurements(con, body.date, extra, note=body.note)


# ---------------------------------------------------------------- 目标


class GoalBody(BaseModel):
    kind: str
    target: float
    date: str | None = None
    note: str | None = None


@app.post("/api/goals", dependencies=[guard])
def create_goal(body: GoalBody, con: sqlite3.Connection = Depends(get_con)):
    return {"goal": add_goal(con, body.kind, body.target, target_date=body.date, note=body.note)}


@app.get("/api/goals", dependencies=[guard])
def goals(con: sqlite3.Connection = Depends(get_con)):
    return {"goals": list_goals(con)}


# ---------------------------------------------------------------- 力量


class StrengthBody(BaseModel):
    lift: str
    weight: float
    reps: int
    date: str | None = None
    rpe: float | None = None
    note: str | None = None


@app.post("/api/strength", dependencies=[guard])
def add_strength(body: StrengthBody, con: sqlite3.Connection = Depends(get_con)):
    return {"log": add_log(
        con, body.lift, body.weight, body.reps,
        date_str=body.date, rpe=body.rpe, note=body.note,
    )}


@app.get("/api/strength/logs", dependencies=[guard])
def strength_logs(days: int = 180, lift: str | None = None,
                  con: sqlite3.Connection = Depends(get_con)):
    return {"logs": list_logs(con, days=days, lift=lift)}


@app.get("/api/strength/pr", dependencies=[guard])
def strength_pr(con: sqlite3.Connection = Depends(get_con)):
    return {"prs": pr_table(con)}


@app.get("/api/strength/percentages/{lift}", dependencies=[guard])
def strength_percentages(lift: str, step: float | None = None,
                         con: sqlite3.Connection = Depends(get_con)):
    return percentages_for_lift(con, lift, step=step)


# ---------------------------------------------------------------- 食物 / 饮食


class MealItemBody(BaseModel):
    query: str
    grams: float


class CustomItemBody(BaseModel):
    name: str
    grams: float
    kcal: float
    protein: float
    fat: float
    carbs: float
    fiber: float = 0.0


class MealBody(BaseModel):
    type: str
    items: list[MealItemBody] = []
    custom: list[CustomItemBody] = []
    date: str | None = None
    note: str | None = None


@app.get("/api/foods/search", dependencies=[guard])
def foods_search(q: str = Query(...), limit: int = 15,
                 con: sqlite3.Connection = Depends(get_con)):
    return {"foods": search_foods(con, q, limit=limit)}


@app.get("/api/foods/show", dependencies=[guard])
def foods_show(q: str = Query(...), con: sqlite3.Connection = Depends(get_con)):
    return {"food": food_detail(con, q)}


@app.post("/api/meals", dependencies=[guard])
def create_meal(body: MealBody, con: sqlite3.Connection = Depends(get_con)):
    meal = add_meal(
        con, body.type,
        item_specs=[f"{i.query}:{i.grams}" for i in body.items],
        custom_specs=[
            f"{c.name}:{c.grams}:{c.kcal}:{c.protein}:{c.fat}:{c.carbs}:{c.fiber}"
            for c in body.custom
        ],
        date_str=body.date, note=body.note,
    )
    stamp_missing(con)
    return {"meal": meal}


@app.get("/api/meals", dependencies=[guard])
def meals(date: str | None = None, days: int | None = None,
          con: sqlite3.Connection = Depends(get_con)):
    if days:
        return {"meals": list_meals(con, days=days)}
    return {"meals": list_meals(con, date_str=date or "today")}


def _tombstone_meal(con: sqlite3.Connection, meal_id: int) -> None:
    """删除前给 meal 及其 items 盖章并记墓碑。"""
    stamp_missing(con)
    meal = con.execute("SELECT uuid FROM meals WHERE id = ?", (meal_id,)).fetchone()
    if not meal:
        return
    if meal["uuid"]:
        stamp.record_tombstone(con, "meals", meal["uuid"])
    items = con.execute(
        "SELECT uuid FROM meal_items WHERE meal_id = ?", (meal_id,)
    ).fetchall()
    for it in items:
        if it["uuid"]:
            stamp.record_tombstone(con, "meal_items", it["uuid"])


def _tombstone_workout(con: sqlite3.Connection, workout_id: int) -> None:
    stamp_missing(con)
    w = con.execute(
        "SELECT uuid FROM workouts WHERE id = ?", (workout_id,)
    ).fetchone()
    if not w:
        return
    if w["uuid"]:
        stamp.record_tombstone(con, "workouts", w["uuid"])
    sets = con.execute(
        "SELECT uuid FROM workout_sets WHERE workout_id = ?", (workout_id,)
    ).fetchall()
    for s in sets:
        if s["uuid"]:
            stamp.record_tombstone(con, "workout_sets", s["uuid"])


@app.delete("/api/meals/{meal_id}", dependencies=[guard])
def remove_meal(meal_id: int, con: sqlite3.Connection = Depends(get_con)):
    _tombstone_meal(con, meal_id)
    result = delete_meal(con, meal_id)
    stamp_missing(con)
    return {"ok": True, **result}


@app.get("/api/day", dependencies=[guard])
def day(date: str | None = None, con: sqlite3.Connection = Depends(get_con)):
    return day_summary(con, date)


@app.get("/api/targets", dependencies=[guard])
def targets(con: sqlite3.Connection = Depends(get_con)):
    return compute_targets(con)


# ---------------------------------------------------------------- 训练


class SetBody(BaseModel):
    name: str
    weight: float
    reps: int
    rpe: float | None = None


class WorkoutBody(BaseModel):
    name: str | None = None
    sets: list[SetBody]
    date: str | None = None
    note: str | None = None


@app.post("/api/workouts", dependencies=[guard])
def create_workout(body: WorkoutBody, con: sqlite3.Connection = Depends(get_con)):
    workout = add_workout(
        con,
        [
            f"{s.name} {s.weight} {s.reps}" + (f" @{s.rpe}" if s.rpe else "")
            for s in body.sets
        ],
        name=body.name, date_str=body.date, note=body.note,
    )
    stamp_missing(con)
    return {"workout": workout}


@app.get("/api/workouts", dependencies=[guard])
def workouts(days: int = 30, limit: int | None = None,
             con: sqlite3.Connection = Depends(get_con)):
    return {"workouts": list_workouts(con, days=days, limit=limit)}


@app.get("/api/workouts/{workout_id}", dependencies=[guard])
def workout_by_id(workout_id: int, con: sqlite3.Connection = Depends(get_con)):
    return {"workout": workout_detail(con, workout_id)}


@app.delete("/api/workouts/{workout_id}", dependencies=[guard])
def remove_workout(workout_id: int, con: sqlite3.Connection = Depends(get_con)):
    _tombstone_workout(con, workout_id)
    result = delete_workout(con, workout_id)
    stamp_missing(con)
    return {"ok": True, **result}


# ---------------------------------------------------------------- 汇总


@app.get("/api/status", dependencies=[guard])
def status(con: sqlite3.Connection = Depends(get_con)):
    return build_status(con)


@app.get("/api/report", dependencies=[guard])
def report(days: int = 7, con: sqlite3.Connection = Depends(get_con)):
    return weekly_report(con, days=days)


@app.get("/api/exercises/search", dependencies=[guard])
def exercises_search(q: str = Query(...), limit: int = 15,
                     con: sqlite3.Connection = Depends(get_con)):
    return {"exercises": search_exercises(con, q, limit=limit)}


@app.get("/api/exercises/show", dependencies=[guard])
def exercises_show(q: str = Query(...), con: sqlite3.Connection = Depends(get_con)):
    return {"exercise": exercise_detail(con, q)}


# ---------------------------------------------------------------- AI 对话


class ChatTurn(BaseModel):
    role: str
    content: str


class ChatBody(BaseModel):
    message: str
    history: list[ChatTurn] = []


@app.post("/api/agent/chat", dependencies=[guard])
def agent_chat(body: ChatBody, con: sqlite3.Connection = Depends(get_con)):
    cfg = llm_config()
    if not cfg.get("configured"):
        raise HTTPException(
            status_code=400,
            detail="服务端未配置 LLM。设置 server/data/llm_config.json"
                   "（base_url/api_key/model，OpenAI 兼容）或对应环境变量后重启。",
        )
    try:
        return run_agent(
            con, body.message,
            history=[t.model_dump() for t in body.history],
        )
    except (httpx.HTTPError, RuntimeError) as exc:
        raise HTTPException(status_code=502, detail=f"LLM 调用失败：{exc}") from exc


# ---------------------------------------------------------------- 同步

app.include_router(sync_router.router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=port())
