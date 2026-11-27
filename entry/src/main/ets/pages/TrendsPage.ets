import { BodyMetricRow, MeasurementRow, MealEntry, WorkoutEntry, SeriesPoint } from '../core/repo/Model';
import { AppServices } from '../core/services';
import { dateDaysAgo } from '../core/util/Time';
import { LineChart, SERIES1, SERIES2, SERIES3 } from '../components/LineChart';
import { CardContainer, SectionTitle, SITES, siteLabel } from '../components/Common';

interface SiteGroup {
  site: string;
  points: SeriesPoint[];
}

/** 按 date 升序复制（趋势图统一旧 → 新）。 */
function sortByDate(points: SeriesPoint[]): SeriesPoint[] {
  return points.slice().sort((a: SeriesPoint, b: SeriesPoint): number =>
    a.date < b.date ? -1 : 1);
}

function compareEntry(a: [string, number], b: [string, number]): number {
  return a[0] < b[0] ? -1 : 1;
}

/// 趋势页：体重/体脂折线 + 围度部位切换 + 近 7 天复盘。
@ComponentV2
export struct TrendsPage {
  @Local metrics: BodyMetricRow[] = [];
  @Local measurements: MeasurementRow[] = [];
  @Local meals: MealEntry[] = [];
  @Local workouts: WorkoutEntry[] = [];
  @Local site: string = 'waist';
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
      ['body_metrics', 'measurements', 'meals', 'meal_items', 'workouts', 'workout_sets'],
      (): void => {
        this.reload();
      });
    await this.reload();
  }

  private async reload(): Promise<void> {
    const svc = AppServices.getInstance();
    if (svc.repo === null) {
      return;
    }
    this.metrics = await svc.repo.listMetrics();
    this.measurements = await svc.repo.listMeasurements();
    this.meals = await svc.repo.listAllMeals(30);
    this.workouts = await svc.repo.listWorkouts(365);
  }

  // ------------------------------------------------------- 序列构造

  private weightPoints(): SeriesPoint[] {
    const raw: SeriesPoint[] = [];
    for (const m of this.metrics) {
      if (m.weightKg !== null) {
        const p: SeriesPoint = { date: m.date, value: m.weightKg };
        raw.push(p);
      }
    }
    return sortByDate(raw);
  }

  private fatPoints(): SeriesPoint[] {
    const raw: SeriesPoint[] = [];
    for (const m of this.metrics) {
      if (m.bodyFatPct !== null) {
        const p: SeriesPoint = { date: m.date, value: m.bodyFatPct };
        raw.push(p);
      }
    }
    return sortByDate(raw);
  }

  private siteGroups(): SiteGroup[] {
    const order: string[] = [];
    const bySite = new Map<string, SeriesPoint[]>();
    for (const m of this.measurements) {
      let arr = bySite.get(m.site);
      if (arr === undefined) {
        arr = [];
        bySite.set(m.site, arr);
        order.push(m.site);
      }
      const p: SeriesPoint = { date: m.date, value: m.valueCm };
      arr.push(p);
    }
    const out: SiteGroup[] = [];
    // 围度卡片按 SITES 顺序展示部位
    for (const s of SITES) {
      const arr = bySite.get(s.site);
      if (arr !== undefined) {
        const g: SiteGroup = { site: s.site, points: sortByDate(arr) };
        out.push(g);
      }
    }
    return out;
  }

  private sitePoints(site: string): SeriesPoint[] {
    for (const g of this.siteGroups()) {
      if (g.site === site) {
        return g.points;
      }
    }
    return [];
  }

  // ------------------------------------------------------- 周复盘

  /** [dietLine, workoutLine, weightLine] 三行文本。 */
  private reviewLines(): string[] {
    const cutoff = dateDaysAgo(7);
    const dayTotals = new Map<string, number>();
    for (const entry of this.meals) {
      let kcal = 0;
      for (const it of entry.items) {
        kcal += it.kcal;
      }
      const cur = dayTotals.get(entry.meal.date) ?? 0;
      dayTotals.set(entry.meal.date, cur + kcal);
    }
    const recent: [string, number][] = [];
    dayTotals.forEach((v: number, k: string): void => {
      if (k > cutoff) {
        const pair: [string, number] = [k, v];
        recent.push(pair);
      }
    });
    recent.sort(compareEntry);
    let dietLine: string;
    if (recent.length === 0) {
      dietLine = '🍚 饮食：无记录';
    } else {
      let total = 0;
      for (const r of recent) {
        total += r[1];
      }
      dietLine = `🍚 饮食：记录 ${recent.length} 天 · 日均 ${(total / recent.length).toFixed(0)} kcal`;
    }

    const weekWorkouts: WorkoutEntry[] = [];
    for (const w of this.workouts) {
      if (w.workout.date > cutoff) {
        weekWorkouts.push(w);
      }
    }
    let volume = 0;
    for (const w of weekWorkouts) {
      for (const s of w.sets) {
        volume += (s.weightKg ?? 0) * (s.reps ?? 0);
      }
    }
    const workoutLine = `🏋️ 训练：${weekWorkouts.length} 次 · 总训练量 ${volume.toFixed(0)} kg`;

    const weights = this.weightPoints();
    let weightLine = '⚖️ 体重：记录两次后显示变化';
    if (weights.length >= 2) {
      const first = weights[0];
      const last = weights[weights.length - 1];
      const delta = last.value - first.value;
      const sign = delta >= 0 ? '+' : '';
      weightLine =
        `⚖️ 体重：${first.value.toFixed(1)} → ${last.value.toFixed(1)} kg（${sign}${delta.toFixed(1)}）`;
    }
    const lines: string[] = [dietLine, workoutLine, weightLine];
    return lines;
  }

  // ------------------------------------------------------- UI

  @Builder
  siteChip(g: SiteGroup) {
    Text(siteLabel(g.site))
      .fontSize(13)
      .fontWeight(this.site === g.site ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.site === g.site ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.site === g.site ? $r('app.color.accent') : $r('app.color.card'))
      .borderWidth(1)
      .borderColor(this.site === g.site ? $r('app.color.accent') : $r('app.color.card_border'))
      .borderRadius(16)
      .margin({ right: 8, top: 4, bottom: 4 })
      .onClick((): void => {
        this.site = g.site;
      })
  }

  @Builder
  comparisonLine(points: SeriesPoint[]) {
    if (points.length >= 2) {
      Text(`${points[0].date} ${points[0].value.toFixed(1)} → ` +
        `${points[points.length - 1].date} ${points[points.length - 1].value.toFixed(1)}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        CardContainer() {
          Column({ space: 8 }) {
            SectionTitle({ text: '体重 (kg)' })
            LineChart({
              points: this.weightPoints(),
              color: SERIES1,
              emptyText: '记录体重后显示趋势',
            })
            this.comparisonLine(this.weightPoints())
          }
          .width('100%')
        }

        CardContainer() {
          Column({ space: 8 }) {
            SectionTitle({ text: '体脂率 (%)' })
            LineChart({
              points: this.fatPoints(),
              color: SERIES2,
              emptyText: '记录体脂率后显示趋势',
            })
            this.comparisonLine(this.fatPoints())
          }
          .width('100%')
        }

        CardContainer() {
          Column({ space: 8 }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.siteGroups(), (g: SiteGroup) => {
                this.siteChip(g)
              }, (g: SiteGroup) => g.site)
            }
            .width('100%')
            SectionTitle({ text: `${siteLabel(this.site)} (cm)` })
            LineChart({
              points: this.sitePoints(this.site),
              color: SERIES3,
              emptyText: '记录围度后显示趋势',
            })
            this.comparisonLine(this.sitePoints(this.site))
          }
          .width('100%')
        }

        CardContainer() {
          Column({ space: 8 }) {
            SectionTitle({ text: '近 7 天复盘' })
            ForEach(this.reviewLines(), (line: string) => {
              Text(line)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
            }, (line: string) => line)
          }
          .width('100%')
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
