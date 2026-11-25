#!/usr/bin/env python3
"""导出鸿蒙 App 需要的参考数据资产。

从 vendor/ 生成（写入 entry 模块 rawfile，随 HAP 打包）：
  app/entry/src/main/resources/rawfile/foods.json       1677 条食物（精简字段）
  app/entry/src/main/resources/rawfile/exercises.json   1324 个动作（含 gif/thumb 相对路径与中英文步骤）
  app/entry/src/main/resources/rawfile/meta.json        版本号与统计
缩略图不内置（12MB），App 首次同步时按需从服务器 /media 拉取并缓存。
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from coachpal.nutrition import _find_food_dir, _load_gi, _norm_name  # noqa: E402

OUT = ROOT / "app" / "entry" / "src" / "main" / "resources" / "rawfile"


def export_foods() -> list[dict]:
    foods_dir = _find_food_dir(ROOT / "vendor" / "foods")
    gi_map = _load_gi(ROOT / "vendor" / "foods" / "glycemic_index_of_foods.json")
    items = []
    seen_codes = set()
    for f in sorted(foods_dir.glob("merged_*.json")):
        category = f.stem.removeprefix("merged_")
        for it in json.loads(f.read_text(encoding="utf-8")):
            code = str(it.get("foodCode") or "").strip()
            if code and code in seen_codes:
                continue
            if code:
                seen_codes.add(code)
            name = str(it.get("foodName") or "").strip()
            if not name:
                continue

            def num(v):
                try:
                    s = str(v).strip()
                    if s in ("", "—", "-", "Tr", "tr"):
                        return None
                    return float(s)
                except (ValueError, TypeError):
                    return None

            items.append({
                "code": code or None,
                "name": name,
                "en": (str(it.get("englishName") or "").strip() or None),
                "cat": category,
                "kcal": num(it.get("energyKCal")),
                "p": num(it.get("protein")),
                "f": num(it.get("fat")),
                "c": num(it.get("CHO")),
                "fiber": num(it.get("dietaryFiber")),
                "gi": gi_map.get(_norm_name(name)),
            })
    return items


def export_exercises(dataset: Path) -> list[dict]:
    data = json.loads((dataset / "data" / "exercises.json").read_text(encoding="utf-8"))
    items = []
    for e in data:
        steps = e.get("instruction_steps") or {}
        items.append({
            "id": f"gd_{e['id']}",
            "dsId": e["id"],
            "name": e["name"],
            "cat": e.get("body_part"),
            "equip": e.get("equipment"),
            "target": e.get("target"),
            "secondary": e.get("secondary_muscles") or [],
            "stepsEn": steps.get("en") or [],
            "stepsZh": steps.get("zh") or [],
            "gif": e.get("gif_url"),
            "thumb": e.get("image"),
        })
    return items


def main() -> int:
    dataset = ROOT / "vendor" / "exercises-dataset"
    if not (dataset / "data" / "exercises.json").exists():
        print("缺少 vendor/exercises-dataset", file=sys.stderr)
        return 2
    OUT.mkdir(parents=True, exist_ok=True)

    foods = export_foods()
    exercises = export_exercises(dataset)
    meta = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "foods": len(foods),
        "exercises": len(exercises),
        "protocol": 1,
    }
    (OUT / "foods.json").write_text(
        json.dumps(foods, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    (OUT / "exercises.json").write_text(
        json.dumps(exercises, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    (OUT / "meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    for name in ("foods.json", "exercises.json"):
        size = (OUT / name).stat().st_size / 1024
        print(f"{name}: {size:.0f} KB")
    print(f"meta: {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
