import { AppServices } from '../core/services';
import { Http, HttpResult } from '../core/net/Http';
import { AiSource, LlmProtocol } from '../core/settings/Settings';
import { localChatModel } from '@kit.DataAugmentationKit';
import { BusinessError } from '@kit.BasicServicesKit';

const COACH_PROMPT: string =
  '你是 CoachPal，一位专业、友好的健身与营养教练助手。'
  + '用简洁的中文回答，给出可执行的建议；涉及训练、饮食、体重管理时注意科学性与安全。'
  + '如果用户描述了当天的记录（体重、饮食、训练等），给出简短点评和下一步建议。';

const DEVICE_MODEL_ERROR: Record<string, string> = {
  '1021900001': '端侧模型响应超时，请稍后重试',
  '1021900002': '本机暂不支持端侧模型，可在「我的 → AI 服务」切换为自定义模型',
  '1021900003': '端侧模型请求失败，请稍后重试',
  '1021900004': '端侧模型正忙，请稍候再试',
  '1021900005': '问题内容过长，请精简后重试',
};

function deviceModelError(code: number): string {
  const v = DEVICE_MODEL_ERROR[`${code}`];
  return v ?? `端侧模型调用失败（${code}）`;
}

interface ChatMessage {
  role: string;
  content: string;
}

interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
}

interface ChoiceJson {
  message?: ChatMessage;
}

interface CompletionJson {
  choices?: ChoiceJson[];
}

interface AnthropicRequest {
  model: string;
  max_tokens: number;
  system?: string;
  messages: ChatMessage[];
}

interface AnthropicContentBlock {
  type?: string;
  text?: string;
}

interface AnthropicResponse {
  content?: AnthropicContentBlock[];
}

@ObservedV2
export class ChatMsg {
  readonly role: string;
  readonly content: string;

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

function greeting(): ChatMsg {
  return new ChatMsg('assistant',
    '你好！我是 CoachPal 教练 💪\n\n'
    + '直接跟我说就行，比如：\n'
    + '· 「今天体重 77.9，体脂 21.4」\n'
    + '· 「午饭吃了 150g 鸡胸肉、200g 米饭」\n'
    + '· 「卧推 80kg 做了 5 组，RPE 8」\n'
    + '· 「帮我安排下周的训练计划」');
}

/// 教练页：AI 对话。来源二选一——华为端侧模型（离线）或自定义 OpenAI 兼容接口（本机配置直连）。
@ComponentV2
export struct ChatPage {
  @Local messages: ChatMsg[] = [greeting()];
  @Local inputText: string = '';
  @Local sending: boolean = false;
  @Local aiReady: boolean = false;
  @Local checked: boolean = false;
  private scroller: Scroller = new Scroller();
  private deviceQuestionId: number = 0;

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    await AppServices.getInstance().whenReady();
    this.aiReady = await AppServices.getInstance().settings.isAiConfigured();
    this.checked = true;
  }

  private async recheck(): Promise<void> {
    await AppServices.getInstance().whenReady();
    this.aiReady = await AppServices.getInstance().settings.isAiConfigured();
    this.checked = true;
  }

  private scrollDown(): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 80);
  }

  private reply(msg: string): void {
    this.messages = this.messages.concat([new ChatMsg('assistant', msg)]);
    this.sending = false;
    this.scrollDown();
  }

  /** 端侧模型：单轮内容 = 角色设定 + 近几轮对话 + 当前问题（content 建议 ≤4500 字节）。 */
  private buildDeviceQuestion(question: string): string {
    let dialog = '';
    const start = Math.max(0, this.messages.length - 7);
    for (let i = start; i < this.messages.length; i++) {
      const m = this.messages[i];
      const who = m.role === 'user' ? '用户' : '教练';
      dialog += `${who}：${m.content}\n`;
    }
    return `${COACH_PROMPT}\n\n以下是最近的对话记录：\n${dialog}\n用户：${question}\n\n请以教练身份回答用户最后的问题。`;
  }

  /** 端侧模型问答（init + chat，非流式），返回完整回答文本；失败抛 Error。 */
  private async askDeviceModel(question: string): Promise<string> {
    const ready = await localChatModel.init();
    if (!ready) {
      throw new Error('本机暂不支持端侧模型，可在「我的 → AI 服务」切换为自定义模型');
    }
    this.deviceQuestionId++;
    const info: localChatModel.QuestionInfo = {
      questionId: this.deviceQuestionId,
      content: this.buildDeviceQuestion(question)
    };
    const config: localChatModel.Config = { isStream: false };
    return new Promise<string>((resolve, reject): void => {
      localChatModel.chat(info, config, (err: BusinessError, ans: localChatModel.Answer): void => {
        if (err) {
          reject(new Error(deviceModelError(err.code)));
          return;
        }
        if (!ans) {
          reject(new Error('端侧模型未返回结果'));
          return;
        }
        resolve(ans.content);
      }).catch((e: BusinessError): void => {
        reject(new Error(deviceModelError(e.code)));
      });
    });
  }

  /** 拼接 chat/completions 端点：已带则不重复追加；兼容以 /v1、/v4 等结尾的 base。 */
  private static buildOpenAiEndpoint(baseUrl: string): string {
    const base = baseUrl.replace(/\/+$/, '');
    if (base.endsWith('/chat/completions')) {
      return base;
    }
    if (base.endsWith('/completions')) {
      return `${base.substring(0, base.length - '/completions'.length)}/chat/completions`;
    }
    return `${base}/chat/completions`;
  }

  /** 拼接 Anthropic messages 端点：已带则不重复追加。 */
  private static buildAnthropicEndpoint(baseUrl: string): string {
    const base = baseUrl.replace(/\/+$/, '');
    if (base.endsWith('/v1/messages') || base.endsWith('/messages')) {
      return base;
    }
    if (base.endsWith('/v1')) {
      return `${base}/messages`;
    }
    return `${base}/v1/messages`;
  }

  /** 自定义模型：按所选协议（OpenAI / Anthropic 兼容）直连，带完整历史。 */
  private async askCustomModel(question: string): Promise<string> {
    const svc = AppServices.getInstance();
    const baseUrl = await svc.settings.getLlmBaseUrl();
    const model = await svc.settings.getLlmModel();
    const apiKey = await svc.settings.getLlmApiKey();
    const protocol = await svc.settings.getLlmProtocol();
    if (baseUrl.length === 0 || model.length === 0 || apiKey === null || apiKey.length === 0) {
      throw new Error('自定义模型未配置完整，请到「我的 → AI 服务」检查');
    }
    const messages: ChatMessage[] = [];
    const start = this.messages.length > 12 ? this.messages.length - 12 : 0;
    for (let i = start; i < this.messages.length; i++) {
      const m = this.messages[i];
      const t: ChatMessage = { role: m.role, content: m.content };
      messages.push(t);
    }
    if (protocol === LlmProtocol.ANTHROPIC) {
      const req: AnthropicRequest = {
        model: model,
        max_tokens: 2048,
        system: COACH_PROMPT,
        messages: messages,
      };
      const endpoint = ChatPage.buildAnthropicEndpoint(baseUrl);
      const headers: Record<string, string> = {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      };
      const resp = await Http.postJson(endpoint, req, apiKey, 90000, headers);
      if (resp.status !== 200) {
        throw new Error(this.customError(resp, endpoint));
      }
      const data = JSON.parse(resp.body) as AnthropicResponse;
      const blocks = data.content ?? [];
      let answer = '';
      for (const b of blocks) {
        if (b.type === 'text' && typeof b.text === 'string') {
          answer += b.text;
        }
      }
      if (answer.length === 0) {
        throw new Error('模型接口未返回结果');
      }
      return answer;
    }
    const sysMsg: ChatMessage = { role: 'system', content: COACH_PROMPT };
    const full: ChatMessage[] = [sysMsg].concat(messages);
    const req: ChatCompletionRequest = { model: model, messages: full };
    const endpoint = ChatPage.buildOpenAiEndpoint(baseUrl);
    const resp = await Http.postJson(endpoint, req, apiKey, 90000);
    if (resp.status !== 200) {
      throw new Error(this.customError(resp, endpoint));
    }
    const data = JSON.parse(resp.body) as CompletionJson;
    const choices = data.choices ?? [];
    if (choices.length === 0) {
      throw new Error('模型接口未返回结果');
    }
    const msg = choices[0].message;
    return msg?.content ?? '（无回复）';
  }

  /** 非预期响应的统一错误文案。 */
  private customError(resp: HttpResult, endpoint: string): string {
    const body = resp.body.length > 160 ? resp.body.substring(0, 160) + '…' : resp.body;
    if (resp.status === 404) {
      return `接口 404（请求地址 ${endpoint}）\n\n`
        + '请检查：\n'
        + '· 接口协议是否与服务商匹配（OpenAI / Anthropic）\n'
        + '· 地址需含版本前缀，且不要重复带路径';
    }
    return `模型接口返回 ${resp.status}：${body}`;
  }

  private async send(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    const svc = AppServices.getInstance();
    const ready = await svc.settings.isAiConfigured();
    if (!ready) {
      this.aiReady = false;
      return;
    }
    this.messages = this.messages.concat([new ChatMsg('user', text)]);
    this.inputText = '';
    this.sending = true;
    this.scrollDown();
    try {
      const source = await svc.settings.getAiSource();
      let answer = '';
      if (source === AiSource.CUSTOM) {
        answer = await this.askCustomModel(text);
      } else {
        answer = await this.askDeviceModel(text);
      }
      this.reply(answer);
    } catch (e) {
      this.reply((e as Error).message);
    }
  }

  @Builder
  bubble(m: ChatMsg) {
    Row() {
      if (m.role === 'user') {
        Blank()
      }
      Text(m.content)
        .fontSize(14)
        .fontColor(m.role === 'user' ? Color.White : $r('app.color.text_primary'))
        .constraintSize({ maxWidth: '82%' })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(m.role === 'user' ? $r('app.color.primary') : $r('app.color.card'))
        .borderRadius({
          topLeft: 14,
          topRight: 14,
          bottomLeft: m.role === 'user' ? 14 : 4,
          bottomRight: m.role === 'user' ? 4 : 14,
        })
        .border({ width: 1, color: $r('app.color.divider') })
      if (m.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  setupHint() {
    Column({ space: 12 }) {
      Text('💪')
        .fontSize(44)
      Text('还没有配置 AI')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Text('在「我的 → AI 服务」里选择华为端侧模型，\n或配置自定义模型后，就可以开始对话。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button('我配置好了，重新检查')
        .backgroundColor($r('app.color.primary'))
        .onClick((): void => {
          this.recheck();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  build() {
    if (!this.checked) {
      Column() {
        Text('正在检查配置…')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (!this.aiReady) {
      this.setupHint()
    } else {
      Column() {
        List({ scroller: this.scroller, space: 4 }) {
          ForEach(this.messages, (m: ChatMsg, idx: number) => {
            ListItem() {
              this.bubble(m)
            }
          }, (m: ChatMsg, idx: number) => `${idx}-${m.role}`)
          if (this.sending) {
            ListItem() {
              Text('正在思考…')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .padding(16)
            }
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding(12)
        .width('100%')

        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(1)
        Row({ space: 8 }) {
          TextArea({ text: this.inputText, placeholder: '说说今天吃了什么、练了什么…' })
            .maxLines(4)
            .fontSize(14)
            .constraintSize({ minHeight: 40 })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .onChange((v: string): void => {
              this.inputText = v;
            })
          Button('发送')
            .backgroundColor($r('app.color.primary'))
            .enabled(!this.sending)
            .onClick((): void => {
              this.send();
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .height('100%')
    }
  }
}
