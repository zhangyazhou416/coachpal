"""汇总数据：状态、周报、看板数据。"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from .body import (
    SITES,
    get_profile,
    latest_metric,
    latest_measurements,
    list_goals,
    list_measurements,
    list_metrics,
    site_label,
)
from .nutrition import compute_targets, daily_nutrition_series, day_summary
from .strength import lift_label, pr_table, progress_series
from .util import now_iso, r0, r1, today_iso
from .workouts import list_workouts, workout_sessions, weekly_volume


def measurement_series(con) -> list[dict[str, Any]]:
    rows = list_measurements(con, days=None)
    buckets: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        buckets.setdefault(row["site"], []).append(
            {"date": row["date"], "value": row["value_cm"]}
        )
    series = []
    for key, (label, _aliases) in SITES.items():
        if key in buckets:
            series.append({"site": key, "label": label, "points": buckets[key]})
    return series


def dashboard_data(con, default_days: int = 90) -> dict[str, Any]:
    profile = get_profile(con)
    latest = latest_metric(con)
    targets = compute_targets(con)
    metrics = list_metrics(con, days=None)
    return {
        "generated_at": now_iso(),
        "default_days": default_days,
        "today": today_iso(),
        "profile": profile,
        "latest": latest,
        "latest_measurements": list(latest_measurements(con).values()),
        "metrics": [
            {
                "date": m["date"],
                "weight_kg": m.get("weight_kg"),
                "body_fat_pct": m.get("body_fat_pct"),
                "skeletal_muscle_kg": m.get("skeletal_muscle_kg"),
                "bmi": m.get("bmi"),
            }
            for m in metrics
        ],
        "measurement_series": measurement_series(con),
        "strength_series": progress_series(con, days=None),
        "prs": pr_table(con),
        "nutrition_daily": daily_nutrition_series(con, days=365),
        "targets": targets,
        "today_summary": day_summary(con, today_iso()),
        "goals": list_goals(con, status="active"),
        "workout_sessions": workout_sessions(con, days=365),
        "weekly_volume": weekly_volume(con, weeks=52),
    }


def status(con) -> dict[str, Any]:
    profile = get_profile(con)
    latest = latest_metric(con)
    targets = compute_targets(con)
    today = day_summary(con, today_iso())
    goals = list_goals(con, status="active")
    prs = pr_table(con)
    recent_workouts = [
        {
            "id": w["id"],
            "date": w["date"],
            "name": w["name"],
            "volume_kg": w["volume_kg"],
            "set_count": w["set_count"],
        }
        for w in list_workouts(con, limit=5)
    ]
    last7 = daily_nutrition_series(con, days=7)
    avg = None
    if last7:
        avg = {
            "days_logged": len(last7),
            "kcal": r0(sum(d["kcal"] or 0 for d in last7) / len(last7)),
            "protein": r1(sum(d["protein"] or 0 for d in last7) / len(last7)),
            "fat": r1(sum(d["fat"] or 0 for d in last7) / len(last7)),
            "carbs": r1(sum(d["carbs"] or 0 for d in last7) / len(last7)),
        }
    return {
        "profile": {
            "sex": profile.get("sex"),
            "age": profile.get("age"),
            "height_cm": profile.get("height_cm"),
            "bmi": profile.get("bmi"),
            "activity_level": profile.get("activity_level"),
            "goal_type": profile.get("goal_type"),
        },
        "latest_weight": latest,
        "latest_measurements": list(latest_measurements(con).values()),
        "targets": targets,
        "today": {
            "date": today["date"],
            "totals": today["totals"],
            "targets": today["targets"],
            "remaining": today["remaining"],
            "meals": [
                {
                    "id": m["id"],
                    "meal_type": m["meal_type"],
                    "meal_label": m["meal_label"],
                    "totals": m["totals"],
                    "items": [
                        {
                            "food_name": i["food_name"],
                            "grams": i["grams"],
                            "kcal": i["kcal"],
                        }
                        for i in m["items"]
                    ],
                }
                for m in today["meals"]
            ],
        },
        "nutrition_7d_average": avg,
        "goals": goals,
        "prs": prs,
        "recent_workouts": recent_workouts,
    }


def weekly_report(con, days: int = 7) -> dict[str, Any]:
    days = max(1, int(days))
    end = date.today()
    start = end - timedelta(days=days - 1)
    start_iso, end_iso = start.isoformat(), end.isoformat()

    nutrition_rows = [
        r
        for r in daily_nutrition_series(con, days=days + 1)
        if start_iso <= r["date"] <= end_iso
    ]
    avg = None
    if nutrition_rows:
        avg = {
            "days_logged": len(nutrition_rows),
            "kcal": r0(sum(r["kcal"] or 0 for r in nutrition_rows) / len(nutrition_rows)),
            "protein": r1(sum(r["protein"] or 0 for r in nutrition_rows) / len(nutrition_rows)),
            "fat": r1(sum(r["fat"] or 0 for r in nutrition_rows) / len(nutrition_rows)),
            "carbs": r1(sum(r["carbs"] or 0 for r in nutrition_rows) / len(nutrition_rows)),
            "fiber": r1(sum(r["fiber"] or 0 for r in nutrition_rows) / len(nutrition_rows)),
        }

    metrics = [
        m for m in list_metrics(con, days=days + 1) if start_iso <= m["date"] <= end_iso
    ]
    weight_change = None
    if len(metrics) >= 2:
        first = next((m for m in metrics if m.get("weight_kg")), None)
        last = next((m for m in reversed(metrics) if m.get("weight_kg")), None)
        if first and last:
            weight_change = {
                "from": first["weight_kg"],
                "to": last["weight_kg"],
                "delta": round(last["weight_kg"] - first["weight_kg"], 1),
                "from_date": first["date"],
                "to_date": last["date"],
            }

    measurements = [
        m
        for m in list_measurements(con, days=days + 1)
        if start_iso <= m["date"] <= end_iso
    ]
    measure_change: dict[str, dict[str, Any]] = {}
    for site in {m["site"] for m in measurements}:
        points = [m for m in measurements if m["site"] == site]
        if len(points) >= 2:
            measure_change[site] = {
                "label": site_label(site),
                "from": points[0]["value_cm"],
                "to": points[-1]["value_cm"],
                "delta": round(points[-1]["value_cm"] - points[0]["value_cm"], 1),
            }

    workouts = list_workouts(con, days=days)
    workout_summary = {
        "sessions": len(workouts),
        "total_volume_kg": round(sum(w["volume_kg"] for w in workouts), 1),
        "total_sets": sum(w["set_count"] for w in workouts),
        "details": [
            {
                "date": w["date"],
                "name": w["name"],
                "volume_kg": w["volume_kg"],
                "set_count": w["set_count"],
            }
            for w in workouts
        ],
    }

    prs = []
    lifts = [r["lift"] for r in con.execute("SELECT DISTINCT lift FROM strength_logs").fetchall()]
    for lift in lifts:
        before = con.execute(
            "SELECT MAX(estimated_1rm) AS best FROM strength_logs WHERE lift = ? AND date < ?",
            (lift, start_iso),
        ).fetchone()["best"]
        during = con.execute(
            "SELECT * FROM strength_logs WHERE lift = ? AND date >= ? AND date <= ? "
            "ORDER BY estimated_1rm DESC, date DESC LIMIT 1",
            (lift, start_iso, end_iso),
        ).fetchone()
        if during and (before is None or during["estimated_1rm"] > before):
            prs.append(
                {
                    "lift": lift,
                    "label": lift_label(lift),
                    "estimated_1rm": during["estimated_1rm"],
                    "previous_best": before,
                    "date": during["date"],
                }
            )

    return {
        "period": {"start": start_iso, "end": end_iso, "days": days},
        "nutrition_average": avg,
        "targets": compute_targets(con),
        "weight_change": weight_change,
        "measurement_changes": list(measure_change.values()),
        "workouts": workout_summary,
        "new_prs": prs,
        "goals": list_goals(con, status="active"),
    }
