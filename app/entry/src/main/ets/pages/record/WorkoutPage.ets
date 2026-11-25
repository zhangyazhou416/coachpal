/// 训练记录页（Phase 4 实现）
@ComponentV2
export struct WorkoutPage {
  build() {
    Column() {
      Text('训练（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
