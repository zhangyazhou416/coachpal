"""个人档案、体重/体成分、围度与目标。"""

from __future__ import annotations

from datetime import date
from typing import Any

from .util import (
    FitFuelError,
    clamp,
    normalize_activity,
    normalize_goal,
    now_iso,
    parse_date,
    parse_float,
    r1,
    today_iso,
)

# 围度部位：规范键 -> (中文名, 接受的别名)
SITES: dict[str, tuple[str, tuple[str, ...]]] = {
    "chest": ("胸围", ("chest", "胸", "胸围")),
    "waist": ("腰围", ("waist", "腰", "腰围")),
    "hip": ("臀围", ("hip", "臀", "臀围")),
    "neck": ("颈围", ("neck", "颈", "颈围")),
    "shoulder": ("肩围", ("shoulder", "肩", "肩围")),
    "arm": ("上臂围", ("arm", "臂", "臂围", "上臂围")),
    "forearm": ("前臂围", ("forearm", "前臂", "前臂围")),
    "thigh": ("大腿围", ("thigh", "大腿", "大腿围")),
    "calf": ("小腿围", ("calf", "小腿", "小腿围")),
    "wrist": ("腕围", ("wrist", "腕", "腕围")),
}

SITE_ALIASES: dict[str, str] = {}
for _key, (_label, _aliases) in SITES.items():
    for _alias in _aliases:
        SITE_ALIASES[_alias.lower()] = _key


def site_label(site: str) -> str:
    return SITES.get(site, (site, ()))[0]


def normalize_site(value: str) -> str:
    key = value.strip().lower()
    if key in SITES:
        return key
    if key in SITE_ALIASES:
        return SITE_ALIASES[key]
    raise FitFuelError(
        f"无法识别的围度部位：{value}",
        ["可用：" + "、".join(f"{k}({v[0]})" for k, v in SITES.items())],
    )


def normalize_sex(value: str) -> str:
    key = value.strip().lower()
    mapping = {
        "male": "male",
        "m": "male",
        "男": "male",
        "男性": "male",
        "female": "female",
        "f": "female",
        "女": "female",
        "女性": "female",
        "other": "other",
        "其他": "other",
    }
    if key in mapping:
        return mapping[key]
    raise FitFuelError(f"无法识别的性别：{value}", ["可用：male/female/other 或 男/女"])


def calc_age(birth_date: str | None) -> int | None:
    if not birth_date:
        return None
    try:
        born = date.fromisoformat(birth_date)
    except ValueError:
        return None
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))


def calc_bmi(weight_kg: float | None, height_cm: float | None) -> float | None:
    if not weight_kg or not height_cm:
        return None
    h = height_cm / 100.0
    return round(weight_kg / (h * h), 1)


def get_profile(con) -> dict[str, Any]:
    row = con.execute("SELECT * FROM profile WHERE id = 1").fetchone()
    profile = dict(row) if row else {}
    if not profile:
        profile = {
            "id": 1,
            "sex": "male",
            "birth_date": None,
            "height_cm": None,
            "activity_level": "moderate",
            "goal_type": "maintain",
            "updated_at": now_iso(),
        }
    profile["age"] = calc_age(profile.get("birth_date"))
    latest = latest_metric(con)
    profile["latest_weight_kg"] = latest.get("weight_kg") if latest else None
    profile["bmi"] = calc_bmi(profile["latest_weight_kg"], profile.get("height_cm"))
    return profile


def set_profile(
    con,
    *,
    sex: str | None = None,
    birth_date: str | None = None,
    height_cm: float | None = None,
    activity_level: str | None = None,
    goal_type: str | None = None,
) -> dict[str, Any]:
    current = get_profile(con)
    values = {
        "sex": normalize_sex(sex) if sex else current.get("sex") or "male",
        "birth_date": parse_date(birth_date) if birth_date else current.get("birth_date"),
        "height_cm": float(height_cm) if height_cm is not None else current.get("height_cm"),
        "activity_level": normalize_activity(activity_level)
        if activity_level
        else current.get("activity_level") or "moderate",
        "goal_type": normalize_goal(goal_type)
        if goal_type
        else current.get("goal_type") or "maintain",
        "updated_at": now_iso(),
    }
    if values["height_cm"] is not None and not (80 <= values["height_cm"] <= 250):
        raise FitFuelError("身高看起来不合理（应在 80-250 cm 之间）")
    con.execute(
        "UPDATE profile SET sex = ?, birth_date = ?, height_cm = ?, "
        "activity_level = ?, goal_type = ?, updated_at = ? WHERE id = 1",
        (
            values["sex"],
            values["birth_date"],
            values["height_cm"],
            values["activity_level"],
            values["goal_type"],
            values["updated_at"],
        ),
    )
    con.commit()
    return get_profile(con)


def add_metric(
    con,
    date_str: str | None = None,
    *,
    weight_kg: float | None = None,
    body_fat_pct: float | None = None,
    skeletal_muscle_kg: float | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    d = parse_date(date_str)
    if weight_kg is None and body_fat_pct is None and skeletal_muscle_kg is None:
        raise FitFuelError("至少提供体重、体脂率或骨骼肌量中的一项")
    if weight_kg is not None and not (20 <= weight_kg <= 400):
        raise FitFuelError("体重看起来不合理（应在 20-400 kg 之间）")
    if body_fat_pct is not None and not (1 <= body_fat_pct <= 70):
        raise FitFuelError("体脂率看起来不合理（应在 1-70% 之间）")
    if skeletal_muscle_kg is not None and not (5 <= skeletal_muscle_kg <= 100):
        raise FitFuelError("骨骼肌量看起来不合理（应在 5-100 kg 之间）")
    con.execute(
        """
        INSERT INTO body_metrics (date, weight_kg, body_fat_pct, skeletal_muscle_kg, note, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            weight_kg = COALESCE(excluded.weight_kg, body_metrics.weight_kg),
            body_fat_pct = COALESCE(excluded.body_fat_pct, body_metrics.body_fat_pct),
            skeletal_muscle_kg = COALESCE(excluded.skeletal_muscle_kg, body_metrics.skeletal_muscle_kg),
            note = COALESCE(excluded.note, body_metrics.note)
        """,
        (d, weight_kg, body_fat_pct, skeletal_muscle_kg, note, now_iso()),
    )
    con.commit()
    return metric_by_date(con, d)


def _height(con) -> float | None:
    row = con.execute("SELECT height_cm FROM profile WHERE id = 1").fetchone()
    return row["height_cm"] if row else None


def metric_by_date(con, date_str: str) -> dict[str, Any]:
    row = con.execute("SELECT * FROM body_metrics WHERE date = ?", (date_str,)).fetchone()
    if not row:
        raise FitFuelError(f"{date_str} 没有体重记录")
    data = dict(row)
    data["bmi"] = calc_bmi(data.get("weight_kg"), _height(con))
    return data


def latest_metric(con) -> dict[str, Any] | None:
    row = con.execute(
        "SELECT * FROM body_metrics ORDER BY date DESC, id DESC LIMIT 1"
    ).fetchone()
    if not row:
        return None
    data = dict(row)
    data["bmi"] = calc_bmi(data.get("weight_kg"), _height(con))
    return data


def list_metrics(con, days: int | None = None, limit: int | None = None) -> list[dict[str, Any]]:
    sql = "SELECT * FROM body_metrics"
    params: list[Any] = []
    if days is not None:
        sql += " WHERE date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    sql += " ORDER BY date ASC"
    if limit:
        sql += " LIMIT ?"
        params.append(limit)
    profile = get_profile(con)
    height = profile.get("height_cm")
    rows = []
    for row in con.execute(sql, params):
        item = dict(row)
        item["bmi"] = calc_bmi(item.get("weight_kg"), height)
        rows.append(item)
    return rows


def add_measurements(
    con,
    date_str: str | None,
    values: dict[str, float],
    note: str | None = None,
) -> dict[str, Any]:
    d = parse_date(date_str)
    if not values:
        raise FitFuelError("没有提供任何围度数据")
    normalized: dict[str, float] = {}
    for raw_site, value in values.items():
        site = normalize_site(raw_site)
        v = parse_float(value)
        if v is None:
            continue
        if not (10 <= v <= 300):
            raise FitFuelError(f"{site_label(site)} 数值看起来不合理：{v} cm")
        normalized[site] = v
    if not normalized:
        raise FitFuelError("没有有效的围度数据")
    for site, value in normalized.items():
        con.execute(
            """
            INSERT INTO measurements (date, site, value_cm, note, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(date, site) DO UPDATE SET
                value_cm = excluded.value_cm,
                note = COALESCE(excluded.note, measurements.note)
            """,
            (d, site, value, note, now_iso()),
        )
    con.commit()
    return {"date": d, "measurements": measurements_by_date(con, d)}


def measurements_by_date(con, date_str: str) -> list[dict[str, Any]]:
    rows = con.execute(
        "SELECT site, value_cm FROM measurements WHERE date = ? ORDER BY id", (date_str,)
    ).fetchall()
    return [
        {"site": r["site"], "label": site_label(r["site"]), "value_cm": r["value_cm"]}
        for r in rows
    ]


def list_measurements(
    con, days: int | None = None, site: str | None = None
) -> list[dict[str, Any]]:
    sql = "SELECT * FROM measurements WHERE 1 = 1"
    params: list[Any] = []
    if days is not None:
        sql += " AND date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    if site:
        sql += " AND site = ?"
        params.append(normalize_site(site))
    sql += " ORDER BY date ASC, site ASC"
    return [
        {
            "date": r["date"],
            "site": r["site"],
            "label": site_label(r["site"]),
            "value_cm": r["value_cm"],
        }
        for r in con.execute(sql, params)
    ]


def latest_measurements(con) -> dict[str, dict[str, Any]]:
    rows = con.execute(
        """
        SELECT m.* FROM measurements m
        JOIN (
            SELECT site, MAX(date) AS max_date FROM measurements GROUP BY site
        ) t ON m.site = t.site AND m.date = t.max_date
        """
    ).fetchall()
    return {
        r["site"]: {"site": r["site"], "label": site_label(r["site"]), "value_cm": r["value_cm"], "date": r["date"]}
        for r in rows
    }


# ---------------------------------------------------------------- goals


GOAL_SIMPLE_ALIASES = {
    "weight": ("weight", "体重", "体重kg", "称重"),
    "body_fat": ("body_fat", "体脂", "体脂率", "bf"),
    "muscle": ("muscle", "skeletal_muscle", "骨骼肌", "肌肉量", "骨骼肌量"),
}

GOAL_UNITS = {
    "weight": "kg",
    "body_fat": "%",
    "muscle": "kg",
}


def normalize_goal_kind(value: str) -> str:
    raw = value.strip()
    key = raw.lower()
    for canonical, aliases in GOAL_SIMPLE_ALIASES.items():
        if key in aliases or raw in aliases:
            return canonical
    if key in SITE_ALIASES or key in SITES:
        return f"measure:{normalize_site(raw)}"
    from .strength import normalize_lift  # 延迟导入，避免循环依赖

    try:
        return f"strength:{normalize_lift(raw)}"
    except FitFuelError:
        pass
    raise FitFuelError(
        f"无法识别的目标指标：{value}",
        [
            "可用：weight/体重、body_fat/体脂率、muscle/骨骼肌量、"
            "围度部位（如 waist/腰围）、力量动作（如 bench/卧推）",
        ],
    )


def goal_label(kind: str) -> str:
    if kind in ("weight", "body_fat", "muscle"):
        return {"weight": "体重", "body_fat": "体脂率", "muscle": "骨骼肌量"}[kind]
    if kind.startswith("measure:"):
        return site_label(kind.split(":", 1)[1])
    if kind.startswith("strength:"):
        from .strength import lift_label

        return f"{lift_label(kind.split(':', 1)[1])} 1RM"
    return kind


def goal_unit(kind: str) -> str:
    if kind in GOAL_UNITS:
        return GOAL_UNITS[kind]
    if kind.startswith("measure:"):
        return "cm"
    if kind.startswith("strength:"):
        return "kg"
    return ""


def current_value_for_kind(con, kind: str) -> float | None:
    if kind == "weight":
        row = con.execute(
            "SELECT weight_kg FROM body_metrics WHERE weight_kg IS NOT NULL ORDER BY date DESC, id DESC LIMIT 1"
        ).fetchone()
        return row["weight_kg"] if row else None
    if kind == "body_fat":
        row = con.execute(
            "SELECT body_fat_pct FROM body_metrics WHERE body_fat_pct IS NOT NULL ORDER BY date DESC, id DESC LIMIT 1"
        ).fetchone()
        return row["body_fat_pct"] if row else None
    if kind == "muscle":
        row = con.execute(
            "SELECT skeletal_muscle_kg FROM body_metrics WHERE skeletal_muscle_kg IS NOT NULL ORDER BY date DESC, id DESC LIMIT 1"
        ).fetchone()
        return row["skeletal_muscle_kg"] if row else None
    if kind.startswith("measure:"):
        site = kind.split(":", 1)[1]
        row = con.execute(
            "SELECT value_cm FROM measurements WHERE site = ? ORDER BY date DESC, id DESC LIMIT 1",
            (site,),
        ).fetchone()
        return row["value_cm"] if row else None
    if kind.startswith("strength:"):
        from .strength import best_e1rm

        lift = kind.split(":", 1)[1]
        pr = best_e1rm(con, lift)
        return pr["estimated_1rm"] if pr else None
    return None


def add_goal(
    con,
    kind_raw: str,
    target_value: float,
    *,
    target_date: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    kind = normalize_goal_kind(kind_raw)
    target = parse_float(target_value)
    if target is None:
        raise FitFuelError("目标值必须是数字")
    baseline = current_value_for_kind(con, kind)
    target_date_iso = parse_date(target_date) if target_date else None
    con.execute(
        "INSERT INTO goals (kind, target_value, unit, baseline_value, target_date, status, note, created_at) "
        "VALUES (?, ?, ?, ?, ?, 'active', ?, ?)",
        (
            kind,
            target,
            goal_unit(kind),
            baseline,
            target_date_iso,
            note,
            now_iso(),
        ),
    )
    con.commit()
    goal_id = con.execute("SELECT last_insert_rowid() AS id").fetchone()["id"]
    return goal_with_progress(con, goal_id)


def goal_with_progress(con, goal_id: int) -> dict[str, Any]:
    row = con.execute("SELECT * FROM goals WHERE id = ?", (goal_id,)).fetchone()
    if not row:
        raise FitFuelError(f"找不到目标 #{goal_id}")
    data = dict(row)
    current = current_value_for_kind(con, data["kind"])
    baseline = data.get("baseline_value")
    target = data["target_value"]
    if baseline is None and current is not None and data.get("status") == "active":
        # 目标先于第一次记录创建时，用第一次数据补上起点
        con.execute("UPDATE goals SET baseline_value = ? WHERE id = ?", (current, goal_id))
        con.commit()
        baseline = current
        data["baseline_value"] = current
    direction = None
    progress = None
    achieved = False
    if baseline is not None and target != baseline:
        direction = "down" if target < baseline else "up"
        if current is not None:
            raw = (current - baseline) / (target - baseline)
            progress = round(clamp(raw, 0.0, 1.0), 3)
            achieved = current <= target if direction == "down" else current >= target
    elif current is not None and target == current:
        progress = 1.0
        achieved = True
    data.update(
        {
            "label": goal_label(data["kind"]),
            "current_value": r1(current),
            "direction": direction,
            "progress": progress,
            "achieved": achieved,
        }
    )
    return data


def list_goals(con, status: str | None = "active") -> list[dict[str, Any]]:
    sql = "SELECT id FROM goals"
    params: list[Any] = []
    if status:
        sql += " WHERE status = ?"
        params.append(status)
    sql += " ORDER BY created_at ASC"
    return [goal_with_progress(con, r["id"]) for r in con.execute(sql, params).fetchall()]
