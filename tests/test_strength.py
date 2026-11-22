from fitfuel.strength import estimate_1rm, parse_set_spec, percentage_table


def test_estimate_1rm_formulas():
    assert estimate_1rm(100, 1) == 100
    assert estimate_1rm(80, 5) == 91.7
    assert estimate_1rm(120, 3) == 129.5
    assert estimate_1rm(60, 15) > 60


def test_percentage_table_rounds_to_plates():
    table = percentage_table(100, step=2.5)
    by_pct = {row["pct"]: row for row in table}
    assert by_pct[100]["weight_kg"] == 100
    assert by_pct[75]["weight_kg"] == 75
    assert by_pct[90]["weight_kg"] == 90
    assert all(row["reps_guide"] >= 1 for row in table)


def test_parse_set_spec_variants():
    a = parse_set_spec("卧推 80 5 @8")
    assert a == {"name": "卧推", "weight_kg": 80.0, "reps": 5, "rpe": 8.0}
    b = parse_set_spec("Barbell Squat 100kg x 3")
    assert b["weight_kg"] == 100.0
    assert b["reps"] == 3
    assert b["rpe"] is None
    c = parse_set_spec("引体向上 0 10")
    assert c["weight_kg"] == 0.0
