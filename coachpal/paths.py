"""路径解析。

数据库默认放在项目根的 data/coachpal.db。
可用环境变量 COACHPAL_DB 指定完整路径，或用 COACHPAL_HOME 指定数据目录。
"""

from __future__ import annotations

import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def home_dir() -> Path:
    env = os.environ.get("COACHPAL_HOME")
    if env:
        return Path(env).expanduser().resolve()
    return PROJECT_ROOT / "data"


def db_path() -> Path:
    env = os.environ.get("COACHPAL_DB")
    if env:
        return Path(env).expanduser().resolve()
    return home_dir() / "coachpal.db"


def dashboard_path() -> Path:
    return home_dir() / "dashboard.html"


def cartoon_images_dir() -> Path:
    """卡通示意图目录（tools/gen_cartoon_images.py 的输出）。"""
    return PROJECT_ROOT / "vendor" / "exercises_cartoon"


def ensure_parent(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def sibling_data_dirs() -> dict[str, Path]:
    """默认数据集位置：项目根的同级目录（用户当前的 Desktop/fitness 布局）。"""
    base = PROJECT_ROOT.parent
    return {
        "foods": base / "china-food-composition-data",
        "exercises": base / "free-exercise-db",
        "gi": base
        / "china-food-composition-data"
        / "json_gi_of_foods"
        / "glycemic_index_of_foods.json",
    }


def vendor_data_dirs() -> dict[str, Path]:
    """项目内嵌数据：vendor/ 目录。"""
    vendor = PROJECT_ROOT / "vendor"
    return {
        "foods": vendor / "foods",
        "gi": vendor / "foods" / "glycemic_index_of_foods.json",
    }


def default_sources() -> dict[str, Path]:
    """seed 的默认数据源：优先项目内嵌 vendor/，缺失时回退到同级数据仓库。"""
    vendor = vendor_data_dirs()
    sources = dict(vendor)
    if not any(sources["foods"].glob("merged_*.json")):
        sources["foods"] = sibling_data_dirs()["foods"]
    if not sources["gi"].exists():
        sources["gi"] = sibling_data_dirs()["gi"]
    return sources


def exercises_dataset_dir(explicit: str | Path | None = None) -> Path | None:
    """exercises-dataset（GIF 动画数据集）位置：显式参数 > 项目内 vendor/ > 同级目录。"""
    if explicit:
        p = Path(explicit).expanduser().resolve()
        return p if (p / "data" / "exercises.json").exists() else None
    for p in (PROJECT_ROOT / "vendor" / "exercises-dataset", PROJECT_ROOT.parent / "exercises-dataset"):
        if (p / "data" / "exercises.json").exists():
            return p
    return None
