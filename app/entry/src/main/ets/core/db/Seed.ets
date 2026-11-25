import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Settings } from '../settings/Settings';

interface FoodJson {
  code: string | null;
  name: string;
  en: string | null;
  cat: string | null;
  kcal: number | null;
  p: number | null;
  f: number | null;
  c: number | null;
  fiber: number | null;
  gi: number | null;
}

interface ExerciseJson {
  id: string;
  name: string;
  cat: string | null;
  equip: string | null;
  target: string | null;
  secondary: string[];
  stepsEn: string[];
  stepsZh: string[];
  gif: string | null;
  thumb: string | null;
}

interface MetaJson {
  exported_at: string;
  foods: number;
  exercises: number;
  protocol: number;
}

/** rawfile → foods/exercises 参考数据导入（空表才执行，幂等；后台跑不阻塞首帧）。 */
export class Seed {
  private db: Db;
  private ctx: common.Context;
  private settings: Settings;

  constructor(db: Db, ctx: common.Context, settings: Settings) {
    this.db = db;
    this.ctx = ctx;
    this.settings = settings;
  }

  async run(): Promise<void> {
    const t0 = Date.now();
    const foodCount = await this.db.count('foods');
    if (foodCount === 0) {
      await this.seedFoods();
    }
    const exCount = await this.db.count('exercises');
    if (exCount === 0) {
      await this.seedExercises();
    }
    await this.seedMeta();
    console.info(`[CoachPal] seed done in ${Date.now() - t0} ms (foods=${foodCount}, exercises=${exCount})`);
  }

  private async rawText(name: string): Promise<string> {
    const raw = await this.ctx.resourceManager.getRawFileContent(name);
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(raw);
  }

  private async seedFoods(): Promise<void> {
    const text = await this.rawText('foods.json');
    const items = JSON.parse(text) as FoodJson[];
    const seen = new Set<string>();
    const buckets: relationalStore.ValuesBucket[] = [];
    for (const it of items) {
      const name = it.name.trim();
      if (name.length === 0 || seen.has(name)) {
        continue;
      }
      seen.add(name);
      const b: relationalStore.ValuesBucket = {
        'name': name,
        'code': it.code,
        'name_en': it.en,
        'category': it.cat,
        'kcal': it.kcal,
        'protein': it.p,
        'fat': it.f,
        'carbs': it.c,
        'fiber': it.fiber,
        'gi': it.gi,
      };
      buckets.push(b);
    }
    await this.db.batchInsert('foods', buckets);
    console.info(`[CoachPal] foods seeded: ${buckets.length}`);
  }

  private async seedExercises(): Promise<void> {
    const text = await this.rawText('exercises.json');
    const items = JSON.parse(text) as ExerciseJson[];
    const buckets: relationalStore.ValuesBucket[] = [];
    for (const e of items) {
      const b: relationalStore.ValuesBucket = {
        'id': e.id,
        'name': e.name,
        'cat': e.cat,
        'equip': e.equip,
        'target': e.target,
        'secondary': JSON.stringify(e.secondary),
        'steps_en': JSON.stringify(e.stepsEn),
        'steps_zh': JSON.stringify(e.stepsZh),
        'gif_path': e.gif,
        'thumb_path': e.thumb,
      };
      buckets.push(b);
    }
    await this.db.batchInsert('exercises', buckets);
    console.info(`[CoachPal] exercises seeded: ${buckets.length}`);
  }

  private async seedMeta(): Promise<void> {
    try {
      const text = await this.rawText('meta.json');
      const meta = JSON.parse(text) as MetaJson;
      await this.settings.setAssetMeta(meta.exported_at);
    } catch (e) {
      console.warn('[CoachPal] meta.json read failed: ' + (e as Error).message);
    }
  }
}
