"""简单认证：密码 → token（个人自部署，单主用户）。"""

from __future__ import annotations

import hmac
import secrets
import sqlite3

from .config import bootstrap_password
from .db import connect, utcnow


def login(con: sqlite3.Connection, password: str) -> str | None:
    expected = bootstrap_password()
    if not hmac.compare_digest(password, expected):
        return None
    token = secrets.token_urlsafe(32)
    con.execute(
        "INSERT INTO tokens (token, created_at) VALUES (?, ?)", (token, utcnow())
    )
    con.commit()
    return token


def verify(con: sqlite3.Connection, token: str | None) -> bool:
    if not token:
        return False
    row = con.execute("SELECT 1 FROM tokens WHERE token = ?", (token,)).fetchone()
    return row is not None
