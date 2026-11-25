/// 自定义食物条目对话框（格式：名称:克数:热量:蛋白:脂肪:碳水）。

@CustomDialog
export struct CustomFoodDialog {
  controller?: CustomDialogController;
  onSubmit: (text: string) => void = (): void => {
  };
  @State input: string = '';

  build() {
    Column({ space: 12 }) {
      Text('自定义条目')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      TextInput({ text: this.input, placeholder: '格式：名称:克数:热量:蛋白:脂肪:碳水' })
        .onChange((v: string): void => {
          this.input = v;
        })
      Row({ space: 12 }) {
        Button('取消')
          .backgroundColor($r('app.color.divider'))
          .fontColor($r('app.color.text_primary'))
          .onClick((): void => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Button('添加')
          .onClick((): void => {
            this.onSubmit(this.input);
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .padding(20)
    .backgroundColor($r('app.color.card'))
    .borderRadius(16)
    .width('92%')
  }
}
