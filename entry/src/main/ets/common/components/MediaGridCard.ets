import { formatDuration, MediaWrapper } from '../models/MediaModels';

/**
 * MediaGridCard —— 网格卡片(video_grid_card.xml)。16:10 缩略图 + 角标(分辨率/已看/更多/选中)+
 * 左下 emoji 行 + 底部进度条 + 标题(16sp)/time(12sp)。padding Start8/Top8/End8(无 Bottom)。
 * 角标定位用「满尺寸透明覆盖层 Row + justifyContent/alignItems」(ArkUI 正确模式,非 .align)。
 */
@ComponentV2
export struct MediaGridCard {
  @Param item: MediaWrapper = new MediaWrapper(0, '', '', 0);
  @Param isPresent: boolean = true;
  @Param isFavorite: boolean = false;
  @Param isNetwork: boolean = false;
  @Param isSD: boolean = false;
  @Param isOTG: boolean = false;
  @Param selected: boolean = false;
  @Param inSelection: boolean = false;
  @Param showProgress: boolean = false;
  /** 设置-界面-视频中的两个展示开关。 */
  @Param showSeenMarker: boolean = true;
  @Param showThumbnail: boolean = true;

  @Event onItemClick: () => void = () => {
  };

  @Event onItemLongClick: () => void = () => {
  };

  @Event onItemMoreClick: () => void = () => {
  };

  @Builder
  emojiBadge(icon: Resource) {
    Image(icon)
      .width(16)
      .height(16)
      .objectFit(ImageFit.Contain)
      .fillColor('#FFFFFF')
      .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
      .borderRadius(3)
      .padding(3)
      .margin({ right: 4 })
  }

  @Builder
  topOverlay() {
    Row() {
      // 左上:分辨率 + 已看勾
      Row() {
        if (this.item.resolution !== '') {
          Text(this.item.resolution)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
            .borderRadius(3)
            .padding({
              left: 4,
              top: 2,
              right: 4,
              bottom: 2
            })
            .margin({ right: 4 })
        }
        if (this.showSeenMarker && this.item.seen !== 0) {
          Image($r('app.media.ic_check'))
            .width(16)
            .height(16)
            .fillColor('#FFFFFF')
            .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
            .borderRadius(3)
            .padding(3)
        }
      }

      Blank()
      // 选中勾仅作展示；更多按钮在 build 中作为播放区域的同级节点渲染。
      if (this.selected) {
        Image($r('app.media.ic_video_grid_check'))
          .width(16)
          .height(16)
          .fillColor('#FF8800')
      }
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.None)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Top)
    .padding({ left: 4, right: 4, top: 4 })
  }

  @Builder
  bottomOverlay() {
    Column() {
      Row() {
        if (this.isFavorite) {
          this.emojiBadge($r('app.media.ic_emoji_favorite_white'))
        }
        if (this.isNetwork && this.isPresent) {
          this.emojiBadge($r('app.media.ic_emoji_network'))
        }
        if (this.isOTG && this.isPresent) {
          this.emojiBadge($r('app.media.ic_emoji_otg'))
        }
        if (this.isSD && this.isPresent) {
          this.emojiBadge($r('app.media.ic_emoji_sd'))
        }
        if (!this.isPresent) {
          this.emojiBadge($r('app.media.ic_emoji_absent'))
        }
      }
      .width('100%')
      .height(16)
      .padding({ left: 8, bottom: 4 })

      if (this.item.progress !== 0 && this.item.showItemProgress) {
        Progress({
          value: this.item.progress, total: this.item.maxProgress > 0 ? this.item.maxProgress : 100,
          type: ProgressType.Linear
        })
          .height(4)
          .width('100%')
          .color($r('app.color.orange'))
          .backgroundColor('#33FF8800')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Start)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          // 缩略图:artworkUrl 为媒体库 uri 时 Image 可直接渲染;为空/加载失败回落占位图。
          Image(this.showThumbnail && this.item.artworkUrl.length > 0 ? this.item.artworkUrl :
            $r('app.media.tv_channel_default'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.tv_channel_default'))
            .draggable(false)
            .backgroundColor($r('app.color.card_background'))
          if (!this.selected && !this.isPresent) {
            Column()
              .width('100%')
              .height('100%')
              .hitTestBehavior(HitTestMode.None)
              .backgroundColor($r('app.color.disabled_overlay'))
          }
          this.topOverlay()
          this.bottomOverlay()
          if (this.showProgress) {
            LoadingProgress().width(32).height(32).hitTestBehavior(HitTestMode.None).color('#FFFFFF')
          }
        }
        .aspectRatio(1.6) // 16:10
        .borderRadius(4)
        .clip(true)
        .width('100%')

        Text(this.item.title)
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
          .opacity(this.isPresent ? 1 : 0.4)

        // 时长行恒定渲染(无时长时留空占位)-- 否则同一行两张卡高度不一致,网格参差不齐。
        Text(this.item.length > 0 ? formatDuration(this.item.length) : ' ')
          .fontSize(12)
          .fontColor($r('app.color.list_subtitle'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .width('100%')
          .opacity(this.isPresent ? 1 : 0.4)
      }
      .width('100%')
      .padding(8)
      .backgroundColor($r('app.color.video_card_background'))
      .borderRadius(8)
      .clip(true)
      .onClick(() => this.onItemClick())
      .gesture(LongPressGesture().onAction(() => this.onItemLongClick()))

      if (!this.selected) {
        // 独立于整卡播放区域，点击更多不会触发父级播放事件。
        Row() {
          Image($r('app.media.ic_more'))
            .width(16)
            .height(16)
            .fillColor('#FFFFFF')
            .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
            .borderRadius(4)
        }
        .width(32)
        .height(32)
        .margin({ top: 4, right: 4 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onItemMoreClick())
      }
    }
    .width('100%')
  }
}
