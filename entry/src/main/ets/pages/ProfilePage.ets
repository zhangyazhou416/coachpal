import { AppServices } from '../core/services';
import { CardContainer, goalKindLabel } from '../components/Common';
import { AiSource } from '../core/settings/Settings';
import { GoalRow, BodyMetricRow, MeasurementRow, StrengthLogRow, MealEntry, WorkoutEntry, ProfileRow } from '../core/repo/Model';
import { router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';

interface GoalWithCurrent {
  goal: GoalRow;
  current: number | null;
}

interface DataStats {
  foods: number;
  exercises: number;
  metricCount: number;
  workoutCount: number;
}

function goalUnit(kind: string): string {
  if (kind.startsWith('measure:')) {
    return 'cm';
  }
  if (kind === 'body_fat') {
    return '%';
  }
  return 'kg';
}

function goalCurrentOf(kind: string, latest: BodyMetricRow | null,
  measurements: MeasurementRow[], logs: StrengthLogRow[]): number | null {
  if (kind === 'weight') {
    return latest === null ? null : latest.weightKg;
  }
  if (kind === 'body_fat') {
    return latest === null ? null : latest.bodyFatPct;
  }
  if (kind === 'muscle') {
    return latest === null ? null : latest.skeletalMuscleKg;
  }
  if (kind.startsWith('measure:')) {
    const site = kind.split(':')[1];
    for (const m of measurements) {
      if (m.site === site) {
        return m.valueCm;
      }
    }
    return null;
  }
  if (kind.startsWith('strength:')) {
    const lift = kind.split(':')[1];
    for (const l of logs) {
      if (l.lift === lift) {
        return l.estimated1rm;
      }
    }
    return null;
  }
  return null;
}

function fmtVal(v: number | null): string {
  return v === null ? '—' : String(Math.round(v * 10) / 10);
}

interface ExportPayload {
  exportedAt: string;
  profile: ProfileRow | null;
  bodyMetrics: BodyMetricRow[];
  measurements: MeasurementRow[];
  goals: GoalRow[];
  strengthLogs: StrengthLogRow[];
  meals: MealEntry[];
  workouts: WorkoutEntry[];
}

/// 我的页：渐变用户卡 + 数据速览 + 目标进度 + 设置菜单（档案/AI/导出）+ 关于。
@ComponentV2
export struct ProfilePage {
  @Param hubVersion: number = 0;
  @Local aiOk: boolean = false;
  @Local aiLabel: string = '';
  @Local stats: DataStats | null = null;
  @Local goalItems: GoalWithCurrent[] = [];
  @Local versionName: string = '';
  @Local exporting: boolean = false;
  private latestMetric: BodyMetricRow | null = null;

  aboutToAppear(): void {
    this.refresh();
  }

  @Monitor('hubVersion')
  onHubVersionChange(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const svc = AppServices.getInstance();
    await svc.whenReady();
    const source = await svc.settings.getAiSource();
    if (source === AiSource.CUSTOM) {
      this.aiOk = await svc.settings.isAiConfigured();
      this.aiLabel = this.aiOk ? 'AI：自定义模型' : 'AI：自定义模型待配置';
    } else {
      this.aiOk = true;
      this.aiLabel = 'AI：华为端侧模型';
    }
    await this.loadExtra();
  }

  private async loadExtra(): Promise<void> {
    const svc = AppServices.getInstance();
    const repo = svc.repo;
    if (repo === null) {
      return;
    }
    const foods = await repo.countTable('foods');
    const exercises = await repo.countTable('exercises');
    const metrics: BodyMetricRow[] = await repo.listMetrics();
    this.latestMetric = metrics.length > 0 ? metrics[0] : null;
    const workouts = await repo.listWorkouts(3650);
    this.stats = {
      foods: foods,
      exercises: exercises,
      metricCount: metrics.length,
      workoutCount: workouts.length,
    };
    const measurements: MeasurementRow[] = await repo.listMeasurements();
    const logs: StrengthLogRow[] = await repo.listStrengthLogs();
    const all: GoalRow[] = await repo.listGoals();
    const items: GoalWithCurrent[] = [];
    for (const g of all) {
      if (g.status !== 'active') {
        continue;
      }
      const cur: GoalWithCurrent = {
        goal: g,
        current: goalCurrentOf(g.kind, this.latestMetric, measurements, logs),
      };
      items.push(cur);
    }
    this.goalItems = items.slice(0, 3);
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '';
    }
  }

  private async exportData(): Promise<void> {
    if (this.exporting) {
      return;
    }
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    this.exporting = true;
    try {
      const profile = await repo.getProfile();
      const payload: ExportPayload = {
        exportedAt: new Date().toISOString(),
        profile: profile,
        bodyMetrics: await repo.listMetrics(),
        measurements: await repo.listMeasurements(),
        goals: await repo.listGoals(),
        strengthLogs: await repo.listStrengthLogs(),
        meals: await repo.listAllMeals(3650),
        workouts: await repo.listWorkouts(3650),
      };
      const opts = new picker.DocumentSaveOptions();
      const result: string[] = await (new picker.DocumentViewPicker()).save(opts);
      if (result.length === 0) {
        return;
      }
      const file = fileIo.openSync(result[0], fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(file.fd, JSON.stringify(payload));
      fileIo.closeSync(file.fd);
      this.toast('数据已导出 ✓');
    } catch (e) {
      this.toast('导出失败：' + (e as Error).message);
    } finally {
      this.exporting = false;
    }
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2400 });
  }

  @Builder
  statCell(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  goalRow(item: GoalWithCurrent) {
    Column({ space: 6 }) {
      Row() {
        Text(goalKindLabel(item.goal.kind))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(fmtVal(item.current) === '—' ? '当前 —'
          : `当前 ${fmtVal(item.current)}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Progress({ value: this.goalPercent(item), total: 100 })
        .width('100%')
        .height(6)
        .color($r('app.color.accent'))
        .backgroundColor($r('app.color.divider'))
      Text(`目标 ${fmtVal(item.goal.targetValue)} ${goalUnit(item.goal.kind)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  private goalPercent(item: GoalWithCurrent): number {
    const base = item.goal.baselineValue;
    const target = item.goal.targetValue;
    const cur = item.current;
    if (base === null || cur === null || target === base) {
      return 0;
    }
    const pct = Math.abs(cur - base) / Math.abs(target - base) * 100;
    return Math.max(0, Math.min(100, Math.round(pct)));
  }

  @Builder
  menuRow(icon: Resource, title: string, sub: string, onTap: () => void) {
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

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 用户信息（渐变 hero）
        Column({ space: 12 }) {
          Row({ space: 14 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
                .fontSize(28)
                .fontColor([$r('app.color.accent')])
            }
            .width(54)
            .height(54)
            .borderRadius(27)
            .backgroundColor(Color.White)
            .justifyContent(FlexAlign.Center)
            .shadow({ radius: 6, color: 'rgba(0,0,0,0.18)', offsetY: 2 })

            Column({ space: 2 }) {
              Text('CoachPal')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(this.aiLabel)
                .fontSize(12)
                .fontColor('#E6FFFFFF')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(this.aiOk ? '✓' : '!')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(this.aiOk ? $r('app.color.status_good') : $r('app.color.status_warn'))
          }
          .width('100%')
        }
        .padding(18)
        .borderRadius(16)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.primary'), 0], [$r('app.color.accent'), 1]],
        })
        .shadow({ radius: 10, color: 'rgba(235,104,52,0.30)', offsetY: 3 })

        // 数据速览
        if (this.stats !== null) {
          CardContainer() {
            Row() {
              this.statCell('食物', String(this.stats.foods))
              this.statCell('动作', String(this.stats.exercises))
              this.statCell('体重记录', String(this.stats.metricCount))
              this.statCell('训练次数', String(this.stats.workoutCount))
            }
            .width('100%')
          }
        }

        // 目标进度
        if (this.goalItems.length > 0) {
          CardContainer() {
            Column({ space: 6 }) {
              Text('我的目标')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ bottom: 2 })
              ForEach(this.goalItems, (item: GoalWithCurrent) => {
                this.goalRow(item)
              }, (item: GoalWithCurrent) => item.goal.uuid)
              Text('目标由教练对话创建，例如「设个目标：体重 72kg」')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }

        // 设置菜单
        CardContainer() {
          Column() {
            this.menuRow($r('sys.symbol.person_fill'), '个人档案',
              '性别 · 身高 · 活动水平 · 目标', (): void => {
                router.pushUrl({ url: 'pages/ProfileEditPage' });
              })
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
            this.menuRow($r('sys.symbol.bolt'), 'AI 服务',
              '端侧模型 · 自定义模型', (): void => {
                router.pushUrl({ url: 'pages/AiConfigPage' });
              })
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
            this.menuRow($r('sys.symbol.download'), '导出数据',
              '全部数据导出为 JSON 备份', (): void => {
                this.exportData();
              })
          }
        }

        // 关于
        Text(`CoachPal v${this.versionName} · 本地数据，不出本机\n食物数据：《中国食物成分表（第 6 版）》 · 动作媒体：© Gym visual（仅限个人使用）`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6 })
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
