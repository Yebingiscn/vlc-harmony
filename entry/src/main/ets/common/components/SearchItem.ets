import { MediaLibraryItem } from '../models/MediaModels';

/**
 * SearchItem —— 搜索结果列表行(SearchActivity 各分组内 item)。
 * 缩略图 + 标题 + 描述。
 */
@ComponentV2
export struct SearchItem {
  @Param item: MediaLibraryItem = new MediaLibraryItem(0, '', 0);
  @Event onItemClick: () => void = () => {};

  build() {
    Row() {
      Image(this.item.artworkUrl && this.item.artworkUrl.length > 0 ? this.item.artworkUrl :
        $r('app.media.ic_no_thumbnail_song'))
        .width(48)
        .height(48)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .margin({ right: 12 })
      Column() {
        Text(this.item.title)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.item.description.length > 0) {
          Text(this.item.description)
            .fontSize(12)
            .fontColor('#9E9E9E')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
          // 列表项描述:时长/分辨率等
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick())
  }
}
