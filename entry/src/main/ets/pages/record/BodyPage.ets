import { GoalRow, MeasurementInput } from '../../core/repo/Model';
import { AppServices } from '../../core/services';
import { todayIso } from '../../core/util/Time';
import { CardContainer, SectionTitle, SITES, goalKindLabel, parseNum } from '../../components/Common';

// 目标下拉：三类 + 10 个围度部位
const GOAL_KINDS: string[] = ['weight', 'body_fat', 'muscle',
  'chest', 'waist', 'hip', 'neck', 'shoulder', 'arm', 'forearm', 'thigh', 'calf', 'wrist'];

function goalOptions(): SelectOption[] {
  const labels: string[] = ['体重 kg', '体脂率 %', '骨骼肌 kg'];
  for (const s of SITES) {
    labels.push(`${s.label} cm`);
  }
  const out: SelectOption[] = [];
  for (const l of labels) {
    const o: SelectOption = { value: l };
    out.push(o);
  }
  return out;
}

/// 身体页：体重/体脂/骨骼肌快捷记录（骨骼肌保存修复 Flutter 缺口）、围度表单、目标管理。
@ComponentV2
export struct BodyPage {
  @Local weightText: string = '';
  @Local bodyFatText: string = '';
  @Local muscleText: string = '';
  @Local siteValues: string[] = new Array<string>(SITES.length).fill('');
  @Local goalKindIndex: number = 0;
  @Local goalTargetText: string = '';
  @Local goals: GoalRow[] = [];
  private goalOpts: SelectOption[] = goalOptions();
  private subId: number = -1;

  aboutToAppear(): void {
    this.init();
  }

  aboutToDisappear(): void {
    if (this.subId >= 0) {
      AppServices.getInstance().bus.unsubscribe(this.subId);
      this.subId = -1;
    }
  }

  private async init(): Promise<void> {
    await AppServices.getInstance().whenReady();
    this.subId = AppServices.getInstance().bus.subscribe(
      ['goals', 'body_metrics', 'measurements'],
      (): void => {
        this.reloadGoals();
      });
    await this.reloadGoals();
  }

  private async reloadGoals(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    this.goals = await repo.listGoals();
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async saveWeight(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const w = parseNum(this.weightText);
    if (w === null || w < 20 || w > 400) {
      this.toast('体重不合理（20-400 kg）');
      return;
    }
    const bodyFat = parseNum(this.bodyFatText);
    const muscle = parseNum(this.muscleText);
    await repo.saveBodyMetric(todayIso(), w, bodyFat, muscle, null);
    this.weightText = '';
    this.bodyFatText = '';
    this.muscleText = '';
    this.toast(`已记录 ${w} kg`);
  }

  private async saveMeasurements(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const inputs: MeasurementInput[] = [];
    for (let i = 0; i < SITES.length; i++) {
      const v = parseNum(this.siteValues[i]);
      if (v !== null) {
        const item: MeasurementInput = { site: SITES[i].site, valueCm: v };
        inputs.push(item);
      }
    }
    if (inputs.length === 0) {
      this.toast('至少填一个围度');
      return;
    }
    await repo.addMeasurements(todayIso(), inputs);
    this.siteValues = new Array<string>(SITES.length).fill('');
    this.toast(`已记录 ${inputs.length} 项围度`);
  }

  private async addGoal(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const t = parseNum(this.goalTargetText);
    if (t === null) {
      this.toast('目标值必须是数字');
      return;
    }
    const raw = GOAL_KINDS[this.goalKindIndex];
    const isBase = raw === 'weight' || raw === 'body_fat' || raw === 'muscle';
    const kind = isBase ? raw : `measure:${raw}`;
    await repo.addGoal(kind, t, null);
    this.goalTargetText = '';
    this.toast('目标已添加');
  }

  private setSiteValue(idx: number, v: string): void {
    const arr = this.siteValues.slice();
    arr[idx] = v;
    this.siteValues = arr;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '体重 / 体成分' })
            Row({ space: 8 }) {
              TextInput({ text: this.weightText, placeholder: '体重 kg' })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.weightText = v;
                })
              TextInput({ text: this.bodyFatText, placeholder: '体脂率 %' })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.bodyFatText = v;
                })
              TextInput({ text: this.muscleText, placeholder: '骨骼肌 kg' })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.muscleText = v;
                })
            }
            .width('100%')
            Button('记录')
              .backgroundColor($r('app.color.primary'))
              .onClick((): void => {
                this.saveWeight();
              })
          }
        }

        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '今日围度 (cm)' })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(SITES, (s: SiteLabelLike, idx: number) => {
                TextInput({ text: this.siteValues[idx], placeholder: s.label })
                  .type(InputType.NUMBER_DECIMAL)
                  .width(150)
                  .margin({ right: 12, bottom: 12 })
                  .onChange((v: string): void => {
                    this.setSiteValue(idx, v);
                  })
              }, (s: SiteLabelLike) => s.site)
            }
            .width('100%')
            Button('记录围度')
              .backgroundColor($r('app.color.primary'))
              .onClick((): void => {
                this.saveMeasurements();
              })
          }
        }

        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '目标' })
            Row({ space: 8 }) {
              Select(this.goalOpts)
                .selected(this.goalKindIndex)
                .value(this.goalOpts[this.goalKindIndex].value)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .onSelect((idx: number): void => {
                  this.goalKindIndex = idx;
                })
              TextInput({ text: this.goalTargetText, placeholder: '目标值' })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .onChange((v: string): void => {
                  this.goalTargetText = v;
                })
            }
            .width('100%')
            Row() {
              Blank()
              Button('添加目标')
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.primary'))
                .onClick((): void => {
                  this.addGoal();
                })
            }
            .width('100%')
            ForEach(this.goals, (g: GoalRow) => {
              Row() {
                Text(goalKindLabel(g.kind))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(`目标 ${g.targetValue} ${g.unit ?? ''}`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }, (g: GoalRow) => g.uuid)
            if (this.goals.length === 0) {
              Text('还没有目标')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8 })
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

interface SiteLabelLike {
  site: string;
  label: string;
}
