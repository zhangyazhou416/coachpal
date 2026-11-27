import { BodyMetricRow, WorkoutEntry, ProfileRow, MealEntry } from '../core/repo/Model';
import { todayIso } from '../core/util/Time';
import { AppServices } from '../core/services';
import { estimate1rm, calcBmi, computeTargets, Targets } from '../core/domain/calc';
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

interface TodayIntake {
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  itemCount: number;
}

/// 概览页（纯展示）：身体素质快照 + 力量最大重量 + 近期摘要。记录统一由教练对话完成。
@ComponentV2
export struct OverviewPage {
  @Local snapshot: BodySnapshot | null = null;
  @Local prs: PrItem[] = [];
  @Local week: WeekSummary | null = null;
  @Local targets: Targets | null = null;
  @Local today: TodayIntake | null = null;
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
    // 每日目标 + 今日摄入
    if (profile !== null && metrics.length > 0 && metrics[0].weightKg !== null
      && profile.heightCm !== null && profile.heightCm > 0) {
      const birth = profile.birthDate;
      let age: number | null = null;
      if (birth !== null && birth.length >= 4) {
        const y = Number(birth.substring(0, 4));
        if (!Number.isNaN(y)) {
          age = new Date().getFullYear() - y;
        }
      }
      this.targets = computeTargets(profile.sex, age, profile.heightCm,
        metrics[0].weightKg, profile.activityLevel, profile.goalType);
    } else {
      this.targets = null;
    }
    const todayMeals: MealEntry[] = await repo.listMeals(todayIso());
    if (todayMeals.length > 0) {
      let tk = 0;
      let tp = 0;
      let tf = 0;
      let tc = 0;
      let items = 0;
      for (const m of todayMeals) {
        for (const it of m.items) {
          tk += it.kcal;
          tp += it.protein;
          tf += it.fat;
          tc += it.carbs;
          items++;
        }
      }
      const t: TodayIntake = {
        kcal: Math.round(tk), protein: Math.round(tp),
        fat: Math.round(tf), carbs: Math.round(tc), itemCount: items,
      };
      this.today = t;
    } else {
      this.today = null;
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
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent'))
      Text(sub)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  macroCell(label: string, actual: number, target: number, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
      Text(`${Math.round(actual)}/${target}g`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Progress({ value: Math.min(Math.round(actual), target), total: target })
        .width('100%')
        .height(4)
        .color(color)
        .backgroundColor($r('app.color.divider'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  intakeCard() {
    CardContainer() {
      Column({ space: 10 }) {
        SectionTitle({ text: '今日摄入' })
        if (this.targets === null) {
          Text('先完善档案并记录一次体重，即可生成每日摄入目标（热量 + 蛋白/脂肪/碳水）')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else if (this.today === null) {
          Text(`每日目标 ${this.targets.kcal} kcal（蛋白 ${this.targets.protein}g / 脂肪 ${this.targets.fat}g / 碳水 ${this.targets.carbs}g）`)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text('今天还没记录饮食，跟教练说一句「午饭吃了…」即可记录')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          Row() {
            Text('已摄入')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`${this.today.kcal} / ${this.targets.kcal} kcal`)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')
          Progress({ value: Math.min(this.today.kcal, this.targets.kcal), total: this.targets.kcal })
            .width('100%')
            .height(6)
            .color($r('app.color.accent'))
            .backgroundColor($r('app.color.divider'))
          Text(`剩余 ${Math.max(0, this.targets.kcal - this.today.kcal)} kcal（已记录 ${this.today.itemCount} 项）`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Row({ space: 8 }) {
            this.macroCell('蛋白', this.today.protein, this.targets.protein, $r('app.color.primary'))
            this.macroCell('脂肪', this.today.fat, this.targets.fat, $r('app.color.series4'))
            this.macroCell('碳水', this.today.carbs, this.targets.carbs, $r('app.color.series3'))
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // ---- 今日摄入 ----
        this.intakeCard()

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
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  Text(`${fmtKg(pr.maxWeight)}kg × ${pr.maxWeightReps}`)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Text(`${pr.est1rm.toFixed(1)} kg`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.accent'))
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
                : '🍚 饮食：近 7 天无记录')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(this.week.workoutCount > 0
                ? `训练：${this.week.workoutCount} 次 · 总训练量 ${this.week.volumeKg.toFixed(0)} kg`
                : '🏋️ 训练：近 7 天无记录')
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
