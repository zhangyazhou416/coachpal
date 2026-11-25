import pytest

from coachpal.body import add_metric, set_profile
from coachpal.db import connect
from coachpal.nutrition import (
    add_meal,
    compute_targets,
    day_summary,
    resolve_food,
    search_foods,
    seed_foods,
)


@pytest.fixture()
def con(tmp_path, foods_dir, gi_path):
    c = connect(tmp_path / "test.db")
    seed_foods(c, foods_dir, gi_path=gi_path)
    yield c
    c.close()


def test_seed_and_search(con):
    results = search_foods(con, "米饭", limit=5)
    assert results
    assert results[0]["name"] == "米饭（测试）"
    assert results[0]["gi"] == 83
    assert results[0]["kcal_per_100g"] == 116


def test_resolve_exact_and_representative(con):
    assert resolve_food(con, "米饭（测试）")["name"] == "米饭（测试）"
    # 去掉括号里的说明后仍能匹配（测试数据只有一个候选）
    assert resolve_food(con, "鸡胸脯肉")["name"] == "鸡胸脯肉（测试）"


def test_add_meal_and_totals(con):
    meal = add_meal(
        con,
        "午餐",
        item_specs=["米饭（测试）:150", "鸡胸脯肉（测试）:100"],
        date_str="2026-11-19",
    )
    assert meal["meal_type"] == "lunch"
    assert len(meal["items"]) == 2
    totals = meal["totals"]
    assert totals["kcal"] == pytest.approx(116 * 1.5 + 118, abs=0.2)
    assert totals["protein"] == pytest.approx(2.6 * 1.5 + 24.6, abs=0.2)
    day = day_summary(con, "2026-11-19")
    assert day["totals"]["kcal"] == pytest.approx(totals["kcal"], abs=0.1)


def test_custom_meal_item(con):
    meal = add_meal(
        con,
        "加餐",
        custom_specs=["蛋白粉:30:120:24:1.5:3:0.5"],
        date_str="2026-11-19",
    )
    item = meal["items"][0]
    assert item["food_name"] == "蛋白粉"
    assert item["source"] == "manual"
    assert meal["totals"]["protein"] == 24


def test_targets_require_profile_and_weight(con):
    info = compute_targets(con)
    assert info["available"] is False
    set_profile(con, sex="male", height_cm=178, goal_type="cut")
    add_metric(con, "2026-11-19", weight_kg=78.0)
    info = compute_targets(con)
    assert info["available"] is True
    targets = info["targets"]
    assert targets["kcal"] > targets["protein"] * 4
    assert targets["protein"] == round(2.0 * 78.0)
