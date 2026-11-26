"""服务端配置：数据目录、端口、密码引导、LLM 配置。"""

from __future__ import annotations

import json
import os
import secrets
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


def data_dir() -> Path:
    env = os.environ.get("COACHPAL_SERVER_DATA")
    if env:
        p = Path(env).expanduser().resolve()
    else:
        p = PROJECT_ROOT / "server" / "data"
    p.mkdir(parents=True, exist_ok=True)
    return p


def db_path() -> Path:
    return data_dir() / "coachpal-server.db"


def port() -> int:
    return int(os.environ.get("COACHPAL_SERVER_PORT", "8321"))


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
    pw = os.environ.get("COACHPAL_SERVER_PASSWORD") or secrets.token_urlsafe(12)
    pf.write_text(pw, encoding="utf-8")
    try:
        os.chmod(pf, 0o600)
    except OSError:
        pass
    return pw


def huawei_oauth_config() -> dict:
    """华为账号 OAuth 配置（Account Kit 服务端换凭证用）。

    优先级：环境变量 > server/data/huawei_oauth.json。
    键：client_id、client_secret（AGC「项目设置 > 常规 > 应用」的
    OAuth 2.0 客户端 ID / 密钥）。
    """
    cfg = {"client_id": None, "client_secret": None}
    f = data_dir() / "huawei_oauth.json"
    if f.exists():
        try:
            cfg.update(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    env_map = {
        "client_id": "COACHPAL_HUAWEI_CLIENT_ID",
        "client_secret": "COACHPAL_HUAWEI_CLIENT_SECRET",
    }
    for key, env in env_map.items():
        v = os.environ.get(env)
        if v:
            cfg[key] = v
    cfg["configured"] = bool(cfg.get("client_id") and cfg.get("client_secret"))
    return cfg


LLM_ENV_MAP = {
    "base_url": "COACHPAL_LLM_BASE_URL",
    "api_key": "COACHPAL_LLM_API_KEY",
    "model": "COACHPAL_LLM_MODEL",
}


def llm_config() -> dict:
    """LLM 配置：OpenAI 兼容接口。

    优先级：环境变量 > server/data/llm_config.json。
    键：base_url（如 https://dashscope.aliyuncs.com/compatible-mode/v1）、
        api_key、model（如 qwen-plus / moonshot-v1-8b / deepseek-chat）。
    文件可经 /api/config/llm 接口修改，每次请求重新读取，保存即生效。
    """
    cfg = {"base_url": None, "api_key": None, "model": None}
    f = data_dir() / "llm_config.json"
    if f.exists():
        try:
            cfg.update(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    for key, env in LLM_ENV_MAP.items():
        v = os.environ.get(env)
        if v:
            cfg[key] = v
    cfg["configured"] = bool(cfg.get("base_url") and cfg.get("api_key") and cfg.get("model"))
    return cfg


def llm_env_overridden() -> bool:
    """环境变量是否已覆盖文件配置（覆盖时接口保存不生效，用于客户端提示）。"""
    return any(os.environ.get(env) for env in LLM_ENV_MAP.values())


def save_llm_config(cfg: dict) -> None:
    """合并写入 server/data/llm_config.json；空值保留原值。"""
    f = data_dir() / "llm_config.json"
    merged: dict = {}
    if f.exists():
        try:
            merged.update(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    for key in LLM_ENV_MAP:
        v = cfg.get(key)
        if v:
            merged[key] = v
    f.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
