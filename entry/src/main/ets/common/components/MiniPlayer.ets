import { PlayState } from '../models/MediaModels';
import { PlaybackListener, PlaybackService, PlaybackState } from '../data/PlaybackService';
import { NavController } from '../data/NavController';

const AUDIO_EXTS = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];

@ObservedV2
class MiniPlayerVM implements PlaybackListener {
  @Trace title: string = '';
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace state: PlayState = PlayState.IDLE;
  @Trace hasCurrent: boolean = false;

  onChange(s: PlaybackState): void {
    // 通过回调拿到最新快照后立即同步检查是否为音频,确保 UI 刷新时判断准确。
    const cur = PlaybackService.getCurrent();
    const lower = cur?.uri?.toLowerCase() ?? '';
    const isAudio = AUDIO_EXTS.some(e => lower.endsWith(e));
    this.title = s.title;
    this.duration = s.duration;
    this.position = s.position;
    this.state = s.state;
    // 显示条件:原本就是音频文件,或当前处于"仅播放音频"模式(视频当音频播)。
    this.hasCurrent = s.queueSize > 0 && s.currentIndex >= 0 && (isAudio || s.playAsAudio);
  }
}

@ComponentV2
export struct MiniPlayer {
  @Local vm: MiniPlayerVM = new MiniPlayerVM();

  aboutToAppear(): void {
    const s = PlaybackService.snapshot();
    this.vm.onChange(s);
    PlaybackService.addListener(this.vm);
  }

  aboutToDisappear(): void {
    PlaybackService.removeListener(this.vm);
  }

  build() {
    if (this.vm.hasCurrent) {
      Column() {
        Row() {
          Text(this.vm.title)
            .fontSize(14)
            .fontColor($r('app.color.list_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 16, right: 8 })

          Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 8 })
            .onClick(() => PlaybackService.togglePlay())

          Image($r('app.media.ic_player_next'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 16 })
            .onClick(() => PlaybackService.next())
        }
        .width('100%').height(48).alignItems(VerticalAlign.Center)

        Progress({
          value: this.vm.duration > 0 ? Math.round(this.vm.position * 100 / this.vm.duration) : 0,
          total: 100, type: ProgressType.Linear
        })
          .width('100%').height(2).color($r('app.color.orange500')).backgroundColor($r('app.color.card_border'))
      }
      .width('100%')
      .backgroundColor($r('app.color.bottom_sheet_background'))
      .border({ width: { top: 0.5 }, color: $r('app.color.card_border') })
      .shadow({ radius: 12, color: '#1A000000', offsetY: -2 })
      .borderRadius({ topLeft: 12, topRight: 12 })
      .onClick(() => NavController.push('AudioPlayer'))
    }
  }
}
