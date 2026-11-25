import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 轻量设置（Preferences）。登录令牌的安全存储走 AssetStoreKit（loadToken/saveToken）。 */
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
}
