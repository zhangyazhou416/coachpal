import { AppServices } from '../core/services';
import { CardContainer, goalKindLabel } from '../components/Common';
import { GoalRow, BodyMetricRow, MeasurementRow, StrengthLogRow, RestorePayload } from '../core/repo/Model';
import { util } from '@kit.ArkTS';
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



/// 我的页：渐变用户卡 + 数据速览 + 目标进度 + 设置菜单（档案/AI/导出）+ 关于。
@ComponentV2
export struct ProfilePage {
  @Param hubVersion: number = 0;
  @Local stats: DataStats | null = null;
  @Local goalItems: GoalWithCurrent[] = [];
  @Local versionName: string = '';
  @Local exporting: boolean = false;
  @Local importing: boolean = false;
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
      const payload: RestorePayload = {
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

  private async importData(): Promise<void> {
    if (this.importing) {
      return;
    }
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    this.importing = true;
    let payload: RestorePayload | null = null;
    try {
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      const uris: string[] = await (new picker.DocumentViewPicker()).select(opts);
      if (uris.length === 0) {
        return;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      const size = fileIo.statSync(file.fd).size;
      const buf = new Uint8Array(size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);
      const text = util.TextDecoder.create('utf-8').decodeToString(buf);
      payload = JSON.parse(text) as RestorePayload;
      if (payload.exportedAt === undefined || payload.bodyMetrics === undefined
        || payload.meals === undefined || payload.workouts === undefined) {
        this.toast('不是有效的 CoachPal 备份文件');
        return;
      }
    } catch (e) {
      this.toast('读取备份失败：' + (e as Error).message);
      this.importing = false;
      return;
    }
    const picked = payload;
    this.getUIContext().showAlertDialog({
      title: '导入备份',
      message: `备份时间：${picked.exportedAt}
导入将覆盖当前全部数据（档案、体重、饮食、训练全部替换）。确定继续？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消', action: (): void => {
          this.importing = false;
        }
      },
      secondaryButton: {
        value: '确认导入', fontColor: $r('app.color.accent'),
        action: (): void => {
          this.applyImport(picked);
        }
      },
    });
  }

  private async applyImport(payload: RestorePayload): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    try {
      await repo.restoreFromBackup(payload);
      this.toast('导入成功 ✓');
      await this.refresh();
    } catch (e) {
      this.toast('导入失败：' + (e as Error).message);
    } finally {
      this.importing = false;
    }
  }

  private showAbout(): void {
    this.getUIContext().showAlertDialog({
      title: `关于 CoachPal`,
      message: `版本 v${this.versionName}

本地优先：所有数据仅存本机，不上传。
食物数据：《中国食物成分表（第 6 版）》
动作媒体：© Gym visual（仅限个人使用）`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '知道了', action: (): void => {
        }
      },
    });
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
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
            this.menuRow($r('sys.symbol.folder'), '导入数据',
              '从 JSON 备份恢复（覆盖现有数据）', (): void => {
                this.importData();
              })
            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 62 })
            this.menuRow($r('sys.symbol.info_circle'), '关于',
              `版本 · 数据来源`, (): void => {
                this.showAbout();
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
