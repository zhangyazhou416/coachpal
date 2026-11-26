import { BodyHub } from './BodyHub';
import { ChatPage } from './ChatPage';
import { ProfilePage } from './ProfilePage';

@Entry
@ComponentV2
struct Index {
  @Local currentTab: number = 1;
  @Local hubVersion: number = 0;

  onPageShow(): void {
    this.hubVersion++;
  }

  @Builder
  tabBarItem(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.currentTab === index ? $r('app.color.primary') : $r('app.color.text_secondary'))
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          BodyHub()
        }.tabBar(this.tabBarItem('身体', 0))

        TabContent() {
          ChatPage()
        }.tabBar(this.tabBarItem('教练', 1))

        TabContent() {
          ProfilePage({ hubVersion: this.hubVersion })
        }.tabBar(this.tabBarItem('我的', 2))
      }
      .scrollable(false)
      .barHeight(52)
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 2) {
          this.hubVersion++;
        }
      })
      .layoutWeight(1)
    }
    .backgroundColor($r('app.color.bg'))
    .width('100%')
    .height('100%')
  }
}
