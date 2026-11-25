/// 饮食记录页（Phase 4 实现）
@ComponentV2
export struct MealPage {
  build() {
    Column() {
      Text('饮食（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
