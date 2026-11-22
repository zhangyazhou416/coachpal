"""共享依赖：数据库连接与鉴权。"""

from __future__ import annotations

import sqlite3
from functools import lru_cache

from fastapi import Depends, Header, HTTPException

from . import auth as auth_mod
from .db import connect


@lru_cache(maxsize=1)
def get_con() -> sqlite3.Connection:
    con = connect()
    return con


def require_token(
    con: sqlite3.Connection = Depends(get_con),
    authorization: str | None = Header(default=None),
    x_token: str | None = Header(default=None),
) -> None:
    token = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    token = token or x_token
    if not auth_mod.verify(con, token):
        raise HTTPException(status_code=401, detail="未登录或 token 无效")
