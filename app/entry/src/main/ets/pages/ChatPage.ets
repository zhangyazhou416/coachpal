import { AppServices } from '../core/services';
import { Http } from '../core/net/Http';

const TOOL_LABELS: Record<string, string> = {
  'record_weight': '记录体重',
  'record_measurements': '记录围度',
  'record_meal': '记录饮食',
  'record_strength': '记录力量',
  'record_workout': '记录训练',
  'set_goal': '设置目标',
  'update_profile': '更新档案',
  'get_today': '查询今日',
  'get_status': '查询状态',
  'get_targets': '计算目标',
  'get_report': '周复盘',
  'list_goals': '查询目标',
  'query_food': '查食物',
  'search_exercises': '搜动作',
  'exercise_detail': '动作详情',
  'list_workouts': '查训练',
  'list_strength': '查力量',
  'list_measurements': '查围度',
  'list_meals': '查饮食',
};

function toolLabel(tool: string): string {
  const v = TOOL_LABELS[tool];
  return v ?? tool;
}

interface HistoryTurn {
  role: string;
  content: string;
}

interface ChatRequest {
  message: string;
  history: HistoryTurn[];
}

interface ActionJson {
  tool?: string;
  ok?: boolean;
}

interface MediaJson {
  url?: string;
  caption?: string;
  steps?: string[];
}

interface ChatResponse {
  reply?: string;
  actions?: ActionJson[];
  media?: MediaJson[];
}

@ObservedV2
export class ChatMedia {
  readonly url: string;
  readonly caption: string;
  readonly steps: string[];
  @Trace failed: boolean = false;

  constructor(url: string, caption: string, steps: string[]) {
    this.url = url;
    this.caption = caption;
    this.steps = steps;
  }
}

@ObservedV2
export class ChatMsg {
  readonly role: string;
  readonly content: string;
  @Trace actions: string[];
  @Trace media: ChatMedia[];

  constructor(role: string, content: string, actions: string[], media: ChatMedia[]) {
    this.role = role;
    this.content = content;
    this.actions = actions;
    this.media = media;
  }
}

function greeting(): ChatMsg {
  return new ChatMsg('assistant',
    '你好！我是 CoachPal 教练 💪\n\n'
    + '直接跟我说就行，比如：\n'
    + '· 「今天体重 77.9，体脂 21.4」\n'
    + '· 「午饭吃了 150g 鸡胸肉、200g 米饭」\n'
    + '· 「卧推 80kg 做了 5 组，RPE 8」\n'
    + '· 「这周复盘一下」/「我该吃多少热量」', [], []);
}

/// 教练页：服务端 Agent 对话（自然语言记录/查询，回复可带工具 chip 与动作 GIF）。
@ComponentV2
export struct ChatPage {
  @Local messages: ChatMsg[] = [greeting()];
  @Local inputText: string = '';
  @Local sending: boolean = false;
  @Local configured: boolean = false;
  @Local checked: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    await AppServices.getInstance().whenReady();
    this.configured = await AppServices.getInstance().settings.isConfigured();
    this.checked = true;
  }

  private async recheck(): Promise<void> {
    await AppServices.getInstance().whenReady();
    this.configured = await AppServices.getInstance().settings.isConfigured();
    this.checked = true;
  }

  private scrollDown(): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 80);
  }

  private async send(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    const svc = AppServices.getInstance();
    const url = (await svc.settings.getServerUrl()).replace(/\/+$/, '');
    const token = await svc.settings.getToken();
    if (url.length === 0 || token === null || token.length === 0) {
      this.configured = false;
      return;
    }
    this.messages = this.messages.concat([new ChatMsg('user', text, [], [])]);
    this.inputText = '';
    this.sending = true;
    this.scrollDown();
    const history: HistoryTurn[] = [];
    // history 为当前这条消息之前的全部轮次
    for (let i = 0; i < this.messages.length - 1; i++) {
      const m = this.messages[i];
      const t: HistoryTurn = { role: m.role, content: m.content };
      history.push(t);
    }
    const req: ChatRequest = { message: text, history: history };
    try {
      const resp = await Http.postJson(`${url}/api/agent/chat`, req, token, 60000);
      if (resp.status !== 200) {
        const body = resp.body.length > 200 ? resp.body.substring(0, 200) + '…' : resp.body;
        this.messages = this.messages.concat(
          [new ChatMsg('assistant', `服务返回 ${resp.status}：${body}`, [], [])]);
        this.sending = false;
        this.scrollDown();
        return;
      }
      const data = JSON.parse(resp.body) as ChatResponse;
      const actions: string[] = [];
      const serverActions = data.actions ?? [];
      for (const a of serverActions) {
        const ok = a.ok === true;
        const item = `${ok ? '✓' : '✗'} ${toolLabel(a.tool ?? '')}`;
        actions.push(item);
      }
      const media: ChatMedia[] = [];
      const serverMedia = data.media ?? [];
      for (const m of serverMedia) {
        const steps: string[] = m.steps ?? [];
        media.push(new ChatMedia(`${url}${m.url ?? ''}`, m.caption ?? '', steps));
      }
      this.messages = this.messages.concat(
        [new ChatMsg('assistant', data.reply ?? '（无回复）', actions, media)]);
      this.sending = false;
      this.scrollDown();
    } catch (e) {
      this.messages = this.messages.concat([new ChatMsg('assistant',
        '连接失败\n\n请检查「我的」页里的服务器地址是否可达。', [], [])]);
      this.sending = false;
      this.scrollDown();
    }
  }

  @Builder
  mediaBlock(md: ChatMedia) {
    Column({ space: 4 }) {
      if (md.failed) {
        Text('动画加载失败')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width(220)
          .height(80)
          .textAlign(TextAlign.Center)
      } else {
        Image(md.url)
          .width(220)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .onError((): void => {
            md.failed = true;
          })
      }
      ForEach(md.steps, (st: string) => {
        Text(`· ${st}`)
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }, (st: string) => st)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  bubble(m: ChatMsg) {
    Row() {
      if (m.role === 'user') {
        Blank()
      }
      Column({ space: 4 }) {
        Text(m.content)
          .fontSize(14)
          .fontColor(m.role === 'user' ? Color.White : $r('app.color.text_primary'))
        ForEach(m.media, (md: ChatMedia) => {
          this.mediaBlock(md)
        }, (md: ChatMedia) => md.url)
        if (m.actions.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(m.actions, (a: string, idx: number) => {
              Text(a)
                .fontSize(11)
                .fontColor(a.startsWith('✓')
                  ? $r('app.color.status_good')
                  : $r('app.color.status_bad'))
                .backgroundColor(a.startsWith('✓') ? '#260CA30C' : '#26D03B3B')
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(16)
                .margin({ right: 6, top: 2, bottom: 2 })
            }, (a: string, idx: number) => `${idx}-${a}`)
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
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
      Text('☁')
        .fontSize(44)
        .fontColor($r('app.color.text_secondary'))
      Text('还没有连接同步服务')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Text('在「我的」页配置服务器地址并登录后，\n就可以用对话完成所有记录。')
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
    } else if (!this.configured) {
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
