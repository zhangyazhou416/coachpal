import { Repo } from '../repo/Repo';
import { ExerciseRow, decodeList } from '../repo/Model';
import { ZH_ALIASES, EQUIPMENT_ZH, MUSCLE_ZH, CATEGORY_ZH } from '../domain/set_parser';

/** 用户消息里的动作问句修饰词，本地匹配前剔除。 */
const EXERCISE_QUERY_NOISE: RegExp =
  /怎么做|怎么练|怎么完成|是什么|介绍一下|给我看看|想看|示范|教学|动作要领|要领|标准|的动作|动作|怎么|如何|\?|？|。|！|!/g;

/** 中文别名键按长度降序：命中时「上斜卧推」优先于「卧推」。 */
const ALIAS_KEYS_BY_LEN: string[] = Object.keys(ZH_ALIASES)
  .sort((a: string, b: string): number => b.length - a.length);

/**
 * 动作技能：本地动作库解析 + 离线动作讲解。
 * 不依赖任何模型，可被工具执行器（get_exercise）、端侧模型兜底、
 * 模型失败离线兜底等任意路径独立调用。
 */
export class ExerciseSkill {
  /** 从用户原话解析动作：先按清洗后的整句，再按包含的最长中文别名。 */
  static async resolveFromUserText(repo: Repo, text: string): Promise<ExerciseRow | null> {
    const cleaned = text.replace(EXERCISE_QUERY_NOISE, '').trim();
    if (cleaned.length === 0) {
      return null;
    }
    const direct = await ExerciseSkill.resolveQuery(repo, cleaned);
    if (direct !== null) {
      return direct;
    }
    for (const key of ALIAS_KEYS_BY_LEN) {
      if (cleaned.includes(key)) {
        const hit = await ExerciseSkill.resolveQuery(repo, key);
        if (hit !== null) {
          return hit;
        }
      }
    }
    return null;
  }

  /** 按名称/别名/子串解析动作（与工具调用共用的单一入口）。 */
  static async resolveQuery(repo: Repo, query: string): Promise<ExerciseRow | null> {
    return repo.resolveExercise(query);
  }

  /** 离线动作讲解文案：模型不可用时也能给出完整要领。 */
  static summarize(ex: ExerciseRow): string {
    const lines: string[] = [`「${ex.name}」动作讲解`];
    const tags: string[] = [];
    if (ex.equip !== null) {
      tags.push(`器械：${EQUIPMENT_ZH[ex.equip] ?? ex.equip}`);
    }
    if (ex.target !== null) {
      tags.push(`主练：${MUSCLE_ZH[ex.target] ?? ex.target}`);
    }
    if (ex.cat !== null) {
      tags.push(`类别：${CATEGORY_ZH[ex.cat] ?? ex.cat}`);
    }
    if (tags.length > 0) {
      lines.push(tags.join(' · '));
    }
    const steps = decodeList(ex.stepsZh);
    if (steps.length > 0) {
      lines.push('动作要领：');
      for (const s of steps) {
        lines.push(`· ${s}`);
      }
    }
    return lines.join('\n');
  }
}
