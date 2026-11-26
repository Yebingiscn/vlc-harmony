@ComponentV2
export struct PlayerControlButton {
  @Param @Require icon: Resource = $r('sys.symbol.list_badge_play');
  @Param @Require label: Resource = $r('app.string.player_queue');
  @Param description: Resource = $r('app.string.player_queue_hint');
  @Param iconColor: ResourceColor = $r('app.color.list_title');
  @Param isEnabled: boolean = true;
  @Event onPress: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(this.icon)
        .fontSize(21)
        .fontColor([this.iconColor])
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label)
    .accessibilityDescription(this.description)
    .enabled(this.isEnabled)
    .onClick(() => this.onPress())
  }
}
