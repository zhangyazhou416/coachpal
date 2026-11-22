"""力量记录与 1RM 估算。"""

from __future__ import annotations

import re
from typing import Any

from .util import FitFuelError, now_iso, parse_date, parse_float, r1

LIFTS: dict[str, tuple[str, tuple[str, ...]]] = {
    "bench": ("卧推", ("bench", "bench press", "卧推", "平板卧推", "杠铃卧推")),
    "squat": ("深蹲", ("squat", "深蹲", "杠铃深蹲")),
    "deadlift": ("硬拉", ("deadlift", "硬拉", "杠铃硬拉")),
    "ohp": ("肩推", ("ohp", "overhead press", "military press", "肩推", "推举", "站姿推举")),
    "row": ("杠铃划船", ("row", "barbell row", "划船", "杠铃划船")),
    "pullup": ("引体向上", ("pullup", "pull-up", "引体", "引体向上")),
    "dip": ("双杠臂屈伸", ("dip", "双杠臂屈伸", "臂屈伸")),
    "curl": ("弯举", ("curl", "弯举", "二头弯举")),
}

LIFT_ALIASES: dict[str, str] = {}
for _key, (_label, _aliases) in LIFTS.items():
    for _alias in _aliases:
        LIFT_ALIASES[_alias.lower()] = _key

REP_GUIDE = {
    100: 1,
    95: 2,
    90: 4,
    85: 6,
    80: 8,
    75: 10,
    70: 12,
    65: 15,
    60: 18,
    55: 20,
    50: 22,
}


def lift_label(lift: str) -> str:
    return LIFTS.get(lift, (lift, ()))[0]


def normalize_lift(value: str, *, allow_custom: bool = False) -> str:
    raw = value.strip()
    key = raw.lower()
    if key in LIFTS:
        return key
    if key in LIFT_ALIASES:
        return LIFT_ALIASES[key]
    if allow_custom:
        return re.sub(r"\s+", "_", key)
    raise FitFuelError(
        f"无法识别的动作：{value}",
        ["可用：" + "、".join(f"{k}({v[0]})" for k, v in LIFTS.items())],
    )


def estimate_1rm(weight_kg: float, reps: int) -> float:
    """Epley 与 Brzycki 的平均；高次数只保留 Epley。"""
    if reps <= 1:
        return round(weight_kg, 1)
    epley = weight_kg * (1 + reps / 30.0)
    if reps <= 12:
        brzycki = weight_kg * 36.0 / (37.0 - reps)
        return round((epley + brzycki) / 2.0, 1)
    return round(epley, 1)


def add_log(
    con,
    lift_raw: str,
    weight_kg: float,
    reps: int,
    *,
    date_str: str | None = None,
    rpe: float | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    lift = normalize_lift(lift_raw, allow_custom=True)
    weight = parse_float(weight_kg)
    if weight is None or not (0 < weight <= 500):
        raise FitFuelError("重量看起来不合理（应在 0-500 kg 之间）")
    reps = int(reps)
    if not (1 <= reps <= 100):
        raise FitFuelError("次数看起来不合理（应在 1-100 之间）")
    if rpe is not None and not (1 <= rpe <= 10):
        raise FitFuelError("RPE 应在 1-10 之间")
    d = parse_date(date_str)
    previous = best_e1rm(con, lift)
    estimated = estimate_1rm(weight, reps)
    is_pr = previous is None or estimated > previous["estimated_1rm"]
    con.execute(
        "INSERT INTO strength_logs (date, lift, weight_kg, reps, rpe, estimated_1rm, note, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (d, lift, weight, reps, rpe, estimated, note, now_iso()),
    )
    con.commit()
    log_id = con.execute("SELECT last_insert_rowid() AS id").fetchone()["id"]
    row = con.execute("SELECT * FROM strength_logs WHERE id = ?", (log_id,)).fetchone()
    data = dict(row)
    data["lift_label"] = lift_label(lift)
    data["is_pr"] = is_pr
    data["previous_best"] = (
        {"estimated_1rm": previous["estimated_1rm"], "date": previous["date"]}
        if previous
        else None
    )
    data["high_rep_warning"] = reps > 12
    return data


def best_e1rm(con, lift: str) -> dict[str, Any] | None:
    row = con.execute(
        "SELECT * FROM strength_logs WHERE lift = ? ORDER BY estimated_1rm DESC, date DESC LIMIT 1",
        (lift,),
    ).fetchone()
    if not row:
        return None
    data = dict(row)
    data["lift_label"] = lift_label(lift)
    return data


def pr_table(con) -> list[dict[str, Any]]:
    lifts = [
        r["lift"]
        for r in con.execute("SELECT DISTINCT lift FROM strength_logs ORDER BY lift").fetchall()
    ]
    result = []
    for lift in lifts:
        best = best_e1rm(con, lift)
        if best:
            result.append(
                {
                    "lift": lift,
                    "label": lift_label(lift),
                    "estimated_1rm": best["estimated_1rm"],
                    "weight_kg": best["weight_kg"],
                    "reps": best["reps"],
                    "date": best["date"],
                }
            )
    result.sort(key=lambda x: x["estimated_1rm"], reverse=True)
    return result


def list_logs(
    con, days: int | None = None, lift: str | None = None
) -> list[dict[str, Any]]:
    sql = "SELECT * FROM strength_logs WHERE 1 = 1"
    params: list[Any] = []
    if days is not None:
        sql += " AND date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    if lift:
        sql += " AND lift = ?"
        params.append(normalize_lift(lift, allow_custom=True))
    sql += " ORDER BY date ASC, id ASC"
    rows = []
    for r in con.execute(sql, params):
        item = dict(r)
        item["lift_label"] = lift_label(item["lift"])
        rows.append(item)
    return rows


def progress_series(con, days: int | None = None) -> list[dict[str, Any]]:
    """每个动作按日期取当日最大估算 1RM。"""
    sql = """
        SELECT lift, date, MAX(estimated_1rm) AS estimated_1rm
        FROM strength_logs
        WHERE 1 = 1
    """
    params: list[Any] = []
    if days is not None:
        sql += " AND date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    sql += " GROUP BY lift, date ORDER BY lift, date"
    buckets: dict[str, list[dict[str, Any]]] = {}
    for r in con.execute(sql, params):
        buckets.setdefault(r["lift"], []).append(
            {"date": r["date"], "value": r["estimated_1rm"]}
        )
    return [
        {"lift": lift, "label": lift_label(lift), "points": points}
        for lift, points in buckets.items()
    ]


def rounding_step(value: float) -> float:
    if value >= 100:
        return 5.0
    if value >= 40:
        return 2.5
    return 1.0


def percentage_table(
    one_rm: float, *, step: float | None = None, max_pct: int = 100, min_pct: int = 50
) -> list[dict[str, Any]]:
    if one_rm <= 0:
        raise FitFuelError("1RM 必须大于 0")
    step = step or rounding_step(one_rm)
    rows = []
    for pct in sorted(REP_GUIDE.keys(), reverse=True):
        if pct > max_pct or pct < min_pct:
            continue
        raw = one_rm * pct / 100.0
        weight = round(raw / step) * step
        rows.append(
            {
                "pct": pct,
                "weight_kg": r1(weight),
                "reps_guide": REP_GUIDE[pct],
            }
        )
    return rows


def percentages_for_lift(con, lift_raw: str, *, step: float | None = None) -> dict[str, Any]:
    lift = normalize_lift(lift_raw)
    best = best_e1rm(con, lift)
    if not best:
        raise FitFuelError(
            f"还没有 {lift_label(lift)} 的记录",
            [f"先记录一组，例如：fitfuel strength add {lift} 80 5"],
        )
    return {
        "lift": lift,
        "label": lift_label(lift),
        "estimated_1rm": best["estimated_1rm"],
        "source": {"weight_kg": best["weight_kg"], "reps": best["reps"], "date": best["date"]},
        "table": percentage_table(best["estimated_1rm"], step=step),
    }


def parse_set_spec(spec: str) -> dict[str, Any]:
    """解析 '卧推 80 5 @8' / '卧推 80kg x 5 @8' / '引体 0 10'。"""
    s = spec.strip()
    pattern = re.compile(
        r"^(?P<name>.+?)\s+(?P<weight>\d+(?:\.\d+)?)\s*(?:kg|公斤|千克)?\s*(?:[x×*]\s*)?(?P<reps>\d+)\s*(?:@\s*(?P<rpe>\d+(?:\.\d+)?))?$",
        re.IGNORECASE,
    )
    m = pattern.match(s)
    if not m:
        raise FitFuelError(
            f"无法解析训练组：{spec}",
            ["格式：动作名 重量 次数 [@RPE]，例如 卧推 80 5 @8；自重动作重量写 0"],
        )
    return {
        "name": m.group("name").strip(),
        "weight_kg": float(m.group("weight")),
        "reps": int(m.group("reps")),
        "rpe": float(m.group("rpe")) if m.group("rpe") else None,
    }
