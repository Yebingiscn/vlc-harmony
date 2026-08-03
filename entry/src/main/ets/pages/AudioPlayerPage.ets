import { PlaybackService, PlaybackState } from '../common/data/PlaybackService';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { NavController } from '../common/data/NavController';
import { PlayState, formatDuration } from '../common/models/MediaModels';
import { AppColors } from '../common/constants/AppConstants';
import { PlaybackSpeedDialog } from './PlaybackSpeedDialog';
import { EqualizerDialog } from './EqualizerDialog';
import { promptAction } from '@kit.ArkUI';

/**
 * AudioPlayerPage —— 音频播放详情页。
 * 封面 + 曲目标题/艺术家 + 时间轴 + 控制按钮。
 * 绑定 PlaybackService 事件驱动。
 */
@ObservedV2
class AudioPlayerViewModel {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace title: string = '';
  @Trace artist: string = '';
  @Trace artworkPath: string = '';
  @Trace shuffle: boolean = false;
  @Trace repeatMode: number = 0;
  @Trace speed: number = 1.0;

  private listenerId: number = 0;
  private lastRecordedUri: string = '';

  attach(): void {
    this.listenerId = setInterval(() => {
      const s: PlaybackState = PlaybackService.snapshot();
      const prev = this.state;
      this.state = s.state;
      this.duration = s.duration;
      this.position = s.position;
      this.title = s.title;
      this.artist = s.artist;
      this.artworkPath = s.artworkPath;
      this.shuffle = s.shuffle;
      this.repeatMode = s.repeatMode;
      this.speed = s.speed;
      // 记录播放历史:状态转为 PLAYING 且非重复记录同一曲目
      if (s.state === PlayState.PLAYING && prev !== PlayState.PLAYING && this.title.length > 0) {
        const cur = PlaybackService.getCurrent();
        const uri = cur ? cur.uri : '';
        if (uri.length > 0 && uri !== this.lastRecordedUri) {
          this.lastRecordedUri = uri;
          void PlaybackHistory.record(uri, this.title, s.duration, this.artworkPath);
        }
      }
    }, 300);
  }

  detach(): void {
    if (this.listenerId > 0) {
      clearInterval(this.listenerId);
      this.listenerId = 0;
    }
  }
}

@ComponentV2
export struct AudioPlayerPage {
  @Local vm: AudioPlayerViewModel = new AudioPlayerViewModel();
  @Local showSpeed: boolean = false;
  @Local showEq: boolean = false;

  aboutToAppear(): void {
    const s = PlaybackService.snapshot();
    this.vm.title = s.title;
    this.vm.artist = s.artist;
    this.vm.artworkPath = s.artworkPath;
    this.vm.duration = s.duration;
    this.vm.position = s.position;
    this.vm.state = s.state;
    this.vm.shuffle = s.shuffle;
    this.vm.repeatMode = s.repeatMode;
    this.vm.speed = s.speed;
    this.vm.attach();
  }

  aboutToDisappear(): void {
    this.vm.detach();
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor($r('app.color.list_title'))
            .onClick(() => NavController.pop())
          Text(this.vm.title).fontSize(16).fontColor($r('app.color.list_title')).layoutWeight(1).margin({ left: 8 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.ic_player_playqueue')).width(24).height(24).fillColor($r('app.color.list_title'))
            .onClick(() => promptAction.showToast({ message: $r('app.string.developing') }))
        }
        .width('100%').padding({ left: 12, right: 12, top: 32, bottom: 8 }).alignItems(VerticalAlign.Center)

        // chip 行:倍速 / 均衡器
        Row() {
          this.chip(this.vm.speed > 0 ? `${this.vm.speed.toFixed(2)}x` : '1.00x',
            () => { this.showSpeed = true; })
          this.chip($r('app.string.equalizer').toString(),
            () => { this.showEq = true; })
          Blank()
        }
        .width('100%').padding({ left: 12, right: 12, bottom: 8 })

        // 专辑封面
        Column() {
          Image(this.vm.artworkPath.length > 0 ? this.vm.artworkPath : $r('app.media.ic_song_big'))
            .width('70%')
            .aspectRatio(1)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })

        // 曲目标题 + 艺术家
        Column() {
          Text(this.vm.title)
            .fontSize(18).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 4 })
          Text(this.vm.artist.length > 0 ? this.vm.artist : '未知艺术家')
            .fontSize(14).fontColor($r('app.color.list_subtitle'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').padding({ left: 24, right: 24, bottom: 12 })
        .alignItems(HorizontalAlign.Center)

        // 时间轴
        Row() {
          Text(formatDuration(this.vm.position)).fontSize(12).fontColor($r('app.color.list_subtitle')).width(48)
          Slider({
            value: this.vm.duration > 0 ? this.vm.position * 100 / this.vm.duration : 0,
            min: 0, max: 100, step: 1, style: SliderStyle.OutSet,
          })
            .layoutWeight(1)
            .blockColor($r('app.color.orange500'))
            .selectedColor($r('app.color.orange500'))
            .trackColor($r('app.color.card_border'))
            .onChange((v: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                const seekMs = Math.floor(this.vm.duration * v / 100);
                PlaybackService.seek(seekMs);
              }
            })
          Text(formatDuration(this.vm.duration)).fontSize(12).fontColor($r('app.color.list_subtitle')).width(48).textAlign(TextAlign.End)
        }
        .width('100%').padding({ left: 12, right: 12, bottom: 12 }).alignItems(VerticalAlign.Center)

        // 控制按钮行
        Row() {
          Image($r('app.media.ic_shuffle_audio')).width(28).height(28)
            .fillColor(this.vm.shuffle ? $r('app.color.orange500') : $r('app.color.list_title'))
            .onClick(() => PlaybackService.toggleShuffle())
          Blank()
          Image($r('app.media.ic_player_previous')).width(40).height(40).fillColor($r('app.color.list_title'))
            .onClick(() => PlaybackService.prev())
          Blank()
          Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
            .width(64).height(64).fillColor($r('app.color.orange500'))
            .onClick(() => PlaybackService.togglePlay())
          Blank()
          Image($r('app.media.ic_player_next')).width(40).height(40).fillColor($r('app.color.list_title'))
            .onClick(() => PlaybackService.next())
          Blank()
          Image(this.vm.repeatMode === 0 ? $r('app.media.ic_repeat_audio') :
            (this.vm.repeatMode === 2 ? $r('app.media.ic_repeat_one_audio') : $r('app.media.ic_repeat_all_audio')))
            .width(28).height(28)
            .fillColor(this.vm.repeatMode > 0 ? $r('app.color.orange500') : $r('app.color.list_title'))
            .onClick(() => PlaybackService.cycleRepeat())
        }
        .width('100%').padding({ left: 24, right: 24, top: 8, bottom: 32 }).alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
      .bindSheet(this.showSpeed, this.speedSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => { this.showSpeed = false; },
      })
      .bindSheet(this.showEq, this.eqSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => { this.showEq = false; },
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
      .fontColor($r('app.color.orange500'))
      .backgroundColor($r('app.color.orange_500_transparent_20'))
      .borderRadius(16)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => onTap())
  }

  @Builder
  speedSheet() {
    PlaybackSpeedDialog({ onClose: () => { this.showSpeed = false; } }).width('100%')
  }

  @Builder
  eqSheet() {
    EqualizerDialog({ onClose: () => { this.showEq = false; } }).width('100%')
  }
}
