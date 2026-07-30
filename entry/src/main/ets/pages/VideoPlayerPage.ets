import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { PlayState } from '../common/models/MediaModels';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { SelectChapterDialog } from './SelectChapterDialog';
import { VideoTracksDialog } from './VideoTracksDialog';
import { RenderersDialog } from './RenderersDialog';

/** 播放队列中的一项(仅携带播放器需要的字段,避免把整个 MediaWrapper 塞进路由参数)。 */
export interface VideoPlayItem {
  uri: string;
  title: string;
}

export interface VideoParam {
  uri: string;
  title: string;
  /** 可选:所在列表,用于上一个/下一个。 */
  list?: VideoPlayItem[];
  /** 可选:uri 在 list 中的下标。 */
  index?: number;
}

/** 播放器专用时长格式化:0 显示 00:00(MediaModels.formatDuration 对 0 返回空串,列表页需要,播放器不需要)。 */
function fmtTime(ms: number): string {
  const safe = ms > 0 ? ms : 0;
  const totalSec = Math.floor(safe / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/**
 * VideoPlayerPage —— VideoPlayerActivity(全屏视频播放器)。
 * 视频画面铺底(AVPlayer + XComponent surface)+ 顶/底 HUD + seek + 倍速。
 * 能力替换约定:libVLC → @kit.MediaKit AVPlayer(surfaceId 绑 XComponent)。
 *
 * 【状态机铁律】surfaceId 必须在 'initialized' 状态下、prepare() 之前设置。
 * 在 idle 状态(设置 fdSrc/url 之前)赋值不会生效,表现为"有声无画"。
 */
@ObservedV2
class VideoPlayerViewModel {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace hudVisible: boolean = true;
  @Trace speed: number = 1.0;
  @Trace title: string = '';
  @Trace errorMsg: string = '';
  @Trace index: number = 0;
  @Trace listLen: number = 1;

  uri: string = '';
  player: media.AVPlayer | null = null;
  surfaceId: string = '';
  private list: VideoPlayItem[] = [];
  private fd: number = -1;
  private released: boolean = false;

  hasPrev(): boolean {
    return this.index > 0;
  }

  hasNext(): boolean {
    return this.index < this.listLen - 1;
  }

  /** XComponent onLoad 后调用:创建播放器、注册回调、装载首个源。 */
  async setup(param: VideoParam, surfaceId: string): Promise<void> {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer setup: uri=%{public}s surfaceId=%{public}s', param.uri, surfaceId);
    this.surfaceId = surfaceId;
    // ArkTS 严格模式:不要用 `param.list && ...` 这种非 boolean 短路做条件。
    const incoming: VideoPlayItem[] = param.list !== undefined ? param.list : [];
    if (incoming.length > 0) {
      this.list = incoming;
    } else {
      const single: VideoPlayItem = { uri: param.uri, title: param.title };
      this.list = [single];
    }
    this.index = param.index !== undefined && param.index >= 0 && param.index < this.list.length ? param.index : 0;
    this.listLen = this.list.length;
    this.uri = this.list[this.index].uri;
    this.title = this.list[this.index].title;

    this.speed = await Settings.getFloat(Settings.VIDEO_SPEED, 1.0);

    if (!this.player) {
      this.player = await media.createAVPlayer();
      // 页面在 createAVPlayer 期间被销毁 → 直接回收,避免野播放器。
      if (this.released) {
        this.player.release();
        this.player = null;
        return;
      }
      this.player.on('stateChange', (s: string) => this.onState(s));
      this.player.on('timeUpdate', (t: number) => {
        this.position = t;
      });
      this.player.on('durationUpdate', (d: number) => {
        this.duration = d;
      });
      this.player.on('error', (err: BusinessError) => {
        this.state = PlayState.ERROR;
        this.errorMsg = `${err.code}: ${err.message}`;
        hilog.error(0x0001, 'VLC', '[VLC] AVPlayer error %{public}d %{public}s', err.code, err.message);
      });
    }
    this.applySource();
  }

  /**
   * 装载媒体源。photoAccessHelper 的 file://media/Photo/... URI 用 fdSrc 打开最稳;
   * 打开失败再回退 url。设置源后 AVPlayer 异步进入 initialized。
   */
  private applySource(): void {
    if (!this.player) {
      return;
    }
    this.errorMsg = '';
    try {
      const file = fs.openSync(this.uri, fs.OpenMode.READ_ONLY);
      this.fd = file.fd;
      let len = -1;
      try {
        len = fs.statSync(file.fd).size;
      } catch (e) {
        len = -1;
      }
      this.player.fdSrc = { fd: file.fd, offset: 0, length: len };
      hilog.info(0x0001, 'VLC', '[VLC] fdSrc set fd=%{public}d len=%{public}d', file.fd, len);
    } catch (e) {
      const msg = (e as BusinessError).message ?? String(e);
      hilog.warn(0x0001, 'VLC', '[VLC] openSync failed, fallback to url: %{public}s', msg);
      this.player.url = this.uri;
    }
  }

  private closeFd(): void {
    if (this.fd !== -1) {
      try {
        fs.closeSync(this.fd);
      } catch (e) {
        // 已关闭 → 忽略
      }
      this.fd = -1;
    }
  }

  private onState(s: string): void {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer state: %{public}s', s);
    if (!this.player) {
      return;
    }
    switch (s) {
      case 'initialized':
        // 【关键】surfaceId 只能在这里绑,且必须在 prepare() 之前。
        // 这两步一旦抛异常就再也走不到 prepared,必须兜住并落到 ERROR 态,否则页面永远停在转圈。
        try {
          this.player.surfaceId = this.surfaceId;
          this.player.prepare();
        } catch (e) {
          const err = e as BusinessError;
          this.state = PlayState.ERROR;
          this.errorMsg = `prepare ${err.code}: ${err.message}`;
          hilog.error(0x0001, 'VLC', '[VLC] prepare failed: %{public}s', err.message);
        }
        break;
      case 'prepared':
        this.state = PlayState.PREPARED;
        try {
          this.player.play();
        } catch (e) {
          const err = e as BusinessError;
          this.state = PlayState.ERROR;
          this.errorMsg = `play ${err.code}: ${err.message}`;
          hilog.error(0x0001, 'VLC', '[VLC] play failed: %{public}s', err.message);
        }
        break;
      case 'playing':
        this.state = PlayState.PLAYING;
        try {
          this.player.setSpeed(VideoPlayerViewModel.toPlaybackSpeed(this.speed));
        } catch (e) {
          // 倍速失败不影响播放本身,仅记录。
          hilog.warn(0x0001, 'VLC', '[VLC] setSpeed failed: %{public}s', (e as BusinessError).message);
        }
        break;
      case 'paused':
        this.state = PlayState.PAUSED;
        break;
      case 'error':
        this.state = PlayState.ERROR;
        break;
      case 'completed':
        this.state = PlayState.STOPPED;
        if (this.hasNext()) {
          this.playAt(this.index + 1);
        }
        break;
      default:
        break;
    }
  }

  /** 切到队列中第 i 项:reset() 回 idle,关旧 fd,再装载新源。 */
  async playAt(i: number): Promise<void> {
    if (!this.player || i < 0 || i >= this.list.length) {
      return;
    }
    this.index = i;
    this.uri = this.list[i].uri;
    this.title = this.list[i].title;
    this.position = 0;
    this.duration = 0;
    this.state = PlayState.IDLE;
    try {
      await this.player.reset();
    } catch (e) {
      hilog.error(0x0001, 'VLC', '[VLC] reset failed: %{public}s', (e as BusinessError).message ?? String(e));
      return;
    }
    this.closeFd();
    this.applySource();
  }

  next(): void {
    if (this.hasNext()) {
      this.playAt(this.index + 1);
    }
  }

  prev(): void {
    // 播放超过 3 秒时,"上一个"先回到本片开头(对齐 VLC 行为)。
    if (this.position > 3000) {
      this.seekTo(0);
    } else if (this.hasPrev()) {
      this.playAt(this.index - 1);
    }
  }

  toggle(): void {
    if (!this.player) {
      return;
    }
    try {
      if (this.state === PlayState.PLAYING) {
        this.player.pause();
      } else if (this.state === PlayState.PAUSED || this.state === PlayState.PREPARED) {
        this.player.play();
      } else if (this.state === PlayState.STOPPED || this.state === PlayState.ERROR) {
        // 播完/出错后重放当前项。
        this.playAt(this.index);
      }
    } catch (e) {
      hilog.error(0x0001, 'VLC', '[VLC] toggle failed: %{public}s', (e as BusinessError).message);
    }
  }

  seekTo(ms: number): void {
    if (!this.player) {
      return;
    }
    if (this.state !== PlayState.PLAYING && this.state !== PlayState.PAUSED && this.state !== PlayState.PREPARED) {
      return;
    }
    const clamped = Math.max(0, Math.min(this.duration > 0 ? this.duration : ms, ms));
    this.position = clamped;
    try {
      this.player.seek(clamped);
    } catch (e) {
      hilog.error(0x0001, 'VLC', '[VLC] seek failed: %{public}s', (e as BusinessError).message);
    }
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    if (this.player && this.state === PlayState.PLAYING) {
      try {
        this.player.setSpeed(VideoPlayerViewModel.toPlaybackSpeed(rate));
      } catch (e) {
        hilog.warn(0x0001, 'VLC', '[VLC] setSpeed failed: %{public}s', (e as BusinessError).message);
      }
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
    this.released = true;
    if (this.player) {
      const p = this.player;
      this.player = null;
      try {
        p.off('stateChange');
        p.off('timeUpdate');
        p.off('durationUpdate');
        p.off('error');
      } catch (e) {
        // 忽略
      }
      // release 抛异常不能冒泡出 aboutToDisappear,否则会带崩页面销毁流程。
      try {
        p.release();
      } catch (e) {
        hilog.warn(0x0001, 'VLC', '[VLC] release failed: %{public}s', (e as BusinessError).message);
      }
    }
    this.closeFd();
  }
}

@ComponentV2
export struct VideoPlayerPage {
  @Local vm: VideoPlayerViewModel = new VideoPlayerViewModel();
  @Param param: VideoParam = { uri: '', title: '' };
  private xComponentController: XComponentController = new XComponentController();
  private hudTimer: number = -1;

  /** 拖动 seek 条期间冻结 timeUpdate 回写,否则滑块被不断拉回。 */
  @Local seeking: boolean = false;
  @Local seekPercent: number = 0;

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

  closeSheet(): void {
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** Jump to Time 确认 → AVPlayer seek(timeMs) 可落地;弹窗关闭。 */
  onJumpConfirm(timeMs: number): void {
    this.vm.seekTo(timeMs);
    this.closeSheet();
  }

  /** Sleep timer 确认:定时动作体依赖 libVLC 媒体引擎契约,保留 TODO。 */
  onSleepConfirm(): void {
    // TODO(libVLC 契约): 写入睡眠定时器(waitBeforeSleep / resetOnInteraction 选项)+ 定时暂停;AVPlayer 无原生定时器接口。
    this.closeSheet();
  }

  /** 章节选择:libVLC getChapters 契约,保留 TODO。 */
  onChapterSelect(index: number): void {
    // TODO(libVLC 契约): playbackService.chapterIdx = index;当前 AVPlayer 无章节概念。
    void index;
    this.closeSheet();
  }

  /** 音轨/字幕/视频轨切换:libVLC 轨道契约,保留 TODO。 */
  onTrackSelect(id: number, type: string): void {
    // TODO(libVLC 契约): 按 type(audio/spu/video) 切换 PlaybackService 轨道;AVPlayer 无多轨切换接口。
    void id;
    void type;
    this.closeSheet();
  }

  /** 投屏渲染器:libVLC renderer 契约,保留 TODO。 */
  onRendererConnect(id: number): void {
    // TODO(libVLC 契约): PlaybackService.renderer.value = 连接的 renderer item;需 RendererDelegate。
    void id;
    this.closeSheet();
  }

  onRendererDisconnect(): void {
    // TODO(libVLC 契约): PlaybackService.renderer.value = null(断开)。
    this.closeSheet();
  }

  aboutToAppear(): void {
    this.resetHudTimer();
  }

  aboutToDisappear(): void {
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    this.vm.release();
  }

  /** 显示 HUD 并重置 4s 自动隐藏计时。任何一次交互都应调用。 */
  resetHudTimer(): void {
    this.vm.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      this.hudTimer = -1;
      // 仅在播放中自动隐藏;暂停/出错时保持可见。
      if (this.vm.state === PlayState.PLAYING && !this.seeking && !this.sheetOpen) {
        this.vm.hudVisible = false;
      }
    }, 4000);
  }

  /** 点击画面:HUD 可见则隐藏,不可见则显示。 */
  toggleHud(): void {
    if (this.vm.hudVisible) {
      if (this.hudTimer !== -1) {
        clearTimeout(this.hudTimer);
        this.hudTimer = -1;
      }
      this.vm.hudVisible = false;
    } else {
      this.resetHudTimer();
    }
  }

  /** 当前应显示的播放位置(拖动中显示拖动目标,否则显示真实进度)。 */
  displayPosition(): number {
    if (this.seeking && this.vm.duration > 0) {
      return Math.floor(this.vm.duration * this.seekPercent / 100);
    }
    return this.vm.position;
  }

  build() {
    NavDestination() {
      Stack() {
        // 视频画面铺底
        XComponent({ id: 'vlc_video_surface', type: XComponentType.SURFACE, controller: this.xComponentController })
          .onLoad(() => {
            const sid = this.xComponentController.getXComponentSurfaceId();
            this.vm.setup(this.param, sid);
          })
          .width('100%')
          .height('100%')
          .onClick(() => this.toggleHud())

        // 加载中 / 出错提示(居中,不随 HUD 隐藏)
        if (this.vm.state === PlayState.IDLE) {
          LoadingProgress().width(48).height(48).color('#FFFFFF')
        } else if (this.vm.state === PlayState.ERROR) {
          Column() {
            Text($r('app.string.encountered_error_message'))
              .fontSize(16).fontColor('#FFFFFF').textAlign(TextAlign.Center)
            if (this.vm.errorMsg !== '') {
              Text(this.vm.errorMsg)
                .fontSize(12).fontColor('#9E9E9E').margin({ top: 8 }).textAlign(TextAlign.Center)
            }
          }
          .padding(24)
          .width('100%')

        }

        // HUD 层:整屏 Column + SpaceBetween,把顶栏推到顶、控制栏推到底。
        // 【关键】Stack 默认 alignContent=Center,直接放两个 Column 会重叠在屏幕正中。
        // hitTestBehavior(None) 让中间空白区的点击穿透到 XComponent。
        if (this.vm.hudVisible) {
          Column() {
            this.topBar()
            this.bottomBar()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .hitTestBehavior(HitTestMode.None)
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
      backgroundColor: $r('app.color.background_default'),
      onDisappear: () => {
        this.closeSheet();
        this.resetHudTimer();
      },
    })
  }

  /** 顶部信息栏(深色遮罩自上而下渐隐:angle=180 才是纵向,原 90 是横向渐变)。 */
  @Builder
  topBar() {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(24).height(24).fillColor('#FFFFFF')
        .onClick(() => NavController.pop())
      Text(this.vm.title)
        .fontSize(18).fontColor('#FFFFFF').layoutWeight(1).margin({ left: 12, right: 12 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Image($r('app.media.ic_player_more'))
        .width(24).height(24).fillColor('#FFFFFF')
        .onClick(() => {
          this.resetHudTimer();
          this.openOptions();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 16 })
    .alignItems(VerticalAlign.Center)
    .linearGradient({ angle: 180, colors: [['#cb000000', 0.0], ['#00000000', 1.0]] })
  }

  /** 底部控制栏(遮罩自下而上渐隐 → 颜色停靠反过来,角度仍是 180)。 */
  @Builder
  bottomBar() {
    Column() {
      // seek bar
      Row() {
        Text(fmtTime(this.displayPosition()))
          .fontSize(12).fontColor('#FFFFFF').width(52)
        Slider({
          value: this.seeking
            ? this.seekPercent
            : (this.vm.duration > 0 ? this.vm.position * 100 / this.vm.duration : 0),
          min: 0,
          max: 100,
          step: 0.1,
          style: SliderStyle.OutSet,
        })
          .layoutWeight(1)
          .blockColor('#FF8800')
          .selectedColor('#FF8800')
          .trackColor('#61FFFFFF')
          .enabled(this.vm.duration > 0)
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin) {
              this.seeking = true;
              this.seekPercent = v;
            } else if (mode === SliderChangeMode.Moving) {
              this.seekPercent = v;
            } else {
              // End / Click → 落 seek
              this.seekPercent = v;
              this.seeking = false;
              this.vm.seekTo(Math.floor(this.vm.duration * v / 100));
            }
            this.resetHudTimer();
          })
        Text(fmtTime(this.vm.duration - this.displayPosition()))
          .fontSize(12).fontColor('#FFFFFF').width(52).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      // 控制按钮行
      Row() {
        Image($r('app.media.ic_player_rewind_10'))
          .width(32).height(32).fillColor('#FFFFFF')
          .onClick(() => {
            this.vm.seekTo(this.vm.position - 10000);
            this.resetHudTimer();
          })
        Blank()
        Image($r('app.media.ic_player_previous'))
          .width(36).height(36).fillColor('#FFFFFF')
          .opacity(this.vm.hasPrev() || this.vm.position > 3000 ? 1 : 0.35)
          .onClick(() => {
            this.vm.prev();
            this.resetHudTimer();
          })
        Blank()
        Image(this.vm.state === PlayState.PLAYING
          ? $r('app.media.ic_pause_player')
          : $r('app.media.ic_play_player'))
          .width(56).height(56).fillColor('#FFFFFF')
          .onClick(() => {
            this.vm.toggle();
            this.resetHudTimer();
          })
        Blank()
        Image($r('app.media.ic_player_next'))
          .width(36).height(36).fillColor('#FFFFFF')
          .opacity(this.vm.hasNext() ? 1 : 0.35)
          .onClick(() => {
            this.vm.next();
            this.resetHudTimer();
          })
        Blank()
        Image($r('app.media.ic_player_forward_10'))
          .width(32).height(32).fillColor('#FFFFFF')
          .onClick(() => {
            this.vm.seekTo(this.vm.position + 10000);
            this.resetHudTimer();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 36 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .linearGradient({ angle: 180, colors: [['#00000000', 0.0], ['#cb000000', 1.0]] })
  }

  /** 更多选项 / 二级弹窗统一 sheet:sheetKind 决定渲染哪一层。 */
  @Builder
  playerSheet() {
    Column() {
      if (this.sheetKind === '') {
        this.optionsList()
      } else if (this.sheetKind === 'jump') {
        JumpToTimeDialog({
          onClose: () => this.closeSheet(),
          onConfirm: (timeMs: number) => this.onJumpConfirm(timeMs),
        }).width('100%')
      } else if (this.sheetKind === 'sleep') {
        SleepTimerDialog({
          onClose: () => this.closeSheet(),
          onDeleteCurrent: () => {
            // TODO(libVLC 契约): 清除已设睡眠定时器。
          },
        }).width('100%')
      } else if (this.sheetKind === 'chapter') {
        SelectChapterDialog({
          onClose: () => this.closeSheet(),
          onSelectChapter: (index: number) => this.onChapterSelect(index),
        }).width('100%')
      } else if (this.sheetKind === 'tracks') {
        VideoTracksDialog({
          onClose: () => this.closeSheet(),
          onTrackSelect: (id: number, type: string) => this.onTrackSelect(id, type),
        }).width('100%')
      } else if (this.sheetKind === 'renderer') {
        RenderersDialog({
          onClose: () => this.closeSheet(),
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
        .padding({ left: 16, right: 16 })
        .height(56)
        .textAlign(TextAlign.Start)

      this.optionRow('Jump to time', () => this.openSub('jump'))
      this.optionRow('Sleep timer', () => this.openSub('sleep'))
      this.optionRow($r('app.string.go_to_chapter'), () => this.openSub('chapter'))
      this.optionRow('Audio & Subtitles tracks', () => this.openSub('tracks'))
      this.optionRow('Displays', () => this.openSub('renderer'))
    }
    .width('100%')
    .padding({ bottom: 16 })
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
      Image($r('app.media.ic_arrow_right'))
        .width(20).height(20)
        .fillColor('#9E9E9E')
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onTap())
  }
}
