import { parseSetSpec, ParsedSet } from '../../core/domain/set_parser';
import { WorkoutEntry, StrengthLogRow } from '../../core/repo/Model';
import { AppServices } from '../../core/services';
import { todayIso } from '../../core/util/Time';
import { CardContainer, SectionTitle, fmtKg } from '../../components/Common';

interface PrItem {
  lift: string;
  est: number;
}

/// 训练记录：组规格解析（别名）+ 保存 + 最近训练与 PR。
@ComponentV2
export struct WorkoutPage {
  @Local nameText: string = '';
  @Local specText: string = '';
  @Local pending: ParsedSet[] = [];
  @Local workouts: WorkoutEntry[] = [];
  @Local prs: PrItem[] = [];
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
      ['workouts', 'workout_sets', 'strength_logs'],
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
    this.workouts = await repo.listWorkouts();
    const logs: StrengthLogRow[] = await repo.listStrengthLogs();
    const byLift = new Map<string, number>();
    for (const l of logs) {
      const cur = byLift.get(l.lift) ?? 0;
      if (l.estimated1rm > cur) {
        byLift.set(l.lift, l.estimated1rm);
      }
    }
    const prs: PrItem[] = [];
    byLift.forEach((v: number, k: string): void => {
      const item: PrItem = { lift: k, est: v };
      prs.push(item);
    });
    prs.sort((a: PrItem, b: PrItem): number => b.est - a.est);
    this.prs = prs;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async addSet(): Promise<void> {
    const parsed = parseSetSpec(this.specText);
    if (parsed === null) {
      this.toast('格式：动作名 重量 次数 [@RPE]，例如 卧推 80 5 @8');
      return;
    }
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    // 别名是否能在库里解析到（提示但不阻塞；解析不到按自定义名记录）
    const ex = await repo.resolveExercise(parsed.name);
    this.pending = this.pending.concat([parsed]);
    this.specText = '';
    if (ex === null) {
      this.toast(`「${parsed.name}」不在动作库，按自定义动作记录`);
    }
  }

  private removeSet(idx: number): void {
    this.pending = this.pending.filter((_: ParsedSet, i: number): boolean => i !== idx);
  }

  private async saveWorkout(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    if (this.pending.length === 0) {
      this.toast('先添加训练组');
      return;
    }
    const name = this.nameText.trim();
    const w = await repo.addWorkout(todayIso(), this.pending,
      name.length > 0 ? name : null, null);
    let volume = 0;
    for (const s of w.sets) {
      volume += (s.weightKg ?? 0) * (s.reps ?? 0);
    }
    this.pending = [];
    this.toast(`已记录 ${w.sets.length} 组 · 总训练量 ${volume.toFixed(0)} kg`);
  }

  private workoutSummary(w: WorkoutEntry): string {
    const parts: string[] = [];
    for (const s of w.sets) {
      parts.push(`${s.exerciseName} ${s.weightKg?.toFixed(0) ?? 0}×${s.reps ?? 0}`);
    }
    return parts.join('、');
  }

  private workoutVolume(w: WorkoutEntry): number {
    let total = 0;
    for (const s of w.sets) {
      total += (s.weightKg ?? 0) * (s.reps ?? 0);
    }
    return total;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        CardContainer() {
          Column({ space: 12 }) {
            TextInput({ text: this.nameText, placeholder: '训练名称（可选，如：推日）' })
              .onChange((v: string): void => {
                this.nameText = v;
              })

            Row({ space: 8 }) {
              TextInput({ text: this.specText, placeholder: '组规格：卧推 80 5 @8' })
                .onChange((v: string): void => {
                  this.specText = v;
                })
                .onSubmit((): void => {
                  this.addSet();
                })
                .layoutWeight(1)
              Button('添加')
                .backgroundColor($r('app.color.primary'))
                .onClick((): void => {
                  this.addSet();
                })
            }
            .width('100%')

            ForEach(this.pending, (s: ParsedSet, idx: number) => {
              Row() {
                Text(`${s.name} ${fmtKg(s.weightKg)}kg × ${s.reps}${s.rpe === null ? '' : ` @${s.rpe}`}`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text('✕')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .padding(8)
                  .onClick((): void => {
                    this.removeSet(idx);
                  })
              }
              .width('100%')
            }, (s: ParsedSet, idx: number) => `${s.name}-${idx}`)

            Row() {
              Blank()
              Button('保存训练')
                .backgroundColor($r('app.color.primary'))
                .onClick((): void => {
                  this.saveWorkout();
                })
            }
            .width('100%')
          }
        }

        if (this.prs.length > 0) {
          CardContainer() {
            Column({ space: 6 }) {
              SectionTitle({ text: '力量 PR（估算 1RM）' })
              ForEach(this.prs, (pr: PrItem) => {
                Row() {
                  Text(pr.lift)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  Text(`${pr.est.toFixed(1)} kg`)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }, (pr: PrItem) => pr.lift)
            }
          }
        }

        SectionTitle({ text: '最近训练' })
        ForEach(this.workouts.slice(0, 10), (w: WorkoutEntry) => {
          CardContainer() {
            Row() {
              Column({ space: 4 }) {
                Text(`${w.workout.date} ${w.workout.name ?? '未命名训练'}`)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text(this.workoutSummary(w))
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${this.workoutVolume(w).toFixed(0)} kg`)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
        }, (w: WorkoutEntry) => w.workout.uuid)
        if (this.workouts.length === 0) {
          Text('还没有训练记录')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(16)
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
