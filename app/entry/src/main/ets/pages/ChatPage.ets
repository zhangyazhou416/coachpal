/// 教练页：AI 对话（Phase 7 实现）
@ComponentV2
export struct ChatPage {
  build() {
    Column() {
      Text('教练（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
