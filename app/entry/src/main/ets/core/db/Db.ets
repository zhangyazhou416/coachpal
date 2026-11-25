import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DDL_STATEMENTS, PROFILE_FALLBACK_SQL } from './Ddl';
import { nowUtc } from '../util/Time';

/** 查询结果行的按名取值封装（列不存在或值为 NULL 返回 null）。 */
export class Row {
  private rs: relationalStore.ResultSet;

  constructor(rs: relationalStore.ResultSet) {
    this.rs = rs;
  }

  str(name: string): string | null {
    const i = this.rs.getColumnIndex(name);
    if (i < 0 || this.rs.isColumnNull(i)) {
      return null;
    }
    return this.rs.getString(i);
  }

  num(name: string): number | null {
    const i = this.rs.getColumnIndex(name);
    if (i < 0 || this.rs.isColumnNull(i)) {
      return null;
    }
    return this.rs.getDouble(i);
  }
}

/** relationalStore 薄封装：物化查询、分批批量插入、事务。 */
export class Db {
  readonly store: relationalStore.RdbStore;
  private static readonly CHUNK: number = 300;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 开库并建表（幂等）。 */
  static async open(context: common.Context): Promise<Db> {
    const config: relationalStore.StoreConfig = {
      name: 'coachpal.db',
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store = await relationalStore.getRdbStore(context, config);
    const db = new Db(store);
    await db.migrate();
    return db;
  }

  private async migrate(): Promise<void> {
    for (const sql of DDL_STATEMENTS) {
      await this.store.executeSql(sql);
    }
    await this.store.executeSql(PROFILE_FALLBACK_SQL, [nowUtc()]);
  }

  async exec(sql: string, args?: relationalStore.ValueType[]): Promise<void> {
    await this.store.executeSql(sql, args ?? []);
  }

  /** 裸 SQL 查询（COUNT 等聚合）。 */
  async rawQuery(sql: string, args?: relationalStore.ValueType[]): Promise<Row[]> {
    const rs = await this.store.querySql(sql, args ?? []);
    return materialize(rs);
  }

  /** 条件查询（物化为 Row 数组，结果集即取即关）。 */
  async query(pred: relationalStore.RdbPredicates, columns?: string[]): Promise<Row[]> {
    const rs = await this.store.query(pred, columns);
    return materialize(rs);
  }

  async queryOne(pred: relationalStore.RdbPredicates, columns?: string[]): Promise<Row | null> {
    pred.limitAs(1);
    const rows = await this.query(pred, columns);
    return rows.length > 0 ? rows[0] : null;
  }

  async count(table: string): Promise<number> {
    const rows = await this.rawQuery(`SELECT COUNT(*) AS c FROM ${table}`);
    return rows.length > 0 ? (rows[0].num('c') ?? 0) : 0;
  }

  async insert(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    await this.store.insert(table, bucket);
  }

  /** INSERT OR REPLACE（主键冲突整行替换）。 */
  async insertOrReplace(table: string, bucket: relationalStore.ValuesBucket): Promise<void> {
    await this.store.insert(table, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  /** 分批批量插入（内置事务语义，300 条/批）。 */
  async batchInsert(table: string, buckets: relationalStore.ValuesBucket[]): Promise<void> {
    for (let i = 0; i < buckets.length; i += Db.CHUNK) {
      const chunk = buckets.slice(i, i + Db.CHUNK);
      await this.store.batchInsert(table, chunk);
    }
  }

  async update(bucket: relationalStore.ValuesBucket, pred: relationalStore.RdbPredicates): Promise<void> {
    await this.store.update(bucket, pred);
  }

  async del(pred: relationalStore.RdbPredicates): Promise<void> {
    await this.store.delete(pred);
  }

  /** 事务包裹异步写入。 */
  async tx<T>(fn: () => Promise<T>): Promise<T> {
    this.store.beginTransaction();
    try {
      const r = await fn();
      this.store.commit();
      return r;
    } catch (e) {
      this.store.rollBack();
      throw e as Error;
    }
  }
}

function materialize(rs: relationalStore.ResultSet): Row[] {
  const out: Row[] = [];
  try {
    let ok = rs.goToFirstRow();
    while (ok) {
      out.push(new Row(rs));
      ok = rs.goToNextRow();
    }
  } finally {
    rs.close();
  }
  return out;
}
