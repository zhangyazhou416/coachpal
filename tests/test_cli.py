import json

from fitfuel.cli import main


def run_json(capsys, db, *argv):
    code = main(["--json", "--db", str(db), *argv])
    captured = capsys.readouterr().out
    data = json.loads(captured)
    return code, data


def test_cli_end_to_end(tmp_path, capsys, foods_dir, exercises_dir):
    db = tmp_path / "fitfuel.db"
    code, data = run_json(
        capsys,
        db,
        "seed",
        "--foods-dir",
        str(foods_dir),
        "--exercises-dir",
        str(exercises_dir),
    )
    assert code == 0 and data["ok"]
    assert data["foods"]["foods_total"] == 2
    assert data["exercises"]["exercises_total"] == 2

    code, data = run_json(
        capsys, db, "profile", "set", "--sex", "male", "--height", "178", "--goal", "cut"
    )
    assert code == 0 and data["profile"]["height_cm"] == 178

    code, data = run_json(capsys, db, "weight", "add", "78", "--body-fat", "22")
    assert code == 0 and data["metric"]["weight_kg"] == 78

    code, data = run_json(capsys, db, "measure", "add", "--waist", "84", "--chest", "100")
    assert code == 0 and len(data["measurements"]) == 2

    code, data = run_json(capsys, db, "goal", "set", "weight", "72")
    assert code == 0 and data["goal"]["target_value"] == 72

    code, data = run_json(capsys, db, "strength", "add", "bench", "80", "5", "--rpe", "8")
    assert code == 0 and data["log"]["estimated_1rm"] == 91.7
    assert data["log"]["is_pr"] is True

    code, data = run_json(
        capsys,
        db,
        "meal",
        "add",
        "--type",
        "午餐",
        "--item",
        "米饭（测试）:150",
        "--item",
        "鸡胸脯肉（测试）:100",
    )
    assert code == 0 and data["meal"]["totals"]["kcal"] > 0

    code, data = run_json(
        capsys,
        db,
        "workout",
        "add",
        "--name",
        "推日",
        "--set",
        "卧推 80 5 @8",
        "--set",
        "深蹲 100 3",
    )
    assert code == 0 and data["workout"]["volume_kg"] == 700

    code, data = run_json(capsys, db, "day")
    assert code == 0 and data["targets"]["kcal"] > 0

    code, data = run_json(capsys, db, "status")
    assert code == 0 and data["prs"]

    code, data = run_json(capsys, db, "report", "--days", "7")
    assert code == 0 and data["period"]["days"] == 7

    code, data = run_json(capsys, db, "dashboard")
    assert code == 0
    html_path = tmp_path / "dashboard.html"
    assert html_path.exists()
    html = html_path.read_text(encoding="utf-8")
    assert "fitfuel-data" in html
    assert "__DATA_JSON__" not in html
    assert "体重趋势" in html


def test_cli_error_is_json(tmp_path, capsys):
    db = tmp_path / "fitfuel.db"
    code, data = run_json(capsys, db, "food", "show", "不存在的食物")
    assert code == 2
    assert data["ok"] is False
    # 空库时提示先 seed，已 seed 后才提示找不到
    assert "食物库" in data["error"] and data["hints"]

    run_json(
        capsys,
        db,
        "seed",
        "--foods-dir",
        "tests/fixtures/foods",
        "--exercises-dir",
        "tests/fixtures/exercises",
    )
    code, data = run_json(capsys, db, "food", "show", "不存在的食物")
    assert code == 2
    assert data["ok"] is False
    assert "找不到" in data["error"]
