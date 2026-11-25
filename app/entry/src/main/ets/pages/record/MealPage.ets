import { resolveFood, FoodHit } from '../../core/domain/food_search';
import { FoodPortion, CustomItemInput, MealEntry } from '../../core/repo/Model';
import { AppServices } from '../../core/services';
import { todayIso } from '../../core/util/Time';
import { CardContainer, SectionTitle, TagChip, MEAL_TYPES, MEAL_TYPE_LABELS,
  mealLabel, fmtKcal, fmtMacro } from '../../components/Common';
import { CustomFoodDialog } from '../../components/CustomFoodDialog';

function mealOptions(): SelectOption[] {
  const out: SelectOption[] = [];
  for (const l of MEAL_TYPE_LABELS) {
    const o: SelectOption = { value: l };
    out.push(o);
  }
  return out;
}

function kcalSum(entry: MealEntry): number {
  let total = 0;
  for (const it of entry.items) {
    total += it.kcal;
  }
  return total;
}

function itemsSummary(entry: MealEntry): string {
  const parts: string[] = [];
  for (const it of entry.items) {
    parts.push(`${it.foodName} ${it.grams.toFixed(0)}g`);
  }
  return parts.join('、');
}

/// 饮食记录：食物搜索（歧义弹窗）+ 自定义条目 + 今日餐次列表。
@ComponentV2
export struct MealPage {
  @Local meals: MealEntry[] = [];
  @Local results: FoodHit[] = [];
  @Local hasSearched: boolean = false;
  @Local pendingPortions: FoodPortion[] = [];
  @Local pendingCustom: CustomItemInput[] = [];
  @Local mealTypeIndex: number = 1;
  @Local gramsText: string = '100';
  @Local searchText: string = '';
  @Local showCandidates: boolean = false;
  @Local candidates: FoodHit[] = [];
  private typeOptions: SelectOption[] = mealOptions();
  private subId: number = -1;

  dialogController: CustomDialogController = new CustomDialogController({
    builder: CustomFoodDialog({
      onSubmit: (text: string): void => {
        this.addCustomFromText(text);
      },
    }),
    autoCancel: true,
    customStyle: true,
  });

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
    this.subId = AppServices.getInstance().bus.subscribe(['meals', 'meal_items'],
      (): void => {
        this.reloadMeals();
      });
    await this.reloadMeals();
  }

  private async reloadMeals(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    this.meals = await repo.listMeals(todayIso());
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private async doSearch(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const hits = await repo.searchFoods(this.searchText);
    this.results = hits;
    this.hasSearched = true;
    if (hits.length === 0) {
      this.toast(`食物库里找不到「${this.searchText}」，可换通用名或用自定义条目`);
    }
  }

  private async pickFood(hit: FoodHit): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    const grams = Number(this.gramsText) || 100;
    const resolved = resolveFood([hit]);
    if (resolved !== null) {
      this.addPortion(resolved, grams);
      return;
    }
    // 歧义：弹候选框
    const matches = await repo.searchFoods(hit.name);
    this.candidates = matches.slice(0, 5);
    this.showCandidates = true;
  }

  private addPortion(food: FoodHit, grams: number): void {
    const p: FoodPortion = { food: food, grams: grams };
    this.pendingPortions = this.pendingPortions.concat([p]);
  }

  private removePortion(idx: number): void {
    this.pendingPortions = this.pendingPortions.filter(
      (_: FoodPortion, i: number): boolean => i !== idx);
  }

  private removeCustom(idx: number): void {
    this.pendingCustom = this.pendingCustom.filter(
      (_: CustomItemInput, i: number): boolean => i !== idx);
  }

  private addCustomFromText(text: string): void {
    const parts = text.split(':');
    if (parts.length < 6) {
      this.toast('格式：名称:克数:热量:蛋白:脂肪:碳水');
      return;
    }
    const nums: number[] = [];
    for (let i = 1; i < 6; i++) {
      const n = Number(parts[i]);
      nums.push(Number.isNaN(n) ? 0 : n);
    }
    const c: CustomItemInput = {
      name: parts[0],
      grams: nums[0],
      kcal: nums[1],
      protein: nums[2],
      fat: nums[3],
      carbs: nums[4],
      fiber: 0,
    };
    this.pendingCustom = this.pendingCustom.concat([c]);
  }

  private async saveMeal(): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    if (this.pendingPortions.length === 0 && this.pendingCustom.length === 0) {
      this.toast('先添加食物');
      return;
    }
    await repo.addMeal(MEAL_TYPES[this.mealTypeIndex], todayIso(),
      this.pendingPortions, this.pendingCustom, null);
    this.pendingPortions = [];
    this.pendingCustom = [];
    this.toast('已记录');
  }

  @Builder
  candidateSheet() {
    Column() {
      Text('匹配到多个食物，请选择：')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .padding(12)
      ForEach(this.candidates, (c: FoodHit) => {
        Column({ space: 2 }) {
          Text(c.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text(`${c.foodCode ?? '-'} · ${fmtKcal(c.kcal)} kcal/100g`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick((): void => {
          const grams = Number(this.gramsText) || 100;
          this.addPortion(c, grams);
          this.showCandidates = false;
        })
      }, (c: FoodHit) => c.foodCode ?? c.name)
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        CardContainer() {
          Column({ space: 12 }) {
            Row() {
              Text('餐次')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 12 })
              Select(this.typeOptions)
                .selected(this.mealTypeIndex)
                .value(MEAL_TYPE_LABELS[this.mealTypeIndex])
                .fontColor($r('app.color.text_primary'))
                .onSelect((idx: number): void => {
                  this.mealTypeIndex = idx;
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              TextInput({ text: this.searchText, placeholder: '搜索食物（如：鸡胸肉、米饭）' })
                .onChange((v: string): void => {
                  this.searchText = v;
                })
                .onSubmit((): void => {
                  this.doSearch();
                })
                .layoutWeight(1)
              Button('搜索')
                .backgroundColor($r('app.color.primary'))
                .onClick((): void => {
                  this.doSearch();
                })
            }
            .width('100%')

            if (this.hasSearched) {
              ForEach(this.results.slice(0, 5), (hit: FoodHit) => {
                Row() {
                  Column({ space: 2 }) {
                    Text(hit.name)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Text(`${fmtKcal(hit.kcal)} kcal/100g · P${fmtMacro(hit.protein)} F${fmtMacro(hit.fat)} C${fmtMacro(hit.carbs)}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  TextInput({ text: this.gramsText, placeholder: '克' })
                    .width(70)
                    .type(InputType.NUMBER_DECIMAL)
                    .onChange((v: string): void => {
                      this.gramsText = v;
                    })
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
                .onClick((): void => {
                  this.pickFood(hit);
                })
              }, (hit: FoodHit) => hit.foodCode ?? hit.name)
            }

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.pendingPortions, (p: FoodPortion, idx: number) => {
                TagChip({
                  label: `${p.food.name} ${p.grams}g`,
                  onRemove: (): void => {
                    this.removePortion(idx);
                  },
                })
              }, (p: FoodPortion) => `${p.food.name}-${p.grams}`)
              ForEach(this.pendingCustom, (c: CustomItemInput, idx: number) => {
                TagChip({
                  label: `${c.name} ${c.grams}g`,
                  onRemove: (): void => {
                    this.removeCustom(idx);
                  },
                })
              }, (c: CustomItemInput) => `${c.name}-${c.grams}`)
            }
            .width('100%')

            Row() {
              Button('自定义')
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.primary'))
                .onClick((): void => {
                  this.dialogController.open();
                })
              Blank()
              Button('记录这一餐')
                .backgroundColor($r('app.color.primary'))
                .onClick((): void => {
                  this.saveMeal();
                })
            }
            .width('100%')
          }
        }

        SectionTitle({ text: '今天已记录' })
        ForEach(this.meals, (entry: MealEntry) => {
          CardContainer() {
            Row() {
              Column({ space: 4 }) {
                Text(`${mealLabel(entry.meal.mealType)} · ${kcalSum(entry).toFixed(0)} kcal`)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text(itemsSummary(entry))
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('删除')
                .fontSize(13)
                .fontColor($r('app.color.status_bad'))
                .padding(8)
                .onClick((): void => {
                  this.deleteMeal(entry);
                })
            }
          }
        }, (entry: MealEntry) => entry.meal.uuid)
        if (this.meals.length === 0) {
          Text('今天还没有饮食记录')
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
    .bindSheet(this.showCandidates, this.candidateSheet(), {
      height: SheetSize.FIT_CONTENT,
      onDisappear: (): void => {
        this.showCandidates = false;
      },
    })
  }

  private async deleteMeal(entry: MealEntry): Promise<void> {
    const repo = AppServices.getInstance().repo;
    if (repo === null) {
      return;
    }
    await repo.deleteMeal(entry.meal.uuid);
  }
}
