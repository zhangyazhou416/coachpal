import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Db, Row } from '../db/Db';
import { ChangeBus } from '../db/ChangeBus';
import { nowUtc, todayIso, dateDaysAgo } from '../util/Time';
import { estimate1rm } from '../domain/calc';
import { FoodHit, FoodRow, scoreFoods, scaleMacros } from '../domain/food_search';
import { Macros } from '../domain/food_search';
import { ParsedSet, ZH_ALIASES } from '../domain/set_parser';
import {
  ProfileRow, BodyMetricRow, MeasurementRow, GoalRow, StrengthLogRow,
  MealRow, MealItemRow, WorkoutRow, WorkoutSetRow, ExerciseRow,
  MealEntry, WorkoutEntry, StrengthResult, StrengthSeries, SeriesPoint,
  FoodPortion, CustomItemInput, MeasurementInput,
} from './Model';

function pred(table: string): relationalStore.RdbPredicates {
  return new relationalStore.RdbPredicates(table);
}

function mapProfile(r: Row): ProfileRow {
  const p: ProfileRow = {
    id: r.num('id') ?? 1,
    sex: r.str('sex') ?? 'male',
    birthDate: r.str('birth_date'),
    heightCm: r.num('height_cm'),
    activityLevel: r.str('activity_level') ?? 'moderate',
    goalType: r.str('goal_type') ?? 'maintain',
    updatedAt: r.str('updated_at') ?? '',
  };
  return p;
}

function mapBodyMetric(r: Row): BodyMetricRow {
  const m: BodyMetricRow = {
    uuid: r.str('uuid') ?? '',
    date: r.str('date') ?? '',
    weightKg: r.num('weight_kg'),
    bodyFatPct: r.num('body_fat_pct'),
    skeletalMuscleKg: r.num('skeletal_muscle_kg'),
    note: r.str('note'),
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return m;
}

function mapMeasurement(r: Row): MeasurementRow {
  const m: MeasurementRow = {
    uuid: r.str('uuid') ?? '',
    date: r.str('date') ?? '',
    site: r.str('site') ?? '',
    valueCm: r.num('value_cm') ?? 0,
    note: r.str('note'),
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return m;
}

function mapGoal(r: Row): GoalRow {
  const g: GoalRow = {
    uuid: r.str('uuid') ?? '',
    kind: r.str('kind') ?? '',
    targetValue: r.num('target_value') ?? 0,
    unit: r.str('unit'),
    baselineValue: r.num('baseline_value'),
    targetDate: r.str('target_date'),
    status: r.str('status') ?? 'active',
    note: r.str('note'),
    createdAt: r.str('created_at') ?? '',
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return g;
}

function mapStrengthLog(r: Row): StrengthLogRow {
  const l: StrengthLogRow = {
    uuid: r.str('uuid') ?? '',
    date: r.str('date') ?? '',
    lift: r.str('lift') ?? '',
    weightKg: r.num('weight_kg') ?? 0,
    reps: Math.round(r.num('reps') ?? 0),
    rpe: r.num('rpe'),
    estimated1rm: r.num('estimated_1rm') ?? 0,
    note: r.str('note'),
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return l;
}

function mapMeal(r: Row): MealRow {
  const m: MealRow = {
    uuid: r.str('uuid') ?? '',
    date: r.str('date') ?? '',
    mealType: r.str('meal_type') ?? '',
    note: r.str('note'),
    createdAt: r.str('created_at') ?? '',
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return m;
}

function mapMealItem(r: Row): MealItemRow {
  const m: MealItemRow = {
    uuid: r.str('uuid') ?? '',
    mealUuid: r.str('meal_uuid') ?? '',
    foodId: r.num('food_id') === null ? null : Math.round(r.num('food_id') ?? 0),
    foodName: r.str('food_name') ?? '',
    grams: r.num('grams') ?? 0,
    kcal: r.num('kcal') ?? 0,
    protein: r.num('protein') ?? 0,
    fat: r.num('fat') ?? 0,
    carbs: r.num('carbs') ?? 0,
    fiber: r.num('fiber'),
    source: r.str('source') ?? 'db',
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return m;
}

function mapWorkout(r: Row): WorkoutRow {
  const w: WorkoutRow = {
    uuid: r.str('uuid') ?? '',
    date: r.str('date') ?? '',
    name: r.str('name'),
    note: r.str('note'),
    createdAt: r.str('created_at') ?? '',
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return w;
}

function mapWorkoutSet(r: Row): WorkoutSetRow {
  const s: WorkoutSetRow = {
    uuid: r.str('uuid') ?? '',
    workoutUuid: r.str('workout_uuid') ?? '',
    exerciseId: r.num('exercise_id') === null ? null : Math.round(r.num('exercise_id') ?? 0),
    exerciseName: r.str('exercise_name') ?? '',
    setNo: r.num('set_no') === null ? null : Math.round(r.num('set_no') ?? 0),
    weightKg: r.num('weight_kg'),
    reps: r.num('reps') === null ? null : Math.round(r.num('reps') ?? 0),
    rpe: r.num('rpe'),
    updatedAt: r.str('updated_at') ?? '',
    deleted: r.num('deleted') ?? 0,
  };
  return s;
}

function mapExercise(r: Row): ExerciseRow {
  const e: ExerciseRow = {
    id: r.str('id') ?? '',
    name: r.str('name') ?? '',
    cat: r.str('cat'),
    equip: r.str('equip'),
    target: r.str('target'),
    secondary: r.str('secondary'),
    stepsEn: r.str('steps_en'),
    stepsZh: r.str('steps_zh'),
    gifPath: r.str('gif_path'),
    thumbPath: r.str('thumb_path'),
  };
  return e;
}

/** 仓库层：UI 与数据库/领域计算之间的桥。所有业务写入都走这里（保证 uuid/时间戳/联动正确）。 */
export class Repo {
  private db: Db;
  private bus: ChangeBus;
  private foodsCache: FoodRow[] | null = null;
  private exercisesCache: ExerciseRow[] | null = null;

  constructor(db: Db, bus: ChangeBus) {
    this.db = db;
    this.bus = bus;
  }

  private newUuid(): string {
    return util.generateRandomUUID(true);
  }

  /** Seed 导入后清缓存（foods/exercises 一次性载入）。 */
  invalidateCaches(): void {
    this.foodsCache = null;
    this.exercisesCache = null;
  }

  // ------------------------------------------------------- profile

  async getProfile(): Promise<ProfileRow | null> {
    const p = pred('profile');
    p.equalTo('id', 1);
    const r = await this.db.queryOne(p);
    return r === null ? null : mapProfile(r);
  }

  async saveProfile(sex: string, heightCm: number | null, activityLevel: string, goalType: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'sex': sex,
      'height_cm': heightCm,
      'activity_level': activityLevel,
      'goal_type': goalType,
      'updated_at': nowUtc(),
    };
    const p = pred('profile');
    p.equalTo('id', 1);
    await this.db.update(bucket, p);
    this.bus.emit(['profile']);
  }

  // ------------------------------------------------------- 身体

  /** 体重/体脂/骨骼肌：按日期 upsert（复用已有 uuid，未提供的字段保留旧值）。 */
  async saveBodyMetric(date: string, weightKg: number | null, bodyFatPct: number | null,
    skeletalMuscleKg: number | null, note: string | null): Promise<void> {
    const now = nowUtc();
    const p = pred('body_metrics');
    p.equalTo('date', date);
    const existing = await this.db.queryOne(p);
    const uuid = existing !== null ? (existing.str('uuid') ?? this.newUuid()) : this.newUuid();
    const bucket: relationalStore.ValuesBucket = {
      'uuid': uuid,
      'date': date,
      'weight_kg': weightKg ?? (existing !== null ? existing.num('weight_kg') : null),
      'body_fat_pct': bodyFatPct ?? (existing !== null ? existing.num('body_fat_pct') : null),
      'skeletal_muscle_kg': skeletalMuscleKg ?? (existing !== null ? existing.num('skeletal_muscle_kg') : null),
      'note': note ?? (existing !== null ? existing.str('note') : null),
      'updated_at': now,
      'deleted': 0,
    };
    await this.db.insertOrReplace('body_metrics', bucket);
    this.bus.emit(['body_metrics']);
  }

  async addWeight(kg: number, bodyFat: number | null): Promise<void> {
    await this.saveBodyMetric(todayIso(), kg, bodyFat, null, null);
  }

  async listMetrics(): Promise<BodyMetricRow[]> {
    const p = pred('body_metrics');
    p.equalTo('deleted', 0).orderByDesc('date');
    const rows = await this.db.query(p);
    return rows.map((r: Row): BodyMetricRow => mapBodyMetric(r));
  }

  // ------------------------------------------------------- 围度

  /** 按 (date, site) upsert：复用已有 uuid，避免二级唯一索引冲突换主键。 */
  async addMeasurements(date: string, inputs: MeasurementInput[]): Promise<void> {
    const now = nowUtc();
    await this.db.tx(async (): Promise<void> => {
      for (const input of inputs) {
        const p = pred('measurements');
        p.equalTo('date', date).equalTo('site', input.site);
        const existing = await this.db.queryOne(p);
        const uuid = existing !== null ? (existing.str('uuid') ?? this.newUuid()) : this.newUuid();
        const bucket: relationalStore.ValuesBucket = {
          'uuid': uuid,
          'date': date,
          'site': input.site,
          'value_cm': input.valueCm,
          'note': null,
          'updated_at': now,
          'deleted': 0,
        };
        await this.db.insertOrReplace('measurements', bucket);
      }
    });
    this.bus.emit(['measurements']);
  }

  async listMeasurements(): Promise<MeasurementRow[]> {
    const p = pred('measurements');
    p.equalTo('deleted', 0).orderByAsc('date');
    const rows = await this.db.query(p);
    return rows.map((r: Row): MeasurementRow => mapMeasurement(r));
  }

  // ------------------------------------------------------- 目标

  async listGoals(): Promise<GoalRow[]> {
    const p = pred('goals');
    p.equalTo('deleted', 0).orderByAsc('created_at');
    const rows = await this.db.query(p);
    return rows.map((r: Row): GoalRow => mapGoal(r));
  }

  async addGoal(kind: string, target: number, targetDate?: string | null): Promise<void> {
    const now = nowUtc();
    let unit: string;
    if (kind === 'weight' || kind === 'muscle') {
      unit = 'kg';
    } else if (kind === 'body_fat') {
      unit = '%';
    } else {
      unit = 'cm';
    }
    const baseline = await this.currentValueForKind(kind);
    const bucket: relationalStore.ValuesBucket = {
      'uuid': this.newUuid(),
      'kind': kind,
      'target_value': target,
      'unit': unit,
      'baseline_value': baseline,
      'target_date': targetDate ?? null,
      'status': 'active',
      'note': null,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    };
    await this.db.insert('goals', bucket);
    this.bus.emit(['goals']);
  }

  private async currentValueForKind(kind: string): Promise<number | null> {
    if (kind === 'weight') {
      const p = pred('body_metrics');
      p.equalTo('deleted', 0).isNotNull('weight_kg').orderByDesc('date');
      const r = await this.db.queryOne(p);
      return r === null ? null : r.num('weight_kg');
    }
    if (kind === 'body_fat') {
      const p = pred('body_metrics');
      p.equalTo('deleted', 0).isNotNull('body_fat_pct').orderByDesc('date');
      const r = await this.db.queryOne(p);
      return r === null ? null : r.num('body_fat_pct');
    }
    if (kind === 'muscle') {
      const p = pred('body_metrics');
      p.equalTo('deleted', 0).isNotNull('skeletal_muscle_kg').orderByDesc('date');
      const r = await this.db.queryOne(p);
      return r === null ? null : r.num('skeletal_muscle_kg');
    }
    if (kind.startsWith('measure:')) {
      const site = kind.split(':')[1];
      const p = pred('measurements');
      p.equalTo('site', site).equalTo('deleted', 0).orderByDesc('date');
      const r = await this.db.queryOne(p);
      return r === null ? null : r.num('value_cm');
    }
    if (kind.startsWith('strength:')) {
      const lift = kind.split(':')[1];
      const p = pred('strength_logs');
      p.equalTo('lift', lift).equalTo('deleted', 0).orderByDesc('estimated_1rm');
      const r = await this.db.queryOne(p);
      return r === null ? null : r.num('estimated_1rm');
    }
    return null;
  }

  // ------------------------------------------------------- 力量

  async listStrengthLogs(): Promise<StrengthLogRow[]> {
    const p = pred('strength_logs');
    p.equalTo('deleted', 0).orderByDesc('date');
    const rows = await this.db.query(p);
    return rows.map((r: Row): StrengthLogRow => mapStrengthLog(r));
  }

  async addStrength(lift: string, weight: number, reps: number,
    rpe?: number | null, date?: string): Promise<StrengthResult> {
    const now = nowUtc();
    const d = date ?? todayIso();
    const estimated = estimate1rm(weight, reps);
    const p = pred('strength_logs');
    p.equalTo('lift', lift).equalTo('deleted', 0).orderByDesc('estimated_1rm');
    const prevRow = await this.db.queryOne(p);
    const prev = prevRow === null ? null : prevRow.num('estimated_1rm');
    const isPr = prev === null || estimated > prev;
    const bucket: relationalStore.ValuesBucket = {
      'uuid': this.newUuid(),
      'date': d,
      'lift': lift,
      'weight_kg': weight,
      'reps': reps,
      'rpe': rpe ?? null,
      'estimated_1rm': estimated,
      'note': null,
      'updated_at': now,
      'deleted': 0,
    };
    await this.db.insert('strength_logs', bucket);
    this.bus.emit(['strength_logs']);
    return new StrengthResult(estimated, isPr);
  }

  /** 每个动作按日期取当日最佳估算 1RM（与 Python progress_series 一致）。 */
  async strengthSeries(): Promise<StrengthSeries[]> {
    const p = pred('strength_logs');
    p.equalTo('deleted', 0).orderByAsc('date');
    const rows = await this.db.query(p);
    const byLift = new Map<string, Map<string, number>>();
    for (const r of rows) {
      const lift = r.str('lift') ?? '';
      const date = r.str('date') ?? '';
      const est = r.num('estimated_1rm') ?? 0;
      let day = byLift.get(lift);
      if (day === undefined) {
        day = new Map<string, number>();
        byLift.set(lift, day);
      }
      const cur = day.get(date);
      if (cur === undefined || est > cur) {
        day.set(date, est);
      }
    }
    const out: StrengthSeries[] = [];
    byLift.forEach((day: Map<string, number>, lift: string): void => {
      const points: SeriesPoint[] = [];
      day.forEach((v: number, d: string): void => {
        const pt: SeriesPoint = { date: d, value: v };
        points.push(pt);
      });
      const s: StrengthSeries = { lift: lift, points: points };
      out.push(s);
    });
    return out;
  }

  // ------------------------------------------------------- 食物 / 饮食

  private async allFoods(): Promise<FoodRow[]> {
    const cached = this.foodsCache;
    if (cached !== null) {
      return cached;
    }
    const rows = await this.db.query(pred('foods'));
    const mapped: FoodRow[] = rows.map((r: Row): FoodRow => {
      const f: FoodRow = {
        key: r.str('name') ?? '',
        foodCode: r.str('code'),
        name: r.str('name') ?? '',
        nameEn: r.str('name_en'),
        category: r.str('category'),
        kcal: r.num('kcal'),
        protein: r.num('protein'),
        fat: r.num('fat'),
        carbs: r.num('carbs'),
        fiber: r.num('fiber'),
        gi: r.num('gi'),
      };
      return f;
    });
    this.foodsCache = mapped;
    return mapped;
  }

  async searchFoods(query: string): Promise<FoodHit[]> {
    return scoreFoods(await this.allFoods(), query);
  }

  async addMeal(mealType: string, date: string, dbItems: FoodPortion[],
    customItems: CustomItemInput[], note: string | null): Promise<MealEntry> {
    const now = nowUtc();
    const mealUuid = this.newUuid();
    await this.db.tx(async (): Promise<void> => {
      const mealBucket: relationalStore.ValuesBucket = {
        'uuid': mealUuid,
        'date': date,
        'meal_type': mealType,
        'note': note,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      };
      await this.db.insert('meals', mealBucket);
      for (const portion of dbItems) {
        const m: Macros = scaleMacros(portion.food, portion.grams);
        const itemBucket: relationalStore.ValuesBucket = {
          'uuid': this.newUuid(),
          'meal_uuid': mealUuid,
          'food_id': null,
          'food_name': portion.food.name,
          'grams': portion.grams,
          'kcal': m.kcal,
          'protein': m.protein,
          'fat': m.fat,
          'carbs': m.carbs,
          'fiber': m.fiber,
          'source': 'db',
          'updated_at': now,
          'deleted': 0,
        };
        await this.db.insert('meal_items', itemBucket);
      }
      for (const c of customItems) {
        const itemBucket: relationalStore.ValuesBucket = {
          'uuid': this.newUuid(),
          'meal_uuid': mealUuid,
          'food_id': null,
          'food_name': c.name,
          'grams': c.grams,
          'kcal': c.kcal,
          'protein': c.protein,
          'fat': c.fat,
          'carbs': c.carbs,
          'fiber': c.fiber,
          'source': 'manual',
          'updated_at': now,
          'deleted': 0,
        };
        await this.db.insert('meal_items', itemBucket);
      }
    });
    const items = await this.listItemsOf(mealUuid);
    const meal: MealRow = {
      uuid: mealUuid,
      date: date,
      mealType: mealType,
      note: note,
      createdAt: now,
      updatedAt: now,
      deleted: 0,
    };
    return new MealEntry(meal, items);
  }

  /** 软删一餐及其明细（时间戳 bump 保证 LWW 推送）。 */
  async deleteMeal(mealUuid: string): Promise<void> {
    const now = nowUtc();
    const mealBucket: relationalStore.ValuesBucket = { 'deleted': 1, 'updated_at': now };
    const mp = pred('meals');
    mp.equalTo('uuid', mealUuid);
    await this.db.update(mealBucket, mp);
    const itemBucket: relationalStore.ValuesBucket = { 'deleted': 1, 'updated_at': now };
    const ip = pred('meal_items');
    ip.equalTo('meal_uuid', mealUuid);
    await this.db.update(itemBucket, ip);
    this.bus.emit(['meals', 'meal_items']);
  }

  private async listItemsOf(mealUuid: string): Promise<MealItemRow[]> {
    const p = pred('meal_items');
    p.equalTo('meal_uuid', mealUuid).equalTo('deleted', 0);
    const rows = await this.db.query(p);
    return rows.map((r: Row): MealItemRow => mapMealItem(r));
  }

  /** 某日餐次（按创建时间升序）。 */
  async listMeals(date: string): Promise<MealEntry[]> {
    const p = pred('meals');
    p.equalTo('date', date).equalTo('deleted', 0).orderByAsc('created_at');
    const rows = await this.db.query(p);
    const out: MealEntry[] = [];
    for (const r of rows) {
      const meal = mapMeal(r);
      const items = await this.listItemsOf(meal.uuid);
      out.push(new MealEntry(meal, items));
    }
    return out;
  }

  /** 近 N 天全部餐次（复盘用，按日期升序）。 */
  async listAllMeals(days: number = 30): Promise<MealEntry[]> {
    const p = pred('meals');
    p.greaterThanOrEqualTo('date', dateDaysAgo(days)).equalTo('deleted', 0).orderByAsc('date');
    const rows = await this.db.query(p);
    const out: MealEntry[] = [];
    for (const r of rows) {
      const meal = mapMeal(r);
      const items = await this.listItemsOf(meal.uuid);
      out.push(new MealEntry(meal, items));
    }
    return out;
  }

  // ------------------------------------------------------- 训练

  async allExercises(): Promise<ExerciseRow[]> {
    const cached = this.exercisesCache;
    if (cached !== null) {
      return cached;
    }
    const rows = await this.db.query(pred('exercises'));
    const mapped: ExerciseRow[] = rows.map((r: Row): ExerciseRow => mapExercise(r));
    this.exercisesCache = mapped;
    return mapped;
  }

  /** 动作解析：精确 id/名 → 中文别名关键词 → 英文子串匹配，均名最短优先。 */
  async resolveExercise(query: string): Promise<ExerciseRow | null> {
    const all = await this.allExercises();
    const ql = query.trim().toLowerCase();
    for (const e of all) {
      if (e.id.toLowerCase() === ql || e.name.toLowerCase() === ql) {
        return e;
      }
    }
    const keywords = ZH_ALIASES[query] ?? ZH_ALIASES[ql];
    if (keywords !== undefined) {
      for (const kw of keywords) {
        const k = kw.toLowerCase();
        const hits = all.filter((e: ExerciseRow): boolean => e.name.toLowerCase().includes(k));
        hits.sort((a: ExerciseRow, b: ExerciseRow): number => a.name.length - b.name.length);
        if (hits.length > 0) {
          return hits[0];
        }
      }
    }
    const contains = all.filter((e: ExerciseRow): boolean => e.name.toLowerCase().includes(ql));
    contains.sort((a: ExerciseRow, b: ExerciseRow): number => a.name.length - b.name.length);
    if (contains.length > 0) {
      return contains[0];
    }
    return null;
  }

  async addWorkout(date: string, sets: ParsedSet[], name?: string | null,
    note?: string | null): Promise<WorkoutEntry> {
    const now = nowUtc();
    const workoutUuid = this.newUuid();
    const counters = new Map<string, number>();
    await this.db.tx(async (): Promise<void> => {
      const workoutBucket: relationalStore.ValuesBucket = {
        'uuid': workoutUuid,
        'date': date,
        'name': name ?? null,
        'note': note ?? null,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
      };
      await this.db.insert('workouts', workoutBucket);
      for (const s of sets) {
        const ex = await this.resolveExercise(s.name);
        const seq = (counters.get(s.name) ?? 0) + 1;
        counters.set(s.name, seq);
        const setBucket: relationalStore.ValuesBucket = {
          'uuid': this.newUuid(),
          'workout_uuid': workoutUuid,
          'exercise_id': null,
          'exercise_name': ex !== null ? ex.name : s.name,
          'set_no': seq,
          'weight_kg': s.weightKg,
          'reps': s.reps,
          'rpe': s.rpe,
          'updated_at': now,
          'deleted': 0,
        };
        await this.db.insert('workout_sets', setBucket);
      }
    });
    return this.loadWorkout(workoutUuid);
  }

  async loadWorkout(workoutUuid: string): Promise<WorkoutEntry> {
    const wp = pred('workouts');
    wp.equalTo('uuid', workoutUuid);
    const wRow = await this.db.queryOne(wp);
    const workout = wRow === null
      ? { uuid: workoutUuid, date: '', name: null, note: null, createdAt: '', updatedAt: '', deleted: 0 } as WorkoutRow
      : mapWorkout(wRow);
    const sp = pred('workout_sets');
    sp.equalTo('workout_uuid', workoutUuid).equalTo('deleted', 0);
    const setRows = await this.db.query(sp);
    const sets: WorkoutSetRow[] = setRows.map((r: Row): WorkoutSetRow => mapWorkoutSet(r));
    return new WorkoutEntry(workout, sets);
  }

  /** 软删一次训练及其组数（时间戳 bump 保证 LWW 推送）。 */
  async deleteWorkout(workoutUuid: string): Promise<void> {
    const now = nowUtc();
    const workoutBucket: relationalStore.ValuesBucket = { 'deleted': 1, 'updated_at': now };
    const wp = pred('workouts');
    wp.equalTo('uuid', workoutUuid);
    await this.db.update(workoutBucket, wp);
    const setBucket: relationalStore.ValuesBucket = { 'deleted': 1, 'updated_at': now };
    const sp = pred('workout_sets');
    sp.equalTo('workout_uuid', workoutUuid);
    await this.db.update(setBucket, sp);
    this.bus.emit(['workouts', 'workout_sets']);
  }

  /** 近 N 天训练（日期降序）。 */
  async listWorkouts(days: number = 365): Promise<WorkoutEntry[]> {
    const p = pred('workouts');
    p.greaterThanOrEqualTo('date', dateDaysAgo(days)).equalTo('deleted', 0).orderByDesc('date');
    const rows = await this.db.query(p);
    const out: WorkoutEntry[] = [];
    for (const r of rows) {
      const workout = mapWorkout(r);
      const sp = pred('workout_sets');
      sp.equalTo('workout_uuid', workout.uuid).equalTo('deleted', 0);
      const setRows = await this.db.query(sp);
      const sets: WorkoutSetRow[] = setRows.map((x: Row): WorkoutSetRow => mapWorkoutSet(x));
      out.push(new WorkoutEntry(workout, sets));
    }
    return out;
  }
}
