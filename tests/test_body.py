from coachpal.body import (
    add_goal,
    add_measurements,
    add_metric,
    get_profile,
    latest_metric,
    list_goals,
    list_measurements,
    set_profile,
)
from coachpal.db import connect


def test_profile_and_bmi(tmp_path):
    con = connect(tmp_path / "test.db")
    set_profile(con, sex="male", height_cm=178, birth_date="1995-06-15", goal_type="cut")
    add_metric(con, "2026-11-19", weight_kg=78.0)
    profile = get_profile(con)
    assert profile["sex"] == "male"
    assert profile["bmi"] == 24.6
    assert profile["age"] >= 30
    assert latest_metric(con)["weight_kg"] == 78.0
    con.close()


def test_measurements_are_upserted_per_day(tmp_path):
    con = connect(tmp_path / "test.db")
    add_measurements(con, "2026-11-19", {"waist": 84, "chest": 100})
    add_measurements(con, "2026-11-19", {"waist": 83.5})
    rows = list_measurements(con, days=None)
    by_site = {row["site"]: row["value_cm"] for row in rows}
    assert by_site == {"waist": 83.5, "chest": 100}
    con.close()


def test_goal_baseline_backfills_after_first_record(tmp_path):
    con = connect(tmp_path / "test.db")
    goal = add_goal(con, "weight", 72, target_date="2027-03-01")
    assert goal["baseline_value"] is None
    add_metric(con, "2026-11-19", weight_kg=78.0)
    goals = list_goals(con)
    assert goals[0]["baseline_value"] == 78.0
    assert goals[0]["progress"] == 0.0
    con.close()
