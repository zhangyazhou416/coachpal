"""服务端配置：数据目录、端口、密码引导、LLM 配置。"""

from __future__ import annotations

import json
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


def llm_config() -> dict:
    """LLM 配置：OpenAI 兼容接口。

    优先级：环境变量 > server/data/llm_config.json。
    键：base_url（如 https://dashscope.aliyuncs.com/compatible-mode/v1）、
        api_key、model（如 qwen-plus / moonshot-v1-8k / deepseek-chat）。
    """
    cfg = {"base_url": None, "api_key": None, "model": None}
    f = data_dir() / "llm_config.json"
    if f.exists():
        try:
            cfg.update(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    env_map = {
        "base_url": "FITFUEL_LLM_BASE_URL",
        "api_key": "FITFUEL_LLM_API_KEY",
        "model": "FITFUEL_LLM_MODEL",
    }
    for key, env in env_map.items():
        v = os.environ.get(env)
        if v:
            cfg[key] = v
    cfg["configured"] = bool(cfg.get("base_url") and cfg.get("api_key") and cfg.get("model"))
    return cfg
