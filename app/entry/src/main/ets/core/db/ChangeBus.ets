/// 关系型库无响应式流：自实现订阅/发布。Repo 每次写后 emit，页面订阅后重查刷新。

type ChangeListener = () => void;

interface Subscription {
  id: number;
  tables: Set<string>;
  fn: ChangeListener;
}

export class ChangeBus {
  private subs: Map<number, Subscription> = new Map();
  private nextId: number = 1;

  /** 订阅一组表的变化，返回订阅 id（用于退订）。 */
  subscribe(tables: string[], fn: ChangeListener): number {
    const id = this.nextId;
    this.nextId += 1;
    const sub: Subscription = { id: id, tables: new Set<string>(tables), fn: fn };
    this.subs.set(id, sub);
    return id;
  }

  unsubscribe(id: number): void {
    this.subs.delete(id);
  }

  /** 通知订阅了任一这些表的监听者。 */
  emit(tables: string[]): void {
    if (this.subs.size === 0) {
      return;
    }
    const changed = new Set<string>(tables);
    this.subs.forEach((sub: Subscription): void => {
      let hit = false;
      sub.tables.forEach((t: string): void => {
        if (changed.has(t)) {
          hit = true;
        }
      });
      if (hit) {
        try {
          sub.fn();
        } catch (e) {
          console.error('[CoachPal] change listener failed: ' + (e as Error).message);
        }
      }
    });
  }
}
