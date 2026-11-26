import { hilog } from '@kit.PerformanceAnalysisKit';
import { Repo } from '../repo/Repo';
import {
  ExerciseRow, CustomItemInput, BodyMetricRow, WorkoutEntry, StrengthLogRow, decodeList,
} from '../repo/Model';
import { ParsedSet, CATEGORY_ZH, EQUIPMENT_ZH, MUSCLE_ZH } from '../domain/set_parser';
import { ExerciseSkill } from './ExerciseSkill';
import { MEAL_TYPES, mealLabel } from '../../components/Common';
import { todayIso, dateDaysAgo } from '../util/Time';

// ------------------------------------------------------- 工具 Schema（JSON Schema）

export interface JsonSchema {
  type: string;
  description?: string;
  properties: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
}

export interface OpenAiToolDef {
  type: string;
  function: OpenAiFunctionDef;
}

export interface OpenAiFunctionDef {
  name: string;
  description: string;
  parameters: JsonSchema;
}

export interface AnthropicToolDef {
  name: string;
  description: string;
  input_schema: JsonSchema;
}

interface CoachToolSpec {
  name: string;
  description: string;
  schema: JsonSchema;
}

function strSchema(desc: string): JsonSchema {
  const s: JsonSchema = { type: 'string', description: desc, properties: {} };
  return s;
}

function numSchema(desc: string): JsonSchema {
  const s: JsonSchema = { type: 'number', description: desc, properties: {} };
  return s;
}

const EXERCISE_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'query': strSchema('动作名称，中英文均可，如：卧推 / bench press / 深蹲'),
  },
  required: ['query'],
};

const FOOD_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'query': strSchema('食物名称，中英文均可，如：鸡胸肉 / 米饭'),
  },
  required: ['query'],
};

const BODY_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'weight_kg': numSchema('体重 kg，用户未提及则不传'),
    'body_fat_pct': numSchema('体脂率 %，用户未提及则不传'),
    'skeletal_muscle_kg': numSchema('骨骼肌量 kg，用户未提及则不传'),
    'date': strSchema('日期 YYYY-MM-DD，默认今天'),
  },
  required: [],
};

const MEAL_ITEM_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'name': strSchema('食物名称'),
    'grams': numSchema('克数'),
    'kcal': numSchema('该份热量 kcal（按 search_food 结果 × 克数换算，查不到则合理估算）'),
    'protein': numSchema('该份蛋白质 g'),
    'fat': numSchema('该份脂肪 g'),
    'carbs': numSchema('该份碳水 g'),
    'fiber': numSchema('该份膳食纤维 g，可选'),
  },
  required: ['name', 'grams', 'kcal', 'protein', 'fat', 'carbs'],
};

const MEAL_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'items': { type: 'array', items: MEAL_ITEM_SCHEMA, properties: {} },
    'meal_type': strSchema('餐次：breakfast/lunch/dinner/snack，未指明可不传（按时间推断）'),
    'note': strSchema('备注，可选'),
  },
  required: ['items'],
};

const WORKOUT_SET_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'exercise': strSchema('动作名称，中英文均可，如：卧推'),
    'weight_kg': numSchema('重量 kg（自重动作传 0）'),
    'reps': numSchema('次数'),
    'rpe': numSchema('RPE 主观强度 1-10，可选'),
  },
  required: ['exercise', 'weight_kg', 'reps'],
};

const WORKOUT_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'sets': { type: 'array', items: WORKOUT_SET_SCHEMA, properties: {} },
    'name': strSchema('训练名称，可选，如：推日'),
    'date': strSchema('日期 YYYY-MM-DD，默认今天'),
  },
  required: ['sets'],
};

const SUMMARY_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {},
  required: [],
};

const COACH_TOOL_SPECS: CoachToolSpec[] = [
  {
    name: 'get_exercise',
    description: '查询动作库：返回动作的器械、目标肌群、动作要领，并展示 GIF 示范图。用户询问某个动作怎么做/标准姿势/想看示范时调用。',
    schema: EXERCISE_SCHEMA,
  },
  {
    name: 'search_food',
    description: '按名称搜索食物库，返回每 100g 的热量与宏量营养（蛋白质/脂肪/碳水/纤维）。记录饮食前先调用。',
    schema: FOOD_SCHEMA,
  },
  {
    name: 'record_body_metric',
    description: '记录身体数据：体重 kg、体脂率 %、骨骼肌量 kg。用户报告体重/体脂等时调用。',
    schema: BODY_SCHEMA,
  },
  {
    name: 'record_meal',
    description: '记录一餐。先用 search_food 查询营养并按克数换算出每项的 kcal/蛋白/脂肪/碳水，再调用本工具落库。',
    schema: MEAL_SCHEMA,
  },
  {
    name: 'record_workout',
    description: '记录一次训练：每组含动作、重量 kg、次数、可选 RPE。用户报告训练内容时调用。',
    schema: WORKOUT_SCHEMA,
  },
  {
    name: 'get_recent_summary',
    description: '获取用户近期概况：最新身体数据、近 7 天饮食热量、近期训练与力量 PR。给建议前调用以了解用户现状。',
    schema: SUMMARY_SCHEMA,
  },
];

export const OPENAI_TOOLS: OpenAiToolDef[] = COACH_TOOL_SPECS.map((s: CoachToolSpec): OpenAiToolDef => {
  const fn: OpenAiFunctionDef = { name: s.name, description: s.description, parameters: s.schema };
  const t: OpenAiToolDef = { type: 'function', function: fn };
  return t;
});

export const ANTHROPIC_TOOLS: AnthropicToolDef[] = COACH_TOOL_SPECS.map((s: CoachToolSpec): AnthropicToolDef => {
  const t: AnthropicToolDef = { name: s.name, description: s.description, input_schema: s.schema };
  return t;
});

// ------------------------------------------------------- 工具入参（原始 JSON 模型）

interface RawMealItem {
  name?: string;
  grams?: number;
  kcal?: number;
  protein?: number;
  fat?: number;
  carbs?: number;
  fiber?: number;
}

interface RawWorkoutSet {
  exercise?: string;
  weight_kg?: number;
  reps?: number;
  rpe?: number;
}

interface RawArgs {
  query?: string;
  meal_type?: string;
  items?: RawMealItem[];
  note?: string;
  weight_kg?: number;
  body_fat_pct?: number;
  skeletal_muscle_kg?: number;
  date?: string;
  name?: string;
  sets?: RawWorkoutSet[];
}

// ------------------------------------------------------- 执行结果

export class ToolOutcome {
  /** 给模型看的工具结果文本。 */
  readonly resultForModel: string;
  /** 在聊天流里展示的确认气泡（如「✅ 已记录体重」），null 表示无需展示。 */
  readonly note: string | null;
  /** 命中的动作（触发 GIF 示范卡片），null 表示无。 */
  readonly exercise: ExerciseRow | null;

  constructor(resultForModel: string, note: string | null, exercise: ExerciseRow | null) {
    this.resultForModel = resultForModel;
    this.note = note;
    this.exercise = exercise;
  }
}

function num(v: number | null | undefined): string {
  return v === null || v === undefined ? '-' : String(v);
}

function guessMealType(): string {
  const h = new Date().getHours();
  if (h < 10) {
    return 'breakfast';
  }
  if (h < 15) {
    return 'lunch';
  }
  if (h < 21) {
    return 'dinner';
  }
  return 'snack';
}

/** 教练工具集：模型 Function Calling 的本地执行器（读动作/食物库、写记录）。 */
export class CoachTools {
  /** 执行工具；参数为 JSON 字符串，异常不外抛（转为失败结果给模型）。 */
  static async execute(repo: Repo, name: string, argsJson: string): Promise<ToolOutcome> {
    let raw: RawArgs = {};
    const trimmed = argsJson.trim();
    if (trimmed.length > 0) {
      try {
        raw = JSON.parse(trimmed) as RawArgs;
      } catch (e) {
        return new ToolOutcome(`参数不是合法 JSON：${trimmed.substring(0, 120)}`, null, null);
      }
    }
    try {
      if (name === 'get_exercise') {
        return await CoachTools.getExercise(repo, raw);
      }
      if (name === 'search_food') {
        return await CoachTools.searchFood(repo, raw);
      }
      if (name === 'record_body_metric') {
        return await CoachTools.recordBodyMetric(repo, raw);
      }
      if (name === 'record_meal') {
        return await CoachTools.recordMeal(repo, raw);
      }
      if (name === 'record_workout') {
        return await CoachTools.recordWorkout(repo, raw);
      }
      if (name === 'get_recent_summary') {
        return await CoachTools.recentSummary(repo);
      }
      return new ToolOutcome(`未知工具：${name}`, null, null);
    } catch (e) {
      return new ToolOutcome(`工具执行失败：${(e as Error).message}`, null, null);
    }
  }

  private static async getExercise(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const query = (raw.query ?? '').trim();
    if (query.length === 0) {
      return new ToolOutcome('参数缺少 query', null, null);
    }
    // 模型可能传整句（如「卧推怎么做」）：走用户原文解析（清洗 + 别名包含扫描），整句/单词均可命中。
    const ex = await ExerciseSkill.resolveFromUserText(repo, query);
    hilog.debug(0x0000, 'CoachPal',
      `get_exercise query="%{public}s" resolved="%{public}s"`, query, ex === null ? 'null' : ex.name);
    if (ex === null) {
      return new ToolOutcome(`动作库中未找到「${query}」。请建议用户换一种说法，或推荐相近动作。`, null, null);
    }
    const lines: string[] = [`动作：${ex.name}`];
    if (ex.equip !== null) {
      lines.push(`器械：${EQUIPMENT_ZH[ex.equip] ?? ex.equip}`);
    }
    if (ex.target !== null) {
      lines.push(`主目标肌群：${MUSCLE_ZH[ex.target] ?? ex.target}`);
    }
    if (ex.cat !== null) {
      lines.push(`类别：${CATEGORY_ZH[ex.cat] ?? ex.cat}`);
    }
    const steps = decodeList(ex.stepsZh);
    if (steps.length > 0) {
      lines.push('动作要领：');
      for (const s of steps) {
        lines.push(`- ${s}`);
      }
    }
    return new ToolOutcome(lines.join('\n'), null, ex);
  }

  private static async searchFood(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const query = (raw.query ?? '').trim();
    if (query.length === 0) {
      return new ToolOutcome('参数缺少 query', null, null);
    }
    const hits = await repo.searchFoods(query);
    if (hits.length === 0) {
      return new ToolOutcome(`食物库中未找到「${query}」，请自行合理估算营养后记录。`, null, null);
    }
    const lines: string[] = [`「${query}」的搜索结果（每 100g）：`];
    const n = Math.min(hits.length, 8);
    for (let i = 0; i < n; i++) {
      const h = hits[i];
      const en = h.nameEn === null || h.nameEn.length === 0 ? '' : ` (${h.nameEn})`;
      lines.push(`${i + 1}. ${h.name}${en}：${num(h.kcal)} kcal、蛋白 ${num(h.protein)}g、` +
        `脂肪 ${num(h.fat)}g、碳水 ${num(h.carbs)}g、纤维 ${num(h.fiber)}g`);
    }
    return new ToolOutcome(lines.join('\n'), null, null);
  }

  private static async recordBodyMetric(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const w = typeof raw.weight_kg === 'number' ? raw.weight_kg : null;
    const f = typeof raw.body_fat_pct === 'number' ? raw.body_fat_pct : null;
    const m = typeof raw.skeletal_muscle_kg === 'number' ? raw.skeletal_muscle_kg : null;
    if (w === null && f === null && m === null) {
      return new ToolOutcome('至少提供 weight_kg / body_fat_pct / skeletal_muscle_kg 之一', null, null);
    }
    const date = typeof raw.date === 'string' && raw.date.length > 0 ? raw.date : todayIso();
    await repo.saveBodyMetric(date, w, f, m, null);
    const parts: string[] = [];
    if (w !== null) {
      parts.push(`体重 ${w}kg`);
    }
    if (f !== null) {
      parts.push(`体脂 ${f}%`);
    }
    if (m !== null) {
      parts.push(`骨骼肌 ${m}kg`);
    }
    const detail = parts.join('、');
    return new ToolOutcome(`已记录（${date}）：${detail}`, `✅ 已记录身体数据：${detail}`, null);
  }

  private static async recordMeal(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const itemsRaw = raw.items ?? [];
    if (itemsRaw.length === 0) {
      return new ToolOutcome('items 不能为空', null, null);
    }
    const items: CustomItemInput[] = [];
    for (const it of itemsRaw) {
      if (typeof it.name !== 'string' || it.name.length === 0) {
        return new ToolOutcome('存在缺少 name 的条目', null, null);
      }
      const input: CustomItemInput = {
        name: it.name,
        grams: typeof it.grams === 'number' ? it.grams : 100,
        kcal: typeof it.kcal === 'number' ? it.kcal : 0,
        protein: typeof it.protein === 'number' ? it.protein : 0,
        fat: typeof it.fat === 'number' ? it.fat : 0,
        carbs: typeof it.carbs === 'number' ? it.carbs : 0,
        fiber: typeof it.fiber === 'number' ? it.fiber : 0,
      };
      items.push(input);
    }
    let mealType = typeof raw.meal_type === 'string' ? raw.meal_type : '';
    if (MEAL_TYPES.indexOf(mealType) < 0) {
      mealType = guessMealType();
    }
    const note = typeof raw.note === 'string' && raw.note.length > 0 ? raw.note : null;
    await repo.addMeal(mealType, todayIso(), [], items, note);
    let totalKcal = 0;
    for (const it of items) {
      totalKcal += it.kcal;
    }
    return new ToolOutcome(
      `已记录${mealLabel(mealType)}：${items.length} 项，共约 ${Math.round(totalKcal)} kcal`,
      `✅ 已记录${mealLabel(mealType)}：${items.length} 项 · 约 ${Math.round(totalKcal)} kcal`,
      null);
  }

  private static async recordWorkout(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const setsRaw = raw.sets ?? [];
    if (setsRaw.length === 0) {
      return new ToolOutcome('sets 不能为空', null, null);
    }
    const sets: ParsedSet[] = [];
    for (const s of setsRaw) {
      if (typeof s.exercise !== 'string' || s.exercise.length === 0) {
        return new ToolOutcome('存在缺少 exercise 的组', null, null);
      }
      const parsed: ParsedSet = {
        name: s.exercise,
        weightKg: typeof s.weight_kg === 'number' ? s.weight_kg : 0,
        reps: typeof s.reps === 'number' ? Math.round(s.reps) : 0,
        rpe: typeof s.rpe === 'number' ? s.rpe : null,
      };
      sets.push(parsed);
    }
    const name = typeof raw.name === 'string' && raw.name.length > 0 ? raw.name : null;
    const entry = await repo.addWorkout(todayIso(), sets, name, null);
    let volume = 0;
    for (const s of entry.sets) {
      volume += (s.weightKg ?? 0) * (s.reps ?? 0);
    }
    return new ToolOutcome(
      `已记录训练「${name ?? '未命名'}」：${entry.sets.length} 组，总训练量 ${volume.toFixed(0)} kg`,
      `✅ 已记录训练：${entry.sets.length} 组 · 总量 ${volume.toFixed(0)} kg`,
      null);
  }

  private static async recentSummary(repo: Repo): Promise<ToolOutcome> {
    const lines: string[] = [];
    const metrics: BodyMetricRow[] = await repo.listMetrics();
    if (metrics.length > 0) {
      const latest = metrics[0];
      const parts: string[] = [`最新身体数据（${latest.date}）：`];
      parts.push(`体重 ${latest.weightKg === null ? '未知' : `${latest.weightKg}kg`}`);
      if (latest.bodyFatPct !== null) {
        parts.push(`体脂 ${latest.bodyFatPct}%`);
      }
      if (latest.skeletalMuscleKg !== null) {
        parts.push(`骨骼肌 ${latest.skeletalMuscleKg}kg`);
      }
      lines.push(parts.join('、'));
    } else {
      lines.push('暂无身体数据记录');
    }
    const meals = await repo.listAllMeals(7);
    const cutoff = dateDaysAgo(7);
    const dayTotals = new Map<string, number>();
    for (const entry of meals) {
      let kcal = 0;
      for (const it of entry.items) {
        kcal += it.kcal;
      }
      const cur = dayTotals.get(entry.meal.date) ?? 0;
      dayTotals.set(entry.meal.date, cur + kcal);
    }
    let total = 0;
    let days = 0;
    dayTotals.forEach((v: number, k: string): void => {
      if (k > cutoff) {
        total += v;
        days++;
      }
    });
    lines.push(days > 0 ? `近 7 天饮食：记录 ${days} 天，日均 ${Math.round(total / days)} kcal` : '近 7 天无饮食记录');
    const workouts: WorkoutEntry[] = await repo.listWorkouts(30);
    const recent = workouts.slice(0, 3);
    if (recent.length > 0) {
      const wLines: string[] = [];
      for (const w of recent) {
        const setParts: string[] = [];
        for (const s of w.sets) {
          setParts.push(`${s.exerciseName} ${(s.weightKg ?? 0).toFixed(0)}kg×${s.reps ?? 0}`);
        }
        wLines.push(`${w.workout.date} ${w.workout.name ?? '未命名'}：${setParts.join('、')}`);
      }
      lines.push(`近期训练：\n${wLines.join('\n')}`);
    } else {
      lines.push('近 30 天无训练记录');
    }
    const logs: StrengthLogRow[] = await repo.listStrengthLogs();
    const byLift = new Map<string, number>();
    for (const l of logs) {
      const cur = byLift.get(l.lift) ?? 0;
      if (l.estimated1rm > cur) {
        byLift.set(l.lift, l.estimated1rm);
      }
    }
    const prs: string[] = [];
    byLift.forEach((v: number, k: string): void => {
      prs.push(`${k} ${v.toFixed(1)}kg`);
    });
    if (prs.length > 0) {
      lines.push(`力量 PR（估算 1RM）：${prs.slice(0, 8).join('、')}`);
    }
    return new ToolOutcome(lines.join('\n'), null, null);
  }
}
