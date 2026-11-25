"""训练记录与训练量统计。"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from .exercises import resolve_exercise
from .strength import parse_set_spec
from .util import CoachPalError, now_iso, parse_date


def add_workout(
    con,
    set_specs: list[str],
    *,
    name: str | None = None,
    date_str: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    d = parse_date(date_str)
    if not set_specs:
        raise CoachPalError(
            "没有训练组",
            ['用 --set "卧推 80 5 @8" 记录，可重复多次'],
        )
    parsed = [parse_set_spec(spec) for spec in set_specs]
    resolved: list[dict[str, Any]] = []
    warnings: list[str] = []
    for spec in parsed:
        if spec["weight_kg"] < 0 or spec["weight_kg"] > 500:
            raise CoachPalError(f"重量看起来不合理：{spec['weight_kg']} kg")
        if not (1 <= spec["reps"] <= 100):
            raise CoachPalError(f"次数看起来不合理：{spec['reps']}")
        if spec["rpe"] is not None and not (1 <= spec["rpe"] <= 10):
            raise CoachPalError("RPE 应在 1-10 之间")
        try:
            exercise = resolve_exercise(con, spec["name"])
            exercise_id = exercise["id"]
            exercise_name = exercise["name"]
            matched = True
        except CoachPalError:
            exercise_id = None
            exercise_name = spec["name"]
            matched = False
            warnings.append(f"动作库里没有「{spec['name']}」，已按自定义动作记录")
        resolved.append({**spec, "exercise_id": exercise_id, "exercise_name": exercise_name, "matched": matched})

    workout_id = con.execute(
        "INSERT INTO workouts (date, name, note, created_at) VALUES (?, ?, ?, ?)",
        (d, name, note, now_iso()),
    ).lastrowid
    counters: dict[str, int] = {}
    for item in resolved:
        counters[item["exercise_name"]] = counters.get(item["exercise_name"], 0) + 1
        con.execute(
            """
            INSERT INTO workout_sets (workout_id, exercise_id, exercise_name, set_no,
                                      weight_kg, reps, rpe, note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                workout_id,
                item["exercise_id"],
                item["exercise_name"],
                counters[item["exercise_name"]],
                item["weight_kg"],
                item["reps"],
                item["rpe"],
                None,
            ),
        )
    con.commit()
    data = workout_detail(con, workout_id)
    data["warnings"] = warnings
    return data


def workout_detail(con, workout_id: int) -> dict[str, Any]:
    workout = con.execute("SELECT * FROM workouts WHERE id = ?", (workout_id,)).fetchone()
    if not workout:
        raise CoachPalError(f"找不到训练记录 #{workout_id}")
    sets = [dict(r) for r in con.execute(
        "SELECT * FROM workout_sets WHERE workout_id = ? ORDER BY id", (workout_id,)
    ).fetchall()]
    for item in sets:
        item["volume_kg"] = round((item["weight_kg"] or 0) * (item["reps"] or 0), 1)
    exercises: dict[str, dict[str, Any]] = {}
    for item in sets:
        entry = exercises.setdefault(
            item["exercise_name"],
            {"exercise_name": item["exercise_name"], "sets": 0, "reps": 0, "volume_kg": 0.0},
        )
        entry["sets"] += 1
        entry["reps"] += item["reps"] or 0
        entry["volume_kg"] = round(entry["volume_kg"] + item["volume_kg"], 1)
    volume = round(sum(item["volume_kg"] for item in sets), 1)
    return {
        "id": workout["id"],
        "date": workout["date"],
        "name": workout["name"],
        "note": workout["note"],
        "sets": sets,
        "exercises": list(exercises.values()),
        "set_count": len(sets),
        "exercise_count": len(exercises),
        "volume_kg": volume,
        "total_reps": sum(item["reps"] or 0 for item in sets),
    }


def list_workouts(con, days: int | None = None, limit: int | None = None) -> list[dict[str, Any]]:
    sql = "SELECT id FROM workouts"
    params: list[Any] = []
    if days is not None:
        sql += " WHERE date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    sql += " ORDER BY date DESC, id DESC"
    if limit:
        sql += " LIMIT ?"
        params.append(limit)
    return [workout_detail(con, r["id"]) for r in con.execute(sql, params).fetchall()]


def delete_workout(con, workout_id: int) -> dict[str, Any]:
    row = con.execute("SELECT * FROM workouts WHERE id = ?", (workout_id,)).fetchone()
    if not row:
        raise CoachPalError(f"找不到训练记录 #{workout_id}")
    con.execute("DELETE FROM workouts WHERE id = ?", (workout_id,))
    con.commit()
    return {"deleted": workout_id, "date": row["date"], "name": row["name"]}


def weekly_volume(con, weeks: int = 12) -> list[dict[str, Any]]:
    start = date.today() - timedelta(days=weeks * 7)
    rows = con.execute(
        """
        SELECT w.date, s.weight_kg, s.reps
        FROM workouts w
        JOIN workout_sets s ON s.workout_id = w.id
        WHERE w.date >= ?
        """,
        (start.isoformat(),),
    ).fetchall()
    buckets: dict[str, dict[str, Any]] = {}
    for r in rows:
        d = date.fromisoformat(r["date"])
        monday = d - timedelta(days=d.weekday())
        key = monday.isoformat()
        bucket = buckets.setdefault(
            key, {"week_start": key, "volume_kg": 0.0, "sets": 0, "workouts": set()}
        )
        bucket["volume_kg"] = round(
            bucket["volume_kg"] + (r["weight_kg"] or 0) * (r["reps"] or 0), 1
        )
        bucket["sets"] += 1
        bucket["workouts"].add(r["date"])
    result = []
    for key in sorted(buckets):
        bucket = buckets[key]
        result.append(
            {
                "week_start": bucket["week_start"],
                "volume_kg": bucket["volume_kg"],
                "sets": bucket["sets"],
                "workouts": len(bucket["workouts"]),
            }
        )
    return result


def workout_sessions(con, days: int = 365) -> list[dict[str, Any]]:
    sessions = []
    for w in list_workouts(con, days=days):
        sessions.append(
            {
                "id": w["id"],
                "date": w["date"],
                "name": w["name"],
                "volume_kg": w["volume_kg"],
                "set_count": w["set_count"],
                "exercise_count": w["exercise_count"],
                "exercises": [e["exercise_name"] for e in w["exercises"]],
            }
        )
    return sessions
