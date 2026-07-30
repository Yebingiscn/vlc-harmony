import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { PlayState, formatDuration } from '../common/models/MediaModels';
import { AppColors } from '../common/constants/AppConstants';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { SelectChapterDialog } from './SelectChapterDialog';
import { VideoTracksDialog } from './VideoTracksDialog';
import { RenderersDialog } from './RenderersDialog';

export interface VideoParam {
  uri: string;
  title: string;
}

/**
 * VideoPlayerPage —— VideoPlayerActivity(全屏视频播放器)。
 * 视频画面铺底(AVPlayer + XComponent surface)+ 顶/底 HUD + seek 手势 + 倍速。
 * 能力替换约定:libVLC → @kit.MediaKit AVPlayer(videoSurfaceId 绑 XComponent)。
 * 状态机事件驱动(对齐 harmonyos-avplayer 手册)。
 */
@ObservedV2
class VideoPlayerViewModel {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace hudVisible: boolean = true;
  @Trace speed: number = 1.0;
  @Trace title: string = '';
  uri: string = '';
  player: media.AVPlayer | null = null;
  surfaceId: string = '';

  async setup(uri: string, title: string, surfaceId: string): Promise<void> {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer setup: uri=%{public}s surfaceId=%{public}s', uri, surfaceId);
    this.uri = uri;
    this.title = title;
    this.surfaceId = surfaceId;
    if (!this.player) {
      this.player = await media.createAVPlayer();
      this.player.on('stateChange', (s: string) => this.onState(s));
      this.player.on('timeUpdate', (t: number) => {
        this.position = t;
      });
      this.player.on('durationUpdate', (d: number) => {
        this.duration = d;
      });
    }
    this.player.surfaceId = surfaceId;
    const savedSpeed = await Settings.getFloat(Settings.VIDEO_SPEED, 1.0);
    this.speed = savedSpeed;
    // photoAccessHelper URI(file://media/Photo/...)用 fdSrc 打开(AVPlayer 的 .url 可能解析不了)。
    // fdSrc 设定后 AVPlayer 异步进 initialized;prepare 在 onState('initialized') 里调(状态机铁律)。
    try {
      const f = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      this.player.fdSrc = { fd: f.fd, offset: 0, length: -1 };
      hilog.info(0x0001, 'VLC', '[VLC] fdSrc set (fd=%{public}d), waiting for initialized...', f.fd);
    } catch (e) {
      // 回退:直接用 url
      this.player.url = uri;
      hilog.info(0x0001, 'VLC', '[VLC] openSync fail, fallback to url: %{public}s', (e as Error).message ?? String(e));
    }
  }

  private onState(s: string): void {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer state: %{public}s', s);
    switch (s) {
      case 'initialized':
        // AVPlayer 进入 initialized → 此时才能调 prepare()(状态机铁律)。
        this.player!.prepare();
        break;
      case 'prepared':
        // prepare 完成 → 开始播放。
        this.state = PlayState.PREPARED;
        this.player!.play();
        break;
      case 'playing':
        this.state = PlayState.PLAYING;
        this.player!.setSpeed(VideoPlayerViewModel.toPlaybackSpeed(this.speed));
        break;
      case 'paused':
        this.state = PlayState.PAUSED;
        break;
      case 'error':
        this.state = PlayState.ERROR;
        break;
      case 'completed':
        this.state = PlayState.STOPPED;
        break;
      default:
        break;
    }
  }

  toggle(): void {
    if (!this.player) {
      return;
    }
    if (this.state === PlayState.PLAYING) {
      this.player.pause();
    } else {
      this.player.play();
    }
    this.hudVisible = true;
  }

  seekTo(ms: number): void {
    if (this.player) {
      this.player.seek(ms);
    }
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    if (this.player) {
      this.player.setSpeed(VideoPlayerViewModel.toPlaybackSpeed(rate));
    }
    Settings.put(Settings.VIDEO_SPEED, rate);
  }

  /** 数值倍速 → AVPlayer PlaybackSpeed 枚举(最近档位)。 */
  private static toPlaybackSpeed(rate: number): media.PlaybackSpeed {
    if (rate <= 0.875) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (rate <= 1.125) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
    if (rate <= 1.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    if (rate <= 2.0) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    }
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }

  release(): void {
    if (this.player) {
      this.player.release();
      this.player = null;
    }
  }
}

@ComponentV2
export struct VideoPlayerPage {
  @Local vm: VideoPlayerViewModel = new VideoPlayerViewModel();
  @Param param: VideoParam = { uri: '', title: '' };
  private xComponentController: XComponentController = new XComponentController();
  private hudTimer: number = -1;

  /** 更多选项/二级弹窗的 sheet 状态。sheetKind 空串=主选项列表;否则=对应二级弹窗。 */
  @Local sheetOpen: boolean = false;
  @Local sheetKind: string = ''; // '' | 'jump' | 'sleep' | 'chapter' | 'tracks' | 'renderer'

  /** 打开主选项列表。 */
  openOptions(): void {
    this.sheetKind = '';
    this.sheetOpen = true;
  }

  /** 进入指定二级弹窗(切换 sheetKind,保持 sheet 展开)。 */
  openSub(kind: string): void {
    this.sheetKind = kind;
    this.sheetOpen = true;
  }

  /** Jump to Time 确认 → AVPlayer seek(timeMs) 可落地;弹窗关闭。 */
  onJumpConfirm(timeMs: number): void {
    this.vm.seekTo(timeMs);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** Sleep timer 确认:定时动作体依赖 libVLC 媒体引擎契约,保留 TODO。 */
  onSleepConfirm(): void {
    // TODO(libVLC 契约): 写入睡眠定时器(waitBeforeSleep / resetOnInteraction 选项)+ 定时暂停;AVPlayer 无原生定时器接口。
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 章节选择:libVLC getChapters 契约,保留 TODO。 */
  onChapterSelect(index: number): void {
    // TODO(libVLC 契约): playbackService.chapterIdx = index;当前 AVPlayer 无章节概念。
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 音轨/字幕/视频轨切换:libVLC 轨道契约,保留 TODO。 */
  onTrackSelect(id: number, type: string): void {
    // TODO(libVLC 契约): 按 type(audio/spu/video) 切换 PlaybackService 轨道;AVPlayer 无多轨切换接口。
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 投屏渲染器:libVLC renderer 契约,保留 TODO。 */
  onRendererConnect(id: number): void {
    // TODO(libVLC 契约): PlaybackService.renderer.value = 连接的 renderer item;需 RendererDelegate。
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onRendererDisconnect(): void {
    // TODO(libVLC 契约): PlaybackService.renderer.value = null(断开)。
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

  build() {
    NavDestination() {
      Stack() {
        // 视频画面铺底
        XComponent({ id: 'vlc_video_surface', type: XComponentType.SURFACE, controller: this.xComponentController })
          .onLoad(() => {
            const sid = this.xComponentController.getXComponentSurfaceId();
            this.vm.setup(this.param.uri, this.param.title, sid);
          })
          .width('100%')
          .height('100%')
          .onClick(() => this.resetHudTimer())

        // 顶部信息 HUD(线性渐变 #cb000000→transparent)
        if (this.vm.hudVisible) {
          Column() {
            Row() {
              Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor('#FFFFFF')
                .onClick(() => NavController.pop())
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

          // 底部控制 HUD
          Column() {
            // seek bar
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

            // 控制按钮行
            Row() {
              Image($r('app.media.ic_player_rewind_10')).width(36).height(36).fillColor('#FFFFFF')
                .onClick(() => this.vm.seekTo(Math.max(0, this.vm.position - 10000)))
              Blank()
              Image($r('app.media.ic_player_previous')).width(40).height(40).fillColor('#FFFFFF')
              Blank()
              Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
                .width(56).height(56).fillColor('#FFFFFF')
                .onClick(() => this.vm.toggle())
              Blank()
              Image($r('app.media.ic_player_next')).width(40).height(40).fillColor('#FFFFFF')
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
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
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

  /** 更多选项 / 二级弹窗统一 sheet:sheetKind 决定渲染哪一层。 */
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
          onDeleteCurrent: () => {
            // TODO(libVLC 契约): 清除已设睡眠定时器。
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

  /** 主选项列表(Jump to time / Sleep timer / Chapters / Audio&Subtitles / Displays)。 */
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

  /** 选项单行(标题 + 右箭头,高 52vp,点击回调)。 */
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
