/// 我的页：档案/服务器/同步（Phase 6 实现）
@ComponentV2
export struct ProfilePage {
  build() {
    Column() {
      Text('我的（待实现）')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
