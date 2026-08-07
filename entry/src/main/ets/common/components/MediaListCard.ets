import { MediaWrapper, formatDuration } from '../models/MediaModels';

/**
 * MediaListCard —— 列表卡片(video_list_card.xml)。横向:80x50 缩略图 + 标题/time + 收藏/更多/选中。
 * padding Start8/Top4/Bottom4(无 End)。标题 16sp,time 12sp。
 */
@ComponentV2
export struct MediaListCard {
  @Param item: MediaWrapper = new MediaWrapper(0, '', '', 0);
  @Param isPresent: boolean = true;
  @Param isFavorite: boolean = false;
  @Param isNetwork: boolean = false;
  @Param isSD: boolean = false;
  @Param isOTG: boolean = false;
  @Param selected: boolean = false;
  @Param inSelection: boolean = false;
  @Param showProgress: boolean = false;
  @Param showSeenMarker: boolean = true;
  @Param showThumbnail: boolean = true;
  @Event onItemClick: () => void = () => {};
  @Event onItemLongClick: () => void = () => {};
  @Event onItemMoreClick: () => void = () => {};

  build() {
    Row() {
      // 可点击区域:缩略图 + 文本(点击播放)。更多按钮与之是兄弟节点,点击不会冒泡到播放
      Row() {
      // 左侧 80x50 缩略图卡
      Stack() {
        Image(this.showThumbnail && this.item.artworkUrl.length > 0 ? this.item.artworkUrl : $r('app.media.tv_channel_default'))
          .width(80)
          .height(50)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.tv_channel_default'))
          .draggable(false)
          .borderRadius(4)
          .backgroundColor($r('app.color.card_background'))
        Row() {
          if (this.isNetwork && this.isPresent) {
            Image($r('app.media.ic_emoji_network')).width(16).height(16).fillColor('#FFFFFF')
              .backgroundColor($r('app.color.rounded_corners_black_more_transparent')).borderRadius(3).padding(3)
          }
          if (this.isSD && this.isPresent) {
            Image($r('app.media.ic_emoji_sd')).width(16).height(16).fillColor('#FFFFFF')
              .backgroundColor($r('app.color.rounded_corners_black_more_transparent')).borderRadius(3).padding(3)
          }
          if (!this.isPresent) {
            Image($r('app.media.ic_emoji_absent')).width(16).height(16).fillColor('#FFFFFF')
              .backgroundColor($r('app.color.rounded_corners_black_more_transparent')).borderRadius(3).padding(3)
          }
        }
        .position({ x: 4, y: 4 })
        if (this.showSeenMarker && this.item.seen !== 0) {
          Image($r('app.media.ic_check'))
            .width(16)
            .height(16)
            .fillColor('#FFFFFF')
            .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
            .borderRadius(3)
            .padding(3)
            .position({ x: 60, y: 4 })
        }
        if (this.item.progress !== 0 && this.item.showItemProgress) {
          Progress({ value: this.item.progress,
            total: this.item.maxProgress > 0 ? this.item.maxProgress : 100, type: ProgressType.Linear })
            .height(3)
            .width(80)
            .color($r('app.color.orange'))
            .backgroundColor('#33FF8800')
            .position({ x: 0, y: 47 })
        }
      }
      .borderRadius(4)
      .clip(true)
      .margin({ right: 16 })

        // 中间:分辨率(置顶)+ 标题 + time
        Column() {
          if (this.item.resolution !== '') {
            Text(this.item.resolution)
              .fontSize(11)
              .fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .opacity(this.isPresent ? 1 : 0.4)
          }
          Text(this.item.title)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .opacity(this.isPresent ? 1 : 0.4)
          if (this.item.length > 0) {
            Text(formatDuration(this.item.length))
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
              .opacity((!this.isNetwork || this.isPresent) ? 1 : 0.4)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ right: 4 })
      }
      .layoutWeight(1)
      .onClick(() => this.onItemClick())

      // 播完对号标识(更多按钮前)
      if (this.showSeenMarker && this.item.seen !== 0) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.list_subtitle'))
          .margin({ right: 4 })
      }

      if (this.isFavorite) {
        Image($r('app.media.ic_emoji_favorite')).width(24).height(24).objectFit(ImageFit.Contain).margin({ right: 4 })
      }

      // 三点更多菜单
      Row() {
        Image($r('app.media.ic_more'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.list_subtitle'))
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ right: 4 })
      .onClick(() => this.onItemMoreClick())

      if (this.selected) {
        Image($r('app.media.ic_video_grid_check')).width(24).height(24).fillColor('#FF8800').margin({ right: 8 })
      }
    }
    .width('100%')
    .padding({ left: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.video_list_background'))
    .gesture(LongPressGesture().onAction(() => this.onItemLongClick()))
  }
}
