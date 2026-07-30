import { PlaybackService, PlaybackListener } from '../common/data/PlaybackService';
import { NavController } from '../common/data/NavController';
import { PlayState, formatDuration } from '../common/models/MediaModels';
import { AppColors } from '../common/constants/AppConstants';
import { PlaybackSpeedDialog } from './PlaybackSpeedDialog';
import { EqualizerDialog } from './EqualizerDialog';
import { promptAction } from '@kit.ArkUI';

/**
 * AudioPlayerPage —— AudioPlayer(底部播放面板,封面态为主)。
 * 头部媒体标题 + 倍速/睡眠 chip + AB 重复标记 + 封面 + 时间轴 + 控制按钮。
 * 绑定 PlaybackService(AVPlayer)事件驱动。
 */
@ObservedV2
class AudioPlayerViewModel implements PlaybackListener {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace title: string = '';
  @Trace shuffle: boolean = false;
  @Trace repeatMode: number = 0;
  @Trace speed: number = 1.0;

  onStateChange(state: PlayState): void {
    this.state = state;
  }

  onTimeUpdate(current: number, duration: number): void {
    this.position = current;
    this.duration = duration;
  }

  onQueueChanged(): void {
    const cur = PlaybackService.getInstance().getCurrent();
    if (cur) {
      this.title = cur.title;
    }
    this.shuffle = PlaybackService.getInstance().getShuffle();
    this.repeatMode = PlaybackService.getInstance().getRepeatMode();
    this.speed = PlaybackService.getInstance().getSpeed();
  }
}

@ComponentV2
export struct AudioPlayerPage {
  @Local vm: AudioPlayerViewModel = new AudioPlayerViewModel();
  @Local showSpeed: boolean = false;
  @Local showEq: boolean = false;

  aboutToAppear(): void {
    PlaybackService.getInstance().addListener(this.vm);
    this.vm.onQueueChanged();
  }

  aboutToDisappear(): void {
    PlaybackService.getInstance().removeListener(this.vm);
  }

  build() {
    NavDestination() {
      Column() {
        // 头部:返回 + 标题 + 列表/封面切换
        Row() {
          Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor('#FFFFFF')
            .onClick(() => NavController.pop())
          Text(this.vm.title).fontSize(16).fontColor('#FFFFFF').layoutWeight(1).margin({ left: 8 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.ic_player_playqueue')).width(24).height(24).fillColor('#FFFFFF')
            .onClick(() => promptAction.showToast({ message: $r('app.string.developing') }))
        }
        .width('100%').padding(12).alignItems(VerticalAlign.Center)

        // chip 行:倍速 / 睡眠 / AB
        Row() {
          this.chip(this.vm.speed > 0 ? `${this.vm.speed.toFixed(2)}x` : '1.00x',
            () => {
              this.showSpeed = true;
            })
          this.chip($r('app.string.equalizer').toString(),
            () => {
              this.showEq = true;
            })
          Blank()
        }
        .width('100%').padding({ left: 12, right: 12, bottom: 8 })

        // 封面
        Column() {
          Image($r('app.media.ic_song_big'))
            .width('60%')
            .aspectRatio(1)
            .objectFit(ImageFit.Contain)
            .fillColor('#424242')
            .borderRadius(4)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        // 时间轴
        Row() {
          Text(formatDuration(this.vm.position)).fontSize(12).fontColor('#FFFFFF').width(56)
          Slider({
            value: this.vm.duration > 0 ? this.vm.position * 100 / this.vm.duration : 0,
            min: 0, max: 100, step: 1, style: SliderStyle.OutSet,
          })
            .layoutWeight(1)
            .blockColor('#FF8800')
            .selectedColor('#FF8800')
            .trackColor('#424242')
            .onChange((v: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                PlaybackService.getInstance().seek(Math.floor(this.vm.duration * v / 100));
              }
            })
          Text(formatDuration(this.vm.duration)).fontSize(12).fontColor('#FFFFFF').width(56).textAlign(TextAlign.End)
        }
        .width('100%').padding({ left: 8, right: 8, bottom: 8 }).alignItems(VerticalAlign.Center)

        // 控制按钮行
        Row() {
          Image($r('app.media.ic_shuffle_audio')).width(28).height(28)
            .fillColor(this.vm.shuffle ? '#FF8800' : '#FFFFFF')
            .onClick(() => PlaybackService.getInstance().toggleShuffle())
          Blank()
          Image($r('app.media.ic_player_previous')).width(40).height(40).fillColor('#FFFFFF')
            .onClick(() => PlaybackService.getInstance().prev())
          Blank()
          Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
            .width(64).height(64).fillColor('#FFFFFF')
            .onClick(() => PlaybackService.getInstance().togglePlay())
          Blank()
          Image($r('app.media.ic_player_next')).width(40).height(40).fillColor('#FFFFFF')
            .onClick(() => PlaybackService.getInstance().next())
          Blank()
          Image(this.vm.repeatMode === 0 ? $r('app.media.ic_repeat_audio') :
            (this.vm.repeatMode === 2 ? $r('app.media.ic_repeat_one_audio') : $r('app.media.ic_repeat_all_audio')))
            .width(28).height(28)
            .fillColor(this.vm.repeatMode > 0 ? '#FF8800' : '#FFFFFF')
            .onClick(() => PlaybackService.getInstance().cycleRepeat())
        }
        .width('100%').padding({ left: 24, right: 24, top: 8, bottom: 24 }).alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.dark_background)
      .bindSheet(this.showSpeed, this.speedSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => {
          this.showSpeed = false;
        },
      })
      .bindSheet(this.showEq, this.eqSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => {
          this.showEq = false;
        },
      })
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  @Builder
  chip(label: string, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor('#FFFFFF')
      .backgroundColor('#33FF8800')
      .borderRadius(16)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => onTap())
  }

  @Builder
  speedSheet() {
    PlaybackSpeedDialog({ onClose: () => {
      this.showSpeed = false;
    } }).width('100%')
  }

  @Builder
  eqSheet() {
    EqualizerDialog({ onClose: () => {
      this.showEq = false;
    } }).width('100%')
  }
}
