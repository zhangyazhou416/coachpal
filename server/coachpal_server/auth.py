"""认证：华为账号登录（Authorization Code → 业务 token）；密码登录保留兜底。

单主用户自部署：华为账号登录首次成功即绑定 UnionID，之后仅该华为账号可登录。
"""

from __future__ import annotations

import base64
import binascii
import hmac
import json
import secrets
import sqlite3
import time

import httpx

from .config import bootstrap_password, huawei_oauth_config
from .db import connect, utcnow

HUAWEI_TOKEN_URL = "https://oauth-login.cloud.huawei.com/oauth2/v3/token"


def _issue_token(con: sqlite3.Connection) -> str:
    token = secrets.token_urlsafe(32)
    con.execute(
        "INSERT INTO tokens (token, created_at) VALUES (?, ?)", (token, utcnow())
    )
    con.commit()
    return token


def login(con: sqlite3.Connection, password: str) -> str | None:
    expected = bootstrap_password()
    if not hmac.compare_digest(password, expected):
        return None
    return _issue_token(con)


def verify(con: sqlite3.Connection, token: str | None) -> bool:
    if not token:
        return False
    row = con.execute("SELECT 1 FROM tokens WHERE token = ?", (token,)).fetchone()
    return row is not None


def _decode_id_token_payload(id_token: str) -> dict:
    """解析 ID Token（JWT）payload。

    不做签名校验：id_token 由本服务端直连华为服务器换取（TLS 可信链），
    非客户端传入，此处只做字段与有效期校验。
    """
    parts = id_token.split(".")
    if len(parts) != 3:
        raise ValueError("ID Token 格式错误")
    pad = "=" * (-len(parts[1]) % 4)
    try:
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + pad))
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("ID Token 解析失败") from exc
    if not isinstance(payload, dict):
        raise ValueError("ID Token payload 非法")
    return payload


def huawei_login(con: sqlite3.Connection, authorization_code: str) -> tuple[str, str]:
    """Authorization Code 换华为凭证，解析 ID Token 取 UnionID，签发业务 token。

    返回 (业务 token, union_id)。校验失败抛 ValueError（调用方转 401/400），
    华为服务不可达抛 httpx.HTTPError（调用方转 502）。
    """
    code = (authorization_code or "").strip()
    if not code:
        raise ValueError("缺少授权码")
    cfg = huawei_oauth_config()
    if not cfg["configured"]:
        raise RuntimeError(
            "服务端未配置华为账号 OAuth。设置 server/data/huawei_oauth.json"
            "（client_id/client_secret）或对应环境变量后重启。"
        )
    resp = httpx.post(
        HUAWEI_TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "client_id": cfg["client_id"],
            "client_secret": cfg["client_secret"],
        },
        timeout=10.0,
    )
    if resp.status_code != 200:
        raise ValueError(f"授权码换凭证失败（HTTP {resp.status_code}）")
    data = resp.json()
    id_token = data.get("id_token") or ""
    if not id_token:
        raise ValueError("华为响应缺少 id_token")
    payload = _decode_id_token_payload(id_token)
    if payload.get("aud") != cfg["client_id"]:
        raise ValueError("ID Token 校验失败（aud 不匹配）")
    exp = payload.get("exp")
    if not isinstance(exp, (int, float)) or exp < time.time():
        raise ValueError("ID Token 已过期")
    union_id = payload.get("sub") or ""
    if not union_id:
        raise ValueError("ID Token 缺少 UnionID")
    row = con.execute("SELECT union_id FROM huawei_account LIMIT 1").fetchone()
    if row is None:
        con.execute(
            "INSERT INTO huawei_account (union_id, display_name, bound_at) VALUES (?, ?, ?)",
            (union_id, payload.get("display_name"), utcnow()),
        )
        con.commit()
    elif row["union_id"] != union_id:
        raise ValueError("该华为账号未绑定本服务")
    return _issue_token(con), union_id
