import { PlayState } from '../models/MediaModels';
import { PlaybackListener, PlaybackService, PlaybackState } from '../data/PlaybackService';
import { NavController } from '../data/NavController';

const AUDIO_EXTS = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];

@ObservedV2
class MiniPlayerVM implements PlaybackListener {
  @Trace title: string = '';
  @Trace artworkPath: string = '';
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace state: PlayState = PlayState.IDLE;
  @Trace hasCurrent: boolean = false;

  onChange(s: PlaybackState): void {
    const cur = PlaybackService.getCurrent();
    const lower = cur?.uri?.toLowerCase() ?? '';
    const isAudio = AUDIO_EXTS.some(e => lower.endsWith(e));
    this.title = s.title;
    this.artworkPath = s.artworkPath;
    this.duration = s.duration;
    this.position = s.position;
    this.state = s.state;
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
      Row() {
        Image(this.vm.artworkPath.length > 0 ? this.vm.artworkPath : $r('app.media.ic_song'))
          .width(32)
          .height(32)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .margin({ left: 12, right: 8 })
          .fillColor(this.vm.artworkPath.length > 0 ? Color.Transparent : $r('app.color.font_light'))

        Text(this.vm.title)
          .fontSize(13)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.MARQUEE })
          .layoutWeight(1)
          .margin({ right: 4 })

        Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 4 })
          .onClick(() => PlaybackService.togglePlay())

        Image($r('app.media.ic_player_next'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 4 })
          .onClick(() => PlaybackService.next())
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .borderRadius(22)
      .onClick(() => NavController.push('AudioPlayer'))
    }
  }
}
