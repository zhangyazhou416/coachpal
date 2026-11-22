"""服务端配置：数据目录、端口、密码引导。"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


def data_dir() -> Path:
    env = os.environ.get("FITFUEL_SERVER_DATA")
    if env:
        p = Path(env).expanduser().resolve()
    else:
        p = PROJECT_ROOT / "server" / "data"
    p.mkdir(parents=True, exist_ok=True)
    return p


def db_path() -> Path:
    return data_dir() / "fitfuel-server.db"


def port() -> int:
    return int(os.environ.get("FITFUEL_SERVER_PORT", "8321"))


def media_dir() -> Path | None:
    """动作 GIF/缩略图目录：优先项目内 vendor/exercises-dataset。"""
    for p in (
        PROJECT_ROOT / "vendor" / "exercises-dataset",
        PROJECT_ROOT.parent / "exercises-dataset",
    ):
        if (p / "data" / "exercises.json").exists():
            return p
    return None


def password_file() -> Path:
    return data_dir() / "server_password"


def bootstrap_password() -> str:
    """首次启动生成随机密码写入 server/data/server_password；已存在则复用。"""
    pf = password_file()
    if pf.exists():
        return pf.read_text(encoding="utf-8").strip()
    pw = os.environ.get("FITFUEL_SERVER_PASSWORD") or secrets.token_urlsafe(12)
    pf.write_text(pw, encoding="utf-8")
    try:
        os.chmod(pf, 0o600)
    except OSError:
        pass
    return pw
