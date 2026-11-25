/// 时间工具：时间戳格式是同步生命线。
/// updated_at 必须是 UTC、秒级、无时区后缀（与服务端 LWW 字符串比较兼容）。

/** UTC 时间戳：2026-01-01T00:00:00（毫秒截断，无 Z）。 */
export function nowUtc(): string {
  return new Date().toISOString().split('.')[0];
}

/** 本地日历日期 YYYY-MM-DD（记录按本地日子归属；禁用 toISOString 的 UTC 偏移）。 */
export function todayIso(): string {
  return toLocalDate(new Date());
}

/** 本地日期往前推 days 天的 YYYY-MM-DD。 */
export function dateDaysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return toLocalDate(d);
}

function toLocalDate(d: Date): string {
  const m = `${d.getMonth() + 1}`.padStart(2, '0');
  const day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}
