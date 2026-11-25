/// 趋势页：折线图与周复盘（Phase 5 实现）
@ComponentV2
export struct TrendsPage {
  build() {
    Column() {
      Text('趋势（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
