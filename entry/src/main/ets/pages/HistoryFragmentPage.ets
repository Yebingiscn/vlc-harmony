import { UiFeedback } from '../common/utils/UiFeedback';
import { NavController } from '../common/data/NavController';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { Settings } from '../common/data/Settings';
import { AppDimens } from '../common/constants/AppConstants';
import { FileBrowserParam, formatDuration, VideoNavParam } from '../common/models/MediaModels';
import { PlaybackHistoryEntry } from '../common/models/PlaybackHistoryModels';
import { ParentalControlAction, ParentalControlParam } from './ParentalControlPage';

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
 * 长按进入多选模式,支持信息/播放/内部存储操作。
 * 文案/数值逐字照搬 .harmonyos/spec/pages/HistoryFragment.md。
 */
@ComponentV2
export struct HistoryFragmentPage {
  @Local vm: HistoryViewModel = new HistoryViewModel();
  @Local isRefreshing: boolean = false;
  @Local incognitoMode: boolean = false;
  @Local historyMenuOpen: boolean = false;
  @Local showVideoThumbnails: boolean = true;
  @Local isSelectionMode: boolean = false;
  @Local selectedUris: Set<string> = new Set();
  @Local selectedCount: number = 0;
  private removeHistoryListener: (() => void) | null = null;
  private removeSettingsListener: (() => void) | null = null;
  private clearHistoryDialogId: number = -1;
  private infoDialogId: number = -1;

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
    this.exitSelectionMode();
  }

  @Builder
  selectionTitleBar() {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.list_title'))
        .margin({ left: 12 })
        .onClick(() => this.exitSelectionMode())
      Text($r('app.string.selected_items_count', this.selectedCount))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.orange500'))
        .margin({ left: AppDimens.kl_half })
        .layoutWeight(1)
        .maxLines(1)
      if (this.selectedUris.size === 1) {
        Image($r('app.media.ic_information'))
          .width(28)
          .height(28)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 20 })
          .onClick(() => this.showFileInfo())
      }
      Image($r('app.media.ic_play'))
        .width(28)
        .height(28)
        .fillColor($r('app.color.list_title'))
        .margin({ right: 20 })
        .onClick(() => this.playSelected())
      if (this.selectedUris.size === 1) {
        Image($r('app.media.ic_storage'))
          .width(28)
          .height(28)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => this.openStorageLocation())
      }
    }
    .width('100%')
    .height(92)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 4,
      right: 4,
      top: 38,
      bottom: 4
    })
    .backgroundColor($r('app.color.background_default'))
  }

  // ── 多选模式 ──────────────────────────────────────────

  @Builder
  selectionDot(uri: string) {
    Stack() {
      if (this.selectedUris.has(uri)) {
        Circle()
          .width(22).height(22)
          .fill($r('app.color.orange500'))
        Image($r('app.media.ic_check'))
          .width(14).height(14)
          .fillColor($r('app.color.white'))
      } else {
        Circle()
          .width(22)
          .height(22)
          .fill(Color.Transparent)
          .stroke($r('app.color.list_subtitle'))
          .strokeWidth(2)
      }
    }
    .width(22).height(22)
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
        .padding({
          left: 16,
          right: 16,
          top: 16,
          bottom: 16
        })
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

  @Builder
  fileInfoDialogContent(item: PlaybackHistoryEntry) {
    Column() {
      Text($r('app.string.file_info'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.list_title'))
        .width('100%')
      this.infoRow($r('app.string.history_title'), item.title)
      this.infoRow($r('app.string.history_path'), item.uri)
      if (item.length > 0) {
        this.infoRow($r('app.string.history_duration'), formatDuration(item.length))
      }
      if (item.playedAt > 0) {
        this.infoRow($r('app.string.history_last_played'), new Date(item.playedAt).toLocaleString())
      }
      Row() {
        Button($r('app.string.close'))
          .type(ButtonType.Normal)
          .fontColor($r('app.color.orange500'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.closeInfoDialog())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 24 })
    }
    .width('84%')
    .borderRadius(16)
    .padding(24)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  infoRow(label: Resource, value: string) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.list_subtitle'))
        .width('100%')
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .margin({ top: 4 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  swipeDeleteButton(item: PlaybackHistoryEntry) {
    Row() {
      Image($r('app.media.ic_delete'))
        .width(20)
        .height(20)
        .fillColor(Color.White)
      Text($r('app.string.delete'))
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ left: 4 })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.delete_red'))
    .onClick(() => {
      void this.deleteHistoryEntry(item.uri);
    })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          // ── 标题栏: 多选模式 / 普通模式 ──
          if (this.isSelectionMode) {
            this.selectionTitleBar()
          } else {
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
                .fontColor($r('app.color.orange500'))
                .margin({ left: AppDimens.kl_half })
                .layoutWeight(1)
                .maxLines(1)
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
              .width(52)
              .height(56)
              .backgroundColor(Color.Transparent)
              .margin({ right: 4 })
              .onClick(() => this.historyMenuOpen = !this.historyMenuOpen)
              .bindMenu(this.historyMenuOpen, this.historyMenu(), {
                placement: Placement.BottomRight,
                showInSubWindow: true,
                onDisappear: () => this.historyMenuOpen = false,
              })
            }
            .width('100%')
            .height(92)
            .alignItems(VerticalAlign.Center)
            .padding({
              left: 4,
              right: 4,
              top: 38,
              bottom: 4
            })
            .backgroundColor($r('app.color.background_default'))
          }

          // ── 内容区 ──
          if (this.vm.isEmpty) {
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
                Repeat(this.vm.dataset).each((itemRepeatItem: RepeatItem<PlaybackHistoryEntry>) => {
                  ListItem() {
                    Row() {
                      // 多选模式: 左侧勾选圆
                      if (this.isSelectionMode) {
                        Row() {
                          this.selectionDot(itemRepeatItem.item.uri)
                        }
                        .margin({ left: AppDimens.kl_normal })
                      }

                      // 缩略图区(16:10 比例占位,40vp 高)
                      Stack() {
                        Image(this.showVideoThumbnails && itemRepeatItem.item.artworkUrl.length > 0 ? itemRepeatItem.item.artworkUrl :
                          $r('app.media.tv_channel_default'))
                          .width('100%')
                          .height('100%')
                          .objectFit(ImageFit.Cover)
                          .alt($r('app.media.tv_channel_default'))
                      }
                      .width(96)
                      .height(60)
                      .backgroundColor($r('app.color.card_background'))
                      .margin({
                        left: this.isSelectionMode ? 12 : AppDimens.kl_normal,
                        top: AppDimens.kl_half,
                        bottom: AppDimens.kl_half
                      })

                      // 中间文字区
                      Column() {
                        Text(itemRepeatItem.item.title)
                          .fontSize(16)
                          .fontColor($r('app.color.list_title'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                        if (itemRepeatItem.item.length > 0) {
                          Text(formatDuration(itemRepeatItem.item.length))
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
                    .backgroundColor(
                      this.isSelectionMode && this.isSelected(itemRepeatItem.item.uri) ? $r('app.color.history_selected_bg') :
                        Color.Transparent)
                    .onClick(() => {
                      if (this.isSelectionMode) {
                        this.toggleSelection(itemRepeatItem.item.uri);
                      } else {
                        this.onItemClick(itemRepeatItem.item);
                      }
                    })
                    .gesture(
                      LongPressGesture({ repeat: false, duration: 500 })
                        .onAction(() => {
                          if (!this.isSelectionMode) {
                            this.enterSelectionMode(itemRepeatItem.item.uri);
                          }
                        })
                    )
                  }
                  .swipeAction({
                    end: {
                      builder: () => {
                        this.swipeDeleteButton(itemRepeatItem.item)
                      },
                      onAction: () => {
                        void this.deleteHistoryEntry(itemRepeatItem.item.uri);
                      }
                    }
                  })
                }).key((item: PlaybackHistoryEntry) => item.uri).virtualScroll()
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
      if (this.isSelectionMode) {
        this.exitSelectionMode();
        return true;
      }
      NavController.pop();
      return true;
    })
  }

  private async refreshHistory(forceReload: boolean): Promise<void> {
    this.isRefreshing = true;
    await this.vm.refresh(forceReload);
    this.incognitoMode = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
    this.isRefreshing = false;
  }

  private enterSelectionMode(uri: string): void {
    this.isSelectionMode = true;
    const s = new Set<string>();
    s.add(uri);
    this.selectedUris = s;
    this.selectedCount = s.size;
  }

  // ── 原有方法 ──────────────────────────────────────────

  private exitSelectionMode(): void {
    this.isSelectionMode = false;
    this.selectedUris = new Set();
    this.selectedCount = 0;
  }

  private toggleSelection(uri: string): void {
    const s = new Set(this.selectedUris);
    if (s.has(uri)) {
      s.delete(uri);
      if (s.size === 0) {
        this.exitSelectionMode();
        return;
      }
    } else {
      s.add(uri);
    }
    this.selectedUris = s;
    this.selectedCount = s.size;
  }

  private isSelected(uri: string): boolean {
    return this.selectedUris.has(uri);
  }

  private selectedEntries(): PlaybackHistoryEntry[] {
    return this.vm.dataset.filter(e => this.selectedUris.has(e.uri));
  }

  private playSelected(): void {
    const entries = this.selectedEntries();
    if (entries.length === 0) {
      return;
    }
    const queue: QueueItem[] = entries.map((item, index) =>
    new QueueItem(index, item.title, item.uri, item.artistName, item.albumName, item.artworkUrl)
    );
    PlaybackService.playList(queue, 0, true);
    const first = entries[0];
    const lower = first.uri.toLowerCase();
    const audioExts = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];
    if (audioExts.some(e => lower.endsWith(e))) {
      NavController.push('AudioPlayer');
    } else {
      const vp: VideoNavParam = { uri: first.uri, title: first.title, artworkUrl: first.artworkUrl };
      NavController.push('VideoPlayer', vp);
    }
    this.exitSelectionMode();
  }

  private showFileInfo(): void {
    const entries = this.selectedEntries();
    if (entries.length !== 1) {
      return;
    }
    const item = entries[0];
    try {
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => this.fileInfoDialogContent(item),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.infoDialogId = dialogId;
      }).catch(() => {
        this.infoDialogId = -1;
      });
    } catch (error) {
      this.infoDialogId = -1;
    }
  }

  private closeInfoDialog(): void {
    if (this.infoDialogId >= 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.infoDialogId);
      } catch (error) {
        // The dialog may already have been dismissed by the system.
      }
    }
    this.infoDialogId = -1;
  }

  private openStorageLocation(): void {
    const fp: FileBrowserParam = { mode: 'storage' };
    NavController.push('FileBrowser', fp);
    this.exitSelectionMode();
  }

  // ── Builder: 多选标题栏 ──────────────────────────────

  private requestClearHistory(): void {
    try {
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => this.clearHistoryDialogContent(),
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.clearHistoryDialogId = dialogId;
      }).catch(() => {
        this.clearHistoryDialogId = -1;
      });
    } catch (error) {
      this.clearHistoryDialogId = -1;
    }
  }

  // ── Builder: 选择圆(多选勾选) ────────────────────────

  private closeClearHistoryDialog(): void {
    if (this.clearHistoryDialogId >= 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.clearHistoryDialogId);
      } catch (error) {
        // The dialog may already have been dismissed by the system.
      }
    }
    this.clearHistoryDialogId = -1;
  }

  // ── Builder: 历史菜单 ─────────────────────────────────

  private async confirmClearHistory(): Promise<void> {
    this.closeClearHistoryDialog();
    if (await this.openHistoryDeletePin(ParentalControlAction.CLEAR_HISTORY)) {
      return;
    }
    await PlaybackHistory.clear();
    UiFeedback.showToast({ message: $r('app.string.clear_history') });
  }

  // ── Builder: 清空历史确认弹窗 ────────────────────────

  private async openHistoryDeletePin(action: ParentalControlAction, uri: string = ''): Promise<boolean> {
    const safeModeEnabled = await Settings.getBoolean('safe_mode', false);
    if (!safeModeEnabled) {
      return false;
    }
    const param = new ParentalControlParam();
    param.action = action;
    param.historyUri = uri;
    NavController.push('ParentalControl', param);
    return true;
  }

  // ── Builder: 文件信息弹窗 ─────────────────────────────

  private async deleteHistoryEntry(uri: string): Promise<void> {
    if (await this.openHistoryDeletePin(ParentalControlAction.DELETE_HISTORY_ENTRY, uri)) {
      return;
    }
    await PlaybackHistory.removeEntry(uri);
  }

  private async setIncognito(enabled: boolean): Promise<void> {
    await PlaybackHistory.setIncognito(enabled);
    this.incognitoMode = enabled;
    UiFeedback.showToast({ message: enabled ? $r('app.string.incognito_on') : $r('app.string.incognito_off') });
  }

  // ── Builder: 滑动删除按钮 ─────────────────────────────

  private async setHistoryMenuIncognito(enabled: boolean): Promise<void> {
    await this.setIncognito(enabled);
    this.historyMenuOpen = false;
  }

  // ── Build ──────────────────────────────────────────────

  private onItemClick(item: PlaybackHistoryEntry): void {
    const lower = item.uri.toLowerCase();
    const audioExts = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];
    const isAudio = audioExts.some(e => lower.endsWith(e));
    if (isAudio) {
      const qi = new QueueItem(0, item.title, item.uri, item.artistName, item.albumName, item.artworkUrl);
      PlaybackService.playList([qi], 0, true);
      NavController.push('AudioPlayer');
    } else {
      const p: VideoNavParam = { uri: item.uri, title: item.title, artworkUrl: item.artworkUrl };
      NavController.push('VideoPlayer', p);
    }
  }
}
