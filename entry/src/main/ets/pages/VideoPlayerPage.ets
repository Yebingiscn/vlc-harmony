import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { PlaybackService, PlaybackListener } from '../common/data/PlaybackService';
import { Settings } from '../common/data/Settings';
import { MediaWrapper, PlayState } from '../common/models/MediaModels';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { SelectChapterDialog } from './SelectChapterDialog';
import { VideoTracksDialog } from './VideoTracksDialog';
import { RenderersDialog } from './RenderersDialog';
import { promptAction } from '@kit.ArkUI';
import {
  buildPlayerAdvancedOptions,
  PlayerAdvancedOptionId,
  PlayerAdvancedOptions,
} from '../common/components/PlayerAdvancedOptions';
import {
  buildVideoPlayerBottomActions,
  VideoPlayerBottomAction,
  VideoPlayerBottomActionId,
} from '../common/components/VideoPlayerControls';

/** 与 Native / XComponent id 一致;libraryname 对齐 nm_modname=libvlcnapi。 */
export const VLC_VIDEO_XCOMPONENT_ID: string = 'vlc_video_surface';
export const VLC_NAPI_LIBRARY: string = 'libvlcnapi';

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

/** 播放器专用时长格式化:0 显示 00:00(MediaModels.formatDuration 对 0 返回空串,列表项需要、播放器不需要)。 */
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
 * 睡眠倒计时时长 → 中文可读文案。
 * 不把分钟换算成小时 —— 与弹窗预览保持一致(弹窗显示 "90m 30s",这里就是 "90分30秒"),
 * 否则用户刚看到 90m、toast 却说 1 小时 30 分 会退疑自己按错了。
 */
function fmtSleepSpan(ms: number): string {
  const totalMin: number = Math.floor(ms / 60000);
  const h: number = Math.floor(totalMin / 60);
  const m: number = totalMin % 60;
  if (h > 0 && m > 0) {
    return `${h}小时${m}分`;
  }
  if (h > 0) {
    return `${h}小时`;
  }
  return `${m}分钟`;
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
    return [containerW, containerW / videoAspect];
  }
  return [containerH * videoAspect, containerH];
}

/**
 * VideoPlayerPage —— VideoPlayerActivity(全屏视频播放器)。
 * UI 布局/显示以 origin/dev 为准;出画与控制走 PlaybackService → libVLC(NAPI + XComponent)。
 * 画面按 libVLC 回报的视频尺寸做 contain 等比例缩放。
 */
@ObservedV2
class VideoPlayerViewModel implements PlaybackListener {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace hudVisible: boolean = true;
  @Trace speed: number = 1.0;
  @Trace title: string = '';
  @Trace errorMsg: string = '';
  @Trace index: number = 0;
  @Trace listLen: number = 1;
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
  private list: VideoPlayItem[] = [];
  private listening: boolean = false;
  private leaving: boolean = false;
  private xcomponentId: string = '';

  hasPrev(): boolean {
    return this.index > 0;
  }

  hasNext(): boolean {
    return this.index < this.listLen - 1;
  }

  /** XComponent onLoad 后调用:准备队列并 bindAndPlay。 */
  async setup(param: VideoParam, xcomponentId: string): Promise<void> {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer setup: uri=%{public}s xc=%{public}s', param.uri, xcomponentId);
    this.leaving = false;
    this.xcomponentId = xcomponentId;
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

    const svc = PlaybackService.getInstance();
    if (!this.listening) {
      svc.addListener(this);
      this.listening = true;
    }

    const mws: MediaWrapper[] = this.list.map((it: VideoPlayItem, i: number) =>
    new MediaWrapper(i + 1, it.title, it.uri, 0));
    await svc.prepareList(mws, this.index, true);
    svc.setSpeed(this.speed);
    const bound = await svc.bindAndPlay(xcomponentId, this.uri, this.title);
    this.state = svc.getState();
    this.duration = svc.getDuration();
    this.position = svc.getPosition();
    if (svc.getVideoWidth() > 0) {
      this.onVideoSize(svc.getVideoWidth(), svc.getVideoHeight());
    }
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.bindAndPlay done bound=%{public}s', String(bound));
    if (!bound) {
      this.state = PlayState.ERROR;
      this.errorMsg = 'bind video surface failed';
    }
  }

  onStateChange(state: PlayState): void {
    this.state = state;
    if (state === PlayState.ERROR) {
      this.errorMsg = 'playback error';
    } else if (state === PlayState.PLAYING) {
      this.errorMsg = '';
      PlaybackService.getInstance().refreshVideoSize();
    }
  }

  onTimeUpdate(current: number, duration: number): void {
    this.position = current;
    this.duration = duration;
  }

  onQueueChanged(): void {
    const svc = PlaybackService.getInstance();
    const cur = svc.getCurrent();
    if (cur) {
      this.uri = cur.uri;
      this.title = cur.title;
      if (cur.width > 0 && cur.height > 0) {
        this.onVideoSize(cur.width, cur.height);
      }
    }
    this.index = svc.getCurrentIndex();
    this.listLen = Math.max(this.list.length, svc.getQueue().length);
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

  async playAt(i: number): Promise<void> {
    if (i < 0 || i >= this.list.length) {
      return;
    }
    this.index = i;
    this.uri = this.list[i].uri;
    this.title = this.list[i].title;
    this.position = 0;
    this.duration = 0;
    this.videoWidth = 0;
    this.videoHeight = 0;
    this.state = PlayState.IDLE;
    const svc = PlaybackService.getInstance();
    const mws: MediaWrapper[] = this.list.map((it: VideoPlayItem, idx: number) =>
    new MediaWrapper(idx + 1, it.title, it.uri, 0));
    await svc.prepareList(mws, i, true);
    if (this.xcomponentId.length > 0) {
      await svc.bindAndPlay(this.xcomponentId, this.uri, this.title);
    }
  }

  next(): void {
    if (this.hasNext()) {
      void this.playAt(this.index + 1);
    }
  }

  prev(): void {
    if (this.position > 3000) {
      this.seekTo(0);
    } else if (this.hasPrev()) {
      void this.playAt(this.index - 1);
    }
  }

  toggle(): void {
    PlaybackService.getInstance().togglePlay();
    this.hudVisible = true;
  }

  /** 睡眠倒计时到点:暂停播放(不 release,用户可继续)。 */
  pauseForSleep(): void {
    const svc = PlaybackService.getInstance();
    if (svc.getState() === PlayState.PLAYING) {
      svc.pause();
      hilog.info(0x0001, 'VLC', '[VLC] paused by sleep timer');
    }
  }

  seekTo(ms: number): void {
    PlaybackService.getInstance().seek(ms);
    this.position = ms;
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    PlaybackService.getInstance().setSpeed(rate);
    Settings.put(Settings.VIDEO_SPEED, rate);
  }

  setStopAfterCurrent(v: boolean): void {
    PlaybackService.getInstance().setStopAfterCurrent(v);
  }

  /** 对齐 Android onPause(isFinishing):尽早 stop。 */
  leaveEarly(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    if (this.listening) {
      PlaybackService.getInstance().removeListener(this);
      this.listening = false;
    }
    PlaybackService.getInstance().setStopAfterCurrent(false);
    PlaybackService.getInstance().stop();
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.leaveEarly/stop');
  }

  cleanUI(): void {
    PlaybackService.getInstance().detachViews();
  }

  release(): void {
    if (!this.leaving) {
      this.leaveEarly();
    }
    this.cleanUI();
  }
}

@ComponentV2
export struct VideoPlayerPage {
  @Local vm: VideoPlayerViewModel = new VideoPlayerViewModel();
  @Param param: VideoParam = { uri: '', title: '' };
  private hudTimer: number = -1;
  private surfaceStarted: boolean = false;

  /** 拖动 seek 条期间冻结 timeUpdate 回写,否则滑块被不断拉回。 */
  @Local seeking: boolean = false;
  @Local seekPercent: number = 0;

  /** 睡眠倒计时状态。 */
  @Local sleepArmed: boolean = false;
  private sleepTimer: number = -1;
  private sleepMillis: number = 0;
  private sleepWaitMediaEnd: boolean = false;
  private sleepResetOnInteraction: boolean = false;

  /** 更多选项/二级弹窗的 sheet 状态。sheetKind 空串=主选项列表;否则=对应二级弹窗。 */
  @Local sheetOpen: boolean = false;
  @Local sheetKind: string = ''; // '' | 'jump' | 'sleep' | 'chapter' | 'tracks' | 'renderer'
  @Local advancedOptionsOpen: boolean = false;
  /**
   * 高级选项菜单选中项的暂存。
   * 为什么不在 onSelect 里直接开弹窗:bindMenu(showInSubWindow) 收起有动画,
   * 菜单还在消失时立刻 bindSheet 会被吞掉(sheet 不显示)。改为等菜单 onDisappear 后再执行。
   */
  private pendingAdvancedAction: PlayerAdvancedOptionId | null = null;

  /** 打开高级选项菜单。 */
  openOptions(): void {
    this.advancedOptionsOpen = true;
    // 菜单期间 HUD 必须常驻(菜单锚在底栏上),顺带重置计时。
    this.resetHudTimer();
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

  /** Jump to Time 确认 → seek 后关闭。 */
  onJumpConfirm(timeMs: number): void {
    this.vm.seekTo(timeMs);
    this.closeSheet();
  }

  /** Sleep timer 确认:起一个倒计时,到点暂停播放。 */
  onSleepConfirm(millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean): void {
    this.clearSleepTimer();
    this.sleepMillis = millis;
    this.sleepWaitMediaEnd = waitForMediaEnd;
    this.sleepResetOnInteraction = resetOnInteraction;
    this.armSleepTimer();
    // 持久化:下次打开弹框能反推回原值;退出 app 再回来也还在。
    Settings.put(Settings.SLEEP_TIMER_MILLIS, millis);
    Settings.put(Settings.SLEEP_TIMER_WAIT_MEDIA_END, waitForMediaEnd);
    Settings.put(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, resetOnInteraction);
    hilog.info(0x0001, 'VLC', '[VLC] sleep timer armed: %{public}d ms wait=%{public}s reset=%{public}s',
      millis, String(waitForMediaEnd), String(resetOnInteraction));
    // 设定成功提示。勾了「先等当前媒体播完」时行为不同(不会在到点那一刻暂停),文案要说清楚,
    // 否则用户设 5 分钟却发现 5 分钟后还在播,会以为没生效。
    const span: string = fmtSleepSpan(millis);
    promptAction.showToast({
      message: waitForMediaEnd
        ? $r('app.string.sleep_timer_set_wait', span)
        : $r('app.string.sleep_timer_set', span),
    });
    this.closeSheet();
  }

  private armSleepTimer(): void {
    if (this.sleepMillis <= 0) {
      return;
    }
    if (this.sleepTimer !== -1) {
      clearTimeout(this.sleepTimer);
    }
    this.sleepArmed = true;
    this.sleepTimer = setTimeout(() => {
      this.sleepTimer = -1;
      if (this.sleepWaitMediaEnd) {
        // 「先等当前媒体播完」→ 不立刻暂停,标记播完即停(见 vm.onState 的 completed 分支)。
        this.vm.setStopAfterCurrent(true);
      } else {
        this.vm.pauseForSleep();
        this.sleepArmed = false;
        // 到点提示 —— 否则画面无缘无故停住,用户不知道是倒计时干的。
        promptAction.showToast({ message: $r('app.string.sleep_timer_fired') });
      }
    }, this.sleepMillis);
  }

  /** 取消倒计时。fromUser=true 时给出取消提示(页面销毁时的清理不需要弹)。 */
  private clearSleepTimer(fromUser: boolean = false): void {
    const wasArmed: boolean = this.sleepArmed;
    if (this.sleepTimer !== -1) {
      clearTimeout(this.sleepTimer);
      this.sleepTimer = -1;
    }
    this.sleepArmed = false;
    this.vm.setStopAfterCurrent(false);
    if (fromUser && wasArmed) {
      promptAction.showToast({ message: $r('app.string.sleep_timer_cancelled') });
    }
  }

  onChapterSelect(index: number): void {
    PlaybackService.getInstance().setChapter(index);
    this.closeSheet();
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
    this.closeSheet();
  }

  onRendererConnect(id: number): void {
    PlaybackService.getInstance().setRenderer(id);
    this.closeSheet();
  }

  onRendererDisconnect(): void {
    PlaybackService.getInstance().clearRenderer();
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
    this.clearSleepTimer();
    this.vm.release();
  }

  /** 显示 HUD 并重置 4s 自动隐藏计时。任何一次交互都应调用。 */
  resetHudTimer(): void {
    // 「有任何交互时重置」勾选后,每次交互顺带把睡眠倒计时重新起算。
    if (this.sleepResetOnInteraction && this.sleepArmed) {
      this.armSleepTimer();
    }
    this.vm.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      this.hudTimer = -1;
      // 仅在播放中自动隐藏;暂停/出错、拖动中、弹窗或高级选项菜单打开时保持可见
      // ——高级选项菜单锚在底栏图标上,底栏一藏菜单就悬空/关掉。
      if (this.vm.state === PlayState.PLAYING && !this.seeking && !this.sheetOpen && !this.advancedOptionsOpen) {
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

  bottomActionIcon(action: VideoPlayerBottomAction): Resource {
    if (action.id === 'play') {
      return this.vm.state === PlayState.PLAYING
        ? $r('app.media.ic_pause_player')
        : $r('app.media.ic_play_player');
    }
    return action.icon;
  }

  onBottomAction(id: VideoPlayerBottomActionId): void {
    if (id === 'tracks') {
      this.openSub('tracks');
    } else if (id === 'play') {
      this.vm.toggle();
    } else if (id === 'orientation') {
      promptAction.showToast({ message: 'Screen orientation is not available yet' });
    } else if (id === 'aspectRatio') {
      promptAction.showToast({ message: 'Aspect ratio is not available yet' });
    }
    this.resetHudTimer();
  }

  build() {
    NavDestination() {
      // alignContent=Center: 视频 Surface 按比例居中;HUD 用整屏 Column 顶底铺开
      Stack({ alignContent: Alignment.Center }) {
        // 视频画面 —— contain 等比例;未拿到尺寸前先铺满
        XComponent({
          id: VLC_VIDEO_XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: VLC_NAPI_LIBRARY,
        })
          .onLoad(() => {
            if (this.surfaceStarted) {
              return;
            }
            this.surfaceStarted = true;
            this.vm.setup(this.param, VLC_VIDEO_XCOMPONENT_ID);
          })
          .onDestroy(() => {
            this.vm.cleanUI();
            this.surfaceStarted = false;
          })
          .width(this.vm.surfaceWidth > 0 ? this.vm.surfaceWidth : '100%')
          .height(this.vm.surfaceHeight > 0 ? this.vm.surfaceHeight : '100%')
          .hitTestBehavior(HitTestMode.None)

        // Keep empty-area taps above the native video surface, below the HUD.
        Column() {
          Blank()
            .width('100%')
            .height('100%')
        }
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
      .onAreaChange((_old: Area, area: Area) => {
        this.vm.onContainerSize(Number(area.width), Number(area.height));
      })
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      this.vm.leaveEarly();
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
        .onClick(() => {
          this.vm.leaveEarly();
          NavController.pop();
        })
      Text(this.vm.title)
        .fontSize(18).fontColor('#FFFFFF').layoutWeight(1).margin({ left: 12, right: 12 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      // 睡眠倒计时已设定的指示灯,点一下取消(否则设完毫无反馈,也无处撤销)。
      if (this.sleepArmed) {
        Image($r('app.media.ic_sleep'))
          .width(22).height(22).fillColor('#FF8800').margin({ right: 16 })
          .onClick(() => {
            this.clearSleepTimer(true);
            this.resetHudTimer();
          })
      }
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

      // 音轨和字幕、屏幕方向、播放、宽高比、高级选项。
      Row() {
        ForEach(buildVideoPlayerBottomActions(), (action: VideoPlayerBottomAction) => {
          if (action.id === 'advanced') {
            Image(action.icon)
              .width(32)
              .height(32)
              .fillColor('#FFFFFF')
              .onClick(() => this.openOptions())
              .bindMenu(this.advancedOptionsOpen!!, this.advancedOptionsMenu(), {
                placement: Placement.TopRight,
                showInSubWindow: true,
                backgroundColor: '#FFFFFF',
                onDisappear: () => this.runPendingAdvancedAction(),
              })
          } else {
            Image(this.bottomActionIcon(action))
              .width(action.id === 'play' ? 56 : 32)
              .height(action.id === 'play' ? 56 : 32)
              .fillColor('#FFFFFF')
              .onClick(() => this.onBottomAction(action.id))
          }
        }, (action: VideoPlayerBottomAction): string => action.id)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 12 })
      .justifyContent(FlexAlign.SpaceBetween)
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
          initialMillis: this.sleepMillis,
          initialWaitMediaEnd: this.sleepWaitMediaEnd,
          initialResetOnInteraction: this.sleepResetOnInteraction,
          onClose: () => this.closeSheet(),
          onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) =>
          this.onSleepConfirm(millis, waitForMediaEnd, resetOnInteraction),
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

  @Builder
  advancedOptionsMenu() {
    PlayerAdvancedOptions({
      items: buildPlayerAdvancedOptions('video'),
      onSelect: (id: PlayerAdvancedOptionId): void => {
        // 只记录选择并收起菜单,真正的动作在菜单消失后执行(见 pendingAdvancedAction 注释)。
        this.pendingAdvancedAction = id;
        this.advancedOptionsOpen = false;
      },
    })
  }

  /** 菜单已完全消失,执行暂存的动作。 */
  runPendingAdvancedAction(): void {
    const id: PlayerAdvancedOptionId | null = this.pendingAdvancedAction;
    this.pendingAdvancedAction = null;
    if (id === null) {
      return;
    }
    if (id === 'sleep') {
      this.openSub('sleep');
      return;
    }
    promptAction.showToast({ message: '该功能暂未实现' });
  }

}
