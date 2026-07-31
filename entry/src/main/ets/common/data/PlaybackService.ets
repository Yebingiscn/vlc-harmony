/**
 * PlaybackService —— 全局单例播放服务(libVLC NAPI)。
 * 视频出画:setVideoOut(xcomponentId) → OHNativeWindow → libvlc_media_player_set_ohos_nativewindow_ptr。
 * 点播视频时先 prepareList(不 play),等 VideoPlayerPage Surface 就绪后再 bindAndPlay。
 */
import {
  init as vlcInit,
  setEventListener as vlcSetEventListener,
  setMedia as vlcSetMedia,
  setMediaFd as vlcSetMediaFd,
  setVideoOut as vlcSetVideoOut,
  hasNativeWindow as vlcHasNativeWindow,
  play as vlcPlay,
  pause as vlcPause,
  stop as vlcStop,
  setTime as vlcSetTime,
  setRate as vlcSetRate,
  getVideoSize as vlcGetVideoSize,
  setScale as vlcSetScale,
  release as vlcRelease,
} from 'libvlcnapi.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { MediaWrapper, PlayState } from '../models/MediaModels';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

/** 鸿蒙媒体库/datashare URI:不能当本地 file 路径交给 VLC,需 fd 打开。 */
function needsFdOpen(uri: string): boolean {
  if (uri.startsWith('file://media/')) {
    return true;
  }
  if (uri.startsWith('datashare://')) {
    return true;
  }
  if (uri.startsWith('file://') && uri.indexOf('/Photo/') >= 0) {
    return true;
  }
  return false;
}

export interface PlaybackListener {
  onStateChange(state: PlayState): void;
  onTimeUpdate(current: number, duration: number): void;
  onQueueChanged(): void;
  /** 视频原始尺寸就绪(用于 UI contain 适配);音频可空实现。 */
  onVideoSize?(width: number, height: number): void;
}

export class PlaybackService {
  private static instance: PlaybackService | null = null;
  private queue: MediaWrapper[] = [];
  private currentIndex: number = -1;
  private state: PlayState = PlayState.IDLE;
  private speed: number = 1.0;
  private shuffle: boolean = false;
  private repeatMode: number = 0;
  private duration: number = 0;
  private position: number = 0;
  private listeners: PlaybackListener[] = [];
  private inited: boolean = false;
  private initializing: boolean = false;
  private videoOutId: string = '';
  private videoWidth: number = 0;
  private videoHeight: number = 0;

  static getInstance(): PlaybackService {
    if (!PlaybackService.instance) {
      PlaybackService.instance = new PlaybackService();
    }
    return PlaybackService.instance;
  }

  private async ensureInit(): Promise<void> {
    if (this.inited) {
      return;
    }
    if (this.initializing) {
      while (this.initializing) {
        await new Promise<void>((r: () => void) => setTimeout(r, 20));
      }
      return;
    }
    this.initializing = true;
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init start');
      if (vlcInit()) {
        vlcSetEventListener((event: string, value: number) => this.onNativeEvent(event, value));
        this.inited = true;
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init ok');
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init FAILED (libvlc_new/media_player)');
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init exception: %{public}s',
        (e as Error).message ?? String(e));
    } finally {
      this.initializing = false;
    }
  }

  private onNativeEvent(event: string, value: number): void {
    hilog.debug(LOG_DOMAIN, LOG_TAG, '[VLC] event %{public}s value=%{public}s', event, String(value));
    switch (event) {
      case 'playing':
        this.state = PlayState.PLAYING;
        this.emitState();
        this.refreshVideoSize();
        break;
      case 'paused':
        this.state = PlayState.PAUSED;
        this.emitState();
        break;
      case 'stopped':
        this.state = PlayState.STOPPED;
        this.emitState();
        break;
      case 'ended':
        this.onComplete();
        break;
      case 'error':
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] MediaPlayerEncounteredError');
        this.state = PlayState.ERROR;
        this.emitState();
        break;
      case 'timeChanged':
        this.position = value;
        this.emitTime();
        break;
      case 'lengthChanged':
        this.duration = value;
        this.emitTime();
        break;
      case 'vout':
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] vout count=%{public}s videoOutId=%{public}s',
          String(value), this.videoOutId);
        this.refreshVideoSize();
        break;
      default:
        break;
    }
  }

  /** 拉取 libVLC 视频尺寸并通知监听者;同时 setScale(0) 让 vout 按窗口比例适配。 */
  refreshVideoSize(): void {
    try {
      vlcSetScale(0);
      const size = vlcGetVideoSize();
      if (size && size.width > 0 && size.height > 0) {
        if (size.width !== this.videoWidth || size.height !== this.videoHeight) {
          this.videoWidth = size.width;
          this.videoHeight = size.height;
          hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] videoSize %{public}dx%{public}d',
            this.videoWidth, this.videoHeight);
          this.emitVideoSize();
        }
      } else {
        // 回退:MediaLibrary 扫描到的元数据
        const cur = this.getCurrent();
        if (cur && cur.width > 0 && cur.height > 0) {
          if (cur.width !== this.videoWidth || cur.height !== this.videoHeight) {
            this.videoWidth = cur.width;
            this.videoHeight = cur.height;
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] videoSize from meta %{public}dx%{public}d',
              this.videoWidth, this.videoHeight);
            this.emitVideoSize();
          }
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] refreshVideoSize: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  getVideoWidth(): number {
    return this.videoWidth;
  }

  getVideoHeight(): number {
    return this.videoHeight;
  }

  getState(): PlayState {
    return this.state;
  }

  getDuration(): number {
    return this.duration;
  }

  getPosition(): number {
    return this.position;
  }

  getQueue(): MediaWrapper[] {
    return this.queue;
  }

  getCurrentIndex(): number {
    return this.currentIndex;
  }

  getCurrent(): MediaWrapper | null {
    return this.currentIndex >= 0 && this.currentIndex < this.queue.length ? this.queue[this.currentIndex] : null;
  }

  getSpeed(): number {
    return this.speed;
  }

  getShuffle(): boolean {
    return this.shuffle;
  }

  getRepeatMode(): number {
    return this.repeatMode;
  }

  addListener(l: PlaybackListener): void {
    if (!this.listeners.includes(l)) {
      this.listeners.push(l);
    }
  }

  removeListener(l: PlaybackListener): void {
    this.listeners = this.listeners.filter((x) => x !== l);
  }

  private emitState(): void {
    for (const l of this.listeners) {
      l.onStateChange(this.state);
    }
  }

  private emitTime(): void {
    for (const l of this.listeners) {
      l.onTimeUpdate(this.position, this.duration);
    }
  }

  private emitQueue(): void {
    for (const l of this.listeners) {
      l.onQueueChanged();
    }
  }

  private emitVideoSize(): void {
    for (const l of this.listeners) {
      if (l.onVideoSize) {
        l.onVideoSize(this.videoWidth, this.videoHeight);
      }
    }
  }

  /**
   * 仅设置播放队列,不立刻 play。
   * 视频页应在 Surface 绑定后再调用 bindAndPlay / play。
   */
  async prepareList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    if (items.length === 0) {
      return;
    }
    await this.ensureInit();
    if (!this.inited) {
      return;
    }
    this.queue = replace ? items.slice() : this.queue.concat(items);
    this.currentIndex = replace ? startIndex : this.queue.length - items.length + startIndex;
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] prepareList size=%{public}d index=%{public}d uri=%{public}s',
      this.queue.length, this.currentIndex, this.getCurrent()?.uri ?? '');
    this.emitQueue();
  }

  /** 音频等无需 Surface 的场景:设队列并立刻播放。 */
  async playList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    await this.prepareList(items, startIndex, replace);
    if (!this.inited) {
      return;
    }
    await this.loadCurrent();
  }

  append(items: MediaWrapper[]): Promise<void> {
    return this.playList(items, 0, false);
  }

  /**
   * 绑定 XComponent 出窗并播放当前队列项。
   * 若 Surface 尚未创建,会短暂重试 setVideoOut;Native 侧 OnSurfaceCreated 也会自动补绑。
   */
  async bindAndPlay(xcomponentId: string, fallbackUri?: string, fallbackTitle?: string): Promise<boolean> {
    await this.ensureInit();
    if (!this.inited) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] bindAndPlay aborted: not inited');
      return false;
    }
    this.videoOutId = xcomponentId;

    if ((!this.getCurrent() || (fallbackUri && this.getCurrent()?.uri !== fallbackUri)) && fallbackUri) {
      const mw = new MediaWrapper(Date.now(), fallbackTitle ?? fallbackUri, fallbackUri, 0);
      this.queue = [mw];
      this.currentIndex = 0;
      this.emitQueue();
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] bindAndPlay fallback queue uri=%{public}s', fallbackUri);
    }

    let bound = false;
    for (let i = 0; i < 30; i++) {
      const hasWin = vlcHasNativeWindow(xcomponentId);
      bound = vlcSetVideoOut(xcomponentId);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] setVideoOut try=%{public}d hasWin=%{public}s bound=%{public}s id=%{public}s',
        i, String(hasWin), String(bound), xcomponentId);
      if (bound) {
        break;
      }
      await new Promise<void>((r: () => void) => setTimeout(r, 50));
    }
    if (!bound) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        '[VLC] NativeWindow not ready after retries; play anyway (native may auto-bind on SurfaceCreated)');
    }

    await this.loadCurrent();
    return bound;
  }

  private async loadCurrent(): Promise<void> {
    const item = this.getCurrent();
    if (!item) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent: empty queue');
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent uri=%{public}s videoOut=%{public}s',
      item.uri, this.videoOutId);

    let ok = false;
    if (needsFdOpen(item.uri)) {
      // 相册 URI → openSync 拿 fd → libvlc_media_new_fd
      try {
        const file = fs.openSync(item.uri, fs.OpenMode.READ_ONLY);
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] openSync ok fd=%{public}d uri=%{public}s', file.fd, item.uri);
        ok = vlcSetMediaFd(file.fd);
        try {
          fs.closeSync(file); // Native 已 dup,可立即关闭
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] closeSync after setMediaFd: %{public}s',
            (closeErr as Error).message ?? String(closeErr));
        }
      } catch (e) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] openSync FAILED uri=%{public}s err=%{public}s',
          item.uri, (e as Error).message ?? String(e));
        ok = false;
      }
    } else {
      ok = vlcSetMedia(item.uri);
    }

    if (!ok) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] setMedia/setMediaFd FAILED uri=%{public}s', item.uri);
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }
    this.duration = 0;
    this.position = 0;
    this.videoWidth = 0;
    this.videoHeight = 0;
    // 元数据预填,vout 前即可先按比例排版
    if (item.width > 0 && item.height > 0) {
      this.videoWidth = item.width;
      this.videoHeight = item.height;
      this.emitVideoSize();
    }
    vlcSetRate(this.speed);
    vlcSetScale(0);
    vlcPlay();
    this.state = PlayState.PREPARED;
    this.emitState();
  }

  private onComplete(): void {
    if (this.repeatMode === 2) {
      vlcSetTime(0);
      vlcPlay();
      return;
    }
    this.next(true);
  }

  async play(): Promise<void> {
    await this.ensureInit();
    if (!this.inited) {
      return;
    }
    if (this.state === PlayState.IDLE || this.state === PlayState.STOPPED || this.state === PlayState.ERROR) {
      await this.loadCurrent();
      return;
    }
    vlcPlay();
  }

  pause(): void {
    vlcPause();
  }

  togglePlay(): void {
    if (this.state === PlayState.PLAYING) {
      this.pause();
    } else {
      this.play();
    }
  }

  stop(): void {
    vlcStop();
    this.state = PlayState.STOPPED;
    this.emitState();
  }

  async next(auto: boolean = false): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }
    let nextIdx: number;
    if (this.shuffle) {
      nextIdx = Math.floor(Math.random() * this.queue.length);
    } else {
      nextIdx = this.currentIndex + 1;
      if (nextIdx >= this.queue.length) {
        if (this.repeatMode === 1 || !auto) {
          nextIdx = 0;
        } else {
          this.stop();
          return;
        }
      }
    }
    this.currentIndex = nextIdx;
    this.emitQueue();
    await this.loadCurrent();
  }

  async prev(): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }
    let prevIdx = this.currentIndex - 1;
    if (prevIdx < 0) {
      prevIdx = this.queue.length - 1;
    }
    this.currentIndex = prevIdx;
    this.emitQueue();
    await this.loadCurrent();
  }

  seek(ms: number): void {
    this.position = ms;
    vlcSetTime(ms);
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    vlcSetRate(rate);
  }

  toggleShuffle(): void {
    this.shuffle = !this.shuffle;
    this.emitQueue();
  }

  cycleRepeat(): void {
    this.repeatMode = (this.repeatMode + 1) % 3;
    this.emitQueue();
  }

  release(): void {
    vlcRelease();
    this.inited = false;
    this.videoOutId = '';
    this.state = PlayState.IDLE;
    this.emitState();
  }
}
