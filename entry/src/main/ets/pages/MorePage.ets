import { NavController } from '../common/data/NavController';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { Settings } from '../common/data/Settings';
import { formatDuration, VideoNavParam } from '../common/models/MediaModels';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { PlaybackHistoryEntry } from '../common/models/PlaybackHistoryModels';
import { historyPreview } from '../common/models/MoreHomeModels';
import { ParentalControlAction, ParentalControlParam } from './ParentalControlPage';

@ObservedV2
class MoreViewModel {
  @Trace history: PlaybackHistoryEntry[] = [];
}

/** 更多 tab：首页结构与安卓 VLC 对齐，串流保留为明确的功能占位。 */
@ComponentV2
export struct MorePage {
  @Local vm: MoreViewModel = new MoreViewModel();
  @Local showVideoThumbnails: boolean = true;
  private removeHistoryListener: (() => void) | null = null;
  private removeSettingsListener: (() => void) | null = null;

  async aboutToAppear(): Promise<void> {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
    if (this.removeSettingsListener) {
      this.removeSettingsListener();
      this.removeSettingsListener = null;
    }
    this.vm.history = historyPreview(await PlaybackHistory.load());
    this.showVideoThumbnails = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    this.removeHistoryListener = PlaybackHistory.subscribe((entries: PlaybackHistoryEntry[]) => {
      this.vm.history = historyPreview(entries);
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

  private openHistory(): void {
    NavController.push('History');
  }

  private async openPreferences(): Promise<void> {
    const restricted = await Settings.getBoolean('restrict_settings', false);
    if (!restricted) {
      NavController.push('Preferences');
      return;
    }
    const param = new ParentalControlParam();
    param.action = ParentalControlAction.OPEN_SETTINGS;
    NavController.push('ParentalControl', param);
  }

  private playHistoryItem(item: PlaybackHistoryEntry): void {
    const lower = item.uri.toLowerCase();
    const audioExts = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];
    const isAudio = audioExts.some(e => lower.endsWith(e));
    if (isAudio) {
      const qi = new QueueItem(0, item.title, item.uri, '', '', item.artworkUrl);
      PlaybackService.playList([qi], 0, true);
      NavController.push('AudioPlayer');
    } else {
      const param: VideoNavParam = { uri: item.uri, title: item.title, artworkUrl: item.artworkUrl };
      NavController.push('VideoPlayer', param);
    }
  }

  @Builder
  ActionButton(icon: Resource, title: string, onClick: () => void) {
    Row() {
      Image(icon)
        .width(26).height(26).objectFit(ImageFit.Contain).fillColor('#FF8800')
      Text(title)
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#FF8800').margin({ left: 12 })
    }
    .width('100%').height(56)
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.card_border'), radius: 8 })
    .onClick(() => onClick())
  }

  @Builder
  SectionTitle(title: string, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FF8800').layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(24).height(24).fillColor($r('app.color.list_title'))
        .onClick(() => onClick())
    }
    .width('100%').padding({ left: 16, right: 16, top: 24, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  @Builder
  NewStreamCard() {
    Column() {
      Image($r('app.media.ic_add')).width(42).height(42).fillColor('#FF8800')
      Text('新建串流')
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.list_title'))
        .margin({ top: 14 })
    }
    .width(180).height(150)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .border({ width: 1, color: $r('app.color.card_border'), radius: 12 })
    .margin({ left: 16 })
    .onClick(() => NavController.push('MrlPanel'))
  }

  @Builder
  HistoryCard(item: PlaybackHistoryEntry) {
    Column() {
      Image(this.showVideoThumbnails && item.artworkUrl.length > 0 ? item.artworkUrl : $r('app.media.tv_channel_default'))
        .width('100%').height(108)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.tv_channel_default'))
        .borderRadius({ topLeft: 8, topRight: 8 })
        .backgroundColor($r('app.color.card_background'))
      Column() {
        Text(item.title)
          .fontSize(14).fontColor($r('app.color.list_title'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (item.length > 0) {
          Text(formatDuration(item.length))
            .fontSize(12).fontColor($r('app.color.list_subtitle')).margin({ top: 4 })
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(12)
    }
    .width(176).height(166)
    .border({ width: 1, color: $r('app.color.card_border'), radius: 8 })
    .clip(true).margin({ right: 12 })
    .onClick(() => this.playHistoryItem(item))
  }

  @Builder
  HistoryPreview() {
    if (this.vm.history.length === 0) {
      Column() {
        Text('暂无播放历史')
          .fontSize(14).fontColor($r('app.color.list_subtitle'))
      }
      .width('100%').height(120)
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start)
      .padding({ left: 16 })
      .border({ width: 1, color: $r('app.color.card_border'), radius: 8 })
      .margin({ left: 16, right: 16 })
      .onClick(() => this.openHistory())
    } else {
      Scroll() {
        Row() {
          ForEach(this.vm.history, (item: PlaybackHistoryEntry) => {
            this.HistoryCard(item)
          }, (item: PlaybackHistoryEntry) => item.uri)
        }
        .padding({ left: 16, right: 4 })
      }
      .width('100%').height(190)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .align(Alignment.Start)
    }
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            this.ActionButton($r('app.media.ic_more_preferences'), '设置', () => { void this.openPreferences(); })
          }
          .layoutWeight(1).margin({ right: 12 })
          Column() {
            this.ActionButton($r('app.media.ic_more_about'), '关于', () => NavController.push('About'))
          }
          .layoutWeight(1)
        }
        .width('100%').padding({ left: 16, right: 16, top: 20 })

        // 串流入口按需求隐藏(保留底层实现,仅不在此展示):
        // this.SectionTitle('串流', () => NavController.push('MrlPanel'))
        // this.NewStreamCard()

        if (this.vm.history.length > 0) {
          this.SectionTitle('历史', () => this.openHistory())
          this.HistoryPreview()
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 28 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    .scrollBar(BarState.Off).align(Alignment.TopStart)
  }
}
