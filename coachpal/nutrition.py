"""食物库导入、食物检索、饮食记录与热量目标。"""

from __future__ import annotations

import difflib
import json
import re
import unicodedata
from pathlib import Path
from typing import Any

from .body import get_profile, latest_metric
from .db import meta_get, meta_set
from .util import (
    ACTIVITY_LABELS,
    CoachPalError,
    MEAL_LABELS,
    normalize_activity,
    normalize_goal,
    normalize_meal_type,
    now_iso,
    parse_date,
    parse_float,
    parse_item_spec,
    r0,
    r1,
    today_iso,
)

# ---------------------------------------------------------------- 食物库导入


def _norm_name(name: str) -> str:
    s = unicodedata.normalize("NFKC", name or "")
    s = s.replace("*", "").replace("＊", "")
    s = re.sub(r"[（(［\[].*?[）)］\]]", "", s)
    s = re.sub(r"[\s·,，、]+", "", s)
    return s.lower()


def _find_food_dir(path: Path) -> Path:
    if not path.exists():
        raise CoachPalError(f"食物数据目录不存在：{path}")
    if list(path.glob("merged_*.json")):
        return path
    candidates = []
    for pattern, preference in (
        ("json_data_*_fixed_en", 3),
        ("json_data_*_fixed", 2),
        ("json_data_*", 1),
    ):
        for p in path.glob(pattern):
            if p.is_dir() and list(p.glob("merged_*.json")):
                candidates.append((preference, p.name, p))
    if not candidates:
        raise CoachPalError(
            f"在 {path} 下找不到食物 JSON（json_data_*/merged_*.json）",
            ["用 --foods-dir 指向 china-food-composition-data 仓库根目录"],
        )
    candidates.sort(key=lambda x: (x[0], x[1]))
    return candidates[-1][2]


def _load_gi(gi_path: Path | None) -> dict[str, float]:
    if not gi_path or not gi_path.exists():
        return {}
    data = json.loads(gi_path.read_text(encoding="utf-8"))
    result: dict[str, float] = {}
    for group in data:
        for item in group.get("list", []):
            name = item.get("foodName", "")
            gi = parse_float(item.get("GI"))
            if name and gi is not None:
                result[_norm_name(name)] = gi
    return result


def seed_foods(
    con,
    foods_dir: str | Path,
    *,
    gi_path: str | Path | None = None,
) -> dict[str, Any]:
    root = Path(foods_dir).expanduser().resolve()
    food_dir = _find_food_dir(root)
    gi_file = Path(gi_path).expanduser().resolve() if gi_path else None
    if gi_file is None:
        candidate = root / "json_gi_of_foods" / "glycemic_index_of_foods.json"
        if candidate.exists():
            gi_file = candidate
    gi_map = _load_gi(gi_file)

    files = sorted(food_dir.glob("merged_*.json"))
    inserted = 0
    foods_seen = 0
    gi_rows = 0
    for file in files:
        category = file.stem.removeprefix("merged_")
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(data, list):
            continue
        for item in data:
            if not isinstance(item, dict):
                continue
            code = str(item.get("foodCode") or "").strip() or None
            name = str(item.get("foodName") or "").strip()
            if not name:
                continue
            foods_seen += 1
            gi = gi_map.get(_norm_name(name))
            con.execute(
                """
                INSERT INTO foods (code, name, name_en, category, edible_pct, kcal, protein,
                                   fat, carbs, fiber, sodium_mg, calcium_mg, iron_mg, gi, source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(code) DO UPDATE SET
                    name = excluded.name,
                    name_en = excluded.name_en,
                    category = excluded.category,
                    edible_pct = excluded.edible_pct,
                    kcal = excluded.kcal,
                    protein = excluded.protein,
                    fat = excluded.fat,
                    carbs = excluded.carbs,
                    fiber = excluded.fiber,
                    sodium_mg = excluded.sodium_mg,
                    calcium_mg = excluded.calcium_mg,
                    iron_mg = excluded.iron_mg,
                    gi = excluded.gi,
                    source = excluded.source
                """,
                (
                    code,
                    name,
                    str(item.get("englishName") or "").strip() or None,
                    category,
                    parse_float(item.get("edible")),
                    parse_float(item.get("energyKCal")),
                    parse_float(item.get("protein")),
                    parse_float(item.get("fat")),
                    parse_float(item.get("CHO")),
                    parse_float(item.get("dietaryFiber")),
                    parse_float(item.get("Na")),
                    parse_float(item.get("Ca")),
                    parse_float(item.get("Fe")),
                    gi,
                    "中国食物成分表（第6版）",
                ),
            )
            inserted += 1

    con.execute("DELETE FROM gi_foods")
    if gi_file and gi_file.exists():
        data = json.loads(gi_file.read_text(encoding="utf-8"))
        for group in data:
            group_name = group.get("foodGroup")
            for item in group.get("list", []):
                gi = parse_float(item.get("GI"))
                name = item.get("foodName")
                if gi is None or not name:
                    continue
                con.execute(
                    "INSERT INTO gi_foods (food_group, name, gi) VALUES (?, ?, ?)",
                    (group_name, name, gi),
                )
                gi_rows += 1

    meta_set(con, "foods_source_dir", str(food_dir))
    meta_set(con, "foods_seeded_at", now_iso())
    con.commit()
    total = con.execute("SELECT COUNT(*) AS n FROM foods").fetchone()["n"]
    with_gi = con.execute("SELECT COUNT(*) AS n FROM foods WHERE gi IS NOT NULL").fetchone()["n"]
    return {
        "food_dir": str(food_dir),
        "files": len(files),
        "seen": foods_seen,
        "upserted": inserted,
        "foods_total": total,
        "with_gi": with_gi,
        "gi_rows": gi_rows,
    }


# ---------------------------------------------------------------- 检索


def _row_summary(row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "code": row["code"],
        "name": row["name"],
        "name_en": row["name_en"],
        "category": row["category"],
        "kcal_per_100g": row["kcal"],
        "protein_g": row["protein"],
        "fat_g": row["fat"],
        "carbs_g": row["carbs"],
        "fiber_g": row["fiber"],
        "gi": row["gi"],
    }


def search_foods(con, query: str, limit: int = 15) -> list[dict[str, Any]]:
    q = (query or "").strip()
    if not q:
        raise CoachPalError("请输入要搜索的食物名称或食物编码")
    if con.execute("SELECT COUNT(*) AS n FROM foods").fetchone()["n"] == 0:
        raise CoachPalError(
            "食物库还是空的",
            ["先运行：coachpal seed --foods-dir ../china-food-composition-data"],
        )
    ql = q.lower()
    qn = _norm_name(q)
    rows = con.execute(
        "SELECT id, code, name, name_en, category, kcal, protein, fat, carbs, fiber, gi FROM foods"
    ).fetchall()
    scored: list[tuple[float, dict[str, Any]]] = []
    for row in rows:
        name = row["name"] or ""
        nn = _norm_name(name)
        name_en = (row["name_en"] or "").lower()
        category = (row["category"] or "").lower()
        code = (row["code"] or "").lower()
        score = 0.0
        if ql == code:
            score = 1000.0
        elif ql == name.lower():
            score = 900.0
        elif qn and qn == nn:
            score = 880.0
        elif qn and nn.startswith(qn):
            score = 760.0 - min(len(nn) - len(qn), 80) * 0.5
        elif qn and qn in nn:
            score = 680.0 - min(len(nn) - len(qn), 80) * 0.5
        else:
            score = difflib.SequenceMatcher(None, qn, nn).ratio() * 520.0
        if name_en and ql in name_en:
            score = max(score, 600.0)
        if ql and ql in category:
            score = max(score, 320.0)
        if score < 300:
            continue
        item = _row_summary(row)
        item["match_score"] = round(score, 1)
        scored.append((score, item))
    scored.sort(key=lambda x: (-x[0], len(x[1]["name"] or ""), x[1]["name"] or ""))
    return [item for _, item in scored[:limit]]


def resolve_food(con, query: str) -> dict[str, Any]:
    q = (query or "").strip()
    if not q:
        raise CoachPalError("食物名不能为空")
    row = con.execute(
        "SELECT * FROM foods WHERE lower(code) = lower(?)", (q,)
    ).fetchone()
    if row:
        return _row_summary(row)
    row = con.execute(
        "SELECT * FROM foods WHERE lower(name) = lower(?)", (q,)
    ).fetchone()
    if row:
        return _row_summary(row)
    matches = search_foods(con, q, limit=8)
    if not matches:
        raise CoachPalError(
            f"食物库里找不到「{q}」",
            [
                "换一个更通用的名称试试，例如 鸡胸肉 / 米饭 / 鸡蛋",
                "或者用 --custom 手动录入营养成分",
            ],
        )
    top = matches[0]
    second = matches[1] if len(matches) > 1 else None
    margin = top["match_score"] - (second["match_score"] if second else 0)
    if top["match_score"] >= 850 and (second is None or margin >= 15):
        return top
    if top["match_score"] >= 700 and (second is None or margin >= 40):
        return top
    near = [m for m in matches if top["match_score"] - m["match_score"] <= 2]
    representatives = [m for m in near if "代表值" in (m["name"] or "")]
    if len(representatives) == 1:
        return representatives[0]
    candidates = "\n".join(
        f"  [{m['code'] or m['id']}] {m['name']} — {m['kcal_per_100g'] or '?'} kcal/100g"
        for m in matches[:5]
    )
    raise CoachPalError(
        f"「{q}」匹配到多个食物，无法自动确定：\n{candidates}",
        [
            "用更完整的名称重试，或把食物编码写进条目：060101:150",
            f"也可以先运行：coachpal food search {q}",
        ],
    )


def food_detail(con, query: str) -> dict[str, Any]:
    match = resolve_food(con, query)
    row = con.execute("SELECT * FROM foods WHERE id = ?", (match["id"],)).fetchone()
    return dict(row)


# ---------------------------------------------------------------- 饮食记录


def _per_100(row: dict[str, Any]) -> tuple[float, float, float, float, float]:
    kcal = row.get("kcal_per_100g")
    protein = row.get("protein_g") or 0.0
    fat = row.get("fat_g") or 0.0
    carbs = row.get("carbs_g") or 0.0
    fiber = row.get("fiber_g") or 0.0
    if kcal is None:
        kcal = protein * 4 + fat * 9 + carbs * 4
    return kcal, protein, fat, carbs, fiber


def _scale(row: dict[str, Any], grams: float) -> dict[str, float]:
    kcal, protein, fat, carbs, fiber = _per_100(row)
    factor = grams / 100.0
    return {
        "kcal": round(kcal * factor, 1),
        "protein": round(protein * factor, 1),
        "fat": round(fat * factor, 1),
        "carbs": round(carbs * factor, 1),
        "fiber": round(fiber * factor, 1),
    }


def _parse_custom(spec: str) -> dict[str, Any]:
    s = spec.strip().replace("：", ":")
    parts = s.split(":")
    if len(parts) < 6:
        raise CoachPalError(
            f"自定义条目格式不对：{spec}",
            ["格式：名称:克数:热量:蛋白:脂肪:碳水[:纤维]，例如 蛋白粉:30:120:24:1.5:3"],
        )
    name = parts[0].strip()
    nums = [parse_float(p) for p in parts[1:7]]
    if not name or any(n is None for n in nums[:5]):
        raise CoachPalError(f"自定义条目格式不对：{spec}")
    grams, kcal, protein, fat, carbs = nums[:5]
    fiber = nums[5] if len(nums) > 5 and nums[5] is not None else 0.0
    if grams is None or grams <= 0:
        raise CoachPalError("自定义条目的克数必须大于 0")
    return {
        "food_id": None,
        "food_name": name,
        "grams": grams,
        "kcal": round(kcal, 1),
        "protein": round(protein, 1),
        "fat": round(fat, 1),
        "carbs": round(carbs, 1),
        "fiber": round(fiber, 1),
        "source": "manual",
    }


def add_meal(
    con,
    meal_type: str,
    item_specs: list[str] | None = None,
    custom_specs: list[str] | None = None,
    *,
    date_str: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    kind = normalize_meal_type(meal_type)
    d = parse_date(date_str)
    resolved: list[dict[str, Any]] = []
    for spec in item_specs or []:
        name, grams = parse_item_spec(spec)
        food = resolve_food(con, name)
        macros = _scale(food, grams)
        resolved.append(
            {
                "food_id": food["id"],
                "food_name": food["name"],
                "grams": grams,
                "source": "db",
                **macros,
            }
        )
    for spec in custom_specs or []:
        resolved.append(_parse_custom(spec))
    if not resolved:
        raise CoachPalError(
            "没有要记录的食物",
            ["用 --item 食物名:克数（来自食物库），或用 --custom 手动录入"],
        )

    meal_id = con.execute(
        "INSERT INTO meals (date, meal_type, note, created_at) VALUES (?, ?, ?, ?)",
        (d, kind, note, now_iso()),
    ).lastrowid
    for item in resolved:
        con.execute(
            """
            INSERT INTO meal_items (meal_id, food_id, food_name, grams, kcal, protein, fat, carbs, fiber, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                meal_id,
                item["food_id"],
                item["food_name"],
                item["grams"],
                item["kcal"],
                item["protein"],
                item["fat"],
                item["carbs"],
                item["fiber"],
                item["source"],
            ),
        )
    con.commit()
    return meal_detail(con, meal_id)


def _totals(items: list[dict[str, Any]]) -> dict[str, float]:
    keys = ("kcal", "protein", "fat", "carbs", "fiber")
    return {k: round(sum(float(i.get(k) or 0) for i in items), 1) for k in keys}


def meal_detail(con, meal_id: int) -> dict[str, Any]:
    meal = con.execute("SELECT * FROM meals WHERE id = ?", (meal_id,)).fetchone()
    if not meal:
        raise CoachPalError(f"找不到饮食记录 #{meal_id}")
    items = [
        dict(r)
        for r in con.execute(
            "SELECT * FROM meal_items WHERE meal_id = ? ORDER BY id", (meal_id,)
        ).fetchall()
    ]
    return {
        "id": meal["id"],
        "date": meal["date"],
        "meal_type": meal["meal_type"],
        "meal_label": MEAL_LABELS.get(meal["meal_type"], meal["meal_type"]),
        "note": meal["note"],
        "items": items,
        "totals": _totals(items),
    }


def list_meals(con, date_str: str | None = None, days: int | None = None) -> list[dict[str, Any]]:
    sql = "SELECT id FROM meals"
    params: list[Any] = []
    if date_str:
        sql += " WHERE date = ?"
        params.append(parse_date(date_str))
    elif days is not None:
        sql += " WHERE date >= date('now', ?)"
        params.append(f"-{int(days)} days")
    sql += " ORDER BY date ASC, id ASC"
    return [meal_detail(con, r["id"]) for r in con.execute(sql, params).fetchall()]


def day_summary(con, date_str: str | None = None) -> dict[str, Any]:
    d = parse_date(date_str)
    meals = list_meals(con, date_str=d)
    items = [item for meal in meals for item in meal["items"]]
    totals = _totals(items)
    target_info = compute_targets(con)
    remaining = None
    if target_info.get("available"):
        remaining = {
            key: round(target_info["targets"][key] - totals[key], 1)
            for key in ("kcal", "protein", "fat", "carbs")
        }
    return {
        "date": d,
        "meals": meals,
        "totals": totals,
        "targets": target_info.get("targets"),
        "remaining": remaining,
        "target_note": None if target_info.get("available") else target_info.get("reason"),
    }


def delete_meal(con, meal_id: int) -> dict[str, Any]:
    meal = con.execute("SELECT * FROM meals WHERE id = ?", (meal_id,)).fetchone()
    if not meal:
        raise CoachPalError(f"找不到饮食记录 #{meal_id}")
    con.execute("DELETE FROM meals WHERE id = ?", (meal_id,))
    con.commit()
    return {"deleted": meal_id, "date": meal["date"], "meal_type": meal["meal_type"]}


# ---------------------------------------------------------------- 目标


ACTIVITY_FACTORS = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "active": 1.725,
    "very_active": 1.9,
}

GOAL_ADJUST = {"cut": -0.15, "maintain": 0.0, "bulk": 0.10}
PROTEIN_PER_KG = {"cut": 2.0, "maintain": 1.6, "bulk": 1.8}


def compute_targets(con) -> dict[str, Any]:
    profile = get_profile(con)
    latest = latest_metric(con)
    weight = latest.get("weight_kg") if latest else None
    height = profile.get("height_cm")
    missing = []
    if not height:
        missing.append("身高")
    if not weight:
        missing.append("体重")
    if missing:
        return {
            "available": False,
            "reason": "缺少" + "、".join(missing) + "，先运行 coachpal profile set / coachpal weight add",
            "missing": missing,
        }
    age = profile.get("age")
    assumptions: list[str] = []
    if age is None:
        age = 30
        assumptions.append("未记录出生日期，按 30 岁估算")
    sex = profile.get("sex") or "male"
    activity = normalize_activity(profile.get("activity_level"))
    goal = normalize_goal(profile.get("goal_type"))
    if sex == "male":
        bmr = 10 * weight + 6.25 * height - 5 * age + 5
    elif sex == "female":
        bmr = 10 * weight + 6.25 * height - 5 * age - 161
    else:
        bmr = 10 * weight + 6.25 * height - 5 * age - 78
    tdee = bmr * ACTIVITY_FACTORS[activity]
    adjust = GOAL_ADJUST[goal]
    raw_kcal = tdee * (1 + adjust)
    floor = 1500 if sex == "male" else 1200
    clamped = False
    if raw_kcal < floor:
        raw_kcal = floor
        clamped = True
        assumptions.append(f"按公式计算低于安全下限，已抬到 {floor} kcal")
    kcal = round(raw_kcal / 10) * 10
    protein = round(PROTEIN_PER_KG[goal] * weight)
    fat = round(kcal * 0.25 / 9)
    carbs = round(max(0.0, (kcal - protein * 4 - fat * 9) / 4))
    fiber = round(kcal / 1000 * 14)
    return {
        "available": True,
        "targets": {
            "kcal": kcal,
            "protein": protein,
            "fat": fat,
            "carbs": carbs,
            "fiber": fiber,
        },
        "bmr": r0(bmr),
        "tdee": r0(tdee),
        "goal_type": goal,
        "goal_label": {"cut": "减脂", "maintain": "维持", "bulk": "增肌"}[goal],
        "activity_level": activity,
        "activity_label": ACTIVITY_LABELS.get(activity, activity),
        "protein_per_kg": PROTEIN_PER_KG[goal],
        "assumptions": assumptions,
        "method": "Mifflin-St Jeor × 活动系数，按目标类型调整；蛋白质按体重系数",
    }


def daily_nutrition_series(con, days: int = 14) -> list[dict[str, Any]]:
    rows = con.execute(
        """
        SELECT m.date,
               ROUND(SUM(i.kcal), 1) AS kcal,
               ROUND(SUM(i.protein), 1) AS protein,
               ROUND(SUM(i.fat), 1) AS fat,
               ROUND(SUM(i.carbs), 1) AS carbs,
               ROUND(SUM(i.fiber), 1) AS fiber
        FROM meals m
        JOIN meal_items i ON i.meal_id = m.id
        WHERE m.date >= date('now', ?)
        GROUP BY m.date
        ORDER BY m.date
        """,
        (f"-{int(days)} days",),
    ).fetchall()
    return [dict(r) for r in rows]
