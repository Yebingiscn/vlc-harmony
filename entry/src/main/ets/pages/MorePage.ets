import { promptAction } from '@kit.ArkUI';
import { NavController } from '../common/data/NavController';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { formatDuration, VideoNavParam } from '../common/models/MediaModels';
import { PlaybackHistoryEntry } from '../common/models/PlaybackHistoryModels';
import { historyPreview } from '../common/models/MoreHomeModels';

@ObservedV2
class MoreViewModel {
  @Trace history: PlaybackHistoryEntry[] = [];
}

/** 更多 tab：首页结构与安卓 VLC 对齐，串流保留为明确的功能占位。 */
@ComponentV2
export struct MorePage {
  @Local vm: MoreViewModel = new MoreViewModel();
  private removeHistoryListener: (() => void) | null = null;

  async aboutToAppear(): Promise<void> {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
    this.vm.history = historyPreview(await PlaybackHistory.load());
    this.removeHistoryListener = PlaybackHistory.subscribe((entries: PlaybackHistoryEntry[]) => {
      this.vm.history = historyPreview(entries);
    });
  }

  aboutToDisappear(): void {
    if (this.removeHistoryListener) {
      this.removeHistoryListener();
      this.removeHistoryListener = null;
    }
  }

  private showStreamsUnavailable(): void {
    promptAction.showToast({ message: '串流功能暂未实现' });
  }

  private openHistory(): void {
    NavController.push('History');
  }

  private playHistoryItem(item: PlaybackHistoryEntry): void {
    const param: VideoNavParam = { uri: item.uri, title: item.title };
    NavController.push('VideoPlayer', param);
  }

  @Builder
  ActionButton(icon: Resource, title: string, onClick: () => void) {
    Row() {
      Image(icon)
        .width(30)
        .height(30)
        .objectFit(ImageFit.Contain)
        .fillColor('#FF8800')
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FF8800')
        .margin({ left: 16 })
    }
    .width('100%')
    .height(64)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: '#454545', radius: 8 })
    .onClick(() => onClick())
  }

  @Builder
  SectionTitle(title: string, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FF8800')
        .layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(28)
        .height(28)
        .fillColor('#FFFFFF')
        .onClick(() => onClick())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 28, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  @Builder
  NewStreamCard() {
    Column() {
      Image($r('app.media.ic_add'))
        .width(48)
        .height(48)
        .fillColor('#FF8800')
      Text('新建串流')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .margin({ top: 18 })
    }
    .width(210)
    .height(170)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .border({ width: 1, color: '#454545', radius: 12 })
    .margin({ left: 16 })
    .onClick(() => this.showStreamsUnavailable())
  }

  @Builder
  HistoryCard(item: PlaybackHistoryEntry) {
    Column() {
      Image(item.artworkUrl.length > 0 ? item.artworkUrl : $r('app.media.ic_no_thumbnail_1610'))
        .width('100%')
        .height(108)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.ic_no_thumbnail_1610'))
        .borderRadius({ topLeft: 8, topRight: 8 })
        .backgroundColor('#1E1E1E')
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (item.length > 0) {
          Text(formatDuration(item.length))
            .fontSize(13)
            .fontColor('#BDBDBD')
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
    }
    .width(190)
    .height(178)
    .border({ width: 1, color: '#454545', radius: 8 })
    .clip(true)
    .margin({ right: 12 })
    .onClick(() => this.playHistoryItem(item))
  }

  @Builder
  HistoryPreview() {
    if (this.vm.history.length === 0) {
      Column() {
        Text('暂无播放历史')
          .fontSize(16)
          .fontColor('#BDBDBD')
      }
      .width('100%')
      .height(120)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .border({ width: 1, color: '#454545', radius: 8 })
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
      .width('100%')
      .height(190)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            this.ActionButton($r('app.media.ic_more_preferences'), '设置', () => NavController.push('Preferences'))
          }
            .layoutWeight(1)
            .margin({ right: 12 })
          Column() {
            this.ActionButton($r('app.media.ic_more_about'), '关于', () => NavController.push('About'))
          }
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24 })

        this.SectionTitle('串流', () => this.showStreamsUnavailable())
        this.NewStreamCard()

        if (this.vm.history.length > 0) {
          this.SectionTitle('历史', () => this.openHistory())
          this.HistoryPreview()
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121212')
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }
}
