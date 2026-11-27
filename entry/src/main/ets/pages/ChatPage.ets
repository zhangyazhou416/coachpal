import { AppServices } from '../core/services';
import { Http, HttpResult } from '../core/net/Http';
import { AiSource, LlmProtocol } from '../core/settings/Settings';
import { localChatModel } from '@kit.DataAugmentationKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ExerciseRow, decodeList } from '../core/repo/Model';
import { Repo } from '../core/repo/Repo';
import {
  CoachTools, ToolOutcome, OPENAI_TOOLS, ANTHROPIC_TOOLS,
  OpenAiToolDef, AnthropicToolDef,
} from '../core/coach/CoachTools';
import { CATEGORY_ZH, EQUIPMENT_ZH, MUSCLE_ZH } from '../core/domain/set_parser';
import { ExerciseSkill } from '../core/coach/ExerciseSkill';
import { MdText } from '../components/MdText';
import { todayIso } from '../core/util/Time';

const COACH_PROMPT: string =
  '你是 CoachPal，一位专业、友好的健身与营养教练助手。'
  + '用简洁的中文回答，给出可执行的建议；涉及训练、饮食、体重管理时注意科学性与安全。'
  + '如果用户描述了当天的记录（体重、饮食、训练等），给出简短点评和下一步建议。';

const COACH_TOOLS_PROMPT: string =
  '你可以调用以下工具：\n'
  + '· get_exercise(query)：查询动作库（器械/目标肌群/动作要领，并自动展示 GIF 示范）。'
  + '用户询问某个动作怎么做、标准姿势、想看示范时必须调用，并把要领整理给用户。\n'
  + '· search_food(query)：搜索食物每 100g 营养成分。\n'
  + '· record_meal(items, meal_type?, note?)：记录一餐。先用 search_food 查询并按克数换算出'
  + '每项的 kcal/蛋白/脂肪/碳水，再调用；查不到时给出合理估算并说明。\n'
  + '· record_body_metric(weight_kg?, body_fat_pct?, skeletal_muscle_kg?, date?)：记录身体数据。\n'
  + '· record_workout(sets, name?, date?)：记录一次训练，每组含 exercise、weight_kg、reps、rpe?。\n'
  + '· get_recent_summary()：获取用户近期身体/饮食/训练概况。\n'
  + '· get_daily_targets()：按档案与最新体重计算每日摄入目标（热量 + 蛋白/脂肪/碳水/纤维）。'
  + '用户问「每天该吃多少、摄入目标、宏量怎么分配、增肌/减脂该怎么吃」时调用，并据此给出饮食建议。\n'
  + '· get_diet_status()：今日已摄入 vs 每日目标的对比（剩余热量/余量/供能占比与参考区间）。'
  + '用户问「今天还需要吃多少、吃得够不够、饮食结构合不合理」时调用，并解读结果给出调整建议。\n'
  + '· set_goal(kind, target, target_date?)：设置目标体重/体脂率/骨骼肌量（kind: weight/body_fat/muscle）。'
  + '用户说「目标体重 72kg」等时调用；设置后先调用 get_recent_summary，再结合现状给出'
  + '达成目标的训练方案（频率、动作选择、组次、进阶与恢复）与饮食要点。\n'
  + '规则：用户给出记录类信息时，主动调用对应工具落库并简要确认；'
  + '需要用户数据支撑的建议，先调用 get_recent_summary 再回答；'
  + '饮食/摄入相关问题先调 get_daily_targets 或 get_diet_status 拿数据再解读；'
  + '制定训练/饮食计划时输出结构化、可执行的方案；不要虚构数据，工具返回未找到时如实告知。';

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

/** 空动作占位（ExerciseCardView 的 @Param 默认值）。 */
const EMPTY_EXERCISE: ExerciseRow = {
  id: '',
  name: '',
  cat: null,
  equip: null,
  target: null,
  secondary: null,
  stepsEn: null,
  stepsZh: null,
  gifPath: null,
  thumbPath: null,
};

@ObservedV2
export class ChatMsg {
  readonly role: string;
  readonly content: string;
  readonly exercise: ExerciseRow | null;
  readonly hero: boolean;

  constructor(role: string, content: string, exercise: ExerciseRow | null = null, hero: boolean = false) {
    this.role = role;
    this.content = content;
    this.exercise = exercise;
    this.hero = hero;
  }
}

// ------------------------------------------------------- OpenAI 兼容协议模型

interface ToolCallFunctionJson {
  name: string;
  arguments: string;
}

interface ToolCallJson {
  id: string;
  type: string;
  function: ToolCallFunctionJson;
}

/** chat/completions 消息（system/user/assistant/tool 通用，未用字段省略）。 */
interface ApiMsg {
  role: string;
  content: string | null;
  tool_calls?: ToolCallJson[];
  tool_call_id?: string;
  reasoning_content?: string | null;
}

interface ChatCompletionRequest {
  model: string;
  messages: ApiMsg[];
  tools?: OpenAiToolDef[];
  tool_choice?: string;
}

interface AssistantMsgJson {
  role?: string;
  content?: string | null;
  tool_calls?: ToolCallJson[];
  reasoning_content?: string | null;
}

interface ChoiceJson {
  message?: AssistantMsgJson;
}

interface CompletionJson {
  choices?: ChoiceJson[];
}

// ------------------------------------------------------- Anthropic 协议模型

interface AnthropicMsg {
  role: string;
  content: string | AnthropicBlock[];
}

interface AnthropicRequest {
  model: string;
  max_tokens: number;
  system?: string;
  messages: AnthropicMsg[];
  tools?: AnthropicToolDef[];
}

interface AnthropicBlock {
  type?: string;
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, Object>;
  tool_use_id?: string;
  content?: string;
}

interface AnthropicResponse {
  content?: AnthropicBlock[];
}

function greeting(): ChatMsg {
  return new ChatMsg('assistant', '', null, true);
}

/// 教练页：AI 对话。华为端侧模型（离线）或自定义接口（OpenAI/Anthropic 兼容，支持工具调用落库/查动作）。
@ComponentV2
export struct ChatPage {
  @Local messages: ChatMsg[] = [greeting()];
  @Local inputText: string = '';
  @Local sending: boolean = false;
  @Local aiReady: boolean = false;
  @Local checked: boolean = false;
  private scroller: Scroller = new Scroller();
  private deviceQuestionId: number = 0;
  private pendingExercise: ExerciseRow | null = null;

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

  private reply(msg: string, exercise: ExerciseRow | null): void {
    this.messages = this.messages.concat([new ChatMsg('assistant', msg, exercise)]);
    this.sending = false;
    this.scrollDown();
  }

  private systemPrompt(withTools: boolean): string {
    const head = `今天是 ${todayIso()}。`;
    if (withTools) {
      return `${head}\n\n${COACH_PROMPT}\n\n${COACH_TOOLS_PROMPT}`;
    }
    return `${head}\n\n${COACH_PROMPT}`;
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
    return `${this.systemPrompt(false)}\n\n以下是最近的对话记录：\n${dialog}\n用户：${question}\n\n请以教练身份回答用户最后的问题。`;
  }

  /** 端侧模型问答（init + chat，非流式），返回完整回答文本；失败抛 Error。 */
  private async askDeviceModel(question: string): Promise<string> {
    // 官方约束：端侧模型问答仅支持 PC/2in1；手机/平板上直接快速失败，走本地兜底
    const type = deviceInfo.deviceType;
    if (type !== 'pc' && type !== '2in1') {
      throw new Error('端侧模型仅支持 PC/2in1 设备；手机上请在「我的 → AI 服务」配置自定义模型');
    }
    const task = this.doAskDeviceModel(question);
    // 超时兜底：callback 可能不触发（Promise 挂起），保证 UI 不会卡在「正在思考…」
    const timer: Promise<string> = new Promise<string>((resolve, reject): void => {
      setTimeout((): void => {
        reject(new Error(DEVICE_MODEL_ERROR['1021900001']));
      }, 25000);
    });
    return Promise.race([task, timer]);
  }

  private async doAskDeviceModel(question: string): Promise<string> {
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

  /** 执行工具：确认气泡即时上屏、动作卡片挂到待附加状态；异常转失败结果。 */
  private async runTool(repo: Repo, name: string, argsJson: string): Promise<ToolOutcome> {
    let outcome: ToolOutcome;
    try {
      outcome = await CoachTools.execute(repo, name, argsJson);
    } catch (e) {
      outcome = new ToolOutcome(`工具执行失败：${(e as Error).message}`, null, null);
    }
    if (outcome.note !== null) {
      this.messages = this.messages.concat([new ChatMsg('note', outcome.note)]);
      this.scrollDown();
    }
    if (outcome.exercise !== null) {
      this.pendingExercise = outcome.exercise;
    }
    return outcome;
  }

  /** 近几轮对话（user/assistant）→ OpenAI 协议消息。 */
  private recentHistory(): ApiMsg[] {
    const out: ApiMsg[] = [];
    const start = this.messages.length > 12 ? this.messages.length - 12 : 0;
    for (let i = start; i < this.messages.length; i++) {
      const m = this.messages[i];
      if (m.role !== 'user' && m.role !== 'assistant') {
        continue;
      }
      const t: ApiMsg = { role: m.role, content: m.content };
      out.push(t);
    }
    return out;
  }

  /** OpenAI 兼容：带 tools 的多轮工具调用循环，返回最终回答文本。 */
  private async openAiLoop(repo: Repo, baseUrl: string, model: string,
    apiKey: string, history: ApiMsg[]): Promise<string> {
    const sys: ApiMsg = { role: 'system', content: this.systemPrompt(true) };
    const msgs: ApiMsg[] = [sys].concat(history);
    const endpoint = ChatPage.buildOpenAiEndpoint(baseUrl);
    for (let round = 0; round < 6; round++) {
      const req: ChatCompletionRequest = {
        model: model,
        messages: msgs,
        tools: OPENAI_TOOLS,
        tool_choice: 'auto',
      };
      console.info(`[CoachPal] oai round=${round} lastMsg=${JSON.stringify(msgs[msgs.length - 1]).substring(0, 400)}`);
      const resp = await Http.postJson(endpoint, req, apiKey, 90000);
      if (resp.status !== 200) {
        console.info(`[CoachPal] oai round=${round} HTTP ${resp.status}: ${resp.body.substring(0, 300)}`);
        throw new Error(this.customError(resp, endpoint));
      }
      const data = JSON.parse(resp.body) as CompletionJson;
      const choices = data.choices ?? [];
      if (choices.length === 0) {
        throw new Error('模型接口未返回结果');
      }
      const msg = choices[0].message;
      if (msg === undefined) {
        throw new Error('模型接口未返回结果');
      }
      console.info(`[CoachPal] oai round=${round} resp content=${msg.content === null ? 'null' : (msg.content ?? '').substring(0, 80)} rc=${msg.reasoning_content === undefined ? 'undef' : (msg.reasoning_content ?? 'null').substring(0, 60)} tc=${(msg.tool_calls ?? []).length}`);
      const calls = msg.tool_calls ?? [];
      if (calls.length === 0) {
        return msg.content ?? '（无回复）';
      }
      const assistantMsg: ApiMsg = {
        role: 'assistant',
        content: msg.content ?? null,
        tool_calls: calls,
        // 思考模型（deepseek-reasoner/qwen thinking 等）要求把 reasoning_content 回传
        reasoning_content: msg.reasoning_content ?? null,
      };
      msgs.push(assistantMsg);
      for (const call of calls) {
        const outcome = await this.runTool(repo, call.function.name, call.function.arguments);
        const toolMsg: ApiMsg = {
          role: 'tool',
          tool_call_id: call.id,
          content: outcome.resultForModel,
        };
        msgs.push(toolMsg);
      }
    }
    throw new Error('工具调用轮次过多，请精简问题后重试');
  }

  /** Anthropic 兼容：带 tools 的多轮工具调用循环，返回最终回答文本。 */
  private async anthropicLoop(repo: Repo, baseUrl: string, model: string,
    apiKey: string, history: ApiMsg[]): Promise<string> {
    const msgs: AnthropicMsg[] = [];
    for (const h of history) {
      const m: AnthropicMsg = { role: h.role, content: h.content ?? '' };
      msgs.push(m);
    }
    const endpoint = ChatPage.buildAnthropicEndpoint(baseUrl);
    const headers: Record<string, string> = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };
    for (let round = 0; round < 6; round++) {
      const req: AnthropicRequest = {
        model: model,
        max_tokens: 2048,
        system: this.systemPrompt(true),
        messages: msgs,
        tools: ANTHROPIC_TOOLS,
      };
      const resp = await Http.postJson(endpoint, req, apiKey, 90000, headers);
      if (resp.status !== 200) {
        throw new Error(this.customError(resp, endpoint));
      }
      const data = JSON.parse(resp.body) as AnthropicResponse;
      const blocks = data.content ?? [];
      let text = '';
      const toolUses: AnthropicBlock[] = [];
      for (const b of blocks) {
        if (b.type === 'text' && typeof b.text === 'string') {
          text += b.text;
        }
        if (b.type === 'tool_use') {
          toolUses.push(b);
        }
      }
      if (toolUses.length === 0) {
        if (text.length === 0) {
          throw new Error('模型接口未返回结果');
        }
        return text;
      }
      const assistantMsg: AnthropicMsg = { role: 'assistant', content: blocks };
      msgs.push(assistantMsg);
      const resultBlocks: AnthropicBlock[] = [];
      for (const u of toolUses) {
        const argsJson = u.input === undefined ? '{}' : JSON.stringify(u.input);
        const outcome = await this.runTool(repo, u.name ?? '', argsJson);
        const rb: AnthropicBlock = {
          type: 'tool_result',
          tool_use_id: u.id ?? '',
          content: outcome.resultForModel,
        };
        resultBlocks.push(rb);
      }
      const userMsg: AnthropicMsg = { role: 'user', content: resultBlocks };
      msgs.push(userMsg);
    }
    throw new Error('工具调用轮次过多，请精简问题后重试');
  }

  /** 自定义模型：按所选协议（OpenAI / Anthropic 兼容）直连，支持 Function Calling。 */
  private async askCustomModel(question: string, frozenHistory: ApiMsg[]): Promise<string> {
    const svc = AppServices.getInstance();
    const repo = svc.repo;
    if (repo === null) {
      throw new Error('本地数据库未就绪，请稍后重试');
    }
    const baseUrl = await svc.settings.getLlmBaseUrl();
    const model = await svc.settings.getLlmModel();
    const apiKey = await svc.settings.getLlmApiKey();
    const protocol = await svc.settings.getLlmProtocol();
    if (baseUrl.length === 0 || model.length === 0 || apiKey === null || apiKey.length === 0) {
      throw new Error('自定义模型未配置完整，请到「我的 → AI 服务」检查');
    }
    const history = frozenHistory;
    if (protocol === LlmProtocol.ANTHROPIC) {
      return this.anthropicLoop(repo, baseUrl, model, apiKey, history);
    }
    return this.openAiLoop(repo, baseUrl, model, apiKey, history);
  }

  /** 取走挂起的动作（工具调用命中）并清空；避免直接读属性被流分析收窄为 never。 */
  private takePendingExercise(): ExerciseRow | null {
    const p: ExerciseRow | null = this.pendingExercise;
    this.pendingExercise = null;
    return p;
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
    this.pendingExercise = null;
    this.scrollDown();
    // 冻结发给模型的历史：必须在插入本地动作讲解（assistant 消息）之前，
    // 否则请求以 assistant 结尾，思考模型会要求回传 reasoning_content 而 400
    const frozenHistory: ApiMsg[] = this.recentHistory();
    // 动作技能即时响应：端侧模型来源时命中本地动作库立刻出讲解 + GIF 卡片，不等待模型
    const repo = svc.repo;
    const source = await svc.settings.getAiSource();
    let localExercise: ExerciseRow | null = null;
    if (repo !== null) {
      localExercise = await ExerciseSkill.resolveFromUserText(repo, text);
    }
    let answered = false;
    if (localExercise !== null) {
      // 命中本地动作库：讲解 + GIF 卡片即时上屏，不等模型（自定义模型可能很慢）
      this.reply(ExerciseSkill.summarize(localExercise), localExercise);
      answered = true;
    }
    try {
      let answer = '';
      if (source === AiSource.CUSTOM) {
        answer = await this.askCustomModel(text, frozenHistory);
      } else {
        answer = await this.askDeviceModel(text);
      }
      let exercise: ExerciseRow | null = this.takePendingExercise();
      if (exercise !== null && answered && localExercise !== null && exercise.id === localExercise.id) {
        exercise = null; // 卡片已即时展示，避免重复
      }
      if (exercise === null && !answered && localExercise !== null) {
        exercise = localExercise;
      }
      this.reply(answer, exercise);
    } catch (e) {
      const msg = (e as Error).message;
      if (localExercise !== null) {
        if (!answered) {
          this.messages = this.messages.concat([new ChatMsg('note', msg)]);
          this.reply(ExerciseSkill.summarize(localExercise), localExercise);
        } else {
          // 已给出动作卡片；模型补充回复失败仅作小字提示
          this.messages = this.messages.concat([new ChatMsg('note', msg)]);
          this.scrollDown();
        }
      } else {
        this.reply(msg, null);
      }
    }
  }

  @Builder
  heroCard() {
    Column({ space: 10 }) {
      Text('你好，我是 CoachPal 教练 💪')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Text('直接跟我说就行，比如：')
        .fontSize(13)
        .fontColor('#E6FFFFFF')
      Column({ space: 6 }) {
        Text('· 「今天体重 77.9，体脂 21.4」').fontSize(13).fontColor('#E6FFFFFF')
        Text('· 「午饭吃了 150g 鸡胸肉、200g 米饭」').fontSize(13).fontColor('#E6FFFFFF')
        Text('· 「卧推 80kg 做了 5 组，RPE 8」').fontSize(13).fontColor('#E6FFFFFF')
        Text('· 「卧推怎么做？」——动作要领 + GIF 示范').fontSize(13).fontColor('#E6FFFFFF')
        Text('· 「帮我安排下周的训练计划」').fontSize(13).fontColor('#E6FFFFFF')
      }
      .alignItems(HorizontalAlign.Start)
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        Button('🏋️ 记体重体脂')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(14)
          .onClick((): void => {
            this.inputText = '今天体重 ，体脂 ';
          })
        Button('🤸 查动作示范')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(14)
          .onClick((): void => {
            this.inputText = '卧推怎么做？';
          })
        Button('🍚 记一顿饭')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(14)
          .onClick((): void => {
            this.inputText = '午饭吃了：';
          })
        Button('📋 排训练计划')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(14)
          .onClick((): void => {
            this.inputText = '帮我安排一周的训练计划，目标是';
          })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .linearGradient({
      angle: 135,
      colors: [[$r('app.color.primary'), 0], [$r('app.color.accent'), 1]],
    })
    .shadow({ radius: 10, color: 'rgba(235,104,52,0.30)', offsetY: 3 })
    .margin({ top: 4, bottom: 6 })
  }

  @Builder
  bubble(m: ChatMsg) {
    if (m.hero === true) {
      this.heroCard()
    } else if (m.role === 'note') {
      Text(m.content)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 2, bottom: 2 })
    } else {
      Row() {
        if (m.role === 'user') {
          Blank()
        }
        Column({ space: 6 }) {
          if (m.exercise !== null) {
            ExerciseCardView({ ex: m.exercise ?? EMPTY_EXERCISE })
          }
          if (m.content.length > 0) {
            if (m.role === 'user') {
              Text(m.content)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .constraintSize({ maxWidth: '82%' })
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.primary'))
                .borderRadius({
                  topLeft: 18,
                  topRight: 18,
                  bottomLeft: 18,
                  bottomRight: 4,
                })
                .shadow({ radius: 6, color: 'rgba(42,120,214,0.28)', offsetY: 2 })
            } else {
              Column() {
                MdText({ content: m.content })
              }
              .alignItems(HorizontalAlign.Start)
              .constraintSize({ maxWidth: '82%' })
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.card'))
              .borderRadius({
                topLeft: 4,
                topRight: 14,
                bottomLeft: 14,
                bottomRight: 14,
              })
              .border({
                width: { left: 3, top: 1, right: 1, bottom: 1 },
                color: {
                  left: $r('app.color.accent'),
                  top: $r('app.color.divider'),
                  right: $r('app.color.divider'),
                  bottom: $r('app.color.divider'),
                },
              })
            }
          }
        }
        .constraintSize({ maxWidth: '86%' })
        .alignItems(HorizontalAlign.Start)
        if (m.role !== 'user') {
          Blank()
        }
      }
      .width('100%')
      .margin({ top: 4, bottom: 4 })
    }
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
          }, (m: ChatMsg, idx: number) => `${idx}-${m.role}-${m.content.length}`)
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
        Row({ space: 10 }) {
          Column() {
            TextArea({ text: this.inputText, placeholder: '问问教练…' })
              .maxLines(4)
              .fontSize(14)
              .constraintSize({ minHeight: 36 })
              .width('100%')
              .backgroundColor(Color.Transparent)
              .onChange((v: string): void => {
                this.inputText = v;
              })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.card'))
          .borderRadius(20)
          .border({ width: 1, color: $r('app.color.divider') })
          .padding({ left: 14, right: 14 })
          .constraintSize({ minHeight: 40 })
          Button(this.sending ? '…' : '发送')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(22)
            .constraintSize({ minHeight: 44 })
            .padding({ left: 18, right: 18 })
            .shadow({ radius: 6, color: 'rgba(235,104,52,0.35)', offsetY: 2 })
            .opacity(this.sending ? 0.55 : 1)
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

/// 动作示范卡片：器械/肌群标签 + rawfile GIF + 中文动作要领。
@ComponentV2
struct ExerciseCardView {
  @Param ex: ExerciseRow = EMPTY_EXERCISE;

  private equipLabel(): string {
    const equip = this.ex.equip;
    return equip === null ? '' : (EQUIPMENT_ZH[equip] ?? equip);
  }

  private targetLabel(): string {
    const target = this.ex.target;
    return target === null ? '' : (MUSCLE_ZH[target] ?? target);
  }

  private catLabel(): string {
    const cat = this.ex.cat;
    return cat === null ? '' : (CATEGORY_ZH[cat] ?? cat);
  }

  private steps(): string[] {
    return decodeList(this.ex.stepsZh);
  }

  @Builder
  chip(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor($r('app.color.divider'))
      .borderRadius(10)
      .margin({ right: 6 })
  }

  build() {
    if (this.ex.id.length > 0) {
      Column({ space: 8 }) {
        Text(this.ex.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Row() {
          if (this.equipLabel().length > 0) {
            this.chip(this.equipLabel())
          }
          if (this.targetLabel().length > 0) {
            this.chip(this.targetLabel())
          }
          if (this.catLabel().length > 0) {
            this.chip(this.catLabel())
          }
        }
        .width('100%')

        if (this.ex.gifPath !== null) {
          Image($rawfile(this.ex.gifPath))
            .autoResize(true)
            .width('100%')
            .aspectRatio(1)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .backgroundColor($r('app.color.divider'))
        }

        ForEach(this.steps(), (s: string, idx: number) => {
          Text(`${idx + 1}. ${s}`)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .lineHeight(19)
        }, (s: string, idx: number) => `${idx}-${s.substring(0, 16)}`)
      }
      .padding(10)
      .backgroundColor($r('app.color.bg'))
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.divider') })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
