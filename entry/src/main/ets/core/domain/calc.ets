/// 领域计算：与 coachpal Python 包逐一对齐（对拍单测见 entry/src/test/CalcTest.ets）。
/// 纯逻辑文件：禁 import @kit，保证 LocalUnit 单测可在宿主 JS 引擎运行。

export const ACTIVITY_FACTORS: Record<string, number> = {
  'sedentary': 1.2,
  'light': 1.375,
  'moderate': 1.55,
  'active': 1.725,
  'very_active': 1.9,
};

export const GOAL_ADJUST: Record<string, number> = {
  'cut': -0.15,
  'maintain': 0.0,
  'bulk': 0.10,
};

export const PROTEIN_PER_KG: Record<string, number> = {
  'cut': 2.0,
  'maintain': 1.6,
  'bulk': 1.8,
};

export const SAFE_FLOORS: Record<string, number> = {
  'male': 1500.0,
  'female': 1200.0,
  'other': 1200.0,
};

/** 保留 1 位小数（与 Dart toStringAsFixed(1)+parse 一致）。 */
export function round1(v: number): number {
  return Number(v.toFixed(1));
}

/** Python round() 的银行家舍入（0.5 向偶数），保证跨语言数值一致。 */
export function roundPy(v: number): number {
  const f = Math.floor(v);
  const diff = v - f;
  if (diff > 0.5) {
    return f + 1;
  }
  if (diff < 0.5) {
    return f;
  }
  return f % 2 === 0 ? f : f + 1;
}

export function calcBmi(weightKg: number | null, heightCm: number | null): number | null {
  if (weightKg === null || heightCm === null || heightCm <= 0) {
    return null;
  }
  const h = heightCm / 100;
  return round1(weightKg / (h * h));
}

/** Epley 与 Brzycki 平均（≤12 次）；更高次数只用 Epley。 */
export function estimate1rm(weightKg: number, reps: number): number {
  if (reps <= 1) {
    return round1(weightKg);
  }
  const epley = weightKg * (1 + reps / 30.0);
  if (reps <= 12) {
    const brzycki = weightKg * 36.0 / (37.0 - reps);
    return round1((epley + brzycki) / 2.0);
  }
  return round1(epley);
}

export interface PercentageRow {
  pct: number;
  weight: number;
  repsGuide: number;
}

// %1RM → 建议次数固定表（与 Python percentage_table 一致），已按 pct 降序
const PCT_KEYS: number[] = [100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50];
const PCT_REPS: number[] = [1, 2, 4, 6, 8, 10, 12, 15, 18, 20, 22];

function roundStep(oneRm: number): number {
  if (oneRm >= 100) {
    return 5.0;
  }
  if (oneRm >= 40) {
    return 2.5;
  }
  return 1.0;
}

/** %1RM 重量表：与 Python percentage_table 一致。 */
export function percentageTable(oneRm: number, step?: number): PercentageRow[] {
  const s = step ?? roundStep(oneRm);
  const rows: PercentageRow[] = [];
  for (let i = 0; i < PCT_KEYS.length; i++) {
    const pct = PCT_KEYS[i];
    const row: PercentageRow = {
      pct: pct,
      weight: round1(roundPy(oneRm * pct / 100 / s) * s),
      repsGuide: PCT_REPS[i],
    };
    rows.push(row);
  }
  return rows;
}

export interface Targets {
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  fiber: number;
  bmr: number;
  tdee: number;
  clamped: boolean;
}

/** Mifflin-St Jeor × 活动系数 + 目标调整；与 Python compute_targets 一致。 */
export function computeTargets(sex: string | null, age: number | null, heightCm: number | null,
  weightKg: number | null, activityLevel: string, goalType: string): Targets | null {
  if (heightCm === null || weightKg === null) {
    return null;
  }
  const effectiveAge = age ?? 30;
  const base = 10 * weightKg + 6.25 * heightCm - 5 * effectiveAge;
  const bmr = sex === 'female' ? base - 161 : (sex === 'other' ? base - 78 : base + 5);
  const tdee = bmr * ACTIVITY_FACTORS[activityLevel];
  const adjust = GOAL_ADJUST[goalType] ?? 0.0;
  let raw = tdee * (1 + adjust);
  const floor = SAFE_FLOORS[sex ?? ''] ?? 1200.0;
  let clamped = false;
  if (raw < floor) {
    raw = floor;
    clamped = true;
  }
  const kcal = roundPy(raw / 10) * 10;
  const protein = roundPy(PROTEIN_PER_KG[goalType] * weightKg);
  const fat = roundPy(kcal * 0.25 / 9);
  const carbs = Math.max(0.0, roundPy((kcal - protein * 4 - fat * 9) / 4));
  const fiber = roundPy(kcal / 1000 * 14);
  const t: Targets = {
    kcal: kcal,
    protein: protein,
    fat: fat,
    carbs: carbs,
    fiber: fiber,
    bmr: roundPy(bmr),
    tdee: roundPy(tdee),
    clamped: clamped,
  };
  return t;
}
