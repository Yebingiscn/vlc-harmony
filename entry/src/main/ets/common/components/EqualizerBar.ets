/**
 * EqualizerBar —— 均衡器频段竖直滑块(EqualizerDialog 内,150dp 竖直 Slider)。
 * 底部频段值标签(10sp)。滑动改增益 dB。
 */
@ComponentV2
export struct EqualizerBar {
  @Param label: string = '';
  @Param value: number = 0; // dB,默认 0
  @Param min: number = -20;
  @Param max: number = 20;
  @Event onChange: (v: number) => void = () => {
  };

  build() {
    Column() {
      Slider({
        value: this.value,
        min: this.min,
        max: this.max,
        step: 1,
        style: SliderStyle.OutSet,
        direction: Axis.Vertical,
      })
        .width(40)
        .height(150)
        .blockColor('#FF8800')
        .selectedColor('#FF8800')
        .trackColor('#424242')
        .onChange((v: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Moving || mode === SliderChangeMode.Click ||
            mode === SliderChangeMode.End) {
            this.onChange(Math.round(v));
          }
        })
      Text(this.label)
        .fontSize(10)
        .fontColor('#9E9E9E')
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Center)
    .margin({ left: 6, right: 6 })
  }
}
