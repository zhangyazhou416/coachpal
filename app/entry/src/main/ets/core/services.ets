import { common } from '@kit.AbilityKit';
import { Db } from './db/Db';
import { ChangeBus } from './db/ChangeBus';
import { Seed } from './db/Seed';
import { Repo } from './repo/Repo';
import { Settings } from './settings/Settings';

/** 全局服务单例：EntryAbility.onCreate 里 init（不阻塞），页面 await whenReady() 后取 db/repo。 */
export class AppServices {
  private static instance: AppServices | null = null;

  readonly bus: ChangeBus = new ChangeBus();
  readonly settings: Settings = new Settings();
  db: Db | null = null;
  repo: Repo | null = null;
  private ctx: common.Context | null = null;
  private readyPromise: Promise<void> | null = null;

  static getInstance(): AppServices {
    if (AppServices.instance === null) {
      AppServices.instance = new AppServices();
    }
    return AppServices.instance;
  }

  /** 幂等初始化（EntryAbility 调用一次）。 */
  async init(context: common.Context): Promise<void> {
    if (this.readyPromise !== null) {
      return this.readyPromise;
    }
    this.ctx = context;
    this.readyPromise = this.bootstrap();
    return this.readyPromise;
  }

  /** 页面入口：等待库就绪（幂等）。 */
  whenReady(): Promise<void> {
    if (this.readyPromise === null) {
      return Promise.reject(new Error('AppServices 未初始化（EntryAbility.onCreate 未调用 init）'));
    }
    return this.readyPromise;
  }

  private async bootstrap(): Promise<void> {
    const ctx = this.ctx;
    if (ctx === null) {
      throw new Error('AppServices init 缺少 context');
    }
    const db = await Db.open(ctx);
    this.db = db;
    const repo = new Repo(db, this.bus);
    this.repo = repo;
    await this.settings.init(ctx);
    // 参考数据后台导入，完成后清 repo 缓存；失败不阻塞应用
    new Seed(db, ctx, this.settings).run()
      .then((): void => {
        repo.invalidateCaches();
      })
      .catch((e: Error): void => {
        console.error('[CoachPal] seed failed: ' + e.message);
      });
  }
}
