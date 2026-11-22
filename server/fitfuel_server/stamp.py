"""同步工具：行盖章、墓碑、LWW 推送。"""

from __future__ import annotations

import sqlite3
import uuid as uuid_mod

from .db import SYNC_TABLES, new_uuid, utcnow

# 各表按 uuid 引用父行的列（用于同步挂接）
PARENT_REF = {
    "meal_items": ("meal_uuid", "meals"),
    "workout_sets": ("workout_uuid", "workouts"),
}


def _row_to_dict(con: sqlite3.Connection, table: str, row) -> dict:
    keys = {r[1] for r in con.execute(f"PRAGMA table_info({table})").fetchall()}
    return {k: row[k] for k in row.keys() if k in keys}


def pull(con: sqlite3.Connection, since: str, tables: list[str]) -> dict:
    """返回 since 之后有变更的行（含墓碑），并先给本地新写入补 uuid。"""
    from .db import stamp_missing

    stamp_missing(con)
    result: dict[str, list[dict]] = {}
    for table in tables or list(SYNC_TABLES):
        if table not in SYNC_TABLES:
            continue
        rows = con.execute(
            f"SELECT * FROM {table} WHERE updated_at > ? ORDER BY updated_at", (since,)
        ).fetchall()
        result[table] = [_row_to_dict(con, table, r) for r in rows]
    tombs = con.execute(
        "SELECT uuid, table_name, deleted_at FROM tombstones WHERE deleted_at > ?",
        (since,),
    ).fetchall()
    result["_tombstones"] = [
        {"uuid": t["uuid"], "table": t["table_name"], "deleted_at": t["deleted_at"]}
        for t in tombs
    ]
    result["_server_time"] = utcnow()
    return result


def push_table(con: sqlite3.Connection, table: str, rows: list[dict]) -> list[dict]:
    """LWW 逐行 upsert：仅当远端 updated_at 更新时覆盖；新行直接插入。"""
    from .db import stamp_missing

    if table not in SYNC_TABLES:
        raise ValueError(f"unknown table {table}")
    results = []
    have = {r[1] for r in con.execute(f"PRAGMA table_info({table})").fetchall()}
    for row in rows:
        uid = row.get("uuid") or new_uuid()
        updated = row.get("updated_at") or utcnow()
        try:
            status = _push_one(con, table, row, uid, updated, have)
        except sqlite3.IntegrityError as exc:
            results.append({"uuid": uid, "status": "error", "detail": str(exc)})
            continue
        results.append({"uuid": uid, "status": status})
    stamp_missing(con)
    con.commit()
    return results


def _push_one(con: sqlite3.Connection, table: str, row: dict, uid: str,
              updated: str, have: set[str]) -> str:
    updated_at = updated
    existing = con.execute(
        f"SELECT id, updated_at FROM {table} WHERE uuid = ?", (uid,)
    ).fetchone()
    if existing and (existing["updated_at"] or "") >= updated_at:
        return "skipped"
    payload = {k: v for k, v in row.items() if k in have}
    payload["uuid"] = uid
    payload["updated_at"] = updated_at
    payload["deleted"] = int(row.get("deleted") or 0)
    if "created_at" in have and not payload.get("created_at"):
        payload["created_at"] = updated_at
    cols = list(payload.keys())
    if existing:
        assignment = ", ".join(f"{c}=?" for c in cols if c != "id")
        con.execute(
            f"UPDATE {table} SET {assignment} WHERE uuid = ?",
            [payload[c] for c in cols if c != "id"] + [uid],
        )
        return "updated"
    ph = ", ".join("?" for _ in cols)
    con.execute(
        f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({ph})",
        [payload[c] for c in cols],
    )
    return "inserted"


def record_tombstone(con: sqlite3.Connection, table: str, row_uuid: str) -> None:
    con.execute(
        "INSERT INTO tombstones (uuid, table_name, deleted_at) VALUES (?, ?, ?) "
        "ON CONFLICT(uuid) DO NOTHING",
        (row_uuid, table, utcnow()),
    )


def delete_by_id(con: sqlite3.Connection, table: str, row_id: int) -> str | None:
    row = con.execute(f"SELECT uuid FROM {table} WHERE id = ?", (row_id,)).fetchone()
    if not row:
        return None
    uid = row["uuid"] or new_uuid()
    con.execute(f"DELETE FROM {table} WHERE id = ?", (row_id,))
    record_tombstone(con, table, uid)
    con.commit()
    return uid
