from coachpal.db import connect
from coachpal.exercises import (
    exercise_detail,
    resolve_exercise,
    search_exercises,
    seed_exercises,
)
from coachpal.workouts import add_workout


def test_seed_from_dataset_and_resolve(tmp_path, exercise_dataset_dir):
    con = connect(tmp_path / "test.db")
    info = seed_exercises(con, exercise_dataset_dir)
    assert info["exercises_total"] == 2
    assert info["with_gif"] == 2
    assert info["with_chinese_name"] == 2

    result = resolve_exercise(con, "卧推")
    assert result["name"] == "barbell bench press"
    detail = exercise_detail(con, "卧推")
    assert detail["images"][0]["style"] == "gif"
    assert detail["steps_zh"]
    assert search_exercises(con, "butterfly")[0]["name"] == "butterfly stretch"
    con.close()


def test_seed_purges_legacy_rows(tmp_path, exercise_dataset_dir):
    con = connect(tmp_path / "test.db")
    # 模拟旧库遗留动作行 + 一条引用它的训练历史
    con.execute(
        "INSERT INTO workouts (id, date, name, note, created_at) "
        "VALUES (1, '2026-11-19', '推日', NULL, '2026-11-19T10:00:00')"
    )
    con.execute(
        "INSERT INTO exercises (id, ext_id, name, primary_muscles, secondary_muscles, "
        "instructions, images) VALUES (999, 'legacy_1', 'Old Exercise', '[]', '[]', '[]', '[]')"
    )
    con.execute(
        "INSERT INTO workout_sets (workout_id, exercise_id, exercise_name, set_no, "
        "weight_kg, reps) VALUES (1, 999, 'Old Exercise', 1, 80, 5)"
    )

    seed_exercises(con, exercise_dataset_dir)

    assert con.execute(
        "SELECT COUNT(*) AS n FROM exercises WHERE ext_id = 'legacy_1'"
    ).fetchone()["n"] == 0
    row = con.execute(
        "SELECT exercise_id, exercise_name FROM workout_sets WHERE id = 1"
    ).fetchone()
    assert row["exercise_id"] is None      # 外键已断开
    assert row["exercise_name"] == "Old Exercise"  # 历史文本保留
    con.close()


def test_workout_volume_and_custom_exercise(tmp_path, exercise_dataset_dir):
    con = connect(tmp_path / "test.db")
    seed_exercises(con, exercise_dataset_dir)
    workout = add_workout(
        con,
        ["卧推 80 5 @8", "卧推 80 5 @8", "跑步 0 30"],
        name="推日",
        date_str="2026-11-19",
    )
    assert workout["set_count"] == 3
    assert workout["volume_kg"] == 800.0
    assert workout["exercises"][0]["sets"] == 2
    assert workout["warnings"]
    con.close()
