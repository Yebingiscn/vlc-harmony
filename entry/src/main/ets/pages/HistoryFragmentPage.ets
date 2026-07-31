import { NavController } from '../common/data/NavController';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { Settings } from '../common/data/Settings';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { formatDuration, VideoNavParam } from '../common/models/MediaModels';
import { HistoryClearPrompt, historyClearPrompt, PlaybackHistoryEntry } from '../common/models/PlaybackHistoryModels';
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
  @Local clearHistoryDialogOpen: boolean = false;
  private removeHistoryListener: (() => void) | null = null;
  private readonly clearHistoryPrompt: HistoryClearPrompt = historyClearPrompt();

  async aboutToAppear(): Promise<void> {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
    await this.refreshHistory(false);
    this.removeHistoryListener = PlaybackHistory.subscribe((entries: PlaybackHistoryEntry[]) => {
      this.vm.apply(entries);
    });
  }

  aboutToDisappear(): void {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
  }

  private async refreshHistory(forceReload: boolean): Promise<void> {
    this.isRefreshing = true;
    await this.vm.refresh(forceReload);
    this.incognitoMode = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
    this.isRefreshing = false;
  }

  private requestClearHistory(): void {
    this.clearHistoryDialogOpen = true;
  }

  private async confirmClearHistory(): Promise<void> {
    this.clearHistoryDialogOpen = false;
    await PlaybackHistory.clear();
    promptAction.showToast({ message: '播放历史已清空' });
  }

  private async setIncognito(enabled: boolean): Promise<void> {
    await PlaybackHistory.setIncognito(enabled);
    this.incognitoMode = enabled;
    promptAction.showToast({ message: enabled ? '无痕模式已开启' : '无痕模式已关闭' });
  }

  private onItemClick(item: PlaybackHistoryEntry): void {
    // TODO(契约):MediaUtils 播放入口 —— 播放该 MediaWrapper(进入播放器)。
    const p: VideoNavParam = { uri: item.uri, title: item.title };
    NavController.push('VideoPlayer', p);
  }

  @Builder
  historyMenu() {
    Column() {
      Row() {
        Text('无痕模式')
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Checkbox, isOn: this.incognitoMode })
          .selectedColor('#FF8800')
          .onChange((enabled: boolean) => this.setIncognito(enabled))
      }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 12 })
        .alignItems(VerticalAlign.Center)
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
      Text('刷新')
        .fontSize(16)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => {
          this.historyMenuOpen = false;
          this.refreshHistory(true);
        })
    }
    .width(220)
    .backgroundColor('#242424')
    .borderRadius(12)
    .shadow({ radius: 16, color: '#66000000', offsetY: 6 })
    .position({ right: 12, top: 64 })
  }

  @Builder
  clearHistoryDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
      Column() {
        Text(this.clearHistoryPrompt.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.list_title'))
          .width('100%')
        Text(this.clearHistoryPrompt.message)
          .fontSize(16)
          .fontColor('#D0D0D0')
          .width('100%')
          .margin({ top: 20 })
        Row() {
          Button(this.clearHistoryPrompt.cancelLabel)
            .type(ButtonType.Normal)
            .fontColor('#FF8800')
            .backgroundColor(Color.Transparent)
            .onClick(() => this.clearHistoryDialogOpen = false)
          Button(this.clearHistoryPrompt.confirmLabel)
            .type(ButtonType.Normal)
            .fontColor('#FF8800')
            .backgroundColor(Color.Transparent)
            .margin({ left: 8 })
            .onClick(() => this.confirmClearHistory())
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 32 })
      }
      .width('84%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(24)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
        // 返回导航栏(标题 = "History")
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text($r('app.string.history'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF8800')
            .margin({ left: AppDimens.kl_half })
          Blank()
          Image($r('app.media.ic_search'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 24 })
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Image($r('app.media.ic_delete'))
              .width(28)
              .height(28)
              .fillColor($r('app.color.list_title'))
          }
          .width(56)
          .height(56)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.requestClearHistory())
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Image($r('app.media.ic_more_w'))
              .width(28)
              .height(28)
          }
          .width(52)
          .height(56)
          .backgroundColor(Color.Transparent)
          .margin({ right: 4 })
          .onClick(() => this.historyMenuOpen = !this.historyMenuOpen)
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
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
                      Image(item.artworkUrl.length > 0 ? item.artworkUrl : $r('app.media.ic_no_thumbnail_1610'))
                        .width('100%')
                        .height('100%')
                        .objectFit(ImageFit.Cover)
                        .alt($r('app.media.ic_no_thumbnail_1610'))
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
        if (this.historyMenuOpen) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => this.historyMenuOpen = false)
          this.historyMenu()
        }
        if (this.clearHistoryDialogOpen) {
          this.clearHistoryDialog()
        }
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
