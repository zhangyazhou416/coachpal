"""动作库导入与检索（数据源：exercises-dataset）。"""

from __future__ import annotations

import difflib
import json
from pathlib import Path
from typing import Any

from .db import meta_get, meta_set
from .util import CoachPalError, now_iso

# 常见动作的中文别名 -> exercises-dataset 中的搜索关键词（按顺序尝试，取最高分命中）
ZH_ALIASES: dict[str, tuple[str, ...]] = {
    "卧推": ("barbell bench press", "bench press"),
    "平板卧推": ("barbell bench press", "bench press"),
    "杠铃卧推": ("barbell bench press",),
    "上斜卧推": ("barbell incline bench press", "incline bench press"),
    "哑铃卧推": ("dumbbell bench press",),
    "哑铃上斜卧推": ("dumbbell incline bench press",),
    "深蹲": ("barbell squat", "squat"),
    "杠铃深蹲": ("barbell squat",),
    "颈前蹲": ("goblet squat",),
    "硬拉": ("barbell deadlift", "deadlift"),
    "杠铃硬拉": ("barbell deadlift",),
    "罗马尼亚硬拉": ("barbell romanian deadlift", "romanian deadlift"),
    "直腿硬拉": ("stiff leg deadlift",),
    "肩推": ("barbell shoulder press", "shoulder press"),
    "推举": ("barbell shoulder press", "shoulder press"),
    "站姿推举": ("barbell shoulder press", "standing barbell press"),
    "坐姿肩推": ("seated shoulder press",),
    "哑铃肩推": ("dumbbell shoulder press",),
    "引体向上": ("pull up",),
    "反手引体": ("chin up",),
    "高位下拉": ("lat pulldown",),
    "坐姿划船": ("seated row",),
    "划船": ("barbell row", "row"),
    "杠铃划船": ("barbell row",),
    "哑铃划船": ("dumbbell row",),
    "弯举": ("biceps curl",),
    "二头弯举": ("biceps curl",),
    "杠铃弯举": ("barbell biceps curl",),
    "锤式弯举": ("hammer curl",),
    "三头下压": ("triceps pushdown",),
    "绳索下压": ("rope triceps pushdown",),
    "臂屈伸": ("dip",),
    "双杠臂屈伸": ("dip",),
    "腿举": ("leg press",),
    "腿弯举": ("leg curl",),
    "腿屈伸": ("leg extension",),
    "侧平举": ("lateral raise",),
    "哑铃侧平举": ("dumbbell lateral raise",),
    "面拉": ("face pull",),
    "臀推": ("hip thrust",),
    "臀桥": ("glute bridge",),
    "保加利亚分腿蹲": ("split squat",),
    "分腿蹲": ("split squat",),
    "箭步蹲": ("lunge",),
    "俯卧撑": ("push up",),
    "卷腹": ("crunch",),
    "平板支撑": ("plank",),
    "悬垂举腿": ("hanging leg raise",),
    "俄罗斯转体": ("russian twist",),
    "登山跑": ("mountain climber",),
    "山羊挺身": ("back extension",),
    "站姿提踵": ("standing calf raise",),
    "耸肩": ("shrug",),
    "杠铃耸肩": ("barbell shrug",),
    "飞鸟": ("fly",),
    "哑铃飞鸟": ("dumbbell fly",),
    "绳索夹胸": ("cable crossover",),
    "农夫行走": ("farmer",),
    "倒立撑": ("handstand push",),
}

MUSCLE_ZH = {
    "abdominals": "腹肌",
    "abs": "腹肌",
    "abductors": "外展肌",
    "adductors": "内收肌",
    "biceps": "肱二头肌",
    "biceps femoris": "股二头肌",
    "brachialis": "肱肌",
    "calves": "小腿",
    "chest": "胸",
    "deltoids": "三角肌",
    "forearms": "前臂",
    "glutes": "臀",
    "hamstrings": "腘绳肌",
    "hip flexors": "屈髋肌",
    "lats": "背阔肌",
    "lower back": "下背",
    "middle back": "中背",
    "neck": "颈",
    "pectorals": "胸",
    "quadriceps": "股四头肌",
    "quads": "股四头肌",
    "rotator cuff": "肩袖",
    "serratus anterior": "前锯肌",
    "shoulders": "肩",
    "solues": "比目鱼肌",
    "splenius": "颈夹肌",
    "synergists": "协同肌",
    "tibialis anterior": "胫骨前肌",
    "traps": "斜方肌",
    "trapezius": "斜方肌",
    "triceps": "肱三头肌",
    "upper back": "上背",
    "wrist flexors": "腕屈肌",
}

EQUIPMENT_ZH = {
    "barbell": "杠铃",
    "dumbbell": "哑铃",
    "machine": "器械",
    "leverage machine": "器械",
    "smith machine": "史密斯机",
    "cable": "绳索",
    "cable machine": "绳索",
    "body only": "自重",
    "body weight": "自重",
    "none": "无器械",
    "bands": "弹力带",
    "band": "弹力带",
    "resistance band": "弹力带",
    "kettlebells": "壶铃",
    "kettlebell": "壶铃",
    "e-z curl bar": "曲杆",
    "ez barbell": "曲杆",
    "olympic barbell": "奥杆",
    "exercise ball": "瑞士球",
    "stability ball": "瑞士球",
    "bosu ball": "波速球",
    "medicine ball": "药球",
    "foam roll": "泡沫轴",
    "rope": "战绳",
    "sled": "雪橇车",
    "pull up bar": "单杠",
    "trap bar": "六角杠",
    "weighted": "负重",
    "wheel roller": "健腹轮",
    "other": "其他",
}

LEVEL_ZH = {"beginner": "新手", "intermediate": "进阶", "expert": "高级"}
CATEGORY_ZH = {
    "powerlifting": "力量举",
    "strength": "力量",
    "stretching": "拉伸",
    "cardio": "有氧",
    "olympic weightlifting": "举重",
    "strongman": "大力士",
    "plyometrics": "爆发力",
    "waist": "腰腹",
    "back": "背",
    "arms": "手臂",
    "chest": "胸",
    "legs": "腿",
    "shoulders": "肩",
    "full body": "全身",
}


def _resolve_exercises_json(path: str | Path) -> tuple[Path, Path | None]:
    root = Path(path).expanduser().resolve()
    if root.is_file():
        return root, None
    candidate = root / "data" / "exercises.json"
    if candidate.exists():
        return candidate, None
    alt = root / "exercises.json"
    if alt.exists():
        return alt, None
    raise CoachPalError(
        f"在 {root} 下找不到 data/exercises.json",
        ["用 --exercises-dir 指向 exercises-dataset 目录（含 data/exercises.json）"],
    )


def seed_exercises(con, exercises_dir: str | Path | None = None) -> dict[str, Any]:
    """从 exercises-dataset 导入动作库，并清理旧数据源的动作行。"""
    from .paths import exercises_dataset_dir

    root = exercises_dataset_dir(exercises_dir)
    if not root:
        raise CoachPalError(
            "找不到 exercises-dataset 数据集",
            [
                "把它放在项目同级目录，或 vendor/exercises-dataset，",
                "或用 --exercises-dir 指向含 data/exercises.json 的目录",
            ],
        )
    json_path = root / "data" / "exercises.json"
    data = json.loads(json_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise CoachPalError(f"{json_path} 格式无法识别（应为动作数组）")

    count = 0
    for item in data:
        ext_id = f"gd_{item.get('id')}"
        name = item.get("name")
        if not item.get("id") or not name:
            continue
        steps = item.get("instruction_steps") or {}
        gif = root / item.get("gif_url", "")
        thumb = root / item.get("image", "")
        con.execute(
            """
            INSERT INTO exercises (ext_id, name, name_zh, force, level, mechanic, equipment,
                                   primary_muscles, secondary_muscles, category, instructions,
                                   images, dataset_id, gif_path, thumb_path,
                                   instructions_zh, steps_zh)
            VALUES (?, ?, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(ext_id) DO UPDATE SET
                name = excluded.name,
                equipment = excluded.equipment,
                primary_muscles = excluded.primary_muscles,
                secondary_muscles = excluded.secondary_muscles,
                category = excluded.category,
                instructions = excluded.instructions,
                dataset_id = excluded.dataset_id,
                gif_path = excluded.gif_path,
                thumb_path = excluded.thumb_path,
                instructions_zh = excluded.instructions_zh,
                steps_zh = excluded.steps_zh
            """,
            (
                ext_id,
                name,
                item.get("equipment"),
                json.dumps([item.get("target")] if item.get("target") else [], ensure_ascii=False),
                json.dumps(item.get("secondary_muscles") or [], ensure_ascii=False),
                item.get("body_part") or item.get("category"),
                json.dumps(steps.get("en") or [], ensure_ascii=False),
                "[]",
                item.get("id"),
                str(gif) if gif.exists() else None,
                str(thumb) if thumb.exists() else None,
                (steps.get("zh") or [None])[0] if steps.get("zh") else None,
                json.dumps(steps.get("zh") or [], ensure_ascii=False),
            ),
        )
        count += 1

    # 清理旧数据源（free-exercise-db）的动作行；训练历史的动作名文本保留，仅断开外键
    con.execute(
        "UPDATE workout_sets SET exercise_id = NULL WHERE exercise_id IN "
        "(SELECT id FROM exercises WHERE ext_id IS NULL OR ext_id NOT LIKE 'gd%')"
    )
    con.execute("DELETE FROM exercises WHERE ext_id IS NULL OR ext_id NOT LIKE 'gd%'")

    meta_set(con, "exercises_source", str(json_path))
    meta_set(con, "exercises_dataset_dir", str(root))
    meta_set(con, "exercises_seeded_at", now_iso())
    con.execute("DELETE FROM meta WHERE key = 'exercise_images_dir'")
    con.commit()
    total = con.execute("SELECT COUNT(*) AS n FROM exercises").fetchone()["n"]
    with_gif = con.execute(
        "SELECT COUNT(*) AS n FROM exercises WHERE gif_path IS NOT NULL"
    ).fetchone()["n"]
    with_zh = con.execute(
        "SELECT COUNT(*) AS n FROM exercises WHERE instructions_zh IS NOT NULL"
    ).fetchone()["n"]
    return {
        "source": str(json_path),
        "upserted": count,
        "exercises_total": total,
        "with_gif": with_gif,
        "with_chinese_name": with_zh,
    }


def _loads(value: str | None) -> list:
    if not value:
        return []
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return []


def _row_summary(row) -> dict[str, Any]:
    primary = _loads(row["primary_muscles"])
    return {
        "id": row["id"],
        "ext_id": row["ext_id"],
        "name": row["name"],
        "name_zh": row["name_zh"],
        "level": row["level"],
        "level_zh": LEVEL_ZH.get(row["level"], row["level"]),
        "equipment": row["equipment"],
        "equipment_zh": EQUIPMENT_ZH.get(row["equipment"], row["equipment"]),
        "mechanic": row["mechanic"],
        "primary_muscles": primary,
        "primary_muscles_zh": [MUSCLE_ZH.get(m, m) for m in primary],
        "category": row["category"],
        "category_zh": CATEGORY_ZH.get(row["category"], row["category"]),
    }


def _haystack(row) -> str:
    parts = [row["name"] or "", row["name_zh"] or "", row["ext_id"] or ""]
    for m in _loads(row["primary_muscles"]) + _loads(row["secondary_muscles"]):
        parts.append(m)
        parts.append(MUSCLE_ZH.get(m, ""))
    eq = row["equipment"]
    parts.append(eq or "")
    parts.append(EQUIPMENT_ZH.get(eq, ""))
    parts.append(row["level"] or "")
    parts.append(LEVEL_ZH.get(row["level"], ""))
    parts.append(row["category"] or "")
    parts.append(CATEGORY_ZH.get(row["category"], ""))
    return " ".join(p for p in parts if p).lower()


def search_exercises(con, query: str, limit: int = 15) -> list[dict[str, Any]]:
    q = (query or "").strip()
    if not q:
        raise CoachPalError("请输入动作名称、肌肉或器械关键词")
    if con.execute("SELECT COUNT(*) AS n FROM exercises").fetchone()["n"] == 0:
        raise CoachPalError(
            "动作库还是空的",
            ["先运行：coachpal seed --exercises-dir ../free-exercise-db"],
        )
    ql = q.lower()
    tokens = [t for t in ql.replace(",", " ").split() if t]
    rows = con.execute("SELECT * FROM exercises").fetchall()
    scored: list[tuple[float, dict[str, Any]]] = []
    for row in rows:
        name = (row["name"] or "").lower()
        name_zh = (row["name_zh"] or "").lower()
        hay = _haystack(row)
        score = 0.0
        if ql == (row["ext_id"] or "").lower() or ql == name:
            score = 1000.0
        elif name_zh and ql in [part.strip() for part in name_zh.split("/")]:
            score = 950.0
        elif ql in name:
            score = 780.0 - min(len(name) - len(ql), 60) * 0.5
        elif all(t in hay for t in tokens):
            score = 640.0 + min(len(tokens), 4) * 10
        else:
            score = difflib.SequenceMatcher(None, ql, name).ratio() * 420.0
        if score < 250:
            continue
        item = _row_summary(row)
        item["match_score"] = round(score, 1)
        scored.append((score, item))
    scored.sort(key=lambda x: (-x[0], x[1]["name"] or ""))
    return [item for _, item in scored[:limit]]


def resolve_exercise(con, query: str) -> dict[str, Any]:
    q = query.strip()
    row = con.execute(
        "SELECT * FROM exercises WHERE lower(ext_id) = lower(?) OR lower(name) = lower(?)",
        (q, q),
    ).fetchone()
    if row:
        return _row_summary(row)
    # 中文别名 → 英文搜索关键词，逐个尝试取最高分命中
    keywords = ZH_ALIASES.get(q) or ZH_ALIASES.get(q.lower())
    if keywords:
        for kw in keywords:
            hits = search_exercises(con, kw, limit=3)
            if hits and hits[0]["match_score"] >= 600:
                return hits[0]
    matches = search_exercises(con, q, limit=8)
    if not matches:
        raise CoachPalError(
            f"动作库里找不到「{q}」",
            ["换一个更通用的名称，或直接写英文名/动作 ID"],
        )
    top = matches[0]
    margin = top["match_score"] - (matches[1]["match_score"] if len(matches) > 1 else 0)
    if top["match_score"] >= 900 or (top["match_score"] >= 700 and margin >= 40):
        return top
    candidates = "\n".join(
        f"  {m['name']}（{m['name_zh'] or '无中文名'}，{m['equipment_zh'] or '未知器械'}）"
        for m in matches[:5]
    )
    raise CoachPalError(
        f"「{q}」匹配到多个动作，无法自动确定：\n{candidates}",
        [f"先运行：coachpal exercise search {q}，再用完整英文名或动作 ID 记录"],
    )


def exercise_detail(con, query: str) -> dict[str, Any]:
    match = resolve_exercise(con, query)
    row = con.execute("SELECT * FROM exercises WHERE id = ?", (match["id"],)).fetchone()
    data = _row_summary(row)
    data["force"] = row["force"]
    data["mechanic"] = row["mechanic"]
    data["secondary_muscles"] = _loads(row["secondary_muscles"])
    data["secondary_muscles_zh"] = [
        MUSCLE_ZH.get(m, m) for m in data["secondary_muscles"]
    ]
    data["instructions"] = _loads(row["instructions"])
    data["steps_zh"] = _loads(row["steps_zh"])
    data["instructions_zh"] = row["instructions_zh"]
    images = _loads(row["images"])
    images_dir = meta_get(con, "exercise_images_dir")
    resolved: list[Any] = []
    gif = row["gif_path"]
    thumb = row["thumb_path"]
    if gif and Path(gif).exists():
        resolved.append({"relative": Path(gif).name, "path": gif, "style": "gif"})
    if thumb and Path(thumb).exists():
        resolved.append({"relative": Path(thumb).name, "path": thumb, "style": "thumb"})
    for img in images:
        if images_dir and (Path(images_dir) / img).exists():
            resolved.append(
                {"relative": img, "path": str(Path(images_dir) / img), "style": "photo"}
            )
        else:
            resolved.append(img)
    data["images"] = resolved
    return data
