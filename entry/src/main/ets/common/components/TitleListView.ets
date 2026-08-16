import { SheetItem } from '../models/MediaModels';

/**
 * TitleListView —— 分组(标题 18sp Medium + 横向卡片列表 + 加载/空态)。
 * 用于 MainBrowserFragment(收藏/本地存储/局域网)与 MoreFragment(Streams/History)。
 * 卡片:item=NoShadow 4vp 圆角 1vp 描边。
 */
@ComponentV2
export struct TitleListView {
  @Param title: Resource = $r('app.string.favorites');
  @Param items: SheetItem[] = [];
  @Param loading: boolean = false;
  @Param emptyText: Resource = $r('app.string.no_favorite');
  @Event onItemClick: (item: SheetItem, index: number) => void = () => {
  };

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Medium)
        .margin({ left: 12, top: 12, bottom: 8 })

      if (this.loading) {
        LoadingProgress().width(28).height(28).color('#FF8800').margin(12)
      } else if (this.items.length === 0) {
        Text(this.emptyText)
          .fontSize(13)
          .fontColor($r('app.color.list_subtitle'))
          .margin({ left: 12, bottom: 8 })
      } else {
        List({ space: 8 }) {
          Repeat(this.items).each((itemRepeatItem: RepeatItem<SheetItem>) => {
            ListItem() {
              Row() {
                if (itemRepeatItem.item.icon) {
                  Image(itemRepeatItem.item.icon)
                    .width(28)
                    .height(28)
                    .objectFit(ImageFit.Contain)
                    .fillColor('#FF8800')
                    .margin({ right: 8 })
                }
                Column() {
                  Text(itemRepeatItem.item.title)
                    .fontSize(14)
                    .fontColor($r('app.color.list_title'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (itemRepeatItem.item.subtitle.length > 0) {
                    Text(itemRepeatItem.item.subtitle)
                      .fontSize(12)
                      .fontColor($r('app.color.list_subtitle'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width(200)
              .padding(12)
              .borderRadius(4)
              .borderWidth(1)
              .borderColor($r('app.color.divider'))
              .backgroundColor($r('app.color.video_card_background'))
              .alignItems(VerticalAlign.Center)
              .onClick(() => this.onItemClick(itemRepeatItem.item, itemRepeatItem.index))
            }
          }).key((item: SheetItem) => item.title).virtualScroll()
        }
        .width('100%')
        .height(88)
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
