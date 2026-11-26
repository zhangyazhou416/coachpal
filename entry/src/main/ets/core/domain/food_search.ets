/// 食物搜索评分：与 coachpal.nutrition.search_foods 对齐。
/// 相似度用 LCS 比近似 difflib ratio（排序效果一致，非逐字符等价）。
/// 纯逻辑文件：禁 import @kit，保证 LocalUnit 单测可在宿主 JS 引擎运行。

/** 去括号内容、去空白/间隔符、去星号后的规范名。 */
export function normName(s: string): string {
  let t = s.toLowerCase();
  t = t.replace(/\*/g, '').replace(/＊/g, '');
  t = t.replace(/[（(［\[].*?[）)］\]]/g, '');
  t = t.replace(/[\s·,，、]+/g, '');
  return t;
}

/** 2*LCS/(len1+len2)，近似 Python difflib.SequenceMatcher.ratio。 */
export function similarity(a: string, b: string): number {
  if (a.length === 0 || b.length === 0) {
    return 0;
  }
  const m: number[][] = [];
  for (let i = 0; i <= a.length; i++) {
    const row: number[] = new Array<number>(b.length + 1);
    row.fill(0);
    m.push(row);
  }
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      m[i][j] = a[i - 1] === b[j - 1]
        ? m[i - 1][j - 1] + 1
        : (m[i - 1][j] > m[i][j - 1] ? m[i - 1][j] : m[i][j - 1]);
    }
  }
  return 2 * m[a.length][b.length] / (a.length + b.length);
}

/** foods 表缓存行（Repo 一次载入后复用）。 */
export interface FoodRow {
  key: string;
  foodCode: string | null;
  name: string;
  nameEn: string | null;
  category: string | null;
  kcal: number | null;
  protein: number | null;
  fat: number | null;
  carbs: number | null;
  fiber: number | null;
  gi: number | null;
}

/** 一条搜索命中。 */
export interface FoodHit {
  foodCode: string | null;
  name: string;
  nameEn: string | null;
  category: string | null;
  kcal: number | null;
  protein: number | null;
  fat: number | null;
  carbs: number | null;
  fiber: number | null;
  gi: number | null;
  matchScore: number;
}

interface ScoredHit {
  score: number;
  hit: FoodHit;
}

function clampDiff(d: number): number {
  return Math.max(0, Math.min(80, d));
}

function hitOf(r: FoodRow, score: number): FoodHit {
  const h: FoodHit = {
    foodCode: r.foodCode,
    name: r.name,
    nameEn: r.nameEn,
    category: r.category,
    kcal: r.kcal,
    protein: r.protein,
    fat: r.fat,
    carbs: r.carbs,
    fiber: r.fiber,
    gi: r.gi,
    matchScore: Number(score.toFixed(1)),
  };
  return h;
}

/** 全库评分搜索：分数降序、同名短名优先，取前 limit 条。 */
export function scoreFoods(rows: FoodRow[], query: string, limit: number = 15): FoodHit[] {
  const q = query.trim();
  if (q.length === 0) {
    return [];
  }
  const ql = q.toLowerCase();
  const qn = normName(q);
  const scored: ScoredHit[] = [];
  for (const r of rows) {
    const name = r.name;
    const nn = normName(name);
    const nameEn = r.nameEn === null ? '' : r.nameEn.toLowerCase();
    const category = r.category === null ? '' : r.category.toLowerCase();
    const code = r.foodCode === null ? '' : r.foodCode.toLowerCase();
    let score: number;
    if (code.length > 0 && ql === code) {
      score = 1000;
    } else if (ql === name.toLowerCase()) {
      score = 900;
    } else if (qn.length > 0 && qn === nn) {
      score = 880;
    } else if (qn.length > 0 && nn.startsWith(qn)) {
      score = 760 - clampDiff(nn.length - qn.length) * 0.5;
    } else if (qn.length > 0 && nn.includes(qn)) {
      score = 680 - clampDiff(nn.length - qn.length) * 0.5;
    } else {
      score = similarity(qn, nn) * 520;
    }
    if (nameEn.length > 0 && nameEn.includes(ql)) {
      score = score > 600 ? score : 600;
    }
    if (category.includes(ql)) {
      score = score > 320 ? score : 320;
    }
    if (score < 300) {
      continue;
    }
    scored.push({ score: score, hit: hitOf(r, score) });
  }
  scored.sort((a: ScoredHit, b: ScoredHit): number => {
    const c = b.score - a.score;
    if (c !== 0) {
      return c;
    }
    return a.hit.name.length - b.hit.name.length;
  });
  const out: FoodHit[] = [];
  const n = Math.min(scored.length, limit);
  for (let i = 0; i < n; i++) {
    out.push(scored[i].hit);
  }
  return out;
}

/** 与 Python resolve_food 一致的歧义策略；null 表示歧义（候选给 UI 弹选择）。 */
export function resolveFood(matches: FoodHit[]): FoodHit | null {
  if (matches.length === 0) {
    return null;
  }
  const top = matches[0];
  const second = matches.length > 1 ? matches[1] : null;
  const margin = top.matchScore - (second === null ? 0 : second.matchScore);
  if (top.matchScore >= 850 && (second === null || margin >= 15)) {
    return top;
  }
  if (top.matchScore >= 700 && (second === null || margin >= 40)) {
    return top;
  }
  const near: FoodHit[] = matches.filter((m: FoodHit): boolean => top.matchScore - m.matchScore <= 2);
  const rep: FoodHit[] = near.filter((m: FoodHit): boolean => m.name.includes('代表值'));
  if (rep.length === 1) {
    return rep[0];
  }
  return null;
}

export interface Macros {
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  fiber: number;
}

/** 每 100g → 指定克数换算（与 Python _scale 一致；热量缺失用 4/9/4 估算）。 */
export function scaleMacros(food: FoodHit, grams: number): Macros {
  const protein = food.protein ?? 0;
  const fat = food.fat ?? 0;
  const carbs = food.carbs ?? 0;
  const fiber = food.fiber ?? 0;
  const kcal = food.kcal ?? (protein * 4 + fat * 9 + carbs * 4);
  const f = grams / 100.0;
  const m: Macros = {
    kcal: Number((kcal * f).toFixed(1)),
    protein: Number((protein * f).toFixed(1)),
    fat: Number((fat * f).toFixed(1)),
    carbs: Number((carbs * f).toFixed(1)),
    fiber: Number((fiber * f).toFixed(1)),
  };
  return m;
}
