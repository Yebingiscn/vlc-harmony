import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { PlaybackService, PlaybackListener } from '../common/data/PlaybackService';
import { Settings } from '../common/data/Settings';
import { PlayState, formatDuration } from '../common/models/MediaModels';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { SelectChapterDialog } from './SelectChapterDialog';
import { VideoTracksDialog } from './VideoTracksDialog';
import { RenderersDialog } from './RenderersDialog';

/** 与 Native / XComponent id 一致;libraryname 对齐 nm_modname=libvlcnapi。 */
export const VLC_VIDEO_XCOMPONENT_ID: string = 'vlc_video_surface';
export const VLC_NAPI_LIBRARY: string = 'libvlcnapi';

export interface VideoParam {
  uri: string;
  title: string;
}

/**
 * 在容器内按视频原始宽高比做 contain 适配(不拉伸)。
 * 返回显示宽高(vp)。
 */
export function fitContain(
  containerW: number,
  containerH: number,
  videoW: number,
  videoH: number
): [number, number] {
  if (containerW <= 0 || containerH <= 0) {
    return [containerW, containerH];
  }
  if (videoW <= 0 || videoH <= 0) {
    return [containerW, containerH];
  }
  const videoAspect = videoW / videoH;
  const viewAspect = containerW / containerH;
  if (videoAspect > viewAspect) {
    // 视频更宽 → 以宽为基准,上下留黑边
    return [containerW, containerW / videoAspect];
  }
  // 视频更高 → 以高为基准,左右留黑边
  return [containerH * videoAspect, containerH];
}

/**
 * VideoPlayerPage —— 全屏视频播放器。
 * XComponent 按原始视频比例 contain 居中,背景黑边 letterbox/pillarbox。
 */
@ObservedV2
class VideoPlayerViewModel implements PlaybackListener {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace hudVisible: boolean = true;
  @Trace speed: number = 1.0;
  @Trace title: string = '';
  /** 视频原始像素 */
  @Trace videoWidth: number = 0;
  @Trace videoHeight: number = 0;
  /** 容器(全屏 Stack)尺寸 */
  @Trace containerWidth: number = 0;
  @Trace containerHeight: number = 0;
  /** contain 后的 XComponent 显示尺寸 */
  @Trace surfaceWidth: number = 0;
  @Trace surfaceHeight: number = 0;
  uri: string = '';
  private listening: boolean = false;
  /** 已发起离开停播(对标 Android playbackStarted=false / isFinishing)。 */
  private leaving: boolean = false;

  async setup(uri: string, title: string, xcomponentId: string): Promise<void> {
    this.leaving = false;
    hilog.info(0x0001, 'VLC',
      '[VLC] VideoPlayer.setup uri=%{public}s title=%{public}s xc=%{public}s',
      uri, title, xcomponentId);
    this.uri = uri;
    this.title = title;
    const svc = PlaybackService.getInstance();
    if (!this.listening) {
      svc.addListener(this);
      this.listening = true;
    }
    this.state = svc.getState();
    this.duration = svc.getDuration();
    this.position = svc.getPosition();
    // 若队列项已有元数据尺寸,先排版
    const cur = svc.getCurrent();
    if (cur && cur.width > 0 && cur.height > 0) {
      this.onVideoSize(cur.width, cur.height);
    } else if (svc.getVideoWidth() > 0) {
      this.onVideoSize(svc.getVideoWidth(), svc.getVideoHeight());
    }
    const savedSpeed = await Settings.getFloat(Settings.VIDEO_SPEED, 1.0);
    this.speed = savedSpeed;
    svc.setSpeed(savedSpeed);

    const bound = await svc.bindAndPlay(xcomponentId, uri, title);
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.bindAndPlay done bound=%{public}s state=%{public}s',
      String(bound), String(this.state));
  }

  onStateChange(state: PlayState): void {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer state=%{public}s', String(state));
    this.state = state;
    if (state === PlayState.PLAYING) {
      PlaybackService.getInstance().refreshVideoSize();
    }
  }

  onTimeUpdate(current: number, duration: number): void {
    this.position = current;
    this.duration = duration;
  }

  onQueueChanged(): void {
    const cur = PlaybackService.getInstance().getCurrent();
    if (cur) {
      this.uri = cur.uri;
      this.title = cur.title;
      if (cur.width > 0 && cur.height > 0) {
        this.onVideoSize(cur.width, cur.height);
      }
    }
  }

  onVideoSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    this.videoWidth = width;
    this.videoHeight = height;
    this.recomputeSurface();
  }

  onContainerSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    this.containerWidth = width;
    this.containerHeight = height;
    this.recomputeSurface();
  }

  private recomputeSurface(): void {
    const result = fitContain(
      this.containerWidth,
      this.containerHeight,
      this.videoWidth,
      this.videoHeight
    );
    this.surfaceWidth = result[0];
    this.surfaceHeight = result[1];
    hilog.info(0x0001, 'VLC',
      '[VLC] contain container=%{public}sx%{public}s video=%{public}sx%{public}s surface=%{public}sx%{public}s',
      String(this.containerWidth), String(this.containerHeight),
      String(this.videoWidth), String(this.videoHeight),
      String(Math.round(result[0])), String(Math.round(result[1])));
  }

  toggle(): void {
    PlaybackService.getInstance().togglePlay();
    this.hudVisible = true;
  }

  seekTo(ms: number): void {
    PlaybackService.getInstance().seek(ms);
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    PlaybackService.getInstance().setSpeed(rate);
    Settings.put(Settings.VIDEO_SPEED, rate);
  }

  next(): void {
    PlaybackService.getInstance().next(false);
  }

  prev(): void {
    PlaybackService.getInstance().prev();
  }

  /**
   * 对齐 Android onPause(isFinishing): 尽早 stop,避免返回动画期间 vout 出错/主线程卡死。
   * 在 onBackPressed / 返回按钮里、pop 之前调用。
   */
  leaveEarly(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    if (this.listening) {
      PlaybackService.getInstance().removeListener(this);
      this.listening = false;
    }
    PlaybackService.getInstance().stop();
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.leaveEarly/stop (onPause finishing)');
  }

  /**
   * 对齐 Android onStop: cleanUI(detach) + 兜底 stop。
   * 在 aboutToDisappear / XComponent.onDestroy 调用。
   */
  cleanUI(): void {
    PlaybackService.getInstance().detachViews();
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.cleanUI/detachViews');
  }

  release(): void {
    if (!this.leaving) {
      this.leaveEarly();
    }
    this.cleanUI();
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.release (onStop)');
  }
}

@ComponentV2
export struct VideoPlayerPage {
  @Local vm: VideoPlayerViewModel = new VideoPlayerViewModel();
  @Param param: VideoParam = { uri: '', title: '' };
  private hudTimer: number = -1;
  private surfaceStarted: boolean = false;

  @Local sheetOpen: boolean = false;
  @Local sheetKind: string = '';

  openOptions(): void {
    this.sheetKind = '';
    this.sheetOpen = true;
  }

  openSub(kind: string): void {
    this.sheetKind = kind;
    this.sheetOpen = true;
  }

  onJumpConfirm(timeMs: number): void {
    this.vm.seekTo(timeMs);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onSleepConfirm(): void {
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onChapterSelect(index: number): void {
    PlaybackService.getInstance().setChapter(index);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onTrackSelect(id: number, type: string): void {
    const svc = PlaybackService.getInstance();
    if (type === 'audio') {
      svc.setAudioTrack(id);
    } else if (type === 'spu') {
      svc.setSpuTrack(id);
    } else if (type === 'video') {
      svc.setVideoTrack(id);
    }
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onRendererConnect(id: number): void {
    PlaybackService.getInstance().setRenderer(id);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onRendererDisconnect(): void {
    PlaybackService.getInstance().clearRenderer();
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  aboutToAppear(): void {
    this.resetHudTimer();
  }

  aboutToDisappear(): void {
    this.vm.release();
  }

  resetHudTimer(): void {
    this.vm.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      if (this.vm.state === PlayState.PLAYING) {
        this.vm.hudVisible = false;
      }
    }, 4000);
  }

  private onSurfaceLoad(): void {
    if (this.surfaceStarted) {
      hilog.warn(0x0001, 'VLC', '[VLC] XComponent onLoad duplicate ignored');
      return;
    }
    this.surfaceStarted = true;
    hilog.info(0x0001, 'VLC',
      '[VLC] XComponent.onLoad id=%{public}s library=%{public}s',
      VLC_VIDEO_XCOMPONENT_ID, VLC_NAPI_LIBRARY);
    this.vm.setup(this.param.uri, this.param.title, VLC_VIDEO_XCOMPONENT_ID);
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // contain 后的 Surface 居中;未拿到尺寸前先铺满,拿到后按比例收缩
        XComponent({
          id: VLC_VIDEO_XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: VLC_NAPI_LIBRARY,
        })
          .onLoad(() => this.onSurfaceLoad())
          .onDestroy(() => {
            hilog.info(0x0001, 'VLC', '[VLC] XComponent.onDestroy');
            // 对齐 Android onStop cleanUI: Surface 销毁时 detach
            this.vm.cleanUI();
            this.surfaceStarted = false;
          })
          .width(this.vm.surfaceWidth > 0 ? this.vm.surfaceWidth : '100%')
          .height(this.vm.surfaceHeight > 0 ? this.vm.surfaceHeight : '100%')
          .onClick(() => this.resetHudTimer())

        if (this.vm.hudVisible) {
          Column() {
            Row() {
              Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor('#FFFFFF')
                .onClick(() => {
                  this.vm.leaveEarly();
                  NavController.pop();
                })
              Text(this.vm.title).fontSize(18).fontColor('#FFFFFF').layoutWeight(1).margin({ left: 12 })
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Image($r('app.media.ic_player_more')).width(24).height(24).fillColor('#FFFFFF')
                .onClick(() => this.openOptions())
            }
            .width('100%').padding(12).alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .linearGradient({ angle: 90, colors: [['#cb000000', 0.0], ['#00000000', 1.0]] })
          .align(Alignment.Top)

          Column() {
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
                    this.vm.seekTo(Math.floor(this.vm.duration * v / 100));
                  }
                })
              Text(formatDuration(this.vm.duration - this.vm.position >= 0 ? this.vm.duration - this.vm.position : 0))
                .fontSize(12).fontColor('#FFFFFF').width(56).textAlign(TextAlign.End)
            }
            .width('100%').padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center)

            Row() {
              Image($r('app.media.ic_player_rewind_10')).width(36).height(36).fillColor('#FFFFFF')
                .onClick(() => this.vm.seekTo(Math.max(0, this.vm.position - 10000)))
              Blank()
              Image($r('app.media.ic_player_previous')).width(40).height(40).fillColor('#FFFFFF')
                .onClick(() => this.vm.prev())
              Blank()
              Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
                .width(56).height(56).fillColor('#FFFFFF')
                .onClick(() => this.vm.toggle())
              Blank()
              Image($r('app.media.ic_player_next')).width(40).height(40).fillColor('#FFFFFF')
                .onClick(() => this.vm.next())
              Blank()
              Image($r('app.media.ic_player_forward_10')).width(36).height(36).fillColor('#FFFFFF')
                .onClick(() => this.vm.seekTo(Math.min(this.vm.duration, this.vm.position + 10000)))
            }
            .width('100%').padding(12).alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .linearGradient({ angle: 270, colors: [['#cb000000', 0.0], ['#00000000', 1.0]] })
          .align(Alignment.Bottom)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onAreaChange((_old: Area, area: Area) => {
        const w = Number(area.width);
        const h = Number(area.height);
        this.vm.onContainerSize(w, h);
      })
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      // 对齐 Android onPause(isFinishing) 尽早 stop,再 pop
      this.vm.leaveEarly();
      NavController.pop();
      return true;
    })
    .bindSheet(this.sheetOpen, this.playerSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => {
        this.sheetOpen = false;
        this.sheetKind = '';
      },
    })
  }

  @Builder
  playerSheet() {
    Column() {
      if (this.sheetKind === '') {
        this.optionsList()
      } else if (this.sheetKind === 'jump') {
        JumpToTimeDialog({
          onClose: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
          onConfirm: (timeMs: number) => this.onJumpConfirm(timeMs),
        }).width('100%')
      } else if (this.sheetKind === 'sleep') {
        SleepTimerDialog({
          onClose: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
          onConfirm: (_millis: number, _waitForMediaEnd: boolean, _resetOnInteraction: boolean) => {
            this.onSleepConfirm();
          },
        }).width('100%')
      } else if (this.sheetKind === 'chapter') {
        SelectChapterDialog({
          onClose: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
          onSelectChapter: (index: number) => this.onChapterSelect(index),
        }).width('100%')
      } else if (this.sheetKind === 'tracks') {
        VideoTracksDialog({
          onClose: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
          onTrackSelect: (id: number, type: string) => this.onTrackSelect(id, type),
        }).width('100%')
      } else if (this.sheetKind === 'renderer') {
        RenderersDialog({
          onClose: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
          onConnect: (id: number) => this.onRendererConnect(id),
          onDisconnect: () => this.onRendererDisconnect(),
        }).width('100%')
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
  }

  @Builder
  optionsList() {
    Column() {
      Text($r('app.string.more'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .height(56)
        .margin({ left: 16, top: 8 })
        .textAlign(TextAlign.Start)

      this.optionRow('Jump to time', () => this.openSub('jump'))
      this.optionRow('Sleep timer', () => this.openSub('sleep'))
      this.optionRow($r('app.string.go_to_chapter'), () => this.openSub('chapter'))
      this.optionRow('Audio & Subtitles tracks', () => this.openSub('tracks'))
      this.optionRow('Displays', () => this.openSub('renderer'))
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  optionRow(title: ResourceStr, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
        .margin({ left: 16, right: 16 })
      Image($r('app.media.ic_arrow_right'))
        .width(20).height(20)
        .fillColor('#9E9E9E')
        .margin({ right: 16 })
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick(() => onTap())
  }
}
