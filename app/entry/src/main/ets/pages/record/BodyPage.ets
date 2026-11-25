/// 身体记录页（Phase 4 实现）
@ComponentV2
export struct BodyPage {
  build() {
    Column() {
      Text('身体（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
