import { http } from '@kit.NetworkKit';

export interface HttpResult {
  status: number;
  body: string;
}

/** POST JSON 封装：15s 超时、可选 Bearer。非 2xx 不抛错（按 status 分支），网络异常向上抛。 */
export class Http {
  static async postJson(url: string, payload: object, token: string | null,
    timeoutMs: number = 15000): Promise<HttpResult> {
    const client = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
      };
      if (token !== null && token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(payload),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      };
      const resp = await client.request(url, opts);
      const body = typeof resp.result === 'string' ? resp.result : String(resp.result);
      const r: HttpResult = { status: resp.responseCode, body: body };
      return r;
    } finally {
      client.destroy();
    }
  }
}
