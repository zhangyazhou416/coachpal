import { MealPage } from './MealPage';
import { WorkoutPage } from './WorkoutPage';
import { BodyPage } from './BodyPage';

/// 记录页：顶部三子 Tab（饮食/训练/身体）
@ComponentV2
export struct RecordHub {
  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          MealPage()
        }.tabBar('饮食')

        TabContent() {
          WorkoutPage()
        }.tabBar('训练')

        TabContent() {
          BodyPage()
        }.tabBar('身体')
      }
      .barMode(BarMode.Fixed)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
