import { OverviewPage } from './OverviewPage';
import { TrendsPage } from './TrendsPage';

/// 身体页（纯展示）：概览（身体素质/力量最大重量）+ 趋势。记录统一由教练对话完成。
@ComponentV2
export struct BodyHub {
  @Local subTab: number = 0;
  private tabsController: TabsController = new TabsController();

  build() {
    Tabs({ barPosition: BarPosition.Start, index: this.subTab, controller: this.tabsController }) {
      TabContent() {
        OverviewPage()
      }.tabBar('概览')

      TabContent() {
        TrendsPage()
      }.tabBar('趋势')
    }
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .barHeight(44)
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      this.subTab = index;
    })
  }
}
