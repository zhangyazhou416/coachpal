import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DDL_STATEMENTS, PROFILE_FALLBACK_SQL } from './Ddl';
import { nowUtc } from '../util/Time';

type RowData = Record<string, string | number | null>;

/** 查询结果行的按名取值封装（列不存在或值为 NULL 返回 null）。
 *  持有的是迭代时快照的数据，而非 ResultSet——结果集关闭后仍可读。 */
export class Row {
  private data: RowData;

  constructor(data: RowData) {
    this.data = data;
  }

  str(name: string): string | null {
    const v: string | number | null = this.data[name];
    if (v === null || v === undefined) {
      return null;
    }
    return typeof v === 'string' ? v : `${v}`;
  }

  num(name: string): number | null {
    const v: string | number | null = this.data[name];
    if (v === null || v === undefined) {
      return null;
    }
    return typeof v === 'number' ? v : Number(v);
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

let matLogged = false;

function materialize(rs: relationalStore.ResultSet): Row[] {
  const out: Row[] = [];
  try {
    const names: string[] = rs.columnNames;
    const colCount = names.length;
    if (!matLogged) {
      matLogged = true;
      console.info(`[CoachPal] rs colNames=${JSON.stringify(names)}`);
      if (rs.goToFirstRow()) {
        console.info(`[CoachPal] row0 col0="${rs.getString(0)}" colCount=${names.length}`);
      }
    }
    let ok = rs.goToFirstRow();
    while (ok) {
      const data: RowData = {};
      for (let i = 0; i < colCount; i++) {
        // 部分模拟器镜像 isColumnNull 恒真，不能信——直接读，异常才算 NULL
        data[names[i]] = readColumn(rs, i);
      }
      out.push(new Row(data));
      ok = rs.goToNextRow();
    }
  } finally {
    rs.close();
  }
  return out;
}

function readColumn(rs: relationalStore.ResultSet, i: number): string | number | null {
  try {
    return rs.getString(i);
  } catch (e) {
    try {
      return rs.getDouble(i);
    } catch (e2) {
      return null;
    }
  }
}
