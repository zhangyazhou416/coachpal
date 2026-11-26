import { http } from '@kit.NetworkKit';

export interface HttpResult {
  status: number;
  body: string;
}

/** HTTP 封装：可选 Bearer/额外头。非 2xx 不抛错（按 status 分支），网络异常向上抛。 */
export class Http {
  private static async doRequest(method: http.RequestMethod, url: string,
    payload: object | null, token: string | null, timeoutMs: number,
    extraHeaders: Record<string, string> | null = null): Promise<HttpResult> {
    const client = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
      };
      if (token !== null && token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      if (extraHeaders !== null) {
        const keys = Object.keys(extraHeaders);
        for (const k of keys) {
          header[k] = extraHeaders[k];
        }
      }
      const opts: http.HttpRequestOptions = {
        method: method,
        header: header,
        extraData: payload === null ? undefined : JSON.stringify(payload),
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

  static async postJson(url: string, payload: object, token: string | null,
    timeoutMs: number = 15000, extraHeaders: Record<string, string> | null = null): Promise<HttpResult> {
    return Http.doRequest(http.RequestMethod.POST, url, payload, token, timeoutMs, extraHeaders);
  }
}
