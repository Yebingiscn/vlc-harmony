import { NavController } from '../common/data/NavController';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { Settings } from '../common/data/Settings';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { BackTitleBar } from '../common/components/BackTitleBar';
import { formatDuration, VideoNavParam } from '../common/models/MediaModels';
import { PlaybackHistoryEntry } from '../common/models/PlaybackHistoryModels';
import { promptAction } from '@kit.ArkUI';

/**
 * HistoryViewModel —— HistoryFragment 的 VM。
 * @Trace 字段;改数组整体 reassign。
 */
@ObservedV2
class HistoryViewModel {
  @Trace dataset: PlaybackHistoryEntry[] = [];
  @Trace loading: boolean = false;
  @Trace isEmpty: boolean = true;

  /** 刷新:历史样例 = MediaLibrary.getVideos().slice(0,5)。 */
  async refresh(forceReload: boolean = false): Promise<void> {
    this.loading = true;
    // TODO(契约):medialibrary.history(HISTORY_TYPE_LOCAL) 未迁移,样例取设备视频前 5 条。
    const entries = forceReload ? await PlaybackHistory.refresh() : await PlaybackHistory.load();
    this.apply(entries);
    this.loading = false;
  }

  apply(entries: PlaybackHistoryEntry[]): void {
    this.dataset = entries;
    this.isEmpty = entries.length === 0;
  }
}

/**
 * HistoryFragmentPage —— HistoryFragment(历史列表页)。
 * Refresh + List/empty 两态;item 行(缩略图 + 标题 14sp + 副标题 12sp)。
 * 文案/数值逐字照搬 .harmonyos/spec/pages/HistoryFragment.md。
 */
@ComponentV2
export struct HistoryFragmentPage {
  @Local vm: HistoryViewModel = new HistoryViewModel();
  @Local isRefreshing: boolean = false;
  @Local incognitoMode: boolean = false;
  @Local historyMenuOpen: boolean = false;
  @Local showVideoThumbnails: boolean = true;
  private removeHistoryListener: (() => void) | null = null;
  private removeSettingsListener: (() => void) | null = null;
  private clearHistoryDialogId: number = -1;

  async aboutToAppear(): Promise<void> {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
    if (this.removeSettingsListener) {
      this.removeSettingsListener();
      this.removeSettingsListener = null;
    }
    await this.refreshHistory(false);
    this.showVideoThumbnails = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    this.removeHistoryListener = PlaybackHistory.subscribe((entries: PlaybackHistoryEntry[]) => {
      this.vm.apply(entries);
    });
    this.removeSettingsListener = Settings.observe((key: string) => {
      if (key === Settings.SHOW_VIDEO_THUMBNAILS) {
        this.showVideoThumbnails = Settings.showVideoThumbs;
      }
    });
  }

  aboutToDisappear(): void {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
    if (this.removeSettingsListener) {
      this.removeSettingsListener();
      this.removeSettingsListener = null;
    }
  }

  private async refreshHistory(forceReload: boolean): Promise<void> {
    this.isRefreshing = true;
    await this.vm.refresh(forceReload);
    this.incognitoMode = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
    this.isRefreshing = false;
  }

  private requestClearHistory(): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => this.clearHistoryDialogContent(),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      maskColor: $r('app.color.dialog_mask'),
      backgroundColor: Color.Transparent,
    }).then((dialogId: number) => {
      this.clearHistoryDialogId = dialogId;
    });
  }

  private closeClearHistoryDialog(): void {
    if (this.clearHistoryDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.clearHistoryDialogId);
    }
    this.clearHistoryDialogId = -1;
  }

  private async confirmClearHistory(): Promise<void> {
    this.closeClearHistoryDialog();
    await PlaybackHistory.clear();
    promptAction.showToast({ message: $r('app.string.clear_history') });
  }

  private async setIncognito(enabled: boolean): Promise<void> {
    await PlaybackHistory.setIncognito(enabled);
    this.incognitoMode = enabled;
    promptAction.showToast({ message: enabled ? '无痕模式已开启' : '无痕模式已关闭' });
  }

  private async setHistoryMenuIncognito(enabled: boolean): Promise<void> {
    await this.setIncognito(enabled);
    this.historyMenuOpen = false;
  }

  private onItemClick(item: PlaybackHistoryEntry): void {
    // TODO(契约):MediaUtils 播放入口 —— 播放该 MediaWrapper(进入播放器)。
    const p: VideoNavParam = { uri: item.uri, title: item.title, artworkUrl: item.artworkUrl };
    NavController.push('VideoPlayer', p);
  }

  @Builder
  historyMenu() {
    Column() {
      Row() {
        Text($r('app.string.incognito_mode'))
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .onClick(() => void this.setHistoryMenuIncognito(!this.incognitoMode))
        Toggle({ type: ToggleType.Checkbox, isOn: this.incognitoMode })
          .selectedColor($r('app.color.orange500'))
          .onChange((enabled: boolean) => void this.setHistoryMenuIncognito(enabled))
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 12 })
      .alignItems(VerticalAlign.Center)
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
      Text($r('app.string.menu_refresh'))
        .fontSize(16)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => {
          this.historyMenuOpen = false;
          void this.refreshHistory(true);
        })
    }
    .width(220)
    .borderRadius(12)
  }

  @Builder
  clearHistoryDialogContent() {
    Column() {
      Text($r('app.string.clear_playback_history'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.list_title'))
        .width('100%')
      Text($r('app.string.clear_history_message'))
        .fontSize(16)
        .fontColor($r('app.color.list_subtitle'))
        .width('100%')
        .margin({ top: 20 })
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontColor($r('app.color.orange500'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.closeClearHistoryDialog())
        Button($r('app.string.clear_history'))
          .type(ButtonType.Normal)
          .fontColor($r('app.color.orange500'))
          .backgroundColor(Color.Transparent)
          .margin({ left: 8 })
          .onClick(() => this.confirmClearHistory())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 32 })
    }
    .width('84%')
    // .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .padding(24)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
        // 返回导航栏
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24).height(24).objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title')).margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text($r('app.string.history'))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FF8800')
            .margin({ left: AppDimens.kl_half })
          Blank()
          Image($r('app.media.ic_search'))
            .width(28).height(28).fillColor($r('app.color.list_title')).margin({ right: 24 })
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Image($r('app.media.ic_delete')).width(28).height(28).fillColor($r('app.color.list_title'))
          }
          .width(56).height(56).backgroundColor(Color.Transparent)
          .onClick(() => this.requestClearHistory())
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
              .fontSize(28).fontColor([$r('sys.color.icon_primary')])
          }
          .width(52).height(56).backgroundColor(Color.Transparent).margin({ right: 4 })
          .onClick(() => this.historyMenuOpen = !this.historyMenuOpen)
          .bindMenu(this.historyMenuOpen, this.historyMenu(), {
            placement: Placement.BottomRight,
            showInSubWindow: true,
            onDisappear: () => this.historyMenuOpen = false,
          })
        }
        .width('100%').height(56).alignItems(VerticalAlign.Center)
        .padding({ top: 32 })
        .backgroundColor($r('app.color.background_default'))

        if (this.vm.isEmpty) {
          // 空态文案:左对齐
          Column() {
            Text($r('app.string.nohistory'))
              .fontSize(16)
              .fontColor($r('app.color.list_subtitle'))
              .textAlign(TextAlign.Start)
              .margin({ top: 30 })
              .padding({ left: AppDimens.kl_normal })
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: 0 }) {
              ForEach(this.vm.dataset, (item: PlaybackHistoryEntry, index: number) => {
                ListItem() {
                  Row() {
                    // 缩略图区(16:10 比例占位,40vp 高)
                    Stack() {
                      Image(this.showVideoThumbnails && item.artworkUrl.length > 0 ? item.artworkUrl : $r('app.media.tv_channel_default'))
                        .width('100%')
                        .height('100%')
                        .objectFit(ImageFit.Cover)
                        .alt($r('app.media.tv_channel_default'))
                    }
                    .width(96)
                    .height(60)
                    .backgroundColor($r('app.color.card_background'))
                    .margin({ left: AppDimens.kl_normal, top: AppDimens.kl_half, bottom: AppDimens.kl_half })

                    // 中间文字区
                    Column() {
                      Text(item.title)
                        .fontSize(16)
                        .fontColor($r('app.color.list_title'))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      if (item.length > 0) {
                        Text(formatDuration(item.length))
                          .fontSize(13)
                          .fontColor($r('app.color.list_subtitle'))
                          .maxLines(1)
                          .margin({ top: 2 })
                          .width('100%')
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_small })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => this.onItemClick(item))
                }
              }, (item: PlaybackHistoryEntry) => item.uri)
            }
            .alignListItem(ListItemAlign.Start)
            .width('100%')
            .height('100%')
            .padding({ top: 18, bottom: AppDimens.default_margin })
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing(() => this.refreshHistory(true))
        }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_default'))
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
