import os
import sys
import uuid
from pathlib import Path

import pytest

SERVER_DIR = Path(__file__).resolve().parent.parent
ROOT = SERVER_DIR.parent
for p in (str(SERVER_DIR), str(ROOT)):
    if p not in sys.path:
        sys.path.insert(0, p)


@pytest.fixture(scope="session")
def server_env(tmp_path_factory):
    data = tmp_path_factory.mktemp("server-data")
    os.environ["FITFUEL_SERVER_DATA"] = str(data)
    os.environ["FITFUEL_SERVER_PASSWORD"] = "test-pass-123"
    yield {"data": data, "password": "test-pass-123"}


@pytest.fixture(scope="session")
def client(server_env):
    from fastapi.testclient import TestClient

    from fitfuel_server.main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def token(client, server_env):
    r = client.post("/api/auth/login", json={"password": server_env["password"]})
    assert r.status_code == 200
    return r.json()["token"]


@pytest.fixture()
def auth_headers(token):
    return {"Authorization": f"Bearer {token}"}


def unique() -> str:
    return uuid.uuid4().hex[:8]
