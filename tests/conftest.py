import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


@pytest.fixture()
def fixtures_dir() -> Path:
    return Path(__file__).resolve().parent / "fixtures"


@pytest.fixture()
def foods_dir(fixtures_dir: Path) -> Path:
    return fixtures_dir / "foods"


@pytest.fixture()
def exercises_dir() -> Path:
    return Path(__file__).resolve().parent / "fixtures" / "exercise-dataset"


@pytest.fixture()
def exercise_dataset_dir() -> Path:
    return Path(__file__).resolve().parent / "fixtures" / "exercise-dataset"


@pytest.fixture()
def gi_path(foods_dir: Path) -> Path:
    return foods_dir / "json_gi_of_foods" / "glycemic_index_of_foods.json"
