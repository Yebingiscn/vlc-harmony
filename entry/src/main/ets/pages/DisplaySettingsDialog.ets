import { AppColors } from '../common/constants/AppConstants';

/** 排序元数据载体(class + 构造函数)。 */
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

/** 排序项:图标 + 标题(左半)+ 升序/降序(右半,行高 42vp,选中态橙字 + ic_check_large)。 */
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
        .fillColor(AppColors.grey400)
      Text(this.title)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .margin({ left: 24 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 升序
      Row() {
        Text(this.ascText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCurrentSort && !this.currentSortDesc ? AppColors.orange500 : '#FFFFFF')
        if (this.isCurrentSort && !this.currentSortDesc) {
          Image($r('app.media.ic_check_large')).width(20).height(20).fillColor(AppColors.orange500)
            .margin({ left: 4 })
        }
      }
      .height(42)
      .padding({ left: 16, right: 8 })
      .margin({ right: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onSortAsc())

      // 降序
      Row() {
        Text(this.descText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCurrentSort && this.currentSortDesc ? AppColors.orange500 : '#FFFFFF')
        if (this.isCurrentSort && this.currentSortDesc) {
          Image($r('app.media.ic_check_large')).width(20).height(20).fillColor(AppColors.orange500)
            .margin({ left: 4 })
        }
      }
      .height(42)
      .padding({ left: 16, right: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onSortDesc())
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

/**
 * DisplaySettingsDialog —— 显示设置 BottomSheet。
 * 18fp Medium 标题(display_settings)+ 8 设置行(列表/网格切换 + 6 个 CheckBox 行 + 视频分组 Select + 默认动作 Select)
 * + 排序区标题(sortby)+ 排序列表。minHeight 48vp,图标 24vp marginStart 24vp。
 * TODO(契约): DisplaySettingsViewModel.send(key,value) 事件总线;video_group/default_actions Select 选中后 send;
 *   sort_asc/desc onClick → send(CURRENT_SORT, Pair(sort,desc));VIDEO_GROUPING 变更后 dismiss()。
 */
@ComponentV2
export struct DisplaySettingsDialog {
  @Event onClose: () => void = () => {
  };
  @Local displayInCards: boolean = false;
  @Local showAllArtists: boolean = false;
  @Local showOnlyMultimediaFiles: boolean = false;
  @Local showTrackNumbers: boolean = false;
  @Local showHiddenFiles: boolean = false;
  @Local onlyFavs: boolean = false;
  @Local currentSort: number = 1;
  @Local currentSortDesc: boolean = false;
  @Local videoGroupOptions: string[] = ['Group by name', 'Group by folder', 'Do not group videos'];
  @Local videoGroupIndex: number = 0;
  @Local actionOptions: string[] = ['Play', 'Play all', 'Append'];
  @Local actionIndex: number = 0;
  @Local sorts: SortMeta[] = [
    new SortMeta(1, 'Name', 'A → Z', 'Z → A', $r('app.media.ic_sort_alpha')),
    new SortMeta(2, 'File name', 'A → Z', 'Z → A', $r('app.media.ic_sort_filename')),
    new SortMeta(5, 'Length', 'Shortest first', 'Longest first', $r('app.media.ic_sort_length')),
    new SortMeta(7, 'Album name', 'A → Z', 'Z → A', $r('app.media.ic_sort_album')),
  ];

  @Builder
  checkboxRow(icon: Resource, title: ResourceStr, checked: boolean, onChange: (v: boolean) => void) {
    Row() {
      Image(icon).width(24).height(24).fillColor('#FFFFFF')
      Text(title)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .margin({ left: 24 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Toggle({ type: ToggleType.Checkbox, isOn: checked })
        .selectedColor(AppColors.orange500)
        .margin({ right: 4 })
        .onChange((on: boolean) => onChange(on))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Scroll() {
      Column() {
        // 标题
        Text('Display settings')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({ left: 16, right: 16, top: 16 })
          .maxLines(1)

        // display_mode_group:列表/网格切换
        Row() {
          Image(this.displayInCards ? $r('app.media.ic_view_list') : $r('app.media.ic_view_grid'))
            .width(24).height(24).fillColor('#FFFFFF')
          Text(this.displayInCards ? 'Display in list' : 'Display in grid')
            .fontSize(16).fontColor('#FFFFFF').margin({ left: 24, right: 16 }).layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.displayInCards = !this.displayInCards;
        })

        // CheckBox 行们
        this.checkboxRow($r('app.media.ic_sort_artist'), $r('app.string.artists'),
          this.showAllArtists, (v) => this.showAllArtists = v)
        this.checkboxRow($r('app.media.ic_multimedia'), 'Show only multimedia files',
          this.showOnlyMultimediaFiles, (v) => this.showOnlyMultimediaFiles = v)
        this.checkboxRow($r('app.media.ic_sort_track'), $r('app.string.albums_show_track_numbers'),
          this.showTrackNumbers, (v) => this.showTrackNumbers = v)
        this.checkboxRow($r('app.media.ic_hidden'), 'Show hidden files',
          this.showHiddenFiles, (v) => this.showHiddenFiles = v)
        this.checkboxRow($r('app.media.ic_favorite'), 'Show only favorites',
          this.onlyFavs, (v) => this.onlyFavs = v)

        // video_groups_group:分组 Select(占右半)
        Row() {
          Image($r('app.media.ic_group_display')).width(24).height(24).fillColor('#FFFFFF')
          Text('Group videos')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .margin({ left: 24 })
            .width('50%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Select(this.actionOptions.map((v: string): SelectOption => ({ value: v })))
            .selected(this.videoGroupIndex)
            .value(this.videoGroupOptions[this.videoGroupIndex])
            .margin({ left: 8 })
            .width('50%')
            .onSelect((idx: number) => {
              this.videoGroupIndex = idx;
              this.onClose(); // 切换分组后关闭弹窗
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .margin({ top: 24 })

        // default_actions_group:默认动作 Select + 副标题(alpha 0.7)
        Row() {
          Image($r('app.media.ic_play')).width(24).height(24).fillColor('#FFFFFF')
          Column() {
            Text('Playback action')
              .fontSize(16).fontColor('#FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('Default action when opening media')
              .fontSize(12)
              .fontColor('#FFFFFF')
              .opacity(0.7)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1).margin({ left: 24 })

          Select(this.actionOptions.map((v: string): SelectOption => ({ value: v })))
            .selected(this.actionIndex)
            .value(this.actionOptions[this.actionIndex])
            .margin({ left: 8 })
            .width('50%')
            .onSelect((idx: number) => {
              this.actionIndex = idx;
            })
        }
        .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 排序区标题
        Text('Sort by…')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(AppColors.orange500)
          .margin({ left: 16, top: 8 })

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
                this.currentSort = meta.key;
                this.currentSortDesc = false;
              },
              onSortDesc: () => {
                this.currentSort = meta.key;
                this.currentSortDesc = true;
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
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
