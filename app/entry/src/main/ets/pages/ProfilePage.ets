import { AppServices } from '../core/services';
import { Http } from '../core/net/Http';
import { todayIso } from '../core/util/Time';
import { CardContainer, SectionTitle, parseNum } from '../components/Common';

interface KindOption {
  value: string;
  label: string;
}

const SEX_OPTIONS: KindOption[] = [
  { value: 'male', label: '男' },
  { value: 'female', label: '女' },
  { value: 'other', label: '其他' },
];
const ACTIVITY_OPTIONS: KindOption[] = [
  { value: 'sedentary', label: '久坐' },
  { value: 'light', label: '轻度' },
  { value: 'moderate', label: '中等' },
  { value: 'active', label: '活跃' },
  { value: 'very_active', label: '非常活跃' },
];
const GOAL_OPTIONS: KindOption[] = [
  { value: 'cut', label: '减脂' },
  { value: 'maintain', label: '维持' },
  { value: 'bulk', label: '增肌' },
];

function toSelectOptions(opts: KindOption[]): SelectOption[] {
  const out: SelectOption[] = [];
  for (const o of opts) {
    const s: SelectOption = { value: o.label };
    out.push(s);
  }
  return out;
}

function indexOfValue(opts: KindOption[], v: string): number {
  for (let i = 0; i < opts.length; i++) {
    if (opts[i].value === v) {
      return i;
    }
  }
  return 0;
}

/// 我的页：档案（性别/身高/活动水平/目标）+ 同步服务（连接/立即同步/自动同步）+ 快捷记体重。
@ComponentV2
export struct ProfilePage {
  // 档案
  @Local sexIndex: number = 0;
  @Local heightText: string = '';
  @Local activityIndex: number = 2;
  @Local goalIndex: number = 0;
  // 同步
  @Local serverUrlText: string = '';
  @Local passwordText: string = '';
  @Local connected: boolean = false;
  @Local busy: boolean = false;
  @Local syncing: boolean = false;
  @Local autoSync: boolean = false;
  @Local assetMeta: string = '';
  // 体重
  @Local weightText: string = '';
  @Local bodyFatText: string = '';
  private sexOpts: SelectOption[] = toSelectOptions(SEX_OPTIONS);
  private activityOpts: SelectOption[] = toSelectOptions(ACTIVITY_OPTIONS);
  private goalOpts: SelectOption[] = toSelectOptions(GOAL_OPTIONS);

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    const svc = AppServices.getInstance();
    await svc.whenReady();
    const repo = svc.repo;
    if (repo !== null) {
      const p = await repo.getProfile();
      if (p !== null) {
        this.sexIndex = indexOfValue(SEX_OPTIONS, p.sex);
        this.activityIndex = indexOfValue(ACTIVITY_OPTIONS, p.activityLevel);
        this.goalIndex = indexOfValue(GOAL_OPTIONS, p.goalType);
        if (p.heightCm !== null) {
          this.heightText = String(p.heightCm);
        }
      }
    }
    const url = await svc.settings.getServerUrl();
    if (this.serverUrlText.length === 0 && url.length > 0) {
      this.serverUrlText = url;
    }
    this.connected = await svc.settings.isConfigured();
    this.autoSync = await svc.settings.getAutoSync();
    this.assetMeta = await svc.settings.getAssetMeta();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  // ------------------------------------------------------- 档案

  private async saveProfile(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const h = parseNum(this.heightText);
    await repo.saveProfile(SEX_OPTIONS[this.sexIndex].value, h,
      ACTIVITY_OPTIONS[this.activityIndex].value, GOAL_OPTIONS[this.goalIndex].value);
    this.toast('档案已保存');
  }

  // ------------------------------------------------------- 同步

  private async login(): Promise<void> {
    const svc = AppServices.getInstance();
    const raw = this.serverUrlText.trim().replace(/\/+$/, '');
    const url = raw.length === 0 ? 'http://127.0.0.1:8321' : raw;
    this.serverUrlText = url;
    if (this.passwordText.length === 0) {
      this.toast('先输入访问密码');
      return;
    }
    this.busy = true;
    try {
      const body: Record<string, string> = { 'password': this.passwordText };
      const resp = await Http.postJson(`${url}/api/auth/login`, body, null);
      if (resp.status !== 200) {
        this.toast(`登录失败：HTTP ${resp.status}`);
        return;
      }
      const data = JSON.parse(resp.body) as Record<string, Object>;
      const tokenVal = data['token'];
      if (typeof tokenVal !== 'string') {
        this.toast('登录响应缺少 token');
        return;
      }
      await svc.settings.setServerUrl(url);
      await svc.settings.saveToken(tokenVal);
      this.connected = true;
      this.passwordText = '';
      this.toast('已连接服务器');
    } catch (e) {
      this.toast('连接失败，请检查服务器地址与网络');
    } finally {
      this.busy = false;
    }
  }

  private async syncNow(): Promise<void> {
    const svc = AppServices.getInstance();
    if (svc.sync === null) {
      return;
    }
    this.syncing = true;
    try {
      const r = await svc.sync.sync();
      if (r.ok) {
        this.toast('同步完成');
      } else {
        this.toast(r.error ?? '同步失败');
      }
    } finally {
      this.syncing = false;
    }
  }

  private async toggleAutoSync(on: boolean): Promise<void> {
    this.autoSync = on;
    await AppServices.getInstance().settings.setAutoSync(on);
  }

  // ------------------------------------------------------- 体重

  private async addWeight(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const w = parseNum(this.weightText);
    if (w === null || w < 20 || w > 400) {
      this.toast('体重不合理（20-400 kg）');
      return;
    }
    const bf = parseNum(this.bodyFatText);
    await repo.addWeight(w, bf);
    const date = todayIso();
    this.weightText = '';
    this.bodyFatText = '';
    this.toast(`已记录 ${date} 体重 ${w} kg`);
  }

  // ------------------------------------------------------- UI

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 个人档案
        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '个人档案' })
            Row({ space: 12 }) {
              Text('性别')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width(72)
              Select(this.sexOpts)
                .selected(this.sexIndex)
                .value(this.sexOpts[this.sexIndex].value)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .onSelect((idx: number): void => {
                  this.sexIndex = idx;
                })
            }
            .width('100%')
            Row({ space: 12 }) {
              Text('身高 cm')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width(72)
              TextInput({ text: this.heightText, placeholder: '178' })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.heightText = v;
                })
            }
            .width('100%')
            Row({ space: 12 }) {
              Text('活动水平')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width(72)
              Select(this.activityOpts)
                .selected(this.activityIndex)
                .value(this.activityOpts[this.activityIndex].value)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .onSelect((idx: number): void => {
                  this.activityIndex = idx;
                })
            }
            .width('100%')
            Row({ space: 12 }) {
              Text('目标')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width(72)
              Select(this.goalOpts)
                .selected(this.goalIndex)
                .value(this.goalOpts[this.goalIndex].value)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .onSelect((idx: number): void => {
                  this.goalIndex = idx;
                })
            }
            .width('100%')
            Button('保存档案')
              .backgroundColor($r('app.color.primary'))
              .width('100%')
              .onClick((): void => {
                this.saveProfile();
              })
          }
        }

        // 同步服务
        CardContainer() {
          Column({ space: 12 }) {
            Row() {
              SectionTitle({ text: '同步服务' })
              Blank()
              Text(this.connected ? '已连接 ✓' : '未连接')
                .fontSize(13)
                .fontColor(this.connected ? $r('app.color.status_good') : $r('app.color.text_secondary'))
            }
            .width('100%')
            TextInput({ text: this.serverUrlText, placeholder: 'http://192.168.1.10:8321' })
              .onChange((v: string): void => {
                this.serverUrlText = v;
              })
            TextInput({ text: this.passwordText, placeholder: '访问密码' })
              .type(InputType.Password)
              .onChange((v: string): void => {
                this.passwordText = v;
              })
            Button(this.busy ? '连接中…' : '连接')
              .backgroundColor($r('app.color.primary'))
              .width('100%')
              .enabled(!this.busy)
              .onClick((): void => {
                this.login();
              })
            Row({ space: 12 }) {
              Button(this.syncing ? '同步中…' : '立即同步')
                .backgroundColor($r('app.color.divider'))
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .enabled(!this.syncing)
                .onClick((): void => {
                  this.syncNow();
                })
              Row() {
                Text('启动自动同步')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
                  .selectedColor($r('app.color.primary'))
                  .margin({ left: 8 })
                  .onChange((on: boolean): void => {
                    this.toggleAutoSync(on);
                  })
              }
            }
            .width('100%')
            Text('连接后即可使用「教练」对话页完成所有记录；数据本地保存并同步到服务。')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
            if (this.assetMeta.length > 0) {
              Text(`资产数据版本：${this.assetMeta}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
          }
        }

        // 记一笔体重
        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '记一笔体重' })
            TextInput({ text: this.weightText, placeholder: '体重 kg' })
              .type(InputType.NUMBER_DECIMAL)
              .onChange((v: string): void => {
                this.weightText = v;
              })
            TextInput({ text: this.bodyFatText, placeholder: '体脂率 %（可选）' })
              .type(InputType.NUMBER_DECIMAL)
              .onChange((v: string): void => {
                this.bodyFatText = v;
              })
            Button('记录体重')
              .backgroundColor($r('app.color.divider'))
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .onClick((): void => {
                this.addWeight();
              })
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
