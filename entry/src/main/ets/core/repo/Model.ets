/// 行模型：行字段接口、条目类与 JSON 解码辅助。
/// deleted 用 0/1 整数（SQLite 布尔存储形式）。

import { FoodHit } from '../domain/food_search';

export interface ProfileRow {
  id: number;
  sex: string;
  birthDate: string | null;
  heightCm: number | null;
  activityLevel: string;
  goalType: string;
  updatedAt: string;
}

export interface BodyMetricRow {
  uuid: string;
  date: string;
  weightKg: number | null;
  bodyFatPct: number | null;
  skeletalMuscleKg: number | null;
  note: string | null;
  updatedAt: string;
  deleted: number;
}

export interface MeasurementRow {
  uuid: string;
  date: string;
  site: string;
  valueCm: number;
  note: string | null;
  updatedAt: string;
  deleted: number;
}

export interface GoalRow {
  uuid: string;
  kind: string;
  targetValue: number;
  unit: string | null;
  baselineValue: number | null;
  targetDate: string | null;
  status: string;
  note: string | null;
  createdAt: string;
  updatedAt: string;
  deleted: number;
}

export interface StrengthLogRow {
  uuid: string;
  date: string;
  lift: string;
  weightKg: number;
  reps: number;
  rpe: number | null;
  estimated1rm: number;
  note: string | null;
  updatedAt: string;
  deleted: number;
}

export interface MealRow {
  uuid: string;
  date: string;
  mealType: string;
  note: string | null;
  createdAt: string;
  updatedAt: string;
  deleted: number;
}

export interface MealItemRow {
  uuid: string;
  mealUuid: string;
  foodId: number | null;
  foodName: string;
  grams: number;
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  fiber: number | null;
  source: string;
  updatedAt: string;
  deleted: number;
}

export interface WorkoutRow {
  uuid: string;
  date: string;
  name: string | null;
  note: string | null;
  createdAt: string;
  updatedAt: string;
  deleted: number;
}

export interface WorkoutSetRow {
  uuid: string;
  workoutUuid: string;
  exerciseId: number | null;
  exerciseName: string;
  setNo: number | null;
  weightKg: number | null;
  reps: number | null;
  rpe: number | null;
  updatedAt: string;
  deleted: number;
}

export interface ExerciseRow {
  id: string;
  name: string;
  cat: string | null;
  equip: string | null;
  target: string | null;
  secondary: string | null;
  stepsEn: string | null;
  stepsZh: string | null;
  gifPath: string | null;
  thumbPath: string | null;
}

/** 一餐 + 其明细。 */
export class MealEntry {
  readonly meal: MealRow;
  readonly items: MealItemRow[];

  constructor(meal: MealRow, items: MealItemRow[]) {
    this.meal = meal;
    this.items = items;
  }
}

/** 一次训练 + 其组数。 */
export class WorkoutEntry {
  readonly workout: WorkoutRow;
  readonly sets: WorkoutSetRow[];

  constructor(workout: WorkoutRow, sets: WorkoutSetRow[]) {
    this.workout = workout;
    this.sets = sets;
  }
}

/** addStrength 的返回（估算 1RM 与是否破 PR）。 */
export class StrengthResult {
  readonly estimated1rm: number;
  readonly isPr: boolean;

  constructor(estimated1rm: number, isPr: boolean) {
    this.estimated1rm = estimated1rm;
    this.isPr = isPr;
  }
}

/** 折线图点。 */
export interface SeriesPoint {
  date: string;
  value: number;
}

/** strengthSeries 的每动作序列（当日取最佳估算 1RM）。 */
export interface StrengthSeries {
  lift: string;
  points: SeriesPoint[];
}

// ------- 写入入参 -------

/** 搜索命中 + 克数（记餐用）。 */
export interface FoodPortion {
  food: FoodHit;
  grams: number;
}

/** 自定义食物条目（记餐用）。 */
export interface CustomItemInput {
  name: string;
  grams: number;
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  fiber: number;
}

/** 围度一条（按日期+部位 upsert）。 */
export interface MeasurementInput {
  site: string;
  valueCm: number;
}

/** steps_zh 等列存 JSON 数组文本，解码失败返回空数组。 */
export function decodeList(json: string | null): string[] {
  if (json === null || json.length === 0) {
    return [];
  }
  try {
    return JSON.parse(json) as string[];
  } catch (e) {
    return [];
  }
}
