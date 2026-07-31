import { EmptyLoadingState } from '../models/MediaModels';

/**
 * EmptyStateView —— EmptyLoadingStateView(7 态:LOADING/EMPTY/EMPTY_SEARCH/EMPTY_FAVORITES/
 * MISSING_PERMISSION/MISSING_VIDEO_PERMISSION/NONE)。
 * 居中 Column(Image+Text+可选 Button)。compactMode(EMPTY 系列)收紧间距。
 */
@ComponentV2
export struct EmptyStateView {
  @Param state: EmptyLoadingState = EmptyLoadingState.LOADING;
  @Param filterQuery: string = '';
  @Event onGrantPermission: () => void = () => {};
  @Event onPickFile: () => void = () => {};
  @Event onOpenStorage: () => void = () => {};

  build() {
    Column() {
      if (this.state === EmptyLoadingState.LOADING) {
        LoadingProgress().width(56).height(56).color('#FF8800')
        Text($r('app.string.loading'))
          .fontSize(14)
          .fontColor($r('app.color.list_subtitle'))
          .margin({ top: 12 })
      } else if (this.state === EmptyLoadingState.EMPTY) {
        Image($r('app.media.ic_empty')).width(96).height(96).objectFit(ImageFit.Contain).fillColor($r('app.color.grey800'))
        Text($r('app.string.nomedia'))
          .fontSize(14)
          .fontColor($r('app.color.list_subtitle'))
          .textAlign(TextAlign.Center)
          .margin({ top: 12, left: 24, right: 24 })
        Button($r('app.string.add'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor('#FF8800')
          .fontColor($r('app.color.colorOnPrimary'))
          .fontSize(14)
          .margin({ top: 16 })
          .onClick(() => this.onPickFile())
      } else if (this.state === EmptyLoadingState.EMPTY_SEARCH) {
        Image($r('app.media.ic_empty')).width(96).height(96).objectFit(ImageFit.Contain).fillColor($r('app.color.grey800'))
        Text(this.filterQuery.length > 0
          ? `No item found for search ${this.filterQuery}`
          : $r('app.string.empty_search').toString())
          .fontSize(14)
          .fontColor($r('app.color.list_subtitle'))
          .textAlign(TextAlign.Center)
          .margin({ top: 12, left: 24, right: 24 })
      } else if (this.state === EmptyLoadingState.EMPTY_FAVORITES) {
        Image($r('app.media.ic_fav_empty')).width(96).height(96).objectFit(ImageFit.Contain).fillColor($r('app.color.grey800'))
        Text($r('app.string.nofav'))
          .fontSize(14)
          .fontColor($r('app.color.list_subtitle'))
          .margin({ top: 12 })
      } else if (this.state === EmptyLoadingState.MISSING_PERMISSION ||
      this.state === EmptyLoadingState.MISSING_VIDEO_PERMISSION) {
        Image($r('app.media.ic_empty_warning')).width(96).height(96).objectFit(ImageFit.Contain).fillColor('#FF8800')
        Text($r('app.string.permission_media'))
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .textAlign(TextAlign.Center)
          .margin({ top: 16, left: 24, right: 24 })
        Button($r('app.string.permission_ask_again'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor('#FF8800')
          .fontColor($r('app.color.colorOnPrimary'))
          .fontSize(14)
          .margin({ top: 12 })
          .onClick(() => this.onGrantPermission())
        Button($r('app.string.add'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor($r('app.color.grey875'))
          .fontColor($r('app.color.colorOnPrimary'))
          .fontSize(14)
          .margin({ top: 8 })
          .onClick(() => this.onPickFile())
      } else {
        // NONE
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
