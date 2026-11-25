import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

const TOKEN_ALIAS: string = 'coachpal_token';

function strToBytes(s: string): Uint8Array {
  return new util.TextEncoder().encodeInto(s);
}

function bytesToStr(b: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(b);
}

function tokenQuery(): asset.AssetMap {
  const q: asset.AssetMap = new Map();
  q.set(asset.Tag.ALIAS, strToBytes(TOKEN_ALIAS));
  return q;
}

/** 轻量设置（Preferences）；登录令牌存 AssetStoreKit（密钥库，非明文 Preferences）。 */
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

  async getServerUrl(): Promise<string> {
    const v = await this.s().get('server_url', '');
    return v as string;
  }

  async setServerUrl(v: string): Promise<void> {
    await this.s().put('server_url', v);
    await this.s().flush();
  }

  async getAutoSync(): Promise<boolean> {
    const v = await this.s().get('auto_sync', false);
    return v as boolean;
  }

  async setAutoSync(v: boolean): Promise<void> {
    await this.s().put('auto_sync', v);
    await this.s().flush();
  }

  /** 资产导出版本（meta.exported_at），仅展示用。 */
  async getAssetMeta(): Promise<string> {
    const v = await this.s().get('asset_meta', '');
    return v as string;
  }

  async setAssetMeta(v: string): Promise<void> {
    await this.s().put('asset_meta', v);
    await this.s().flush();
  }

  // ------------------------------------------------------- token（AssetStoreKit）

  async getToken(): Promise<string | null> {
    const q = tokenQuery();
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
      // 24000002 未找到视为未登录
      return null;
    }
  }

  /** 覆盖写（CONFLICT_RESOLUTION.OVERWRITE 幂等）。 */
  async saveToken(v: string): Promise<void> {
    const m: asset.AssetMap = new Map();
    m.set(asset.Tag.ALIAS, strToBytes(TOKEN_ALIAS));
    m.set(asset.Tag.SECRET, strToBytes(v));
    m.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(m);
  }

  async clearToken(): Promise<void> {
    try {
      await asset.remove(tokenQuery());
    } catch (e) {
      // 不存在即已清除
    }
  }

  /** 服务器地址与 token 齐备才算已配置。 */
  async isConfigured(): Promise<boolean> {
    const url = await this.getServerUrl();
    if (url.length === 0) {
      return false;
    }
    const token = await this.getToken();
    return token !== null && token.length > 0;
  }
}
