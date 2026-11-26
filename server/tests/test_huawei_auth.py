"""华为账号登录测试：code 换凭证（mock）、UnionID 绑定、业务 token 签发。"""

import base64
import json
import time
import uuid

import httpx
import pytest

from .conftest import unique


def make_id_token(client_id: str, union_id: str, exp_offset: int = 600) -> str:
    header = base64.urlsafe_b64encode(b'{"alg":"RS256"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        json.dumps(
            {
                "aud": client_id,
                "sub": union_id,
                "openid": "openid-" + union_id,
                "exp": int(time.time()) + exp_offset,
            }
        ).encode()
    ).rstrip(b"=").decode()
    return f"{header}.{payload}.fake-signature"


class FakeTokenResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def json(self) -> dict:
        return self._payload


@pytest.fixture()
def huawei_env(server_env, monkeypatch):
    from coachpal_server.db import connect

    con = connect()
    con.execute("DELETE FROM huawei_account")
    con.commit()
    client_id = "agc-client-" + unique()
    monkeypatch.setenv("COACHPAL_HUAWEI_CLIENT_ID", client_id)
    monkeypatch.setenv("COACHPAL_HUAWEI_CLIENT_SECRET", "secret-" + unique())
    return {"client_id": client_id, "union_id": "union-" + unique()}


def test_huawei_login_binds_and_issues_token(client, huawei_env, monkeypatch):
    union_id = huawei_env["union_id"]
    id_token = make_id_token(huawei_env["client_id"], union_id)
    captured = {}

    def fake_post(url, data=None, timeout=None):
        captured["url"] = url
        captured["data"] = data
        return FakeTokenResponse({"id_token": id_token, "access_token": "at"})

    monkeypatch.setattr(httpx, "post", fake_post)
    r = client.post("/api/auth/huawei", json={"authorizationCode": "code-1"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True
    assert body["union_id"] == union_id
    assert body["token"]
    assert captured["url"].endswith("/oauth2/v3/token")
    assert captured["data"]["grant_type"] == "authorization_code"
    assert captured["data"]["code"] == "code-1"
    assert captured["data"]["client_id"] == huawei_env["client_id"]

    auth = {"Authorization": f"Bearer {body['token']}"}
    assert client.get("/api/profile", headers=auth).status_code == 200


def test_huawei_login_same_union_again(client, huawei_env, monkeypatch):
    union_id = huawei_env["union_id"]
    monkeypatch.setattr(
        httpx,
        "post",
        lambda url, data=None, timeout=None: FakeTokenResponse(
            {"id_token": make_id_token(huawei_env["client_id"], union_id)}
        ),
    )
    assert client.post("/api/auth/huawei", json={"authorizationCode": "a"}).status_code == 200
    assert client.post("/api/auth/huawei", json={"authorizationCode": "b"}).status_code == 200


def test_huawei_login_rejects_other_union(client, huawei_env, monkeypatch):
    monkeypatch.setattr(
        httpx,
        "post",
        lambda url, data=None, timeout=None: FakeTokenResponse(
            {"id_token": make_id_token(huawei_env["client_id"], huawei_env["union_id"])}
        ),
    )
    assert client.post("/api/auth/huawei", json={"authorizationCode": "a"}).status_code == 200
    monkeypatch.setattr(
        httpx,
        "post",
        lambda url, data=None, timeout=None: FakeTokenResponse(
            {"id_token": make_id_token(huawei_env["client_id"], "union-someone-else")}
        ),
    )
    assert client.post("/api/auth/huawei", json={"authorizationCode": "b"}).status_code == 401


def test_huawei_login_rejects_expired_token(client, huawei_env, monkeypatch):
    monkeypatch.setattr(
        httpx,
        "post",
        lambda url, data=None, timeout=None: FakeTokenResponse(
            {"id_token": make_id_token(huawei_env["client_id"], huawei_env["union_id"],
                                       exp_offset=-10)}
        ),
    )
    assert client.post("/api/auth/huawei", json={"authorizationCode": "a"}).status_code == 401


def test_huawei_login_rejects_wrong_aud(client, huawei_env, monkeypatch):
    monkeypatch.setattr(
        httpx,
        "post",
        lambda url, data=None, timeout=None: FakeTokenResponse(
            {"id_token": make_id_token("other-app", huawei_env["union_id"])}
        ),
    )
    assert client.post("/api/auth/huawei", json={"authorizationCode": "a"}).status_code == 401


def test_huawei_login_requires_config(client, server_env, monkeypatch):
    monkeypatch.delenv("COACHPAL_HUAWEI_CLIENT_ID", raising=False)
    monkeypatch.delenv("COACHPAL_HUAWEI_CLIENT_SECRET", raising=False)
    data_dir = server_env["data"]
    f = data_dir / "huawei_oauth.json"
    if f.exists():
        f.unlink()
    r = client.post("/api/auth/huawei", json={"authorizationCode": "x"})
    assert r.status_code == 400
