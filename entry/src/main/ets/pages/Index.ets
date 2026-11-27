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
  navItem(emoji: string, label: string, index: number) {
    Column({ space: 2 }) {
      Text(emoji)
        .fontSize(22)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_secondary'))
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
    .onClick((): void => {
      this.switchTo(index);
    })
  }

  /** 核心入口：教练（凸起渐变圆钮）。 */
  @Builder
  coachItem() {
    Column({ space: 3 }) {
      Column() {
        Text('💪')
          .fontSize(26)
      }
      .width(54)
      .height(54)
      .borderRadius(27)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [[$r('app.color.primary'), 0], [$r('app.color.accent'), 1]],
      })
      .shadow({ radius: 10, color: 'rgba(235,104,52,0.40)', offsetY: 3 })
      Text('教练')
        .fontSize(11)
        .fontColor(this.currentTab === 1 ? $r('app.color.accent') : $r('app.color.text_secondary'))
        .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Start)
    .layoutWeight(1)
    .height('100%')
    .offset({ y: -12 })
    .onClick((): void => {
      this.switchTo(1);
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
        this.navItem('🏃', '身体', 0)
        this.coachItem()
        this.navItem('👤', '我的', 2)
      }
      .width('100%')
      .height(72)
      .backgroundColor($r('app.color.card'))
      .border({
        width: { top: 1 },
        color: { top: $r('app.color.divider') },
      })
      .alignItems(VerticalAlign.Top)
    }
    .backgroundColor($r('app.color.bg'))
    .width('100%')
    .height('100%')
  }
}
