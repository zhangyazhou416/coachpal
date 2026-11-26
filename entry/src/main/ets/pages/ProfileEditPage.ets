import { AppServices } from '../core/services';
import { todayIso } from '../core/util/Time';
import { CardContainer, SectionTitle, parseNum } from '../components/Common';
import { router } from '@kit.ArkUI';

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

/// 个人档案页：性别/身高/活动水平/目标 + 快捷记体重。
@Entry
@ComponentV2
struct ProfileEditPage {
  @Local sexIndex: number = 0;
  @Local heightText: string = '';
  @Local activityIndex: number = 2;
  @Local goalIndex: number = 0;
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
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

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

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.titleBar('个人档案')

        // 档案
        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '基础档案' })
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
