import { ChatPage } from './ChatPage';
import { RecordHub } from './record/RecordHub';
import { TrendsPage } from './TrendsPage';
import { ProfilePage } from './ProfilePage';

@Entry
@ComponentV2
struct Index {
  @Local currentTab: number = 0;

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
          ChatPage()
        }.tabBar(this.tabBarItem('教练', 0))

        TabContent() {
          RecordHub()
        }.tabBar(this.tabBarItem('记录', 1))

        TabContent() {
          TrendsPage()
        }.tabBar(this.tabBarItem('趋势', 2))

        TabContent() {
          ProfilePage()
        }.tabBar(this.tabBarItem('我的', 3))
      }
      .scrollable(false)
      .barHeight(52)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .layoutWeight(1)
    }
    .backgroundColor($r('app.color.bg'))
    .width('100%')
    .height('100%')
  }
}
