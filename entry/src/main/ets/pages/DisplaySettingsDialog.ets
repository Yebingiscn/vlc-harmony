import { AppColors } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';

class SortMeta {
  key: number;
  title: string;
  ascText: string;
  descText: string;
  icon: Resource;

  constructor(key: number, title: string, ascText: string, descText: string, icon: Resource) {
    this.key = key;
    this.title = title;
    this.ascText = ascText;
    this.descText = descText;
    this.icon = icon;
  }
}

@ComponentV2
struct SortItem {
  @Param title: string = '';
  @Param ascText: string = '';
  @Param descText: string = '';
  @Param icon: Resource = $r('app.media.ic_sort');
  @Param isCurrentSort: boolean = false;
  @Param currentSortDesc: boolean = false;
  @Event onSortAsc: () => void = () => {
  };
  @Event onSortDesc: () => void = () => {
  };

  build() {
    Row() {
      Image(this.icon)
        .width(24).height(24)
        .fillColor(AppColors.grey600)
      Text(this.title)
        .fontSize(16)
        .fontColor(AppColors.grey900)
        .margin({ left: 24 })
        .width(100)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column() {
        Row() {
          Text(this.ascText)
            .fontSize(14)
            .fontColor(this.isCurrentSort && !this.currentSortDesc ? AppColors.orange500 : AppColors.grey900)
          if (this.isCurrentSort && !this.currentSortDesc) {
            Image($r('app.media.ic_check_large'))
              .width(20).height(20)
              .fillColor(AppColors.orange500)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .height(36)
        .padding({ left: 16, right: 8 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onSortAsc())

        Row() {
          Text(this.descText)
            .fontSize(14)
            .fontColor(this.isCurrentSort && this.currentSortDesc ? AppColors.orange500 : AppColors.grey900)
          if (this.isCurrentSort && this.currentSortDesc) {
            Image($r('app.media.ic_check_large'))
              .width(20).height(20)
              .fillColor(AppColors.orange500)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .height(36)
        .padding({ left: 16, right: 8 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onSortDesc())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct DisplaySettingsDialog {
  @Event onClose: () => void = () => {
  };
  @Local displayInCards: boolean = false;
  @Local onlyFavs: boolean = false;
  @Local currentSort: number = 1;
  @Local currentSortDesc: boolean = false;
  @Local videoGroupIndex: number = 0;
  @Local actionIndex: number = 0;
  @Local videoGroupOptions: string[] = ['按名称分组', '按文件夹分组', '不分组'];
  @Local actionOptions: string[] = ['播放', '全部播放', '追加'];
  @Local sorts: SortMeta[] = [
    new SortMeta(1, '名称', 'A -> Z', 'Z -> A', $r('app.media.ic_sort_alpha')),
    new SortMeta(2, '长度', '时长 短 -> 长', '时长长 -> 短', $r('app.media.ic_sort_length')),
    new SortMeta(3, '修改时间', '最旧的优先', '最新的优先', $r('app.media.ic_sort_date')),
    new SortMeta(4, '轨道编号', '视频较多的群组优先', '视频较少的群组优先', $r('app.media.ic_sort_track')),
    new SortMeta(5, '插入时间', '最旧的优先', '最新的优先', $r('app.media.ic_medialibrary_date')),
  ];

  async aboutToAppear(): Promise<void> {
    const cards = await Settings.getBoolean(Settings.KEY_VIDEOS_CARDS, true);
    this.displayInCards = !cards;
    this.currentSort = await Settings.getInt(Settings.KEY_VIDEO_SORT, 1);
    this.currentSortDesc = await Settings.getBoolean(Settings.KEY_VIDEO_SORT_DESC, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_VIDEO_ONLY_FAVS, false);
  }

  toggleDisplayMode(): void {
    this.displayInCards = !this.displayInCards;
    Settings.put(Settings.KEY_VIDEOS_CARDS, !this.displayInCards);
  }

  setSort(key: number, desc: boolean): void {
    this.currentSort = key;
    this.currentSortDesc = desc;
    Settings.put(Settings.KEY_VIDEO_SORT, key);
    Settings.put(Settings.KEY_VIDEO_SORT_DESC, desc);
  }

  build() {
    Scroll() {
      Column() {
        // 标题
        Text('显示设置')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({
            left: 16,
            right: 16,
            top: 16,
            bottom: 8
          })
          .maxLines(1)

        // 显示模式:当前为列表时显示"网格",当前为网格时显示"列表"
        Row() {
          Image(this.displayInCards ? $r('app.media.ic_view_list') : $r('app.media.ic_view_grid'))
            .width(24).height(24).fillColor(AppColors.grey600)
          Text(this.displayInCards ? '以列表形式显示' : '以网格形式显示')
            .fontSize(16)
            .fontColor(AppColors.grey900)
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.toggleDisplayMode();
        })

        // 只显示收藏
        Row() {
          Image($r('app.media.ic_favorite'))
            .width(24).height(24).fillColor(AppColors.grey600)
          Text('只显示收藏')
            .fontSize(16)
            .fontColor(AppColors.grey900)
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Toggle({ type: ToggleType.Checkbox, isOn: this.onlyFavs })
            .selectedColor(AppColors.orange500)
            .margin({ right: 4 })
            .onChange((on: boolean) => {
              this.onlyFavs = on;
              Settings.put(Settings.KEY_VIDEO_ONLY_FAVS, on);
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 视频分组
        Row() {
          Image($r('app.media.ic_group_display')).width(24).height(24).fillColor(AppColors.grey600)
          Text('视频分组')
            .fontSize(16)
            .fontColor(AppColors.grey900)
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Select(this.videoGroupOptions.map((v: string): SelectOption => ({ value: v })))
            .selected(this.videoGroupIndex)
            .value(this.videoGroupOptions[this.videoGroupIndex])
            .margin({ left: 8 })
            .width('40%')
            .onSelect((idx: number) => {
              this.videoGroupIndex = idx;
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 「播放」动作
        Row() {
          Image($r('app.media.ic_play')).width(24).height(24).fillColor(AppColors.grey600)
          Column() {
            Text('「播放」动作')
              .fontSize(16)
              .fontColor(AppColors.grey900)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('视频')
              .fontSize(12)
              .fontColor(AppColors.grey600)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .margin({ left: 24 })
          .alignItems(HorizontalAlign.Start)

          Select(this.actionOptions.map((v: string): SelectOption => ({ value: v })))
            .selected(this.actionIndex)
            .value(this.actionOptions[this.actionIndex])
            .margin({ left: 8 })
            .width('40%')
            .onSelect((idx: number) => {
              this.actionIndex = idx;
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 排序条件标题
        Text('排序条件')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({
            left: 16,
            right: 16,
            top: 24,
            bottom: 8
          })

        // 排序列表
        Column() {
          ForEach(this.sorts, (meta: SortMeta) => {
            SortItem({
              title: meta.title,
              ascText: meta.ascText,
              descText: meta.descText,
              icon: meta.icon,
              isCurrentSort: this.currentSort === meta.key,
              currentSortDesc: this.currentSortDesc,
              onSortAsc: () => {
                this.setSort(meta.key, false);
              },
              onSortDesc: () => {
                this.setSort(meta.key, true);
              },
            })
          }, (meta: SortMeta) => `${meta.key}`)
        }
        .width('100%')
        .margin({ bottom: 16 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.PARENT_FIRST,
    })
  }
}
