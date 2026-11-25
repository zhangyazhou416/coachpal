import { relationalStore } from '@kit.ArkData';
import { Http } from '../net/Http';
import { Db, Row } from '../db/Db';
import { ChangeBus } from '../db/ChangeBus';
import { Settings } from '../settings/Settings';
import { nowUtc } from '../util/Time';

/** 与服务端 SYNC_TABLES 一致的 8 张同步表（foods/exercises 为静态种子数据不参与）。 */
const SYNC_TABLES: string[] = [
  'body_metrics', 'measurements', 'goals', 'strength_logs',
  'meals', 'meal_items', 'workouts', 'workout_sets',
];
const EPOCH: string = '1970-01-01T00:00:00';

interface SyncCol {
  name: string;
  numeric: boolean;
}

function col(name: string, numeric: boolean): SyncCol {
  const c: SyncCol = { name: name, numeric: numeric };
  return c;
}

/** 本地/服务端共有的同步列（snake_case；不含服务端自增 id 与 meal_id/workout_id）。 */
const COLUMNS: Record<string, SyncCol[]> = {
  'body_metrics': [col('uuid', false), col('date', false), col('weight_kg', true),
    col('body_fat_pct', true), col('skeletal_muscle_kg', true), col('note', false),
    col('updated_at', false), col('deleted', true)],
  'measurements': [col('uuid', false), col('date', false), col('site', false),
    col('value_cm', true), col('note', false), col('updated_at', false), col('deleted', true)],
  'goals': [col('uuid', false), col('kind', false), col('target_value', true),
    col('unit', false), col('baseline_value', true), col('target_date', false),
    col('status', false), col('note', false), col('created_at', false),
    col('updated_at', false), col('deleted', true)],
  'strength_logs': [col('uuid', false), col('date', false), col('lift', false),
    col('weight_kg', true), col('reps', true), col('rpe', true),
    col('estimated_1rm', true), col('note', false), col('updated_at', false),
    col('deleted', true)],
  'meals': [col('uuid', false), col('date', false), col('meal_type', false),
    col('note', false), col('created_at', false), col('updated_at', false),
    col('deleted', true)],
  'meal_items': [col('uuid', false), col('meal_uuid', false), col('food_id', true),
    col('food_name', false), col('grams', true), col('kcal', true), col('protein', true),
    col('fat', true), col('carbs', true), col('fiber', true), col('source', false),
    col('updated_at', false), col('deleted', true)],
  'workouts': [col('uuid', false), col('date', false), col('name', false),
    col('note', false), col('created_at', false), col('updated_at', false),
    col('deleted', true)],
  'workout_sets': [col('uuid', false), col('workout_uuid', false), col('exercise_id', true),
    col('exercise_name', false), col('set_no', true), col('weight_kg', true),
    col('reps', true), col('rpe', true), col('updated_at', false), col('deleted', true)],
};

export interface SyncResult {
  ok: boolean;
  error: string | null;
}

interface PushBody {
  rows: Record<string, object[]>;
}

interface PullBody {
  since: string;
}

interface PullData {
  body_metrics?: object[];
  measurements?: object[];
  goals?: object[];
  strength_logs?: object[];
  meals?: object[];
  meal_items?: object[];
  workouts?: object[];
  workout_sets?: object[];
  _tombstones?: object[];
  _server_time?: string;
}

function asStr(v: relationalStore.ValueType | undefined): string | null {
  return typeof v === 'string' ? v : null;
}

function asNum(v: relationalStore.ValueType | undefined): number | null {
  return typeof v === 'number' ? v : null;
}

/** 双向 LWW 同步：push 本地 updated_at > 游标 的行（含软删），pull 应用远端变更与墓碑。 */
export class SyncEngine {
  private db: Db;
  private bus: ChangeBus;
  private settings: Settings;

  constructor(db: Db, bus: ChangeBus, settings: Settings) {
    this.db = db;
    this.bus = bus;
    this.settings = settings;
  }

  // ------------------------------------------------------- 游标

  private async minLastPull(): Promise<string> {
    const rows = await this.db.rawQuery('SELECT MIN(last_pull) AS m FROM sync_state');
    const m = rows.length > 0 ? rows[0].str('m') : null;
    return m === null || m.length === 0 ? EPOCH : m;
  }

  private async setAllLastPull(v: string): Promise<void> {
    for (const t of SYNC_TABLES) {
      await this.db.exec(
        'INSERT OR REPLACE INTO sync_state (table_, last_pull) VALUES (?, ?)', [t, v]);
    }
  }

  // ------------------------------------------------------- push

  /** updated_at > since 的本地行（含 deleted=1 软删墓碑）。无变更返回 null。 */
  private async buildPushBody(since: string): Promise<PushBody | null> {
    const payload: Record<string, object[]> = {};
    for (const table of SYNC_TABLES) {
      const rows = await this.db.rawQuery(
        `SELECT * FROM ${table} WHERE updated_at > ? AND uuid IS NOT NULL`, [since]);
      if (rows.length === 0) {
        continue;
      }
      const arr: object[] = [];
      for (const row of rows) {
        arr.push(this.rowToJson(table, row));
      }
      payload[table] = arr;
    }
    const keys = Object.keys(payload);
    if (keys.length === 0) {
      return null;
    }
    const body: PushBody = { rows: payload };
    return body;
  }

  private rowToJson(table: string, row: Row): object {
    const obj: Record<string, relationalStore.ValueType> = {};
    for (const c of COLUMNS[table]) {
      if (c.numeric) {
        const n = row.num(c.name);
        obj[c.name] = n === null ? null : n;
      } else {
        const s = row.str(c.name);
        obj[c.name] = s === null ? null : s;
      }
    }
    return obj;
  }

  // ------------------------------------------------------- pull

  private async applyPull(data: PullData): Promise<void> {
    const tombs = data._tombstones ?? [];
    for (const t of tombs) {
      await this.applyTombstone(t as Record<string, relationalStore.ValueType>);
    }
    await this.applyTableRows('body_metrics', data.body_metrics);
    await this.applyTableRows('measurements', data.measurements);
    await this.applyTableRows('goals', data.goals);
    await this.applyTableRows('strength_logs', data.strength_logs);
    await this.applyTableRows('meals', data.meals);
    await this.applyTableRows('meal_items', data.meal_items);
    await this.applyTableRows('workouts', data.workouts);
    await this.applyTableRows('workout_sets', data.workout_sets);
  }

  /** 墓碑本地硬删；父行（meal/workout）连带清子行。 */
  private async applyTombstone(t: Record<string, relationalStore.ValueType>): Promise<void> {
    const uuid = asStr(t['uuid']);
    const table = asStr(t['table']);
    if (uuid === null || table === null) {
      return;
    }
    if (SYNC_TABLES.indexOf(table) < 0) {
      return;
    }
    await this.db.exec(`DELETE FROM ${table} WHERE uuid = ?`, [uuid]);
    if (table === 'meals') {
      await this.db.exec('DELETE FROM meal_items WHERE meal_uuid = ?', [uuid]);
    }
    if (table === 'workouts') {
      await this.db.exec('DELETE FROM workout_sets WHERE workout_uuid = ?', [uuid]);
    }
  }

  private async applyTableRows(table: string, rows: object[] | undefined): Promise<void> {
    if (rows === undefined) {
      return;
    }
    for (const row of rows) {
      const r = row as Record<string, relationalStore.ValueType>;
      const uuid = asStr(r['uuid']);
      const updated = asStr(r['updated_at']);
      if (uuid === null || updated === null) {
        continue;
      }
      // LWW：本地更旧才覆盖（相等跳过）
      const existing = await this.db.rawQuery(
        `SELECT updated_at FROM ${table} WHERE uuid = ?`, [uuid]);
      if (existing.length > 0 && (existing[0].str('updated_at') ?? '') >= updated) {
        continue;
      }
      await this.db.insertOrReplace(table, this.bucketFromRemote(table, r, uuid, updated));
    }
  }

  private bucketFromRemote(table: string, r: Record<string, relationalStore.ValueType>,
    uuid: string, updated: string): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    for (const c of COLUMNS[table]) {
      if (c.name === 'uuid') {
        bucket[c.name] = uuid;
      } else if (c.name === 'updated_at') {
        bucket[c.name] = updated;
      } else if (c.numeric) {
        bucket[c.name] = asNum(r[c.name]);
      } else {
        bucket[c.name] = asStr(r[c.name]);
      }
    }
    return bucket;
  }

  // ------------------------------------------------------- 入口

  /** 完整一轮同步：push → pull → 游标推进到 _server_time。 */
  async sync(): Promise<SyncResult> {
    const rawUrl = await this.settings.getServerUrl();
    const url = rawUrl.replace(/\/+$/, '');
    const token = await this.settings.getToken();
    if (url.length === 0 || token === null) {
      const r: SyncResult = { ok: false, error: '未配置服务器或未连接' };
      return r;
    }
    const since = await this.minLastPull();
    try {
      const pushBody = await this.buildPushBody(since);
      if (pushBody !== null) {
        const resp = await Http.postJson(`${url}/api/sync/push`, pushBody, token);
        if (resp.status === 401) {
          await this.settings.clearToken();
          const r: SyncResult = { ok: false, error: '登录过期，请重新连接' };
          return r;
        }
        if (resp.status !== 200) {
          const r: SyncResult = { ok: false, error: `推送失败：HTTP ${resp.status}` };
          return r;
        }
      }
      const pullReq: PullBody = { since: since };
      const pullResp = await Http.postJson(`${url}/api/sync/pull`, pullReq, token);
      if (pullResp.status === 401) {
        await this.settings.clearToken();
        const r: SyncResult = { ok: false, error: '登录过期，请重新连接' };
        return r;
      }
      if (pullResp.status !== 200) {
        const r: SyncResult = { ok: false, error: `拉取失败：HTTP ${pullResp.status}` };
        return r;
      }
      const data = JSON.parse(pullResp.body) as PullData;
      await this.applyPull(data);
      await this.setAllLastPull(data._server_time ?? nowUtc());
      this.bus.emit(SYNC_TABLES);
      const ok: SyncResult = { ok: true, error: null };
      return ok;
    } catch (e) {
      const r: SyncResult = { ok: false, error: '连接失败，请检查服务器地址与网络' };
      return r;
    }
  }
}
