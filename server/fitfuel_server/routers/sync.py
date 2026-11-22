"""同步路由：pull / push（LWW）。"""

from __future__ import annotations

import sqlite3

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import utcnow
from ..deps import get_con, require_token
from ..stamp import pull as pull_rows
from ..stamp import push_table

router = APIRouter(prefix="/api/sync", tags=["sync"])


class PullBody(BaseModel):
    since: str
    tables: list[str] | None = None


class PushBody(BaseModel):
    rows: dict[str, list[dict]]


@router.post("/pull", dependencies=[Depends(require_token)])
def pull(body: PullBody, con: sqlite3.Connection = Depends(get_con)):
    return pull_rows(con, body.since, body.tables)


@router.post("/push", dependencies=[Depends(require_token)])
def push(body: PushBody, con: sqlite3.Connection = Depends(get_con)):
    results: dict[str, list[dict]] = {}
    for table, rows in body.rows.items():
        results[table] = push_table(con, table, rows)
    return {"ok": True, "results": results, "server_time": utcnow()}
