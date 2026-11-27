import { hilog } from '@kit.PerformanceAnalysisKit';
import { Repo } from '../repo/Repo';
import {
  ExerciseRow, CustomItemInput, BodyMetricRow, WorkoutEntry, StrengthLogRow, decodeList,
} from '../repo/Model';
import { ParsedSet, CATEGORY_ZH, EQUIPMENT_ZH, MUSCLE_ZH } from '../domain/set_parser';
import { computeTargets, Targets } from '../domain/calc';
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
  enum?: string[];
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

const TARGETS_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {},
  required: [],
};

const DIET_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {},
  required: [],
};

const GOAL_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    'kind': {
      type: 'string',
      description: '目标类型',
      properties: {},
      required: [],
      enum: ['weight', 'body_fat', 'muscle'],
    },
    'target': strSchema('目标数值：体重 kg / 体脂率 % / 骨骼肌 kg'),
    'target_date': strSchema('目标达成日期 YYYY-MM-DD，可选'),
  },
  required: ['kind', 'target'],
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
  {
    name: 'get_daily_targets',
    description: '根据档案（性别/年龄/身高/活动水平/目标）与最新体重计算每日摄入目标：热量、蛋白质、脂肪、碳水、纤维。用户问「每天该吃多少/摄入目标是多少/宏量怎么分配」时调用。',
    schema: TARGETS_SCHEMA,
  },
  {
    name: 'get_diet_status',
    description: '今日已摄入 vs 每日目标对比：剩余热量与各营养素余量、三大营养素供能占比（附参考区间）。用户问「今天还需要吃多少/吃得够不够/饮食结构是否合理」时调用。',
    schema: DIET_SCHEMA,
  },
  {
    name: 'set_goal',
    description: '设置目标：目标体重 kg / 体脂率 % / 骨骼肌量 kg。用户说「目标体重 72kg」「减脂到 15%」等时调用；设置后结合 get_recent_summary 给出训练方案建议。',
    schema: GOAL_SCHEMA,
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
  kind?: string;
  target?: number;
  target_date?: string;
  name?: string;
  sets?: RawWorkoutSet[];
}

// ------------------------------------------------------- 执行结果

interface TargetsPair {
  t: Targets | null;
  hint: string;
}

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
      if (name === 'get_daily_targets') {
        return await CoachTools.dailyTargets(repo);
      }
      if (name === 'get_diet_status') {
        return await CoachTools.dietStatus(repo);
      }
      if (name === 'set_goal') {
        return await CoachTools.setGoal(repo, raw);
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


  private static ageFromBirth(birth: string | null): number | null {
    if (birth === null || birth.length < 10) {
      return null;
    }
    const y = Number(birth.substring(0, 4));
    const m = Number(birth.substring(5, 7));
    if (Number.isNaN(y) || Number.isNaN(m)) {
      return null;
    }
    const now = new Date();
    let age = now.getFullYear() - y;
    if (now.getMonth() + 1 < m) {
      age--;
    }
    return age;
  }

  private static goalTypeLabel(t: string): string {
    if (t === 'cut') {
      return '减脂';
    }
    if (t === 'bulk') {
      return '增肌';
    }
    return '维持';
  }

  /** 档案 + 最新体重 → 每日摄入目标。null 表示资料不足。 */
  private static async computeUserTargets(repo: Repo): Promise<TargetsPair> {
    const profile = await repo.getProfile();
    const metrics = await repo.listMetrics();
    const weight = metrics.length > 0 ? metrics[0].weightKg : null;
    const t = computeTargets(
      profile === null ? null : profile.sex,
      CoachTools.ageFromBirth(profile === null ? null : profile.birthDate),
      profile === null ? null : profile.heightCm,
      weight,
      profile === null ? 'moderate' : profile.activityLevel,
      profile === null ? 'maintain' : profile.goalType,
    );
    let hint = '';
    if (t === null) {
      const missing: string[] = [];
      if (profile === null) {
        missing.push('档案（性别/年龄/身高/活动水平/目标）');
      } else {
        if (profile.heightCm === null) {
          missing.push('身高');
        }
      }
      if (weight === null) {
        missing.push('体重');
      }
      hint = `还缺少：${missing.join('、')}。请用户直接告诉教练这些信息。`;
    }
    const out: TargetsPair = { t: t, hint: hint };
    return out;
  }

  private static async dailyTargets(repo: Repo): Promise<ToolOutcome> {
    const pair = await CoachTools.computeUserTargets(repo);
    if (pair.t === null) {
      return new ToolOutcome(pair.hint, null, null);
    }
    const t = pair.t;
    const profile = await repo.getProfile();
    const goalText = profile === null ? '维持' : CoachTools.goalTypeLabel(profile.goalType);
    const lines: string[] = [
      `目标类型：${goalText}`,
      `BMR ${t.bmr} kcal · TDEE ${t.tdee} kcal`,
      `每日摄入目标：${t.kcal} kcal`,
      `蛋白质 ${t.protein}g · 脂肪 ${t.fat}g · 碳水 ${t.carbs}g · 纤维 ${t.fiber}g`,
    ];
    if (t.clamped) {
      lines.push('（热量已按安全下限抬高）');
    }
    lines.push('请基于以上数值给用户解释每日应摄入多少热量与三大营养素。');
    return new ToolOutcome(lines.join('\n'), null, null);
  }

  private static async dietStatus(repo: Repo): Promise<ToolOutcome> {
    const pair = await CoachTools.computeUserTargets(repo);
    if (pair.t === null) {
      return new ToolOutcome(pair.hint, null, null);
    }
    const t = pair.t;
    const today = todayIso();
    const meals = await repo.listMeals(today);
    let kcal = 0;
    let protein = 0;
    let fat = 0;
    let carbs = 0;
    let itemCount = 0;
    const mealLines: string[] = [];
    for (const m of meals) {
      let mk = 0;
      for (const it of m.items) {
        kcal += it.kcal;
        protein += it.protein;
        fat += it.fat;
        carbs += it.carbs;
        mk += it.kcal;
        itemCount++;
      }
      mealLines.push(`${mealLabel(m.meal.mealType)}（${m.meal.date}）：约 ${Math.round(mk)} kcal`);
    }
    const rK = Math.round(t.kcal - kcal);
    const rP = Math.round(t.protein - protein);
    const rF = Math.round(t.fat - fat);
    const rC = Math.round(t.carbs - carbs);
    const lines: string[] = [
      `每日目标：${t.kcal} kcal（蛋白 ${t.protein}g / 脂肪 ${t.fat}g / 碳水 ${t.carbs}g）`,
      meals.length > 0
        ? `今日已摄入（${today}）：${Math.round(kcal)} kcal（蛋白 ${Math.round(protein)}g / 脂肪 ${Math.round(fat)}g / 碳水 ${Math.round(carbs)}g），${meals.length} 餐共 ${itemCount} 项`
        : `今日（${today}）还没有饮食记录`,
      `剩余：热量 ${rK} kcal · 蛋白 ${rP}g · 脂肪 ${rF}g · 碳水 ${rC}g`,
    ];
    if (mealLines.length > 0) {
      lines.push(`今日明细：\n${mealLines.join('\n')}`);
    }
    const macroKcal = protein * 4 + fat * 9 + carbs * 4;
    if (macroKcal > 0) {
      const pp = Math.round(protein * 4 / macroKcal * 100);
      const ff = Math.round(fat * 9 / macroKcal * 100);
      const cc = 100 - pp - ff;
      lines.push(`三大营养素供能占比：蛋白 ${pp}% / 脂肪 ${ff}% / 碳水 ${cc}%（一般参考：蛋白 10-20%、脂肪 20-30%、碳水 50-60%）`);
    }
    lines.push('请对比目标与实际，指出剩余量、结构是否合理并给出调整建议。');
    return new ToolOutcome(lines.join('\n'), null, null);
  }

  private static async setGoal(repo: Repo, raw: RawArgs): Promise<ToolOutcome> {
    const kind = (raw.kind ?? '').trim();
    if (kind !== 'weight' && kind !== 'body_fat' && kind !== 'muscle') {
      return new ToolOutcome('kind 只支持 weight / body_fat / muscle', null, null);
    }
    const target = raw.target;
    if (target === undefined || target === null || target <= 0) {
      return new ToolOutcome('缺少有效的 target 数值', null, null);
    }
    const date = typeof raw.target_date === 'string' && raw.target_date.length === 10
      ? raw.target_date : null;
    await repo.addGoal(kind, target, date);
    const kindLabel = kind === 'weight' ? '体重' : (kind === 'body_fat' ? '体脂率' : '骨骼肌量');
    const unit = kind === 'body_fat' ? '%' : 'kg';
    const metrics = await repo.listMetrics();
    let current = '未知';
    if (metrics.length > 0) {
      const w = metrics[0].weightKg;
      const bf = metrics[0].bodyFatPct;
      const mu = metrics[0].skeletalMuscleKg;
      const v = kind === 'weight' ? w : (kind === 'body_fat' ? bf : mu);
      if (v !== null) {
        current = `${v}${unit}`;
      }
    }
    const note = `🎯 目标已设置：${kindLabel} → ${target}${unit}${date === null ? '' : `（${date} 前）`}，当前 ${current}`;
    const forModel = `目标已保存：${kindLabel} → ${target}${unit}（当前 ${current}）。` +
      '请调用 get_recent_summary 了解现状后，给出达成该目标的训练方案（频率/动作/组次/进阶）与饮食要点。';
    return new ToolOutcome(forModel, note, null);
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
