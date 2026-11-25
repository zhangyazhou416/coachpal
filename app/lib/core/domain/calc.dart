/// 领域计算：与 coachpal Python 包逐一对齐（对拍单测见 test/calc_test.dart）。
library;

const activityFactors = {
  'sedentary': 1.2,
  'light': 1.375,
  'moderate': 1.55,
  'active': 1.725,
  'very_active': 1.9,
};

const goalAdjust = {'cut': -0.15, 'maintain': 0.0, 'bulk': 0.10};

const proteinPerKg = {'cut': 2.0, 'maintain': 1.6, 'bulk': 1.8};

const safeFloors = {'male': 1500.0, 'female': 1200.0, 'other': 1200.0};

double? calcBmi(double? weightKg, double? heightCm) {
  if (weightKg == null || heightCm == null || heightCm <= 0) return null;
  final h = heightCm / 100;
  return double.parse((weightKg / (h * h)).toStringAsFixed(1));
}

/// Epley 与 Brzycki 平均（≤12 次）；更高次数只用 Epley。
double estimate1rm(double weightKg, int reps) {
  if (reps <= 1) return _r1(weightKg);
  final epley = weightKg * (1 + reps / 30.0);
  if (reps <= 12) {
    final brzycki = weightKg * 36.0 / (37.0 - reps);
    return _r1((epley + brzycki) / 2.0);
  }
  return _r1(epley);
}

double _r1(double v) => double.parse(v.toStringAsFixed(1));

/// Python round() 的银行家舍入（0.5 向偶数），保证跨语言数值一致。
double _roundPy(double v) {
  final f = v.floorToDouble();
  final diff = v - f;
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f % 2 == 0 ? f : f + 1;
}

double _roundStep(double oneRm) {
  if (oneRm >= 100) return 5.0;
  if (oneRm >= 40) return 2.5;
  return 1.0;
}

/// %1RM 重量表：与 Python percentage_table 一致。
List<({int pct, double weight, int repsGuide})> percentageTable(
  double oneRm, {
  double? step,
}) {
  final s = step ?? _roundStep(oneRm);
  const guide = {
    100: 1, 95: 2, 90: 4, 85: 6, 80: 8, 75: 10, 70: 12,
    65: 15, 60: 18, 55: 20, 50: 22,
  };
  final pcts = guide.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final pct in pcts)
      (
        pct: pct,
        weight: _r1(_roundPy(oneRm * pct / 100 / s) * s),
        repsGuide: guide[pct]!,
      )
  ];
}

class Targets {
  final double kcal, protein, fat, carbs, fiber;
  final double bmr, tdee;
  final bool clamped;
  const Targets(this.kcal, this.protein, this.fat, this.carbs, this.fiber,
      this.bmr, this.tdee, this.clamped);
}

/// Mifflin-St Jeor × 活动系数 + 目标调整；与 Python compute_targets 一致。
Targets? computeTargets({
  required String? sex,
  required int? age,
  required double? heightCm,
  required double? weightKg,
  required String activityLevel,
  required String goalType,
}) {
  if (heightCm == null || weightKg == null) return null;
  final effectiveAge = age ?? 30;
  final bmr = sex == 'female'
      ? 10 * weightKg + 6.25 * heightCm - 5 * effectiveAge - 161
      : sex == 'other'
          ? 10 * weightKg + 6.25 * heightCm - 5 * effectiveAge - 78
          : 10 * weightKg + 6.25 * heightCm - 5 * effectiveAge + 5;
  final tdee = bmr * activityFactors[activityLevel]!;
  final adjust = goalAdjust[goalType] ?? 0.0;
  var raw = tdee * (1 + adjust);
  final floor = safeFloors[sex] ?? 1200.0;
  var clamped = false;
  if (raw < floor) {
    raw = floor;
    clamped = true;
  }
  final kcal = _roundPy(raw / 10) * 10;
  final protein = _roundPy(proteinPerKg[goalType]! * weightKg);
  final fat = _roundPy(kcal * 0.25 / 9);
  final carbs =
      _roundPy((kcal - protein * 4 - fat * 9) / 4).clamp(0.0, double.infinity);
  final fiber = _roundPy(kcal / 1000 * 14);
  return Targets(kcal, protein, fat, carbs, fiber,
      _roundPy(bmr), _roundPy(tdee), clamped);
}
