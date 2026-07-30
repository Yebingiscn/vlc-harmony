/**
 * VlcToolbar —— MaterialToolbar(actionBarSize≈56vp,elevation=0)。
 * 返回箭头(非根页显示)+ VLC 标题(20fp Bold colorPrimary)+ 可选隐身图标。
 */
@ComponentV2
export struct VlcToolbar {
  @Param title: Resource = $r('app.string.app_name');
  @Param showBack: boolean = false;
  @Param showIncognito: boolean = false;
  @Event onBack: () => void = () => {};
  @Event onSearch: () => void = () => {};
  @Param showSearch: boolean = false;

  build() {
    Row() {
      if (this.showBack) {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor('#FFFFFF')
          .margin({ left: 4 })
          .onClick(() => this.onBack())
      }
      if (!this.showBack) {
        // 主屏工具栏:VLC 交通锥 logo(标题左侧),保留源图原生橙色,不染色。
        Image($r('app.media.ic_default_cone'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .margin({ left: 12 })
      }
      Text(this.title)
        .fontSize(20)
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(1)
      if (this.showIncognito) {
        Image($r('app.media.ic_incognito'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .margin({ right: 8 })
      }
      if (this.showSearch) {
        Image($r('app.media.ic_search'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor('#FFFFFF')
          .margin({ right: 8 })
          .onClick(() => this.onSearch())
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .backgroundColor($r('app.color.background_actionbar'))
    .alignItems(VerticalAlign.Center)
  }
}
