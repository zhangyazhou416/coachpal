import { BodyMetricRow, WorkoutEntry, ProfileRow } from '../core/repo/Model';
import { AppServices } from '../core/services';
import { estimate1rm, calcBmi } from '../core/domain/calc';
import { CardContainer, SectionTitle, fmtKg } from '../components/Common';

interface PrItem {
  lift: string;
  maxWeight: number;
  maxWeightReps: number;
  est1rm: number;
}

interface BodySnapshot {
  weightKg: number | null;
  weightDelta: number | null;
  bodyFatPct: number | null;
  skeletalMuscleKg: number | null;
  bmi: number | null;
  date: string;
}

interface WeekSummary {
  dietDays: number;
  avgKcal: number;
  workoutCount: number;
  volumeKg: number;
}

/// 概览页（纯展示）：身体素质快照 + 力量最大重量 + 近期摘要。记录统一由教练对话完成。
@ComponentV2
export struct OverviewPage {
  @Local snapshot: BodySnapshot | null = null;
  @Local prs: PrItem[] = [];
  @Local week: WeekSummary | null = null;
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
      ['body_metrics', 'meals', 'meal_items', 'workouts', 'workout_sets', 'profile'],
      (): void => {
        this.reload();
      });
    await this.reload();
  }

  private async reload(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    // 身体素质快照：最新一条 + 上一条对比 + BMI
    const profile: ProfileRow | null = await repo.getProfile();
    const metrics: BodyMetricRow[] = await repo.listMetrics();
    if (metrics.length > 0) {
      const latest = metrics[0];
      let delta: number | null = null;
      for (let i = 1; i < metrics.length; i++) {
        if (metrics[i].weightKg !== null) {
          delta = latest.weightKg !== null ? latest.weightKg - (metrics[i].weightKg ?? 0) : null;
          break;
        }
      }
      const snap: BodySnapshot = {
        weightKg: latest.weightKg,
        weightDelta: delta,
        bodyFatPct: latest.bodyFatPct,
        skeletalMuscleKg: latest.skeletalMuscleKg,
        bmi: calcBmi(latest.weightKg, profile === null ? null : profile.heightCm),
        date: latest.date,
      };
      this.snapshot = snap;
    } else {
      this.snapshot = null;
    }
    // 力量最大重量：按动作聚合（最大重量 + 估算 1RM）
    const workouts: WorkoutEntry[] = await repo.listWorkouts(3650);
    const byLift = new Map<string, PrItem>();
    for (const w of workouts) {
      for (const s of w.sets) {
        const weight = s.weightKg ?? 0;
        const reps = s.reps ?? 0;
        if (weight <= 0 && reps <= 0) {
          continue;
        }
        const est = estimate1rm(weight, reps);
        const cur = byLift.get(s.exerciseName);
        if (cur === undefined) {
          const item: PrItem = {
            lift: s.exerciseName,
            maxWeight: weight,
            maxWeightReps: reps,
            est1rm: est,
          };
          byLift.set(s.exerciseName, item);
          continue;
        }
        if (weight > cur.maxWeight) {
          cur.maxWeight = weight;
          cur.maxWeightReps = reps;
        } else if (weight === cur.maxWeight && reps > cur.maxWeightReps) {
          cur.maxWeightReps = reps;
        }
        if (est > cur.est1rm) {
          cur.est1rm = est;
        }
      }
    }
    const prs: PrItem[] = [];
    byLift.forEach((v: PrItem): void => {
      prs.push(v);
    });
    prs.sort((a: PrItem, b: PrItem): number => b.est1rm - a.est1rm);
    this.prs = prs.slice(0, 8);
    // 近期摘要
    const meals = await repo.listAllMeals(7);
    const dayTotals = new Map<string, number>();
    for (const entry of meals) {
      let kcal = 0;
      for (const it of entry.items) {
        kcal += it.kcal;
      }
      const cur = dayTotals.get(entry.meal.date) ?? 0;
      dayTotals.set(entry.meal.date, cur + kcal);
    }
    let total = 0;
    let days = 0;
    dayTotals.forEach((v: number): void => {
      total += v;
      days++;
    });
    let volume = 0;
    let count = 0;
    for (const w of workouts) {
      count++;
      for (const s of w.sets) {
        volume += (s.weightKg ?? 0) * (s.reps ?? 0);
      }
    }
    const week: WeekSummary = {
      dietDays: days,
      avgKcal: days > 0 ? total / days : 0,
      workoutCount: count,
      volumeKg: volume,
    };
    this.week = week;
  }

  @Builder
  metricCell(label: string, value: string, sub: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(sub)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // ---- 身体素质 ----
        CardContainer() {
          Column({ space: 12 }) {
            SectionTitle({ text: '身体素质' })
            if (this.snapshot !== null) {
              Row() {
                this.metricCell('体重 (kg)',
                  this.snapshot.weightKg === null ? '—' : this.snapshot.weightKg.toFixed(1),
                  this.snapshot.weightDelta === null ? this.snapshot.date
                    : `${this.snapshot.weightDelta >= 0 ? '+' : ''}${this.snapshot.weightDelta.toFixed(1)} 较上次`)
                this.metricCell('体脂率 (%)',
                  this.snapshot.bodyFatPct === null ? '—' : this.snapshot.bodyFatPct.toFixed(1),
                  this.snapshot.date)
                this.metricCell('骨骼肌 (kg)',
                  this.snapshot.skeletalMuscleKg === null ? '—' : this.snapshot.skeletalMuscleKg.toFixed(1),
                  this.snapshot.date)
                this.metricCell('BMI',
                  this.snapshot.bmi === null ? '—' : this.snapshot.bmi.toFixed(1),
                  this.snapshot.date)
              }
              .width('100%')
            } else {
              Text('还没有身体数据，跟教练说一句「今天体重 77.5」即可记录')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
        }

        // ---- 力量最大重量 ----
        CardContainer() {
          Column({ space: 6 }) {
            SectionTitle({ text: '力量最大重量' })
            if (this.prs.length > 0) {
              Row() {
                Text('动作')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Text('最大重量')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Text('估算 1RM')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 20 })
              }
              .width('100%')
              ForEach(this.prs, (pr: PrItem) => {
                Row() {
                  Text(pr.lift)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  Text(`${fmtKg(pr.maxWeight)}kg × ${pr.maxWeightReps}`)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`${pr.est1rm.toFixed(1)} kg`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 20 })
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }, (pr: PrItem) => pr.lift)
            } else {
              Text('还没有训练记录，跟教练说「卧推 80kg 5 组」即可记录')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
        }

        // ---- 近期摘要 ----
        if (this.week !== null) {
          CardContainer() {
            Column({ space: 6 }) {
              SectionTitle({ text: '近 7 天' })
              Text(this.week.dietDays > 0
                ? `饮食：记录 ${this.week.dietDays} 天 · 日均 ${this.week.avgKcal.toFixed(0)} kcal`
                : '饮食：近 7 天无记录')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(this.week.workoutCount > 0
                ? `训练：${this.week.workoutCount} 次 · 总训练量 ${this.week.volumeKg.toFixed(0)} kg`
                : '训练：近 7 天无记录')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
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
