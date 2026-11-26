@ComponentV2
export struct FloatingAddButton {
  @Param label: Resource = $r('app.string.add');
  @Event onPress: () => void = () => {};

  build() {
    Stack() {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_add'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.colorOnPrimary'))
      }
      .width('100%')
      .height('100%')
      .padding(0)
      .backgroundColor($r('app.color.orange500transparent'))
      .accessibilityText(this.label)
      .onClick(() => this.onPress())
    }
    .width(48)
    .height(48)
    .borderRadius(24)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .clip(true)
  }
}
