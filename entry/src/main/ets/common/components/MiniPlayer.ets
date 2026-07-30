import { PlayState } from '../models/MediaModels';
import { PlaybackService, PlaybackListener } from '../data/PlaybackService';
import { NavController } from '../data/NavController';
import { AppColors } from '../constants/AppConstants';

/**
 * MiniPlayer —— 全局音频迷你播放条(对应 Android PlaybackService.getMiniPlayer 控件)。
 * 展示当前曲目标题 + 进度细条 + play/pause + next;整行点击进入 AudioPlayer。
 * 无媒体时不渲染(可见性由 VM 据 getCurrent()!=null 控制)。
 */
@ObservedV2
class MiniPlayerVM implements PlaybackListener {
  @Trace title: string = '';
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace state: PlayState = PlayState.IDLE;
  @Trace hasCurrent: boolean = false;

  refresh(): void {
    const item = PlaybackService.getInstance().getCurrent();
    this.hasCurrent = item !== null;
    if (item) {
      this.title = item.title;
      this.duration = PlaybackService.getInstance().getDuration();
      this.position = PlaybackService.getInstance().getPosition();
      this.state = PlaybackService.getInstance().getState();
    } else {
      this.title = '';
      this.duration = 0;
      this.position = 0;
    }
  }

  isPlaying(): boolean {
    return this.state === PlayState.PLAYING;
  }

  onStateChange(state: PlayState): void {
    this.state = state;
    this.refresh();
  }

  onTimeUpdate(current: number, duration: number): void {
    this.position = current;
    this.duration = duration;
  }

  onQueueChanged(): void {
    this.refresh();
  }
}

@ComponentV2
export struct MiniPlayer {
  @Local vm: MiniPlayerVM = new MiniPlayerVM();

  aboutToAppear(): void {
    PlaybackService.getInstance().addListener(this.vm);
    this.vm.refresh();
  }

  aboutToDisappear(): void {
    PlaybackService.getInstance().removeListener(this.vm);
  }

  build() {
    if (this.vm.hasCurrent) {
      Column() {
        // 内容行:标题(带进度细条)+ play/pause + next
        Row() {
          Text(this.vm.title)
            .fontSize(14)
            .fontColor(AppColors.white)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 12, right: 8 })

          Image(this.vm.isPlaying() ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.white)
            .margin({ right: 8 })
            .onClick(() => PlaybackService.getInstance().togglePlay())

          Image($r('app.media.ic_player_next'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.white)
            .margin({ right: 12 })
            .onClick(() => PlaybackService.getInstance().next())
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)

        // 进度细条(position 占 duration 的比例)
        Progress({
          value: this.vm.duration > 0 ? (this.vm.position / this.vm.duration) * 100 : 0,
          total: 100,
          type: ProgressType.Linear,
        })
          .width('100%')
          .height(2)
          .color(AppColors.orange500)
          .backgroundColor(AppColors.grey800)
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.dark_background)
      .onClick(() => NavController.push('AudioPlayer'))
    }
  }
}
