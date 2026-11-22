"""通用工具：日期、数值解析、输出格式化。"""

from __future__ import annotations

import json
import re
import unicodedata
from datetime import date, datetime, timedelta
from typing import Any, Iterable

JUNK_VALUES = {"", "—", "-", "--", "tr", "nd", "n/a", "na", "null", "none", "/"}


class FitFuelError(Exception):
    """可预期的业务错误，CLI 会转成友好提示。"""

    def __init__(self, message: str, hints: Iterable[str] | None = None):
        super().__init__(message)
        self.message = message
        self.hints = list(hints or [])


def today_iso() -> str:
    return date.today().isoformat()


def now_iso() -> str:
    return datetime.now().replace(microsecond=0).isoformat()


def parse_date(value: str | None) -> str:
    """接受 today/今天/yesterday/昨天/YYYY-MM-DD/MM-DD。"""
    if value is None or str(value).strip() == "":
        return today_iso()
    s = str(value).strip().lower()
    if s in {"today", "今天", "今日"}:
        return today_iso()
    if s in {"yesterday", "昨天", "昨日"}:
        return (date.today() - timedelta(days=1)).isoformat()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        datetime.strptime(s, "%Y-%m-%d")
        return s
    if re.fullmatch(r"\d{4}/\d{1,2}/\d{1,2}", s):
        y, m, d = s.split("/")
        return date(int(y), int(m), int(d)).isoformat()
    if re.fullmatch(r"\d{1,2}-\d{1,2}", s):
        m, d = s.split("-")
        return date(date.today().year, int(m), int(d)).isoformat()
    raise FitFuelError(f"无法识别的日期：{value}", ["请使用 YYYY-MM-DD，或 today / yesterday"])


def parse_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if s.lower() in JUNK_VALUES:
        return None
    s = s.replace(",", "").replace("＜", "<").replace("＞", ">")
    s = s.replace("≤", "").replace("≥", "").replace("<", "").replace(">", "")
    try:
        return float(s)
    except ValueError:
        return None


def r1(value: float | None) -> float | None:
    return None if value is None else round(value, 1)


def r0(value: float | None) -> int | None:
    return None if value is None else round(value)


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def normalize_meal_type(value: str | None) -> str:
    raw = (value or "").strip().lower()
    mapping = {
        "breakfast": "breakfast",
        "早餐": "breakfast",
        "早饭": "breakfast",
        "lunch": "lunch",
        "午餐": "lunch",
        "午饭": "lunch",
        "中餐": "lunch",
        "dinner": "dinner",
        "晚餐": "dinner",
        "晚饭": "dinner",
        "snack": "snack",
        "加餐": "snack",
        "零食": "snack",
        "夜宵": "snack",
        "练前": "snack",
        "练后": "snack",
    }
    if raw in mapping:
        return mapping[raw]
    raise FitFuelError(
        f"无法识别的餐次：{value}",
        ["可用：breakfast/lunch/dinner/snack，或 早餐/午餐/晚餐/加餐"],
    )


MEAL_LABELS = {
    "breakfast": "早餐",
    "lunch": "午餐",
    "dinner": "晚餐",
    "snack": "加餐",
}


def normalize_activity(value: str | None) -> str:
    raw = (value or "").strip().lower()
    mapping = {
        "sedentary": "sedentary",
        "久坐": "sedentary",
        "不运动": "sedentary",
        "light": "light",
        "轻度": "light",
        "每周1-3": "light",
        "moderate": "moderate",
        "中等": "moderate",
        "每周3-5": "moderate",
        "active": "active",
        "活跃": "active",
        "每周6-7": "active",
        "very_active": "very_active",
        "非常活跃": "very_active",
        "very active": "very_active",
        "体力劳动": "very_active",
    }
    if raw in mapping:
        return mapping[raw]
    raise FitFuelError(
        f"无法识别的活动水平：{value}",
        ["可用：sedentary/light/moderate/active/very_active，或 久坐/轻度/中等/活跃/非常活跃"],
    )


ACTIVITY_LABELS = {
    "sedentary": "久坐",
    "light": "轻度活动",
    "moderate": "中等活动",
    "active": "活跃",
    "very_active": "非常活跃",
}

GOAL_LABELS = {"cut": "减脂", "maintain": "维持", "bulk": "增肌"}


def normalize_goal(value: str | None) -> str:
    raw = (value or "").strip().lower()
    mapping = {
        "cut": "cut",
        "减脂": "cut",
        "减肥": "cut",
        "减重": "cut",
        "maintain": "maintain",
        "维持": "maintain",
        "保持": "maintain",
        "bulk": "bulk",
        "增肌": "bulk",
        "增重": "bulk",
    }
    if raw in mapping:
        return mapping[raw]
    raise FitFuelError(
        f"无法识别的目标类型：{value}",
        ["可用：cut/maintain/bulk，或 减脂/维持/增肌"],
    )


def parse_item_spec(spec: str) -> tuple[str, float]:
    """把 '鸡胸肉:150' 解析成 (名称, 克数)。支持中文冒号和 x 后缀。"""
    s = spec.strip().replace("：", ":")
    if ":" not in s:
        raise FitFuelError(
            f"条目格式不对：{spec}",
            ["格式应为 食物名:克数，例如 鸡胸肉:150"],
        )
    name, grams = s.rsplit(":", 1)
    name = name.strip()
    weight = parse_float(grams.replace("g", "").replace("克", ""))
    if not name or weight is None or weight <= 0:
        raise FitFuelError(
            f"条目格式不对：{spec}",
            ["格式应为 食物名:克数，例如 鸡胸肉:150"],
        )
    return name, weight


def display_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def pad(text: str, width: int) -> str:
    return text + " " * max(0, width - display_width(text))


def print_table(headers: list[str], rows: list[list[Any]]) -> None:
    if not rows:
        print("（无数据）")
        return
    str_rows = [[("" if v is None else str(v)) for v in row] for row in rows]
    widths = [display_width(h) for h in headers]
    for row in str_rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], display_width(cell))
    print("  ".join(pad(h, widths[i]) for i, h in enumerate(headers)))
    print("  ".join("-" * widths[i] for i in range(len(headers))))
    for row in str_rows:
        print("  ".join(pad(c, widths[i]) for i, c in enumerate(row)))


def dumps_zh(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, default=str)


def json_escape_for_html(data: Any) -> str:
    """安全地把 JSON 嵌进 <script>。"""
    return json.dumps(data, ensure_ascii=False, default=str).replace("</", "<\\/")
