import { relationalStore } from '@kit.ArkData';
import { Db } from '../db/Db';
import { nowUtc } from '../util/Time';

/** 落库的聊天消息（exercise 仅存 id，加载时再解析回 ExerciseRow）。 */
export interface StoredChatMsg {
  role: string;
  content: string;
  exerciseId: string | null;
}

/** 教练对话历史存取：chat_messages 表（RDB），重启后恢复会话。 */
export class ChatStore {
  private db: Db;

  constructor(db: Db) {
    this.db = db;
  }

  /** 追加一条消息。 */
  async append(role: string, content: string, exerciseId: string | null): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'role': role,
      'content': content,
      'exercise_id': exerciseId,
      'created_at': nowUtc(),
    };
    await this.db.insert('chat_messages', bucket);
  }

  /** 最近 limit 条消息（按时间升序返回）。 */
  async recent(limit: number): Promise<StoredChatMsg[]> {
    const rows = await this.db.rawQuery(
      `SELECT role, content, exercise_id FROM chat_messages ORDER BY id DESC LIMIT ?`, [limit]);
    const out: StoredChatMsg[] = [];
    for (let i = rows.length - 1; i >= 0; i--) {
      const r = rows[i];
      const m: StoredChatMsg = {
        role: r.str('role') ?? 'assistant',
        content: r.str('content') ?? '',
        exerciseId: r.str('exercise_id'),
      };
      out.push(m);
    }
    return out;
  }

  /** 清空会话历史。 */
  async clear(): Promise<void> {
    await this.db.exec('DELETE FROM chat_messages');
  }
}
