import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

const KEY_ALIAS: string = 'coachpal_llm_key';

/** AI 来源常量：device=华为端侧模型；custom=自定义接口。 */
export class AiSource {
  static readonly DEVICE: string = 'device';
  static readonly CUSTOM: string = 'custom';
}

/** 自定义模型接口协议：openai=/chat/completions；anthropic=/v1/messages。 */
export class LlmProtocol {
  static readonly OPENAI: string = 'openai';
  static readonly ANTHROPIC: string = 'anthropic';
}

function strToBytes(s: string): Uint8Array {
  return new util.TextEncoder().encodeInto(s);
}

function bytesToStr(b: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(b);
}

function keyQuery(): asset.AssetMap {
  const q: asset.AssetMap = new Map();
  q.set(asset.Tag.ALIAS, strToBytes(KEY_ALIAS));
  return q;
}

/** 轻量设置（Preferences）；自定义模型的 API Key 存 AssetStoreKit（密钥库，非明文 Preferences）。 */
export class Settings {
  private store: preferences.Preferences | null = null;

  async init(context: common.Context): Promise<void> {
    const opts: preferences.Options = { name: 'coachpal_prefs' };
    this.store = await preferences.getPreferences(context, opts);
  }

  private s(): preferences.Preferences {
    if (this.store === null) {
      throw new Error('Settings 未初始化（先调用 init）');
    }
    return this.store;
  }

  // ------------------------------------------------------- AI 来源

  async getAiSource(): Promise<string> {
    const v = await this.s().get('ai_source', AiSource.DEVICE);
    return v as string;
  }

  async setAiSource(v: string): Promise<void> {
    await this.s().put('ai_source', v);
    await this.s().flush();
  }

  // ------------------------------------------------------- 自定义模型（OpenAI 兼容）

  async getLlmBaseUrl(): Promise<string> {
    const v = await this.s().get('llm_base_url', '');
    return v as string;
  }

  async setLlmBaseUrl(v: string): Promise<void> {
    await this.s().put('llm_base_url', v);
    await this.s().flush();
  }

  async getLlmModel(): Promise<string> {
    const v = await this.s().get('llm_model', '');
    return v as string;
  }

  async setLlmModel(v: string): Promise<void> {
    await this.s().put('llm_model', v);
    await this.s().flush();
  }

  async getLlmProtocol(): Promise<string> {
    const v = await this.s().get('llm_protocol', LlmProtocol.OPENAI);
    return v as string;
  }

  async setLlmProtocol(v: string): Promise<void> {
    await this.s().put('llm_protocol', v);
    await this.s().flush();
  }

  // ------------------------------------------------------- API Key（AssetStoreKit）

  async getLlmApiKey(): Promise<string | null> {
    const q = keyQuery();
    q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(q);
      if (results.length === 0) {
        return null;
      }
      const secret = results[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return null;
      }
      return bytesToStr(secret);
    } catch (e) {
      // 24000002 未找到视为未配置
      return null;
    }
  }

  /** 覆盖写（CONFLICT_RESOLUTION.OVERWRITE 幂等）。 */
  async saveLlmApiKey(v: string): Promise<void> {
    const m: asset.AssetMap = new Map();
    m.set(asset.Tag.ALIAS, strToBytes(KEY_ALIAS));
    m.set(asset.Tag.SECRET, strToBytes(v));
    m.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(m);
  }

  async clearLlmApiKey(): Promise<void> {
    try {
      await asset.remove(keyQuery());
    } catch (e) {
      // 不存在即已清除
    }
  }

  /** AI 是否可用：端侧模型默认可用；自定义需接口地址/Key/模型名齐备。 */
  async isAiConfigured(): Promise<boolean> {
    const source = await this.getAiSource();
    if (source === AiSource.DEVICE) {
      return true;
    }
    const url = await this.getLlmBaseUrl();
    if (url.length === 0) {
      return false;
    }
    const model = await this.getLlmModel();
    if (model.length === 0) {
      return false;
    }
    const key = await this.getLlmApiKey();
    return key !== null && key.length > 0;
  }
}
