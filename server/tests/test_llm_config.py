"""/api/config/llm 接口测试：读取（脱敏）、保存（合并保留旧 key）、鉴权。"""

from .conftest import unique


def _clear_llm_env(monkeypatch):
    for env in ("COACHPAL_LLM_BASE_URL", "COACHPAL_LLM_API_KEY", "COACHPAL_LLM_MODEL"):
        monkeypatch.delenv(env, raising=False)


def test_llm_config_requires_auth(client):
    assert client.get("/api/config/llm").status_code == 401
    assert client.put("/api/config/llm", json={"model": "m"}).status_code == 401


def test_llm_config_roundtrip(client, auth_headers, server_env, monkeypatch):
    _clear_llm_env(monkeypatch)
    base = "https://llm-" + unique() + ".example.com/v1"
    model = "model-" + unique()

    r = client.put(
        "/api/config/llm",
        headers=auth_headers,
        json={"base_url": base, "api_key": "sk-test", "model": model},
    )
    assert r.status_code == 200
    assert r.json() == {"ok": True}

    body = client.get("/api/config/llm", headers=auth_headers).json()
    assert body["base_url"] == base
    assert body["model"] == model
    assert body["api_key_set"] is True
    assert body["configured"] is True
    assert body["env_overridden"] is False


def test_llm_config_keeps_old_api_key(client, auth_headers, server_env, monkeypatch):
    _clear_llm_env(monkeypatch)
    client.put(
        "/api/config/llm",
        headers=auth_headers,
        json={"base_url": "https://a.example.com/v1", "api_key": "sk-keep", "model": "m1"},
    )
    r = client.put(
        "/api/config/llm",
        headers=auth_headers,
        json={"base_url": "https://b.example.com/v1", "model": "m2"},
    )
    assert r.status_code == 200
    body = client.get("/api/config/llm", headers=auth_headers).json()
    assert body["base_url"] == "https://b.example.com/v1"
    assert body["model"] == "m2"
    assert body["api_key_set"] is True


def test_llm_config_rejects_empty_body(client, auth_headers):
    r = client.put("/api/config/llm", headers=auth_headers, json={})
    assert r.status_code == 400
