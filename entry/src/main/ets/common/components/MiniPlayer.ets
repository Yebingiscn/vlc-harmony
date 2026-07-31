import { PlayState } from '../models/MediaModels';
import { PlaybackService, PlaybackState, PlaybackListener } from '../data/PlaybackService';
import { NavController } from '../data/NavController';
import { AppColors } from '../constants/AppConstants';

@ObservedV2
class MiniPlayerVM implements PlaybackListener {
  @Trace title: string = '';
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace state: PlayState = PlayState.IDLE;
  @Trace hasCurrent: boolean = false;

  onChange(s: PlaybackState): void {
    this.title = s.title;
    this.duration = s.duration;
    this.position = s.position;
    this.state = s.state;
    this.hasCurrent = s.queueSize > 0 && s.currentIndex >= 0;
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
            .fontSize(14).fontColor(AppColors.white).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .margin({ left: 12, right: 8 })

          Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
            .width(32).height(32).objectFit(ImageFit.Contain).fillColor(AppColors.white)
            .margin({ right: 8 })
            .onClick(() => PlaybackService.togglePlay())

          Image($r('app.media.ic_player_next')).width(32).height(32)
            .objectFit(ImageFit.Contain).fillColor(AppColors.white).margin({ right: 12 })
            .onClick(() => PlaybackService.next())
        }
        .width('100%').height(48).alignItems(VerticalAlign.Center)

        Progress({
          value: this.vm.duration > 0 ? Math.round(this.vm.position * 100 / this.vm.duration) : 0,
          total: 100, type: ProgressType.Linear
        })
          .width('100%').height(2).color('#FF8800').backgroundColor('#424242')
          .visibility(this.vm.hasCurrent ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')
      .backgroundColor(AppColors.black_transparent_80)
      .onClick(() => NavController.push('AudioPlayer'))
    }
  }
}
