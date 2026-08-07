import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlaybackService, PlaybackListener } from '../../common/data/PlaybackService';
import { Settings } from '../../common/data/Settings';
import { MediaWrapper, PlayState } from '../../common/models/MediaModels';
import { VideoPlayerResizeDelegate } from './VideoPlayerResizeDelegate';

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

/** 播放器专用时长格式化:0 显示 00:00。 */
export function fmtTime(ms: number): string {
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
 * VideoPlayerViewModel —— 播放状态 / 队列 / Surface 尺寸。
 * 对齐 Android VideoPlayerActivity 中与 PlaybackService 交互的部分。
 */
@ObservedV2
export class VideoPlayerViewModel implements PlaybackListener {
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
  private resize: VideoPlayerResizeDelegate = new VideoPlayerResizeDelegate();

  /** Page 注入共享 ResizeDelegate，保证宽高比面板与 contain 同一实例。 */
  attachResize(delegate: VideoPlayerResizeDelegate): void {
    this.resize = delegate;
  }

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
    await svc.prepareList(mws, this.index, true, 'video');
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
    const result = this.resize.computeSurface(
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
    await svc.prepareList(mws, i, true, 'video');
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
