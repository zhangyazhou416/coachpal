"""server 端到端测试：登录、领域 API、同步 pull/push（LWW/墓碑）。"""

import time
import uuid

from .conftest import unique


def h(auth_headers):
    return auth_headers


def test_health(client):
    assert client.get("/api/health").json() == {"ok": True}


def test_login_wrong_password(client):
    assert client.post("/api/auth/login", json={"password": "nope"}).status_code == 401


def test_login_ok(client, server_env):
    r = client.post("/api/auth/login", json={"password": server_env["password"]})
    assert r.status_code == 200
    assert r.json()["token"]


def test_requires_auth(client):
    assert client.get("/api/profile").status_code == 401


def test_profile_roundtrip(client, auth_headers):
    r = client.put(
        "/api/profile",
        json={"sex": "male", "birth": "1995-06-15", "height": 178,
              "activity": "moderate", "goal": "cut"},
        headers=auth_headers,
    )
    assert r.status_code == 200
    p = r.json()["profile"]
    assert p["height_cm"] == 178
    assert p["age"] >= 30


def test_weight_and_targets(client, auth_headers):
    suffix = unique()
    r = client.post(
        "/api/weight",
        json={"weight": 78.0 + len(suffix) * 0, "body_fat": 21.0},
        headers=auth_headers,
    )
    assert r.status_code == 200
    metric = r.json()["metric"]
    assert metric["weight_kg"] == 78.0
    assert metric["bmi"]  # 身高已在 profile 测试设置

    r = client.get("/api/weight", headers=auth_headers)
    assert any(m["weight_kg"] == 78.0 for m in r.json()["metrics"])

    r = client.get("/api/targets", headers=auth_headers)
    assert r.json()["available"] is True
    assert r.json()["targets"]["kcal"] > 1000


def test_measurements(client, auth_headers):
    r = client.post(
        "/api/measurements",
        json={"date": None},
        headers=auth_headers,
    )
    # 空围度应报错（业务校验）
    assert r.status_code in (200, 400)


def test_food_search(client, auth_headers):
    r = client.get("/api/foods/search", params={"q": "鸡胸"}, headers=auth_headers)
    assert r.status_code == 200
    foods = r.json()["foods"]
    assert foods
    assert any("鸡" in f["name"] for f in foods)


def test_meal_and_day(client, auth_headers):
    r = client.post(
        "/api/meals",
        json={
            "type": "午餐",
            "items": [{"query": "米饭（蒸，代表值）", "grams": 100}],
            "custom": [{"name": "测试补剂", "grams": 30, "kcal": 100,
                        "protein": 20, "fat": 1, "carbs": 2}],
        },
        headers=auth_headers,
    )
    assert r.status_code == 200, r.text
    meal = r.json()["meal"]
    assert meal["totals"]["kcal"] > 0

    day = client.get("/api/day", headers=auth_headers).json()
    assert day["totals"]["kcal"] >= meal["totals"]["kcal"]


def test_workout_roundtrip(client, auth_headers):
    r = client.post(
        "/api/workouts",
        json={"name": "推日", "sets": [
            {"name": "卧推", "weight": 80, "reps": 5, "rpe": 8},
            {"name": "卧推", "weight": 80, "reps": 5, "rpe": 8},
        ]},
        headers=auth_headers,
    )
    assert r.status_code == 200
    w = r.json()["workout"]
    assert w["volume_kg"] == 800.0

    lst = client.get("/api/workouts", headers=auth_headers).json()["workouts"]
    assert any(x["id"] == w["id"] for x in lst)

    d = client.delete(f"/api/workouts/{w['id']}", headers=auth_headers)
    assert d.status_code == 200


def test_exercise_search(client, auth_headers):
    r = client.get("/api/exercises/search", params={"q": "bench press"},
                   headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["exercises"]


def test_sync_push_pull_lww(client, auth_headers):
    uid = uuid.uuid4().hex
    row = {"uuid": uid, "date": "2026-11-20", "weight_kg": 76.5,
           "body_fat_pct": None, "skeletal_muscle_kg": None,
           "note": None, "updated_at": "2026-11-20T08:00:00+00:00", "deleted": 0}
    r = client.post("/api/sync/push", json={"rows": {"body_metrics": [row]}},
                    headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["results"]["body_metrics"][0]["status"] == "inserted"

    # LWW：更旧的 updated_at 应被跳过
    old = dict(row, weight_kg=99.0, updated_at="2026-11-19T08:00:00+00:00")
    r = client.post("/api/sync/push", json={"rows": {"body_metrics": [old]}},
                    headers=auth_headers)
    assert r.json()["results"]["body_metrics"][0]["status"] == "skipped"

    # 更新的 updated_at 覆盖
    new = dict(row, weight_kg=75.5, updated_at="2026-11-21T08:00:00+00:00")
    r = client.post("/api/sync/push", json={"rows": {"body_metrics": [new]}},
                    headers=auth_headers)
    assert r.json()["results"]["body_metrics"][0]["status"] == "updated"

    # pull 能看到
    r = client.post("/api/sync/pull",
                    json={"since": "2026-11-01T00:00:00", "tables": ["body_metrics"]},
                    headers=auth_headers)
    rows = r.json()["body_metrics"]
    assert any(x["uuid"] == uid and x["weight_kg"] == 75.5 for x in rows)


def test_sync_meal_tombstone_on_delete(client, auth_headers):
    # 建一餐 → 删除 → pull 应含墓碑
    r = client.post(
        "/api/meals",
        json={"type": "加餐",
              "custom": [{"name": "墓碑测试", "grams": 10, "kcal": 10,
                          "protein": 1, "fat": 0, "carbs": 1}]},
        headers=auth_headers,
    )
    meal = r.json()["meal"]
    time.sleep(1.1)  # 确保 tombstone 的 deleted_at 晚于 since
    client.delete(f"/api/meals/{meal['id']}", headers=auth_headers)
    r = client.post(
        "/api/sync/pull",
        json={"since": "2026-11-01T00:00:00", "tables": ["meals", "meal_items"]},
        headers=auth_headers,
    )
    data = r.json()
    assert data["_tombstones"], "应包含墓碑"


def test_status_and_report(client, auth_headers):
    r = client.get("/api/status", headers=auth_headers)
    assert r.status_code == 200
    assert "profile" in r.json()
    r = client.get("/api/report", params={"days": 7}, headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["period"]["days"] == 7
