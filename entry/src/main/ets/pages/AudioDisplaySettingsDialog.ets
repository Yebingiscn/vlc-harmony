import { AppColors } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';

/**
 * AudioDisplaySettingsDialog -- 音频显示设置 BottomSheet。
 * 列表/网格切换 + 显示所有艺术家 + 只显示收藏 + 按名称排序(正序/倒序)。
 */
@ComponentV2
export struct AudioDisplaySettingsDialog {
  @Local displayAsList: boolean = false;
  @Local showAllArtists: boolean = false;
  @Local onlyFavs: boolean = false;
  @Local playActionIndex: number = 0;
  @Local sortDesc: boolean = false;
  readonly playActions: string[] = ['播放', '添加到播放队列', '插入为下一项'];

  @Event onClose: () => void = () => {
  };
  @Event onDisplayModeChange: () => void = () => {
  };

  async aboutToAppear(): Promise<void> {
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.showAllArtists = await Settings.getBoolean(Settings.KEY_ARTISTS_SHOW_ALL, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_AUDIO_ONLY_FAVS, false);
    this.playActionIndex = await Settings.getInt(Settings.KEY_AUDIO_PLAY_ACTION, 0);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
  }

  async toggleDisplayMode(): Promise<void> {
    this.displayAsList = !this.displayAsList;
    await Settings.put(Settings.KEY_DISPLAY_AS_LIST, this.displayAsList);
    this.onDisplayModeChange();
  }

  setSortDesc(desc: boolean): void {
    this.sortDesc = desc;
    Settings.put(Settings.KEY_AUDIO_SORT_DESC, desc);
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

        // 列表/网格切换
        Row() {
          Image(this.displayAsList ? $r('app.media.ic_view_list') : $r('app.media.ic_view_grid'))
            .width(24).height(24).fillColor($r('app.color.list_subtitle'))
          Text(this.displayAsList ? '以列表形式显示' : '以网格形式显示')
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => void this.toggleDisplayMode())

        // 显示所有艺术家
        Row() {
          Image($r('app.media.ic_artist_big'))
            .width(24).height(24).fillColor($r('app.color.list_subtitle'))
          Text('显示所有艺术家')
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Toggle({ type: ToggleType.Checkbox, isOn: this.showAllArtists })
            .selectedColor(AppColors.orange500)
            .margin({ right: 4 })
            .onChange((on: boolean) => {
              this.showAllArtists = on;
              Settings.put(Settings.KEY_ARTISTS_SHOW_ALL, on);
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 只显示收藏
        Row() {
          Image($r('app.media.ic_favorite'))
            .width(24).height(24).fillColor($r('app.color.list_subtitle'))
          Text('只显示收藏')
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 24 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Toggle({ type: ToggleType.Checkbox, isOn: this.onlyFavs })
            .selectedColor(AppColors.orange500)
            .margin({ right: 4 })
            .onChange((on: boolean) => {
              this.onlyFavs = on;
              Settings.put(Settings.KEY_AUDIO_ONLY_FAVS, on);
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 「播放」动作
        Row() {
          Image($r('app.media.ic_play'))
            .width(24).height(24).fillColor($r('app.color.list_subtitle'))
          Column() {
            Text('「播放」动作')
              .fontSize(16)
              .fontColor($r('app.color.list_title'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('艺术家')
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .margin({ left: 24 })
          .alignItems(HorizontalAlign.Start)

          Select(this.playActions.map((v: string): SelectOption => ({ value: v })))
            .selected(this.playActionIndex)
            .value(this.playActions[this.playActionIndex])
            .fontColor($r('app.color.list_title'))
            .margin({ left: 8 })
            .width('40%')
            .onSelect((idx: number) => {
              this.playActionIndex = idx;
              Settings.put(Settings.KEY_AUDIO_PLAY_ACTION, idx);
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

        // 按名称排序:正序/倒序
        Row() {
          Image($r('app.media.ic_sort_alpha'))
            .width(24).height(24)
            .fillColor($r('app.color.list_subtitle'))
          Text('名称')
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 24 })
            .width(100)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Column() {
            Row() {
              Text('A -> Z')
                .fontSize(14)
                .fontColor(!this.sortDesc ? AppColors.orange500 : $r('app.color.list_title'))
              if (!this.sortDesc) {
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
            .onClick(() => this.setSortDesc(false))

            Row() {
              Text('Z -> A')
                .fontSize(14)
                .fontColor(this.sortDesc ? AppColors.orange500 : $r('app.color.list_title'))
              if (this.sortDesc) {
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
            .onClick(() => this.setSortDesc(true))
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
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .clip(false)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.bottom_sheet_background'))
  }
}
