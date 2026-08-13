/**
 * SimpleListItem —— 多选列表行(PlaylistDialog 的 existing playlist 列表)。
 * 文本 + 末尾勾选状态。
 */
@ComponentV2
export struct SimpleListItem {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param selected: boolean = false;
  @Param showCheckbox: boolean = true;
  @Event onItemClick: () => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor('#9E9E9E')
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.showCheckbox) {
        Image(this.selected ? $r('app.media.ic_checkbox_true_normal') : $r('app.media.ic_checkbox_false'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick())
  }
}
