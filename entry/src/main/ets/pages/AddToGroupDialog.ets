import { AppColors } from '../common/constants/AppConstants';
import { MediaItemType, MediaLibraryItem } from '../common/models/MediaModels';

/** 列表项(simple_item.xml):48vp 封面 + 16fp 标题 + 副标题,整行可点。 */
@ComponentV2
struct GroupListItem {
  @Param item: MediaLibraryItem = new MediaLibraryItem(0, '', MediaItemType.MEDIA);
  @Param cover: Resource = $r('app.media.ic_empty');
  @Event onItemClick: () => void = () => {
  };

  build() {
    Row() {
      Image(this.cover)
        .width(48)
        .height(48)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .margin({ left: 8, top: 8, bottom: 8 })
      Column() {
        Text(this.item.title)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow(TextOverflow.Ellipsis)
        if (this.item.description.length > 0) {
          Text(this.item.description)
            .fontSize(12)
            .fontColor(AppColors.grey500)
            .maxLines(1)
            .textOverflow(TextOverflow.Ellipsis)
        }
      }
      .layoutWeight(1)
      .margin({ left: 8, right: 8 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({
      left: 8,
      right: 8,
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick())
  }
}

/**
 * AddToGroupDialog —— 「Add to video group」BottomSheet。
 * 18fp Medium 标题(56vp minHeight)+ 可选 32vp LoadingProgress + 分组列表(48vp 封面 + 标题/复数描述)
 * + 空态 no_group_found。仅显示 mediaCount>1 的分组;新建组 DummyItem 仅 newTrack.size>1 && !forbidNewGroup 时置顶。
 * TODO(契约): VideosViewModel(VideoGroupingType.NAME).provider.pagedList → groupList;addToGroup(group) 把 newTrack 加入组;
 *   新建组 DummyItem onClick → setFragmentResult(CONFIRM_ADD_TO_GROUP_RESULT, KEY_TRACKS=newTrack) 由调用方 emitter 实现。
 */
@ComponentV2
export struct AddToGroupDialog {
  @Param newTrackCount: number = 0;
  @Param forbidNewGroup: boolean = true;
  @Local isLoading: boolean = false;
  @Local groupList: MediaLibraryItem[] = [];

  @Event onClose: () => void = () => {
  };

  @Event onSelectGroup: (group: MediaLibraryItem) => void = () => {
  };

  @Event onCreateNewGroup: () => void = () => {
  };

  aboutToAppear(): void {
    // TODO(契约): 订阅 VideosViewModel(VideoGroupingType.NAME).provider.pagedList:
    //   过滤 mediaCount>1;设 description=getQuantityString(media_quantity, n);
    //   if (newTrackCount>1 && !forbidNewGroup) 列表头插入 DummyItem(ic_add_to_group, "New group", "Create a new group")。
    //   进入默认 empty 态(showPinIfNeeded() PIN 校验,需 PIN 则 dismiss)。
  }

  onItemClick(item: MediaLibraryItem): void {
    if (item.id === -1) {
      // DummyItem 新建组
      this.onCreateNewGroup();
    } else {
      this.onSelectGroup(item);
    }
    this.onClose();
  }

  build() {
    Column() {
      // 标题行 + 转圈
      Row() {
        Text($r('app.string.add_to_group'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .height(56)
          .padding({ left: 16, right: 16 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow(TextOverflow.Ellipsis)
          .textAlign(TextAlign.Start)
        if (this.isLoading) {
          LoadingProgress().width(32).height(32).margin({ left: 8, right: 16 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 列表容器
      Stack({ alignContent: Alignment.TopStart }) {
        List({ space: 0 }) {
          ForEach(this.groupList, (item: MediaLibraryItem) => {
            ListItem() {
              GroupListItem({
                item: item,
                cover: item.id === -1 ? $r('app.media.ic_add_to_group') : $r('app.media.ic_folder'),
                onItemClick: () => this.onItemClick(item),
              })
            }
          }, (item: MediaLibraryItem) => `${item.id}`)
        }
        .width('100%')
        .scrollBar(BarState.Off)
        .layoutWeight(1)

        if (this.groupList.length === 0) {
          Text($r('app.string.no_group_found'))
            .width('100%')
            .fontSize(14)
            .fontColor(AppColors.grey500)
            .textAlign(TextAlign.Center)
            .margin({ bottom: 16 })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
