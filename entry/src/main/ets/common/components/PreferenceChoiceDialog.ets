/**
 * 设置页通用单选弹窗。由 UIContext.openCustomDialog 承载，避免把安卓式居中弹窗
 * 错当成底部 Sheet；点击任一选项即回调并由宿主关闭。
 */
@ComponentV2
export struct PreferenceChoiceDialog {
  @Param title: ResourceStr = '';
  @Param labels: ResourceStr[] = [];
  @Param values: string[] = [];
  @Param selectedValue: string = '';
  @Event onSelect: (value: string) => void = () => {
  };
  @Event onCancel: () => void = () => {
  };

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ bottom: 12 })

      List() {
        Repeat(this.labels).each((labelRepeatItem: RepeatItem<ResourceStr>) => {
          ListItem() {
            Row() {
              Text(labelRepeatItem.item)
                .fontSize(16)
                .layoutWeight(1)
              if (this.valueAt(labelRepeatItem.index) === this.selectedValue) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(22)
                  .fontColor([$r('sys.color.icon_primary')])
                // Image($r('app.media.ic_check'))
                //   .width(22)
                //   .height(22)
              }
            }
            .width('100%')
            .padding({
              left: 4,
              right: 4,
              top: 16,
              bottom: 16
            })
            .onClick(() => this.onSelect(this.valueAt(labelRepeatItem.index)))
          }
        }).key((label: ResourceStr, index: number) => `${index}`)
      }
      .width('100%')
      .height(this.labels.length > 5 ? 360 : undefined)
      .scrollBar(BarState.Off)

      Button($r('app.string.cancel'))
        .type(ButtonType.Normal)
        .fontSize(15)
        .fontColor($r('app.color.orange500'))
        .backgroundColor(Color.Transparent)
        .alignSelf(ItemAlign.End)
        .margin({ top: 8 })
        .onClick(() => this.onCancel())
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
  }

  private valueAt(index: number): string {
    return index >= 0 && index < this.values.length ? this.values[index] : '';
  }
}
