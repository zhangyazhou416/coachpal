import { AppServices } from '../core/services';
import { CardContainer, SectionTitle } from '../components/Common';
import { AiSource, LlmProtocol } from '../core/settings/Settings';
import { Http, HttpResult } from '../core/net/Http';
import { router } from '@kit.ArkUI';

interface TestMessage {
  role: string;
  content: string;
}

interface TestRequest {
  model: string;
  messages: TestMessage[];
}

interface AnthropicTestRequest {
  model: string;
  max_tokens: number;
  messages: TestMessage[];
}

/// AI 服务页：选择 AI 来源（华为端侧模型 / 自定义 OpenAI 兼容接口），自定义配置仅保存在本机。
@Entry
@ComponentV2
struct AiConfigPage {
  @Local source: string = AiSource.DEVICE;
  @Local baseUrlText: string = '';
  @Local apiKeyText: string = '';
  @Local modelText: string = '';
  @Local apiKeySet: boolean = false;
  @Local saving: boolean = false;
  @Local testing: boolean = false;
  @Local protocol: string = LlmProtocol.OPENAI;

  aboutToAppear(): void {
    this.init();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async init(): Promise<void> {
    const svc = AppServices.getInstance();
    await svc.whenReady();
    this.source = await svc.settings.getAiSource();
    this.protocol = await svc.settings.getLlmProtocol();
    this.baseUrlText = await svc.settings.getLlmBaseUrl();
    this.modelText = await svc.settings.getLlmModel();
    const key = await svc.settings.getLlmApiKey();
    this.apiKeySet = key !== null && key.length > 0;
  }

  private async selectSource(v: string): Promise<void> {
    this.source = v;
    await AppServices.getInstance().settings.setAiSource(v);
  }

  private async saveCustomConfig(): Promise<void> {
    const svc = AppServices.getInstance();
    const b = this.baseUrlText.trim().replace(/\/+$/, '');
    const m = this.modelText.trim();
    const k = this.apiKeyText.trim();
    if (b.length === 0) {
      this.toast('请填写接口地址');
      return;
    }
    if (m.length === 0) {
      this.toast('请填写模型名');
      return;
    }
    if (!this.apiKeySet && k.length === 0) {
      this.toast('请填写 API Key');
      return;
    }
    this.saving = true;
    try {
      await svc.settings.setLlmBaseUrl(b);
      await svc.settings.setLlmModel(m);
      if (k.length > 0) {
        await svc.settings.saveLlmApiKey(k);
        this.apiKeySet = true;
      }
      this.baseUrlText = b;
      this.apiKeyText = '';
      this.toast('配置已保存到本机');
    } catch (e) {
      this.toast('保存失败：' + (e as Error).message);
    } finally {
      this.saving = false;
    }
  }

  private async selectProtocol(v: string): Promise<void> {
    this.protocol = v;
    await AppServices.getInstance().settings.setLlmProtocol(v);
  }

  /** 拼接 chat/completions 端点：已带则不重复追加。 */
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

  private async testConnection(): Promise<void> {
    const svc = AppServices.getInstance();
    const baseUrl = this.baseUrlText.trim().replace(/\/+$/, '');
    const model = this.modelText.trim();
    const key = this.apiKeyText.trim();
    const apiKey = key.length > 0 ? key : await svc.settings.getLlmApiKey();
    if (baseUrl.length === 0 || model.length === 0 || apiKey === null || apiKey.length === 0) {
      this.toast('请先填写完整接口地址、API Key 和模型名');
      return;
    }
    this.testing = true;
    try {
      const msg: TestMessage = { role: 'user', content: '你好' };
      let endpoint = '';
      let resp: HttpResult;
      if (this.protocol === LlmProtocol.ANTHROPIC) {
        endpoint = AiConfigPage.buildAnthropicEndpoint(baseUrl);
        const req: AnthropicTestRequest = { model: model, max_tokens: 32, messages: [msg] };
        const headers: Record<string, string> = {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        };
        resp = await Http.postJson(endpoint, req, apiKey, 30000, headers);
      } else {
        endpoint = AiConfigPage.buildOpenAiEndpoint(baseUrl);
        const req: TestRequest = { model: model, messages: [msg] };
        resp = await Http.postJson(endpoint, req, apiKey, 30000);
      }
      if (resp.status === 200) {
        this.toast('连接成功 ✓');
      } else {
        const body = resp.body.length > 80 ? resp.body.substring(0, 80) + '…' : resp.body;
        this.toast(`测试失败 HTTP ${resp.status}\n${endpoint}\n${body}`);
      }
    } catch (e) {
      this.toast('网络请求失败，请检查地址与网络');
    } finally {
      this.testing = false;
    }
  }

  @Builder
  titleBar(title: string) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
        .onClick((): void => {
          router.back();
        })
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sourceRow(value: string, icon: Resource, title: string, sub: string) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(18)
          .fontColor([$r('app.color.accent')])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor('rgba(235,104,52,0.12)')
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(sub)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.source === value) {
        Text('✓')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .backgroundColor($r('app.color.accent'))
      } else {
        Text('')
          .width(18)
          .height(18)
          .borderRadius(9)
          .border({ width: 1.5, color: $r('app.color.divider') })
      }
    }
    .width('100%')
    .height(62)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.selectSource(value);
    })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.titleBar('AI 服务')

        // AI 来源
        CardContainer() {
          Column() {
            SectionTitle({ text: 'AI 来源' })
            this.sourceRow(AiSource.DEVICE, $r('sys.symbol.AI_phone'),
              '华为端侧模型（推荐）', '设备内置大模型 · 离线可用 · 数据不出本机')
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 46 })
            this.sourceRow(AiSource.CUSTOM, $r('sys.symbol.gearshape'),
              '自定义模型', 'OpenAI 兼容接口 · 自备 API Key · 联网调用')
          }
        }
        if (this.source === AiSource.DEVICE) {
          CardContainer() {
            Column({ space: 8 }) {
              SectionTitle({ text: '端侧模型说明' })
              Text('调用华为手机内置的端侧大模型回答问题，全程离线、隐私数据不出设备。\n\n'
                + '需要设备系统支持端侧模型能力；如对话中提示模型不可用，可切换到「自定义模型」。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(19)
            }
            .alignItems(HorizontalAlign.Start)
          }
        } else {
          // 自定义模型配置
          CardContainer() {
            Column({ space: 12 }) {
              SectionTitle({ text: '模型配置' })
              Text('接口协议')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              Row({ space: 8 }) {
                Text('OpenAI 兼容')
                  .fontSize(13)
                  .fontWeight(this.protocol === LlmProtocol.OPENAI ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.protocol === LlmProtocol.OPENAI ? Color.White : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(this.protocol === LlmProtocol.OPENAI
                    ? $r('app.color.accent') : $r('app.color.card'))
                  .border({ width: 1, color: this.protocol === LlmProtocol.OPENAI
                    ? $r('app.color.accent') : $r('app.color.divider') })
                  .onClick((): void => {
                    this.selectProtocol(LlmProtocol.OPENAI);
                  })
                Text('Anthropic 兼容')
                  .fontSize(13)
                  .fontWeight(this.protocol === LlmProtocol.ANTHROPIC ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.protocol === LlmProtocol.ANTHROPIC ? Color.White : $r('app.color.text_primary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(this.protocol === LlmProtocol.ANTHROPIC
                    ? $r('app.color.accent') : $r('app.color.card'))
                  .border({ width: 1, color: this.protocol === LlmProtocol.ANTHROPIC
                    ? $r('app.color.accent') : $r('app.color.divider') })
                  .onClick((): void => {
                    this.selectProtocol(LlmProtocol.ANTHROPIC);
                  })
              }
              .width('100%')
              TextInput({ text: this.baseUrlText,
                placeholder: this.protocol === LlmProtocol.ANTHROPIC
                  ? '网关地址，如 https://uni-api.cstcloud.cn' : '接口地址，如 https://api.deepseek.com/v1' })
                .onChange((v: string): void => {
                  this.baseUrlText = v;
                })
              TextInput({
                text: this.apiKeyText,
                placeholder: this.apiKeySet ? 'API Key 已配置（留空保持不变）' : 'sk-…'
              })
                .type(InputType.Password)
                .onChange((v: string): void => {
                  this.apiKeyText = v;
                })
              TextInput({ text: this.modelText, placeholder: '模型名，如 deepseek-chat' })
                .onChange((v: string): void => {
                  this.modelText = v;
                })
              Button(this.saving ? '保存中…' : '保存配置')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .backgroundColor($r('app.color.accent'))
                .borderRadius(22)
                .constraintSize({ minHeight: 44 })
                .width('100%')
                .enabled(!this.saving)
                .onClick((): void => {
                  this.saveCustomConfig();
                })
              Button(this.testing ? '测试中…' : '测试连接')
                .fontSize(14)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.accent'))
                .border({ width: 1.5, color: $r('app.color.accent') })
                .borderRadius(22)
                .constraintSize({ minHeight: 44 })
                .width('100%')
                .enabled(!this.testing && !this.saving)
                .onClick((): void => {
                  this.testConnection();
                })
              Text(this.protocol === LlmProtocol.ANTHROPIC
                ? '调用 Anthropic 兼容的 /v1/messages 接口（x-api-key 鉴权），地址末尾自动拼接，已含则不重复。'
                : '调用 OpenAI 兼容的 /chat/completions 接口，地址末尾自动拼接，已含则不重复。')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(17)
              Text('接口地址、模型名保存在本机，API Key 加密存储在系统密钥库。')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(17)
            }
          }
        }
      }
      .padding(16)
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
  }
}
