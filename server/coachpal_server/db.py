"""服务端数据库：coachpal schema + 同步列（uuid/updated_at/deleted）。

复用 coachpal 包的表结构与领域计算函数（它们按列名访问 sqlite 行），
在此基础上追加同步所需列，并保证旧行在同步时补齐 uuid。
"""

from __future__ import annotations

import sqlite3
import uuid as uuid_mod
from datetime import datetime, timezone
from pathlib import Path

from coachpal.db import SCHEMA

from .config import db_path  # noqa: F401  (延迟使用，避免循环导入困扰)

SYNC_TABLES = (
    "body_metrics",
    "measurements",
    "goals",
    "strength_logs",
    "meals",
    "meal_items",
    "workouts",
    "workout_sets",
)

_EXTRA_COLUMNS = {
    "body_metrics": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "measurements": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "goals": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "strength_logs": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "meals": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "meal_items": (("uuid", "TEXT"), ("updated_at", "TEXT"),
                   ("deleted", "INTEGER DEFAULT 0"), ("meal_uuid", "TEXT")),
    "workouts": (("uuid", "TEXT"), ("updated_at", "TEXT"), ("deleted", "INTEGER DEFAULT 0")),
    "workout_sets": (("uuid", "TEXT"), ("updated_at", "TEXT"),
                     ("deleted", "INTEGER DEFAULT 0"), ("workout_uuid", "TEXT")),
}


def utcnow() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def connect(path: str | Path | None = None) -> sqlite3.Connection:
    target = Path(path) if path else db_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(target, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA busy_timeout = 5000")
    con.executescript(SCHEMA)
    for table, cols in _EXTRA_COLUMNS.items():
        have = {r[1] for r in con.execute(f"PRAGMA table_info({table})").fetchall()}
        for name, ddl in cols:
            if name not in have:
                con.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")
        # uuid 唯一性用部分唯一索引实现（ALTER 无法直接加 UNIQUE 列）
        con.execute(
            f"CREATE UNIQUE INDEX IF NOT EXISTS idx_{table}_uuid "
            f"ON {table}(uuid) WHERE uuid IS NOT NULL"
        )
    con.execute(
        "CREATE TABLE IF NOT EXISTS tombstones ("
        " uuid TEXT PRIMARY KEY, table_name TEXT NOT NULL, deleted_at TEXT NOT NULL)"
    )
    con.execute(
        "CREATE TABLE IF NOT EXISTS tokens ("
        " token TEXT PRIMARY KEY, created_at TEXT NOT NULL)"
    )
    con.execute(
        "CREATE TABLE IF NOT EXISTS huawei_account ("
        " union_id TEXT PRIMARY KEY, display_name TEXT, bound_at TEXT NOT NULL)"
    )
    # 与 coachpal.db.connect 一致：保证 profile id=1 行存在（set_profile 靠 UPDATE 它）
    con.execute(
        "INSERT OR IGNORE INTO profile (id, updated_at) VALUES (1, ?)", (utcnow(),)
    )
    con.commit()
    return con


def stamp_missing(con: sqlite3.Connection) -> None:
    """给缺 uuid/updated_at 的行盖章（服务端本地产生的写入走领域函数，不带同步列）。"""
    now = utcnow()
    for table in SYNC_TABLES:
        rows = con.execute(
            f"SELECT id FROM {table} WHERE uuid IS NULL OR updated_at IS NULL"
        ).fetchall()
        for r in rows:
            con.execute(
                f"UPDATE {table} SET uuid=?, updated_at=?, deleted=COALESCE(deleted, 0) "
                f"WHERE id=?",
                (uuid_mod.uuid4().hex, now, r["id"]),
            )
    # 子表补父 uuid
    con.execute(
        "UPDATE meal_items SET meal_uuid = (SELECT uuid FROM meals WHERE meals.id = meal_items.meal_id) "
        "WHERE meal_uuid IS NULL"
    )
    con.execute(
        "UPDATE workout_sets SET workout_uuid = "
        "(SELECT uuid FROM workouts WHERE workouts.id = workout_sets.workout_id) "
        "WHERE workout_uuid IS NULL"
    )
    con.commit()


def new_uuid() -> str:
    return uuid_mod.uuid4().hex
