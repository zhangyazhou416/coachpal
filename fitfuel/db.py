"""SQLite 连接与表结构。"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from .paths import db_path, ensure_parent
from .util import now_iso

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS profile (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    sex TEXT NOT NULL DEFAULT 'male' CHECK (sex IN ('male', 'female', 'other')),
    birth_date TEXT,
    height_cm REAL,
    activity_level TEXT NOT NULL DEFAULT 'moderate',
    goal_type TEXT NOT NULL DEFAULT 'maintain',
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS body_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL UNIQUE,
    weight_kg REAL,
    body_fat_pct REAL,
    skeletal_muscle_kg REAL,
    note TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS measurements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    site TEXT NOT NULL,
    value_cm REAL NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    UNIQUE (date, site)
);

CREATE TABLE IF NOT EXISTS goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    target_value REAL NOT NULL,
    unit TEXT,
    baseline_value REAL,
    target_date TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    note TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS strength_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    lift TEXT NOT NULL,
    weight_kg REAL NOT NULL,
    reps INTEGER NOT NULL,
    rpe REAL,
    estimated_1rm REAL NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS foods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE,
    name TEXT NOT NULL,
    name_en TEXT,
    category TEXT,
    edible_pct REAL,
    kcal REAL,
    protein REAL,
    fat REAL,
    carbs REAL,
    fiber REAL,
    sodium_mg REAL,
    calcium_mg REAL,
    iron_mg REAL,
    gi REAL,
    source TEXT
);
CREATE INDEX IF NOT EXISTS idx_foods_name ON foods(name);
CREATE INDEX IF NOT EXISTS idx_foods_category ON foods(category);

CREATE TABLE IF NOT EXISTS gi_foods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    food_group TEXT,
    name TEXT NOT NULL,
    gi REAL
);

CREATE TABLE IF NOT EXISTS meals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    meal_type TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_meals_date ON meals(date);

CREATE TABLE IF NOT EXISTS meal_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meal_id INTEGER NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
    food_id INTEGER,
    food_name TEXT NOT NULL,
    grams REAL NOT NULL,
    kcal REAL NOT NULL,
    protein REAL NOT NULL,
    fat REAL NOT NULL,
    carbs REAL NOT NULL,
    fiber REAL,
    source TEXT NOT NULL DEFAULT 'db'
);
CREATE INDEX IF NOT EXISTS idx_meal_items_meal ON meal_items(meal_id);

CREATE TABLE IF NOT EXISTS exercises (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ext_id TEXT UNIQUE,
    name TEXT NOT NULL,
    name_zh TEXT,
    force TEXT,
    level TEXT,
    mechanic TEXT,
    equipment TEXT,
    primary_muscles TEXT,
    secondary_muscles TEXT,
    category TEXT,
    instructions TEXT,
    images TEXT,
    dataset_id TEXT,
    gif_path TEXT,
    thumb_path TEXT,
    instructions_zh TEXT,
    steps_zh TEXT
);
CREATE INDEX IF NOT EXISTS idx_exercises_name ON exercises(name);

CREATE TABLE IF NOT EXISTS workouts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    name TEXT,
    note TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts(date);

CREATE TABLE IF NOT EXISTS workout_sets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id INTEGER,
    exercise_name TEXT NOT NULL,
    set_no INTEGER,
    weight_kg REAL,
    reps INTEGER,
    rpe REAL,
    note TEXT
);
CREATE INDEX IF NOT EXISTS idx_workout_sets_workout ON workout_sets(workout_id);
"""


def connect(path: str | Path | None = None) -> sqlite3.Connection:
    target = Path(path) if path else db_path()
    ensure_parent(target)
    con = sqlite3.connect(target)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript(SCHEMA)
    _migrate(con)
    con.execute(
        "INSERT OR IGNORE INTO profile (id, updated_at) VALUES (1, ?)", (now_iso(),)
    )
    version = con.execute("PRAGMA user_version").fetchone()[0]
    if version < SCHEMA_VERSION:
        con.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    con.commit()
    return con


# 旧库升级：为 exercises 表补充 exercises-dataset 相关列（幂等）
_EXERCISE_EXTRA_COLUMNS = (
    ("dataset_id", "TEXT"),
    ("gif_path", "TEXT"),
    ("thumb_path", "TEXT"),
    ("instructions_zh", "TEXT"),
    ("steps_zh", "TEXT"),
)


def _migrate(con: sqlite3.Connection) -> None:
    cols = {r[1] for r in con.execute("PRAGMA table_info(exercises)").fetchall()}
    for col, ddl in _EXERCISE_EXTRA_COLUMNS:
        if col and col not in cols:
            con.execute(f"ALTER TABLE exercises ADD COLUMN {col} {ddl}")


def meta_get(con: sqlite3.Connection, key: str, default: str | None = None) -> str | None:
    row = con.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default


def meta_set(con: sqlite3.Connection, key: str, value: str) -> None:
    con.execute(
        "INSERT INTO meta (key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, value),
    )


def row_to_dict(row: sqlite3.Row | None) -> dict | None:
    return dict(row) if row is not None else None


def rows_to_dicts(rows) -> list[dict]:
    return [dict(r) for r in rows]
