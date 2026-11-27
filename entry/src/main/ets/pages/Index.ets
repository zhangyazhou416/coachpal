import { BodyHub } from './BodyHub';
import { ChatPage } from './ChatPage';
import { ProfilePage } from './ProfilePage';

@Entry
@ComponentV2
struct Index {
  @Local currentTab: number = 1;
  @Local hubVersion: number = 0;
  private tabsController: TabsController = new TabsController();

  onPageShow(): void {
    this.hubVersion++;
  }

  private switchTo(index: number): void {
    this.currentTab = index;
    this.tabsController.changeIndex(index);
    if (index === 2) {
      this.hubVersion++;
    }
  }

  @Builder
  navItem(icon: Resource, label: string, index: number) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_secondary')])
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
    .onClick((): void => {
      this.switchTo(index);
    })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.tabsController }) {
        TabContent() {
          BodyHub()
        }.tabBar(' ')

        TabContent() {
          ChatPage()
        }.tabBar(' ')

        TabContent() {
          ProfilePage({ hubVersion: this.hubVersion })
        }.tabBar(' ')
      }
      .barHeight(0)
      .scrollable(false)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 2) {
          this.hubVersion++;
        }
      })
      .layoutWeight(1)

      Row() {
        this.navItem($r('sys.symbol.figure_walk'), '身体', 0)
        this.navItem($r('sys.symbol.intelligent_coach'), '教练', 1)
        this.navItem($r('sys.symbol.person_crop_circle_fill'), '我的', 2)
      }
      .width('100%')
      .height(52)
      .backgroundColor(Color.Transparent)
      .alignItems(VerticalAlign.Center)
    }
    .backgroundColor($r('app.color.bg'))
    .width('100%')
    .height('100%')
  }
}
