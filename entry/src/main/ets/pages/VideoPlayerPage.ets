import { promptAction, window } from '@kit.ArkUI';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import PiPWindow from '@ohos.PiPWindow';
import { NavController } from '../common/data/NavController';
import { AppContext } from '../common/data/AppContext';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { PlaybackService, PlaybackListener, QueueItem } from '../common/data/PlaybackService';
import { VlcChapterInfo } from 'libvlcnapi.so';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { Settings } from '../common/data/Settings';
import { VideoSeenState } from '../common/data/VideoSeenState';
import { MediaWrapper, PlayState } from '../common/models/MediaModels';
import { shouldRecordPlaybackStart } from '../common/models/PlaybackHistoryModels';
import { BookMark } from '../common/models/BookmarkModels';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { SelectChapterDialog } from './SelectChapterDialog';
import { VideoTracksDialog } from './VideoTracksDialog';
import { RenderersDialog } from './RenderersDialog';
import { PlaybackSpeedDialog, PlaybackSpeedAction } from './PlaybackSpeedDialog';
import { VideoControlsSettingsDialog, ControlsState } from './VideoControlsSettingsDialog';
import { EqualizerDialog } from './EqualizerDialog';
import { VideoInfoDialog } from './VideoInfoDialog';
import { BookmarkDialog } from './BookmarkDialog';
import { AddToPlaylistDialog, AddToPlaylistAction } from './AddToPlaylistDialog';
import {
  SCREEN_ORIENTATION_DEFAULT,
  SCREEN_ORIENTATION_LABELS,
  SCREEN_ORIENTATION_VALUES,
  ScreenOrientationDialog,
} from './ScreenOrientationDialog';
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
import { VideoPanMode, VideoTouchDelegate } from './videoplayer/VideoTouchDelegate';

/** 与 Native / XComponent id 一致;libraryname 对齐 nm_modname=libvlcnapi。 */
export const VLC_VIDEO_XCOMPONENT_ID: string = 'vlc_video_surface';
export const VLC_NAPI_LIBRARY: string = 'libvlcnapi';

/** 播放队列中的一项(仅携带播放器需要的字段,避免把整个 MediaWrapper 塞进路由参数)。 */
export interface VideoPlayItem {
  uri: string;
  title: string;
  artworkUrl?: string;
}

export interface VideoParam {
  uri: string;
  title: string;
  artworkUrl?: string;
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

/** 「视频屏幕方向」设置值 → HarmonyOS 窗口方向。 */
function windowOrientationFor(value: string): window.Orientation {
  switch (value) {
    case '102':
      return window.Orientation.PORTRAIT;
    case '101':
      return window.Orientation.LANDSCAPE;
    case '103':
      return window.Orientation.LANDSCAPE_INVERTED;
    case '98':
      return window.Orientation.LOCKED;
    case '99':
    default:
      return window.Orientation.AUTO_ROTATION;
  }
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
  /** 播放器锁定状态:锁定后点击画面不显 HUD,需手动解锁。 */
  @Trace locked: boolean = false;
  /** 当前循环模式:0=关闭,1=列表循环,2=单曲循环。 */
  @Trace repeatMode: number = 0;
  /** A-B 循环状态。-1 表示未设。 */
  @Trace abPointA: number = -1;
  @Trace abPointB: number = -1;
  @Trace abActive: boolean = false;

  /** ISO 光盘镜像:使用章节导航替代时间 seek。 */
  isIsoFile: boolean = false;
  isoChapters: VlcChapterInfo[] = [];
  @Trace isoChapterIdx: number = 0;

  uri: string = '';
  currentArtworkUrl: string = '';
  private list: VideoPlayItem[] = [];
  private listening: boolean = false;
  private leaving: boolean = false;
  private xcomponentId: string = '';
  private lastHistoryUri: string = '';

  hasPrev(): boolean {
    return this.index > 0;
  }

  hasNext(): boolean {
    return this.index < this.listLen - 1;
  }

  /** XComponent onLoad 后调用:准备队列并 bindAndPlay。 */
  async setup(param: VideoParam, xcomponentId: string): Promise<void> {
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer setup: uri=%{public}s xc=%{public}s', param.uri, xcomponentId);

    // 如果从"仅播放音频"模式(单元素队列、无 XComponent、player 仍 PLAYING)
    // 切到新的视频,先把 player 彻底 reset,否则 attachViews 会失败导致
    // 30 次重试 + 1.5s 卡死 + native crash。
    // 这次 reset 三步:stop → detachViews(清 videoOutId)→ 清标记,并 await 给 native 100ms 收尾。
    if (PlaybackService.isPlayAsAudio()) {
      const svc = PlaybackService.getInstance();
      svc.stop();
      svc.detachViews();
      svc.setPlayAsAudio(false);
    }

    this.leaving = false;
    this.xcomponentId = xcomponentId;
    const incoming: VideoPlayItem[] = param.list !== undefined ? param.list : [];
    if (incoming.length > 0) {
      this.list = incoming;
    } else {
      const single: VideoPlayItem = { uri: param.uri, title: param.title, artworkUrl: param.artworkUrl };
      this.list = [single];
    }
    this.index = param.index !== undefined && param.index >= 0 && param.index < this.list.length ? param.index : 0;
    this.listLen = this.list.length;
    this.uri = this.list[this.index].uri;
    this.title = this.list[this.index].title;
    this.currentArtworkUrl = this.list[this.index].artworkUrl ?? '';

    this.speed = await Settings.getFloat(Settings.VIDEO_SPEED, 1.0);

    // 检测 ISO 光盘镜像,加载章节用于虚拟时间轴导航。
    this.isIsoFile = param.uri.toLowerCase().endsWith('.iso');
    this.isoChapters = [];
    this.isoChapterIdx = 0;

    const svc = PlaybackService.getInstance();
    this.repeatMode = svc.getRepeatMode();
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

    // ISO 文件:延迟加载章节(媒体解析需要时间),构建虚拟时间轴。
    if (this.isIsoFile) {
      await new Promise<void>((r: () => void) => setTimeout(r, 500));
      this.isoChapters = svc.getChapters();
      hilog.info(0x0001, 'VLC', '[VLC] ISO chapters count=%{public}d', this.isoChapters.length);
      if (this.isoChapters.length > 0) {
        // 总时长 = 各章节时长之和。
        let total = 0;
        for (const ch of this.isoChapters) {
          total += ch.duration;
        }
        this.duration = total;
        this.isoChapterIdx = svc.getChapterIdx();
        hilog.info(0x0001, 'VLC', '[VLC] ISO chapters=%{public}d totalDuration=%{public}d', this.isoChapters.length, total);
      }
    }
  }

  onStateChange(state: PlayState): void {
    this.state = state;
    if (state === PlayState.ERROR) {
      this.errorMsg = 'playback error';
    } else if (state === PlayState.PLAYING) {
      this.errorMsg = '';
      const svc = PlaybackService.getInstance();
      svc.refreshVideoSize();
      if (shouldRecordPlaybackStart('playing', this.lastHistoryUri, this.uri)) {
        this.lastHistoryUri = this.uri;
        void PlaybackHistory.record(this.uri, this.title, svc.getDuration(),
          this.currentArtworkUrl);
      }
    }
  }

  /** 仅在 LibVLC 的真实 ended 事件到来时标记，手动停止或半途退出不会算作已看。 */
  onMediaEnded(): void {
    void VideoSeenState.markSeen(this.uri);
  }

  onTimeUpdate(current: number, duration: number): void {
    this.position = current;
    this.duration = duration;
    // A-B 循环:到达 B 时回到 A。200ms 余量防止越界。
    if (this.abActive && this.abPointA >= 0 && this.abPointB > this.abPointA &&
        current >= this.abPointB - 200) {
      PlaybackService.getInstance().seek(this.abPointA);
      this.position = this.abPointA;
    }
    if (this.isIsoFile && this.isoChapters.length > 0) {
      // DVD/BD:get_time 返回的是当前标题内的绝对时间,直接用,不累加章节偏移。
      const svc = PlaybackService.getInstance();
      const chIdx = svc.getChapterIdx();
      if (chIdx >= 0) {
        this.isoChapterIdx = chIdx;
      }
      this.position = current;
      this.duration = duration > 0 ? duration : this.duration;
    } else {
      this.position = current;
      this.duration = duration;
    }
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
    // cycleRepeat() 等内部操作通过 emitQueue() 通知 ViewModel,避免高级菜单需点击两次才看到激活态变化。
    const nextMode = svc.getRepeatMode();
    if (this.repeatMode !== nextMode) {
      this.repeatMode = nextMode;
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
    this.isoChapters = [];
    this.isoChapterIdx = 0;
    this.isIsoFile = this.uri.toLowerCase().endsWith('.iso');
    const svc = PlaybackService.getInstance();
    const mws: MediaWrapper[] = this.list.map((it: VideoPlayItem, idx: number) =>
    new MediaWrapper(idx + 1, it.title, it.uri, 0));
    await svc.prepareList(mws, i, true);
    if (this.xcomponentId.length > 0) {
      await svc.bindAndPlay(this.xcomponentId, this.uri, this.title);
    }
    // ISO:延迟重新加载章节
    if (this.isIsoFile) {
      await new Promise<void>((r: () => void) => setTimeout(r, 500));
      this.isoChapters = svc.getChapters();
      if (this.isoChapters.length > 0) {
        let total = 0;
        for (const ch of this.isoChapters) {
          total += ch.duration;
        }
        this.duration = total;
        this.isoChapterIdx = svc.getChapterIdx();
      }
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

  toggleLock(): void {
    this.locked = !this.locked;
    if (this.locked) {
      this.hudVisible = false;
    }
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
    const svc = PlaybackService.getInstance();
    // 仅当存在真实章节导航(>1 章)时走章节分支;单章节(如合成 BD 测试盘默认 1 章)的
    // setChapter(0) 会把任何 seek 都拉回开头,此时改用 position seek。
    if (this.isIsoFile && this.isoChapters.length > 1) {
      // DVD/BD:按虚拟时间轴定位到对应章节(setTime 会被 navigator 覆盖弹回)。
      let elapsed = 0;
      for (let i = 0; i < this.isoChapters.length; i++) {
        const chEnd = elapsed + this.isoChapters[i].duration;
        if (ms < chEnd || i === this.isoChapters.length - 1) {
          // 先用章节时间偏移估算位置,等 onTimeUpdate 用真实 chapterIdx 修正。
          this.isoChapterIdx = i;
          this.position = elapsed;
          svc.setChapter(i);
          return;
        }
        elapsed = chEnd;
      }
    }
    // 无章节/单章节 ISO(BD/VCD):setTime 会被 bluray/dvdnav navigator 覆盖弹回 0,改用 position seek。
    if (this.isIsoFile && this.duration > 0) {
      hilog.info(0x0001, 'VLC',
        '[VLC] seekTo ISO(position) ms=%{public}d duration=%{public}d isoChapters=%{public}d',
        ms, this.duration, this.isoChapters.length);
      svc.seekPosition(Math.max(0, Math.min(1, ms / this.duration)));
      this.position = ms;
      return;
    }
    svc.seek(ms);
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

  /** A-B 循环:标记起点 A(当前位置)。 */
  setAbPointA(): void {
    this.abPointA = Math.max(0, Math.floor(this.position));
    this.abPointB = -1;
    this.abActive = false;
  }

  /** A-B 循环:标记终点 B(当前位置)。B 必须在 A 之后,否则忽略。 */
  setAbPointB(): void {
    if (this.abPointA < 0) {
      return;
    }
    const b: number = Math.max(0, Math.floor(this.position));
    if (b <= this.abPointA) {
      return;
    }
    this.abPointB = b;
    this.abActive = true;
  }

  /** A-B 循环:关闭并重置。 */
  resetAb(): void {
    this.abPointA = -1;
    this.abPointB = -1;
    this.abActive = false;
  }

  /**
   * 对齐 Android onPause(isFinishing):尽早 stop。
   * 顺序很关键:先 detach 视频面(对 audio 输出无影响),再决定是否 stop。
   * 如果先 stop 再 detach,player 已经停了再调 detachViews 在某些 libVLC 版本上会
   * 把 audio track 一起释放,导致后续 audio playback 失败。
   * "仅播放音频"模式:detach 后跳过 stop,音频继续在 MiniPlayer 播。
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
    // 先 detach 视频面(总是安全,不影响 audio)
    PlaybackService.getInstance().detachViews();
    // 仅播放音频模式下跳过 stop,让音频继续
    if (!PlaybackService.isPlayAsAudio()) {
      PlaybackService.getInstance().setStopAfterCurrent(false);
      PlaybackService.getInstance().stop();
    }
    hilog.info(0x0001, 'VLC', '[VLC] VideoPlayer.leaveEarly/detach+stop');
  }

  cleanUI(): void {
    // detachViews 已在 leaveEarly 中调用,这里保持幂等(重复 detach 在 libVLC 是 no-op)
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
  /** 画中画所需的 XComponent 控制器(创建 XComponent 时传入,与 native surface 共享同一实例)。 */
  private pipXc: XComponentController = new XComponentController();
  /** 画中画控制器(enterPopupPlayer 启动后持有,stopPiP 时清理)。 */
  private pipController: PiPWindow.PiPController | null = null;
  private touch: VideoTouchDelegate = new VideoTouchDelegate();
  private touchBound: boolean = false;
  private mainWindow: window.Window | null = null;
  private brightnessHudTimer: number = -1;
  private volumeHudTimer: number = -1;
  private seekHudTimer: number = -1;
  private saveBrightness: boolean = false;
  private volumeAcc: number = 0;
  private pendingSeekTarget: number = -1;

  @Local volumeLevel: number = 0;
  @Local volumeMin: number = 0;
  @Local volumeMax: number = 15;
  /** 窗口亮度 0..1（勿命名 brightness：与组件属性冲突）。 */
  @Local brightnessLevel: number = 0.5;
  @Local brightnessHudVisible: boolean = false;
  @Local volumeHudVisible: boolean = false;
  @Local seekHudVisible: boolean = false;
  @Local seekHudText: string = '';

  /** 拖动 seek 条期间冻结 timeUpdate 回写,否则滑块被不断拉回。 */
  @Local seeking: boolean = false;
  @Local seekPercent: number = 0;

  /** 睡眠倒计时状态。 */
  @Local sleepArmed: boolean = false;
  private sleepTimer: number = -1;
  private sleepMillis: number = 0;
  private sleepWaitMediaEnd: boolean = false;
  private sleepResetOnInteraction: boolean = false;
  /** 视频屏幕方向弹窗状态。 */
  @Local orientationValue: string = SCREEN_ORIENTATION_DEFAULT;
  @Local orientationDialogId: number = -1;

  /** 更多选项/二级弹窗的 sheet 状态。sheetKind 空串=主选项列表;否则=对应二级弹窗。 */
  @Local sheetOpen: boolean = false;
  @Local sheetKind: string = ''; // '' | 'jump' | 'sleep' | 'chapter' | 'tracks' | 'renderer' | 'speed' | 'controls' | 'equalizer' | 'videoInfo' | 'savePlaylist'
  /** 书签弹框独立走 Stack 覆盖层(不走 bindSheet)以保持半透效果,不遮挡背后视频。 */
  @Local bookmarkOpen: boolean = false;
  /** 当前视频的书签列表（每次变更自动持久化）。 */
  @Local bookmarks: BookMark[] = [];
  private bookmarkIdSeq: number = 1;
  private bookmarkUri: string = '';
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
    this.vm.isoChapterIdx = index;
    // 更新虚拟位置到选中章节的起始位置。
    if (this.vm.isIsoFile && this.vm.isoChapters.length > 0 && index < this.vm.isoChapters.length) {
      let base = 0;
      for (let i = 0; i < index; i++) {
        base += this.vm.isoChapters[i].duration;
      }
      this.vm.position = base;
    }
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

  /** VideoInfo 用的轨道元数据(由 refreshVideoInfoTracks 刷新)。 */
  @Local videoCodecName: string = '';
  @Local audioCodecName: string = '';
  @Local videoLang: string = '';
  @Local videoFps: string = '';
  @Local audioLang: string = '';
  @Local audioChannels: string = '';
  @Local audioSampleRate: string = '';
  @Local bitrate: string = '';

  /** 刷新视频信息弹框要展示的全部字段:从 libVLC 真实轨道数据填入。 */
  refreshVideoInfoTracks(): void {
    const svc = PlaybackService.getInstance();
    this.videoCodecName = svc.getCurrentVideoTrackInfo()?.name ?? '';
    this.audioCodecName = svc.getCurrentAudioTrackInfo()?.name ?? '';

    // 从 media tracks info 取当前选中轨道的 fps / lang / channels / sampleRate / bitrate
    const allTracks = svc.getMediaTracksInfo();
    const curVideoId = svc.getVideoTrack();
    const curAudioId = svc.getAudioTrack();

    const videoTrack = allTracks.find((t) => t.type === 1 && t.id === curVideoId);
    if (videoTrack) {
      this.videoLang = videoTrack.language.length > 0 ? videoTrack.language : '';
      if (videoTrack.frameRateNum !== undefined && videoTrack.frameRateDen !== undefined &&
          videoTrack.frameRateDen > 0) {
        this.videoFps = (videoTrack.frameRateNum / videoTrack.frameRateDen).toFixed(3);
      } else {
        this.videoFps = '';
      }
      if (videoTrack.bitrate > 0) {
        this.bitrate = String(videoTrack.bitrate);
      } else {
        this.bitrate = '';
      }
    } else {
      this.videoLang = '';
      this.videoFps = '';
      this.bitrate = '';
    }

    const audioTrack = allTracks.find((t) => t.type === 0 && t.id === curAudioId);
    if (audioTrack) {
      this.audioLang = audioTrack.language.length > 0 ? audioTrack.language : '';
      this.audioChannels = audioTrack.channels !== undefined && audioTrack.channels > 0 ? String(audioTrack.channels) : '';
      this.audioSampleRate = audioTrack.sampleRate !== undefined && audioTrack.sampleRate > 0 ? String(audioTrack.sampleRate) : '';
      // 如果视频轨道没给码率但音频有,兜底用音频的
      if (this.bitrate.length === 0 && audioTrack.bitrate > 0) {
        this.bitrate = String(audioTrack.bitrate);
      }
    } else {
      this.audioLang = '';
      this.audioChannels = '';
      this.audioSampleRate = '';
    }
  }

  onSpeedConfirm(action: PlaybackSpeedAction): void {
    this.vm.setSpeed(action.speed);
    promptAction.showToast({ message: `播放速度已设为 ${action.speed.toFixed(2)}x` });
    this.closeSheet();
  }

  onControlsConfirm(s: ControlsState): void {
    // 持久化控制设置偏好
    Settings.put(Settings.ENABLE_VOLUME_GESTURE, s.volGesture);
    Settings.put(Settings.ENABLE_BRIGHTNESS_GESTURE, s.brightGesture);
    Settings.put(Settings.ENABLE_SEEK_BUTTONS, s.swipeSeek);
    Settings.put(Settings.ENABLE_SWIPE_SEEK, s.swipeSeek);
    Settings.put(Settings.ENABLE_DOUBLE_TAP_SEEK, s.doubleTapSeek);
    void this.touch.refreshPrefs();
    promptAction.showToast({ message: '控制设置已保存' });
    this.closeSheet();
  }

  /** 「保存到播放列表」确认回调:将当前视频 URI 写入选中歌单并持久化。 */
  async onSavePlaylistConfirm(action: AddToPlaylistAction): Promise<void> {
    const uri: string = this.vm.uri;
    if (uri.length === 0) {
      promptAction.showToast({ message: '当前没有可保存的视频' });
      this.closeSheet();
      return;
    }
    await MediaLibrary.initPlaylistCache();
    for (const playlistId of action.selectedIds) {
      if (action.replace) {
        await MediaLibrary.replacePlaylist(playlistId, [uri]);
      } else {
        await MediaLibrary.addToPlaylist(playlistId, uri);
      }
    }
    const count: number = action.selectedIds.length;
    promptAction.showToast({ message: count === 1 ? '已保存到播放列表' : `已保存到 ${count} 个播放列表` });
    this.closeSheet();
  }

  /** 加载当前视频的持久化书签（URI 变化时重新加载）。 */
  async loadBookmarksForCurrentUri(): Promise<void> {
    const uri: string = this.vm.uri;
    if (uri.length === 0 || uri === this.bookmarkUri) {
      return;
    }
    this.bookmarkUri = uri;
    const loaded: BookMark[] = await MediaLibrary.loadBookmarks(uri);
    this.bookmarks = loaded.sort((a: BookMark, b: BookMark) => a.timeMs - b.timeMs);
    this.bookmarkIdSeq = loaded.length > 0 ? Math.max(...loaded.map((b: BookMark) => b.id)) + 1 : 1;
  }

  /** 持久化当前书签列表。 */
  private async persistBookmarks(): Promise<void> {
    if (this.bookmarkUri.length > 0) {
      await MediaLibrary.saveBookmarks(this.bookmarkUri, this.bookmarks);
    }
  }

  /** 在当前播放位置新增一条书签（自动持久化）。 */
  addBookmarkAtCurrent(): void {
    const timeMs: number = Math.max(0, Math.floor(this.vm.position));
    const bm: BookMark = new BookMark(this.bookmarkIdSeq++, -1, timeMs, '');
    this.bookmarks = [...this.bookmarks, bm].sort((a: BookMark, b: BookMark) => a.timeMs - b.timeMs);
    void this.persistBookmarks();
    promptAction.showToast({ message: '已保存书签' });
  }

  /** 删除指定 id 的书签（自动持久化）。 */
  deleteBookmark(id: number): void {
    this.bookmarks = this.bookmarks.filter((b: BookMark) => b.id !== id);
    void this.persistBookmarks();
  }

  /** 重命名书签:本期直接在 toBoolean 提示里给出占位 toast。 */
  renameBookmark(id: number): void {
    void id;
    promptAction.showToast({ message: '书签重命名功能开发中' });
  }

  /** A-B 循环点时间显示:mm:ss / h:mm:ss。 */
  fmtAbPoint(ms: number): string {
    const safe: number = ms > 0 ? ms : 0;
    const totalSec: number = Math.floor(safe / 1000);
    const h: number = Math.floor(totalSec / 3600);
    const m: number = Math.floor((totalSec % 3600) / 60);
    const s: number = totalSec % 60;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const ss: string = s < 10 ? `0${s}` : `${s}`;
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  aboutToAppear(): void {
    this.bindTouch();
    void this.initVolumeAndBrightness();
    void this.applyScreenOrientation();
    void this.touch.refreshPrefs();
    this.resetHudTimer();
  }

  aboutToDisappear(): void {
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    if (this.brightnessHudTimer !== -1) {
      clearTimeout(this.brightnessHudTimer);
      this.brightnessHudTimer = -1;
    }
    if (this.volumeHudTimer !== -1) {
      clearTimeout(this.volumeHudTimer);
      this.volumeHudTimer = -1;
    }
    if (this.seekHudTimer !== -1) {
      clearTimeout(this.seekHudTimer);
      this.seekHudTimer = -1;
    }
    void this.restoreScreenOrientation();
    void this.restoreSystemBrightnessIfNeeded();
    this.touch.clearTouchAction();
    this.clearSleepTimer();
    void this.stopPopupPlayer();
    this.vm.release();
  }

  /**
   * "仅播放音频"模式:把当前视频以音频形式播放,关闭视频渲染,弹回主页让 MiniPlayer 显示。
   *
   * 关键:不要在这里手动 stop/leaveEarly —— aboutToDisappear 会按 stop → detachViews 的
   * 正常顺序清理,中途插入 stop 会让 native 层进入混乱状态(切到下一首时 attachViews 失败导致
   * 30 次重试 + 卡死 + 闪退)。让 aboutToDisappear 一并处理。
   */
  async playAsAudio(): Promise<void> {
    const cur: QueueItem | null = PlaybackService.getCurrent();
    const uri: string = cur?.uri ?? this.vm.uri;
    if (uri.length === 0) {
      promptAction.showToast({ message: '没有可播放的视频' });
      return;
    }
    const svc = PlaybackService.getInstance();
    // 保存当前播放进度(stop 之后 position 会清零)
    const savedPosition: number = svc.getPosition();

    // 1. 先 stop + detach,让 player 进入干净状态(stopped + 无 videoOut)
    //    这样 leaveEarly 里的 detachViews 就是 no-op,不会"播放中 detach"
    svc.stop();
    svc.detachViews();

    // 2. 构建单元素队列并加载(prepareList replace=true 会重置 playAsAudio=false)
    const qi: QueueItem = new QueueItem(
      cur?.id ?? 0,
      cur?.title ?? this.vm.title,
      uri,
      cur?.artistName ?? '',
      cur?.albumName ?? '',
      cur?.artworkPath ?? ''
    );
    await PlaybackService.playList([qi], 0, true);
    // 把保存的进度 seek 回去(>0 才有意义,且要在 play 之前让 libVLC 准备时间)
    if (savedPosition > 0) {
      PlaybackService.seek(savedPosition);
    }
    // 重新打开"仅播放音频"标记
    PlaybackService.setPlayAsAudio(true);
    // 触发播放(若 loadCurrent 已经启动,这步会保持 PLAYING)
    await PlaybackService.play();
    // 现在安全 pop —— aboutToDisappear 会调 vm.release() → leaveEarly(stop) + cleanUI(detachViews)
    NavController.pop();
    promptAction.showToast({ message: '已切换为仅播放音频' });
  }

  /** 进入画中画模式:用 XComponent 控制器创建 PiPController 并启动。 */
  async enterPopupPlayer(): Promise<void> {
    if (!PiPWindow.isPiPEnabled()) {
      promptAction.showToast({ message: '当前设备不支持画中画' });
      return;
    }
    if (!this.pipXc) {
      promptAction.showToast({ message: '视频尚未就绪' });
      return;
    }
    try {
      const ctx = AppContext.get();
      const config: PiPWindow.PiPConfiguration = {
        context: ctx,
        componentController: this.pipXc,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: this.vm.videoWidth > 0 ? this.vm.videoWidth : 1920,
        contentHeight: this.vm.videoHeight > 0 ? this.vm.videoHeight : 1080,
        controlGroups: [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT],
      };
      const controller = await PiPWindow.create(config);
      controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        hilog.info(0x0001, 'VLC', '[PiP] state=%{public}d reason=%{public}s', state, reason);
        if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ABOUT_TO_STOP) {
          controller.off('stateChange');
          controller.off('controlPanelActionEvent');
          this.pipController = null;
        }
      });
      // 视频模板的控制事件:nextVideo / previousVideo 转发到 ViewModel
      controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType) => {
        if (event === 'nextVideo') {
          this.vm.next();
        } else if (event === 'previousVideo') {
          this.vm.prev();
        } else if (event === 'playbackStateChanged') {
          this.vm.toggle();
        }
      });
      await controller.startPiP();
      this.pipController = controller;
      promptAction.showToast({ message: '已进入画中画' });
    } catch (e) {
      hilog.error(0x0001, 'VLC', '[PiP] failed: %{public}s', (e as Error).message ?? String(e));
      promptAction.showToast({ message: '画中画启动失败' });
    }
  }

  /** 停止画中画并清理回调。 */
  async stopPopupPlayer(): Promise<void> {
    if (!this.pipController) {
      return;
    }
    const c = this.pipController;
    this.pipController = null;
    try {
      c.off('stateChange');
      c.off('controlPanelActionEvent');
      await c.stopPiP();
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[PiP] stop failed: %{public}s', (e as Error).message ?? String(e));
    }
  }

  private bindTouch(): void {
    if (this.touchBound) {
      return;
    }
    this.touchBound = true;
    this.touch.bind({
      doPlayPause: (): void => {
        if (this.vm.locked) {
          return;
        }
        this.vm.toggle();
        this.resetHudTimer();
      },
      onSingleTap: (): void => {
        this.toggleHud();
      },
      seekDelta: (deltaMs: number): void => {
        if (this.vm.locked) {
          return;
        }
        const next: number = this.vm.position + deltaMs;
        const clamped: number = this.vm.duration > 0
          ? Math.max(0, Math.min(this.vm.duration, next))
          : Math.max(0, next);
        this.vm.seekTo(clamped);
        this.resetHudTimer();
      },
      getContainerWidth: (): number => {
        return this.vm.containerWidth;
      },
      getContainerHeight: (): number => {
        return this.vm.containerHeight;
      },
      getPosition: (): number => {
        return this.vm.position;
      },
      getDuration: (): number => {
        return this.vm.duration;
      },
      isHudVisible: (): boolean => {
        return this.vm.hudVisible;
      },
      onPanBegan: (): void => {
        if (this.vm.locked) {
          return;
        }
        if (this.hudTimer !== -1) {
          clearTimeout(this.hudTimer);
          this.hudTimer = -1;
        }
        this.vm.hudVisible = false;
        this.volumeAcc = this.volumeLevel;
      },
      onVolumePan: (deltaNorm: number): void => {
        if (this.vm.locked) {
          return;
        }
        const span: number = Math.max(1, this.volumeMax - this.volumeMin);
        this.volumeAcc = Math.max(this.volumeMin, Math.min(this.volumeMax, this.volumeAcc + deltaNorm * span));
        const next: number = Math.round(this.volumeAcc);
        if (next !== this.volumeLevel) {
          this.volumeLevel = next;
          hilog.info(0x0001, 'VLC', '[VLC] volumeLevel -> %{public}d', next);
        }
        this.volumeHudVisible = true;
        this.brightnessHudVisible = false;
        this.seekHudVisible = false;
        this.armVolumeHudTimer();
      },
      onBrightnessPan: (deltaNorm: number): void => {
        if (this.vm.locked) {
          return;
        }
        this.brightnessLevel = Math.max(0, Math.min(1, this.brightnessLevel + deltaNorm));
        this.brightnessHudVisible = true;
        this.volumeHudVisible = false;
        this.seekHudVisible = false;
        void this.applyBrightness(this.brightnessLevel);
        hilog.info(0x0001, 'VLC', '[VLC] brightnessLevel -> %{public}s',
          this.brightnessLevel.toFixed(2));
        this.armBrightnessHudTimer();
      },
      onSeekPan: (jumpMs: number, targetMs: number): void => {
        if (this.vm.locked) {
          return;
        }
        this.pendingSeekTarget = targetMs;
        const sign: string = jumpMs >= 0 ? '+' : '';
        this.seekHudText = `${sign}${fmtTime(Math.abs(jumpMs))} (${fmtTime(targetMs)})`;
        this.seekHudVisible = true;
        this.volumeHudVisible = false;
        this.brightnessHudVisible = false;
        if (this.seekHudTimer !== -1) {
          clearTimeout(this.seekHudTimer);
          this.seekHudTimer = -1;
        }
      },
      onPanEnded: (mode: VideoPanMode): void => {
        if (this.vm.locked) {
          return;
        }
        if (mode === VideoPanMode.Brightness && this.saveBrightness) {
          void Settings.put(Settings.BRIGHTNESS_VALUE, this.brightnessLevel);
        }
        if (mode === VideoPanMode.Brightness) {
          this.armBrightnessHudTimer();
        }
        if (mode === VideoPanMode.Volume) {
          this.volumeAcc = this.volumeLevel;
          this.armVolumeHudTimer();
        }
        if (mode === VideoPanMode.Seek) {
          if (this.pendingSeekTarget >= 0) {
            this.vm.seekTo(this.pendingSeekTarget);
            hilog.info(0x0001, 'VLC', '[VLC] swipe seek -> %{public}d', this.pendingSeekTarget);
            this.pendingSeekTarget = -1;
          }
          this.armSeekHudTimer();
        }
      },
    });
  }

  private async initVolumeAndBrightness(): Promise<void> {
    try {
      const volMgr = audio.getAudioManager().getVolumeManager();
      const group = await volMgr.getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
      this.volumeMin = await group.getMinVolume(audio.AudioVolumeType.MEDIA);
      this.volumeMax = await group.getMaxVolume(audio.AudioVolumeType.MEDIA);
      this.volumeLevel = await group.getVolume(audio.AudioVolumeType.MEDIA);
      this.volumeAcc = this.volumeLevel;
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] init volume failed %{public}s', JSON.stringify(e));
    }
    try {
      this.mainWindow = await window.getLastWindow(AppContext.get());
      this.saveBrightness = await Settings.getBoolean(Settings.SAVE_BRIGHTNESS, false);
      if (this.saveBrightness) {
        const saved: number = await Settings.getFloat(Settings.BRIGHTNESS_VALUE, 0.5);
        this.brightnessLevel = Math.max(0, Math.min(1, saved));
        await this.mainWindow.setWindowBrightness(this.brightnessLevel);
      } else {
        this.brightnessLevel = 0.5;
      }
      await this.mainWindow.setWindowKeepScreenOn(true);
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] init brightness failed %{public}s', JSON.stringify(e));
    }
  }

  private async restoreSystemBrightnessIfNeeded(): Promise<void> {
    if (this.mainWindow === null) {
      return;
    }
    try {
      await this.mainWindow.setWindowKeepScreenOn(false);
      if (!this.saveBrightness) {
        await this.mainWindow.setWindowBrightness(-1);
      }
    } catch (_e) {
      // ignore
    }
  }

  /** 依据「视频屏幕方向」设置旋转主窗口(进入播放页时应用,勾选后即可控制视频播放方向)。 */
  private async applyScreenOrientation(): Promise<void> {
    try {
      const value: string = await Settings.getString(Settings.SCREEN_ORIENTATION, SCREEN_ORIENTATION_DEFAULT);
      this.orientationValue = value;
      if (this.mainWindow === null) {
        this.mainWindow = await window.getLastWindow(AppContext.get());
      }
      await this.mainWindow.setPreferredOrientation(windowOrientationFor(value));
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] applyScreenOrientation failed %{public}s', JSON.stringify(e));
    }
  }

  /** 离开播放页时恢复系统默认方向,避免设置页等其它页面保持横屏。 */
  private async restoreScreenOrientation(): Promise<void> {
    try {
      if (this.mainWindow === null) {
        this.mainWindow = await window.getLastWindow(AppContext.get());
      }
      await this.mainWindow.setPreferredOrientation(window.Orientation.UNSPECIFIED);
    } catch (_e) {
      // ignore
    }
  }

  private openOrientationDialog(): void {
    Settings.getString(Settings.SCREEN_ORIENTATION, SCREEN_ORIENTATION_DEFAULT).then((value: string) => {
      this.orientationValue = value;
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.playerOrientationDialogContent();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.orientationDialogId = dialogId;
      });
    });
  }

  private closeOrientationDialog(): void {
    if (this.orientationDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.orientationDialogId);
    }
    this.orientationDialogId = -1;
  }

  private onOrientationSelect(value: string): void {
    this.orientationValue = value;
    Settings.put(Settings.SCREEN_ORIENTATION, value);
    this.closeOrientationDialog();
    void this.applyScreenOrientation();
  }

  @Builder
  playerOrientationDialogContent() {
    Column() {
      ScreenOrientationDialog({
        title: '视频屏幕方向',
        labels: SCREEN_ORIENTATION_LABELS,
        values: SCREEN_ORIENTATION_VALUES,
        selectedValue: this.orientationValue,
        onSelect: (value: string) => this.onOrientationSelect(value),
        onCancel: () => this.closeOrientationDialog(),
      })
        .width('100%')
    }
    .width('100%')
  }

  private async applyBrightness(value: number): Promise<void> {
    try {
      if (this.mainWindow === null) {
        this.mainWindow = await window.getLastWindow(AppContext.get());
      }
      await this.mainWindow.setWindowBrightness(value);
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] setWindowBrightness failed %{public}s', JSON.stringify(e));
    }
  }

  private armBrightnessHudTimer(): void {
    if (this.brightnessHudTimer !== -1) {
      clearTimeout(this.brightnessHudTimer);
    }
    this.brightnessHudTimer = setTimeout(() => {
      this.brightnessHudTimer = -1;
      this.brightnessHudVisible = false;
    }, 1200);
  }

  private armVolumeHudTimer(): void {
    if (this.volumeHudTimer !== -1) {
      clearTimeout(this.volumeHudTimer);
    }
    this.volumeHudTimer = setTimeout(() => {
      this.volumeHudTimer = -1;
      this.volumeHudVisible = false;
    }, 1200);
  }

  private armSeekHudTimer(): void {
    if (this.seekHudTimer !== -1) {
      clearTimeout(this.seekHudTimer);
    }
    this.seekHudTimer = setTimeout(() => {
      this.seekHudTimer = -1;
      this.seekHudVisible = false;
    }, 1200);
  }

  /** 显示 HUD 并重置 4s 自动隐藏计时。锁定态下禁止显示 HUD。 */
  resetHudTimer(): void {
    if (this.vm.locked) {
      return;
    }
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
      // A-B 循环等待设 B 时也保持可见:用户需要看到「设置 B」按钮。
      const waitingAbB: boolean = this.vm.abPointA >= 0 && !this.vm.abActive;
      if (this.vm.state === PlayState.PLAYING && !this.seeking && !this.sheetOpen &&
          !this.advancedOptionsOpen && !waitingAbB) {
        this.vm.hudVisible = false;
      }
    }, 4000);
  }

  /** 点击画面:HUD 可见则隐藏,不可见则显示。锁定态下无响应(锁图标已提供视觉反馈)。 */
  toggleHud(): void {
    if (this.vm.locked) {
      return;
    }
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
    if (this.vm.locked) {
      return;
    }
    if (id === 'tracks') {
      this.openSub('tracks');
    } else if (id === 'play') {
      this.vm.toggle();
    } else if (id === 'orientation') {
      this.openOrientationDialog();
    } else if (id === 'aspectRatio') {
      promptAction.showToast({ message: 'Aspect ratio is not available yet' });
    }
    this.resetHudTimer();
  }

  build() {
    NavDestination() {
      // z 序：XComponent → 指示 HUD → 控制 HUD → 顶层 Transparent 手势层
      Stack({ alignContent: Alignment.Center }) {
        // 视频画面 —— contain 等比例;未拿到尺寸前先铺满
        XComponent({
          id: VLC_VIDEO_XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: VLC_NAPI_LIBRARY,
          controller: this.pipXc,
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

        AVVolumePanel({ volumeLevel: this.volumeLevel })
          .hitTestBehavior(HitTestMode.None)

        if (this.brightnessHudVisible) {
          this.brightnessHud()
        }
        if (this.volumeHudVisible) {
          this.volumeHud()
        }
        if (this.seekHudVisible) {
          this.seekHud()
        }

        // 加载中 / 出错提示(居中,不随 HUD 隐藏)
        if (this.vm.state === PlayState.IDLE) {
          LoadingProgress()
            .width(48).height(48).color('#FFFFFF')
            .hitTestBehavior(HitTestMode.None)
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
          .hitTestBehavior(HitTestMode.None)
        }

        // HUD 在手势层之下；中间 Transparent 透传，顶/底栏 Default 可点
        if (this.vm.hudVisible) {
          Column() {
            this.topBar()
            Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
            this.bottomBar()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .hitTestBehavior(HitTestMode.Transparent)
        }

        // 最顶手势层：竖/横滑 + 延迟单击；双击用 TapGesture。锁定时完全禁止触摸。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#01000000')
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch((event: TouchEvent) => {
            if (this.vm.locked) {
              return;
            }
            this.touch.onTouchEvent(event);
          })
          .gesture(
            TapGesture({ count: 2 })
              .onAction((event: GestureEvent) => {
                if (this.vm.locked) {
                  return;
                }
                let x: number = 0;
                if (event.fingerList.length > 0) {
                  x = event.fingerList[0].localX;
                }
                this.touch.onDoubleTap(x);
              })
          )

        // 锁定图标：锁定后始终显示在最左侧，点击可解锁
        if (this.vm.locked) {
          Row() {
            Image($r('app.media.ic_lock_player'))
              .width(28).height(28)
              .fillColor('#FFFFFF')
          }
          .width(52).height(52)
          .borderRadius(26)
          .backgroundColor('#66000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Default)
          .position({ x: 16, y: '50%' })
          .translate({ x: 0, y: -26 })
          .onClick(() => {
            this.vm.toggleLock();
            // 解锁后显示 HUD 以便用户操作
            if (!this.vm.locked) {
              this.resetHudTimer();
            }
          })
        }

        // 书签弹框:不走 bindSheet,直接以 Stack 子层叠在视频上方,保持半透看到背后画面。
        if (this.bookmarkOpen) {
          Column() {
            Blank()
            BookmarkDialog({
              bookmarks: this.bookmarks,
              currentTimeMs: this.vm.position,
              durationMs: this.vm.duration,
              onClose: () => {
                this.bookmarkOpen = false;
                this.resetHudTimer();
              },
              onSeek: (timeMs: number) => { this.vm.seekTo(timeMs); },
              onAddAtCurrent: () => this.addBookmarkAtCurrent(),
              onDelete: (id: number) => this.deleteBookmark(id),
              onRename: (id: number) => this.renameBookmark(id),
            })
              .width('100%')
              .height('66.66%')
          }
          .width('100%')
          .height('100%')
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
      height: (this.sheetKind === 'speed' || this.sheetKind === 'savePlaylist')
        ? SheetSize.MEDIUM
        : SheetSize.FIT_CONTENT,
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
          if (this.vm.locked) {
            return;
          }
          this.vm.leaveEarly();
          NavController.pop();
        })
      Text(this.vm.title)
        .fontSize(18).fontColor('#FFFFFF').layoutWeight(1).margin({ left: 12, right: 12 })
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      // A-B 循环指示灯
      if (this.vm.abPointA >= 0) {
        Row() {
          Text('A-B')
            .fontSize(12).fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('#FF8800')
        }
        .margin({ right: 12 })
        .onClick(() => this.vm.resetAb())
      }
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
          if (this.vm.locked) {
            return;
          }
          this.resetHudTimer();
          this.openOptions();
        })
        .bindMenu(this.advancedOptionsOpen!!, this.advancedOptionsMenu(), {
          placement: Placement.BottomRight,
          showInSubWindow: true,
          backgroundColor: $r('app.color.background_default'),
          onDisappear: () => this.runPendingAdvancedAction(),
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 16 })
    .alignItems(VerticalAlign.Center)
    .linearGradient({ angle: 180, colors: [['#cb000000', 0.0], ['#00000000', 1.0]] })
    .hitTestBehavior(HitTestMode.Default)
  }

  /** 底部控制栏(遮罩自下而上渐隐 → 颜色停靠反过来,角度仍是 180)。 */
  @Builder
  bottomBar() {
    Column() {
      // A-B 循环设置行(已设 A 后显示)
      if (this.vm.abPointA >= 0) {
        Row() {
          Text(`A ${this.fmtAbPoint(this.vm.abPointA)} → B ${this.vm.abActive ? this.fmtAbPoint(this.vm.abPointB) : '???'}`)
            .fontSize(12).fontColor('#FF8800')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.vm.abActive) {
            Text('关闭')
              .fontSize(12).fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12)
              .backgroundColor('#33FFFFFF')
              .onClick(() => this.vm.resetAb())
          } else {
            Text('设置 B')
              .fontSize(12).fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .borderRadius(12)
              .backgroundColor('#FF8800')
              .onClick(() => {
                this.vm.setAbPointB();
                promptAction.showToast({ message: this.vm.abActive ? 'A-B 循环已开启' : 'B 点需在 A 点之后' });
              })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }

      // seek bar
      Row() {
        Text(fmtTime(this.displayPosition()))
          .fontSize(12).fontColor('#FFFFFF').width(52)
        // Slider 外面套 Stack:进度条上叠加 A 点竖线 + 顶部小三角。
        Stack({ alignContent: Alignment.TopStart }) {
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
            .enabled(true)
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

          // A 点标记:竖线 + 顶部小三角 + 「A」徽标
          if (this.vm.abPointA >= 0 && this.vm.duration > 0) {
            Column() {
              Text('A')
                .fontSize(10).fontColor('#FFFFFF')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor('#FF8800')
              // 倒三角
              Text('▼')
                .fontSize(8).fontColor('#FF8800')
                .margin({ top: -1 })
            }
            .alignItems(HorizontalAlign.Center)
            .offset({
              x: `${Math.min(100, Math.max(0, this.vm.abPointA * 100 / this.vm.duration))}%`,
              y: 0,
            })
            // 让 Column 中心对到 offset 处
            .translate({ x: -8 })

          // B 点标记:竖线 + 顶部小三角 + 「B」徽标
          if (this.vm.abActive) {
            Column() {
              Text('B')
                .fontSize(10).fontColor('#FFFFFF')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor('#FF3B30')
              Text('▼')
                .fontSize(8).fontColor('#FF3B30')
                .margin({ top: -1 })
            }
            .alignItems(HorizontalAlign.Center)
            .offset({
              x: `${Math.min(100, Math.max(0, this.vm.abPointB * 100 / this.vm.duration))}%`,
              y: 0,
            })
            .translate({ x: -8 })
          }
          }
        }
        .layoutWeight(1)
        .height(40)
        Text(fmtTime(this.vm.duration))
          .fontSize(12).fontColor('#FFFFFF').width(52).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      // 音轨和字幕、屏幕方向、播放、宽高比、高级选项。
      Row() {
        ForEach(buildVideoPlayerBottomActions(), (action: VideoPlayerBottomAction) => {
            Image(this.bottomActionIcon(action))
              .width(action.id === 'play' ? 56 : 32)
              .height(action.id === 'play' ? 56 : 32)
              .fillColor('#FFFFFF')
              .onClick(() => this.onBottomAction(action.id))
        }, (action: VideoPlayerBottomAction): string => action.id)
        // 循环模式:0=关闭(白),1=列表循环(橙),2=单曲循环(橙 + 数字 1)
        Image(this.vm.repeatMode === 2 ? $r('app.media.ic_repeat_one_audio') : $r('app.media.ic_repeat_audio'))
          .width(32).height(32)
          .fillColor(this.vm.repeatMode > 0 ? '#FF8800' : '#FFFFFF')
          .onClick(() => {
            const svc = PlaybackService.getInstance();
            // 二态切换(0↔1)：与高级菜单中 'repeat' 项保持一致。
            const next = svc.getRepeatMode() === 0 ? 1 : 0;
            while (svc.getRepeatMode() !== next) {
              svc.cycleRepeat();
            }
            this.vm.repeatMode = next;
            promptAction.showToast({
              message: next === 1 ? '已开启循环播放' : '已关闭循环播放'
            });
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 12 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .linearGradient({ angle: 180, colors: [['#00000000', 0.0], ['#cb000000', 1.0]] })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  seekHud() {
    Column({ space: 6 }) {
      Text('进度')
        .fontSize(14).fontColor('#FFFFFF')
      Text(this.seekHudText)
        .fontSize(16).fontColor('#FF8800').fontWeight(FontWeight.Medium)
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  brightnessHud() {
    Column({ space: 8 }) {
      Text('亮度')
        .fontSize(14).fontColor('#FFFFFF')
      Progress({
        value: this.brightnessLevel * 100,
        total: 100,
        type: ProgressType.Linear,
      })
        .width(140)
        .height(4)
        .color('#FF8800')
        .backgroundColor('#61FFFFFF')
      Text(`${Math.round(this.brightnessLevel * 100)}%`)
        .fontSize(12).fontColor('#FFFFFF')
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  volumeHud() {
    Column({ space: 8 }) {
      Text('音量')
        .fontSize(14).fontColor('#FFFFFF')
      Progress({
        value: this.volumeMax > this.volumeMin
          ? ((this.volumeLevel - this.volumeMin) * 100 / (this.volumeMax - this.volumeMin))
          : 0,
        total: 100,
        type: ProgressType.Linear,
      })
        .width(140)
        .height(4)
        .color('#FF8800')
        .backgroundColor('#61FFFFFF')
      Text(`${this.volumeLevel}`)
        .fontSize(12).fontColor('#FFFFFF')
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
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
      } else if (this.sheetKind === 'speed') {
        PlaybackSpeedDialog({
          currentSpeed: this.vm.speed,
          onClose: () => this.closeSheet(),
          onConfirm: (action: PlaybackSpeedAction) => this.onSpeedConfirm(action),
        }).width('100%')
      } else if (this.sheetKind === 'controls') {
        VideoControlsSettingsDialog({
          onClose: () => this.closeSheet(),
          onConfirm: (s: ControlsState) => this.onControlsConfirm(s),
        }).width('100%')
      } else if (this.sheetKind === 'equalizer') {
        EqualizerDialog({
          onClose: () => this.closeSheet(),
        }).width('100%')
      } else if (this.sheetKind === 'videoInfo') {
        VideoInfoDialog({
          title: this.vm.title,
          durationMs: this.vm.duration,
          videoWidth: this.vm.videoWidth,
          videoHeight: this.vm.videoHeight,
          videoCodec: this.videoCodecName,
          audioCodec: this.audioCodecName,
          videoLang: this.videoLang,
          videoFps: this.videoFps,
          audioLang: this.audioLang,
          audioChannels: this.audioChannels,
          audioSampleRate: this.audioSampleRate,
          bitrate: this.bitrate,
          onClose: () => this.closeSheet(),
        }).width('100%')
      } else if (this.sheetKind === 'savePlaylist') {
        AddToPlaylistDialog({
          mediaCount: this.vm.listLen,
          onClose: () => this.closeSheet(),
          onConfirm: (action: AddToPlaylistAction) => this.onSavePlaylistConfirm(action),
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
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .padding({ left: 16, right: 16 })
        .height(56)
        .textAlign(TextAlign.Start)

      this.optionRow('Jump to time', () => this.openSub('jump'))
      this.optionRow('Playback speed', () => this.openSub('speed'))
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
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(20).height(20)
        .fillColor($r('app.color.font_light'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onTap())
  }

  advancedActiveIds(): PlayerAdvancedOptionId[] {
    const ids: PlayerAdvancedOptionId[] = [];
    if (this.vm.locked) {
      ids.push('lock');
    }
    if (this.vm.repeatMode !== 0) {
      ids.push('repeat');
    }
    return ids;
  }

  @Builder
  advancedOptionsMenu() {
    PlayerAdvancedOptions({
      items: buildPlayerAdvancedOptions('video'),
      activeIds: this.advancedActiveIds(),
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
    if (id === 'lock') {
      this.vm.toggleLock();
      this.resetHudTimer();
      return;
    }
    if (id === 'sleep') {
      this.openSub('sleep');
      return;
    }
    if (id === 'speed') {
      this.openSub('speed');
      return;
    }
    if (id === 'jumpToTime') {
      this.openSub('jump');
      return;
    }
    if (id === 'equalizer') {
      this.openSub('equalizer');
      return;
    }
    if (id === 'videoInfo') {
      this.refreshVideoInfoTracks();
      this.openSub('videoInfo');
      return;
    }
    if (id === 'bookmark') {
      void this.loadBookmarksForCurrentUri();
      this.bookmarkOpen = true;
      return;
    }
    if (id === 'videoControls') {
      this.openSub('controls');
      return;
    }
    if (id === 'savePlaylist') {
      this.openSub('savePlaylist');
      return;
    }
    if (id === 'playAsAudio') {
      void this.playAsAudio();
      return;
    }
    if (id === 'popupPlayer') {
      void this.enterPopupPlayer();
      return;
    }
    if (id === 'abRepeat') {
      if (this.vm.abActive) {
        this.vm.resetAb();
        promptAction.showToast({ message: '已关闭 A-B 循环' });
      } else if (this.vm.abPointA < 0) {
        this.vm.setAbPointA();
        // 强制 HUD 持续可见 —— 等待用户设 B 时不能自动隐藏。
        this.vm.hudVisible = true;
        if (this.hudTimer !== -1) {
          clearTimeout(this.hudTimer);
          this.hudTimer = -1;
        }
        promptAction.showToast({ message: '已设置 A 点,请拖动至结束位置后再次点击 A-B 循环' });
      } else {
        this.vm.setAbPointB();
        if (this.vm.abActive) {
          promptAction.showToast({ message: 'A-B 循环已开启' });
        } else {
          promptAction.showToast({ message: 'B 点需在 A 点之后' });
        }
      }
      return;
    }
    if (id === 'repeat') {
      const svc = PlaybackService.getInstance();
      // 二态切换(0↔1):用户视角是「开关」式,避免三态循环让「关闭循环」需要两次点击。
      const next: number = svc.getRepeatMode() === 0 ? 1 : 0;
      // 走 cycleRepeat 三次等价于循环回原值;此处用 emitQueue 让 onQueueChanged 同步 vm 状态。
      while (svc.getRepeatMode() !== next) {
        svc.cycleRepeat();
      }
      this.vm.repeatMode = next;
      promptAction.showToast({ message: next === 1 ? '已开启循环播放' : '已关闭循环播放' });
      return;
    }
    promptAction.showToast({ message: '该功能暂未实现' });
  }

}
