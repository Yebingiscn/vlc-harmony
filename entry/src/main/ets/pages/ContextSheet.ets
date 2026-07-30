import { AppColors } from '../common/constants/AppConstants';
import { SheetItem } from '../common/models/MediaModels';

/** 上下文动作行:24vp 图标(grey900 fill)+ 18fp 标题,minHeight 48vp,整行可点。 */
@ComponentV2
struct ContextItem {
  @Param item: SheetItem = new SheetItem('');
  @Event onItemClick: () => void = () => {};

  build() {
    Row() {
      if (this.item.icon !== null) {
        Image(this.item.icon)
          .width(24).height(24)
          .fillColor('#FFFFFF')
          .margin({ top: 8, bottom: 8 })
      }
      Text(this.item.title)
        .fontSize(18)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 24 })
        .layoutWeight(1)
    }
    .constraintSize({ minHeight: 48 })
    .padding({ left: 24, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick())
  }
}

/**
 * ContextSheet —— 长按 item 的上下文动作菜单 BottomSheet。
 * 可选封面+标题区(showCover;48vp 封面 4vp 圆角)+ 纯标题区(互斥)+ 动作列表。
 * 每行图标+标题;点击回传 option id 后关闭。
 * TODO(契约): populateMenuItems(flags) 由 ContextOption 位掩码生成(Play/Append/Delete/Share…);
 *   CtxActionReceiver.onCtxAction(position, option) 由调用方实现;MediaLibraryItem schema 由调用方注入。
 */
@ComponentV2
export struct ContextSheet {
  @Param showCover: boolean = false;
  @Param coverTitle: string = '';
  @Param title: string = '';
  @Param cover: Resource = $r('app.media.ic_empty');
  @Param menuItems: SheetItem[] = [];
  @Event onClose: () => void = () => {};
  @Event onItemClick: (index: number) => void = () => {};

  onItemTap(index: number): void {
    this.onItemClick(index);
    this.onClose();
  }

  build() {
    Column() {
      // 区块 A:封面 + 标题
      if (this.showCover) {
        Row() {
          Image(this.cover)
            .width(48).height(48)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)
            .margin(8)
          Text(this.coverTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .padding({ left: 16, right: 16 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      } else {
        // 区块 B:纯标题
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 区块 C:动作列表
      List({ space: 0 }) {
        ForEach(this.menuItems, (item: SheetItem, index: number) => {
          ListItem() {
            ContextItem({
              item: item,
              onItemClick: () => this.onItemTap(index),
            })
          }
        }, (item: SheetItem) => item.title)
      }
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
