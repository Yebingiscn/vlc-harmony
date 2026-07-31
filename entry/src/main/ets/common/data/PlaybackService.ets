/**
 * PlaybackService —— 全局单例播放业务层。
 * 通过 ArkTS LibVLC/Media/MediaPlayer 对接 libVLC(不再直接 import libvlcnapi.so)。
 * 另提供 QueueItem / PlaybackState / 静态方法门面,兼容 origin/dev 音频 UI 调用方式。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { MediaWrapper, PlayState } from '../models/MediaModels';
import { LibVLC, Media, MediaPlayer, Equalizer, RendererDiscoverer, MediaSlaveType } from '../../libvlc';
import { VlcTrackInfo, VlcChapterInfo, VlcRendererInfo } from 'libvlcnapi.so';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

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

/** 播放队列条目(兼容 origin/dev 音频列表 API;内部仍转 MediaWrapper 走 libVLC)。 */
export class QueueItem {
  id: number;
  title: string;
  uri: string;
  artistName: string;
  albumName: string;
  artworkPath: string;

  constructor(id: number, title: string, uri: string, artistName: string, albumName: string, artworkPath: string) {
    this.id = id;
    this.title = title;
    this.uri = uri;
    this.artistName = artistName;
    this.albumName = albumName;
    this.artworkPath = artworkPath;
  }

  toMediaWrapper(type: number = 1): MediaWrapper {
    const mw = new MediaWrapper(this.id, this.title, this.uri, type);
    mw.artistName = this.artistName;
    mw.albumName = this.albumName;
    mw.artworkPath = this.artworkPath;
    return mw;
  }

  static fromMediaWrapper(mw: MediaWrapper): QueueItem {
    return new QueueItem(mw.id, mw.title, mw.uri, mw.artistName, mw.albumName, mw.artworkPath);
  }
}

/** 播放器可观察快照(兼容 MiniPlayer / AudioPlayer onChange)。 */
export interface PlaybackState {
  state: PlayState;
  title: string;
  artist: string;
  album: string;
  artworkPath: string;
  duration: number;
  position: number;
  speed: number;
  shuffle: boolean;
  repeatMode: number;
  queueSize: number;
  currentIndex: number;
}

export interface PlaybackListener {
  onStateChange?(state: PlayState): void;
  onTimeUpdate?(current: number, duration: number): void;
  onQueueChanged?(): void;
  onVideoSize?(width: number, height: number): void;
  onTracksChanged?(): void;
  /** 兼容 origin/dev:一次推送完整快照。 */
  onChange?(s: PlaybackState): void;
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
  private volume: number = 100;
  /** 睡眠计时「先等当前媒体播完」:播完后 stop,不自动下一首。 */
  private stopAfterCurrent: boolean = false;

  private lib: LibVLC | null = null;
  private player: MediaPlayer | null = null;
  private equalizer: Equalizer | null = null;
  private rendererDiscoverer: RendererDiscoverer | null = null;
  private currentRendererHandle: number = -1;

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
      this.lib = new LibVLC();
      if (this.lib.getHandle() === 0) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] LibVLC create FAILED');
        this.lib.release();
        this.lib = null;
        return;
      }
      this.player = new MediaPlayer(this.lib);
      if (this.player.getHandle() === 0) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] MediaPlayer create FAILED');
        this.player.release();
        this.player = null;
        this.lib.release();
        this.lib = null;
        return;
      }
      this.player.setEventListener((event: string, value: number) => this.onNativeEvent(event, value));
      this.inited = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init ok');
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
      case 'esAdded':
      case 'esDeleted':
      case 'esSelected':
        this.emitTracksChanged();
        break;
      default:
        break;
    }
  }

  refreshVideoSize(): void {
    if (!this.player) {
      return;
    }
    try {
      this.player.setScale(0);
      const size = this.player.getVideoSize();
      if (size && size.width > 0 && size.height > 0) {
        if (size.width !== this.videoWidth || size.height !== this.videoHeight) {
          this.videoWidth = size.width;
          this.videoHeight = size.height;
          hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] videoSize %{public}dx%{public}d',
            this.videoWidth, this.videoHeight);
          this.emitVideoSize();
        }
      } else {
        const cur = this.getCurrent();
        if (cur && cur.width > 0 && cur.height > 0) {
          if (cur.width !== this.videoWidth || cur.height !== this.videoHeight) {
            this.videoWidth = cur.width;
            this.videoHeight = cur.height;
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

  getVolume(): number {
    return this.player ? this.player.getVolume() : this.volume;
  }

  setVolume(v: number): void {
    this.volume = v;
    this.player?.setVolume(v);
  }

  getAudioTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getAudioTracks() : [];
  }

  getSpuTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getSpuTracks() : [];
  }

  getVideoTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getVideoTracks() : [];
  }

  getAudioTrack(): number {
    return this.player ? this.player.getAudioTrack() : -1;
  }

  getSpuTrack(): number {
    return this.player ? this.player.getSpuTrack() : -1;
  }

  getVideoTrack(): number {
    return this.player ? this.player.getVideoTrack() : -1;
  }

  setAudioTrack(id: number): boolean {
    return this.player ? this.player.setAudioTrack(id) : false;
  }

  setSpuTrack(id: number): boolean {
    return this.player ? this.player.setSpuTrack(id) : false;
  }

  setVideoTrack(id: number): boolean {
    return this.player ? this.player.setVideoTrack(id) : false;
  }

  getChapters(): VlcChapterInfo[] {
    return this.player ? this.player.getChapters(-1) : [];
  }

  getChapterIdx(): number {
    return this.player ? this.player.getChapter() : -1;
  }

  setChapter(index: number): void {
    this.player?.setChapter(index);
  }

  addSubtitleSlave(uri: string): boolean {
    return this.player ? this.player.addSlave(MediaSlaveType.Subtitle, uri, true) : false;
  }

  applyEqualizer(enabled: boolean, presetIndex: number, preamp: number, bands: number[]): void {
    if (!this.player) {
      return;
    }
    if (!enabled) {
      this.player.setEqualizer(null);
      if (this.equalizer) {
        this.equalizer.release();
        this.equalizer = null;
      }
      return;
    }
    if (this.equalizer) {
      this.equalizer.release();
      this.equalizer = null;
    }
    this.equalizer = Equalizer.fromPreset(presetIndex) ?? Equalizer.create();
    if (!this.equalizer) {
      return;
    }
    this.equalizer.setPreAmp(preamp);
    for (let i = 0; i < bands.length; i++) {
      this.equalizer.setAmp(i, bands[i]);
    }
    this.player.setEqualizer(this.equalizer);
  }

  async startRendererDiscovery(): Promise<VlcRendererInfo[]> {
    await this.ensureInit();
    if (!this.lib) {
      return [];
    }
    if (this.rendererDiscoverer) {
      return this.rendererDiscoverer.getItems();
    }
    const names = RendererDiscoverer.listNames(this.lib);
    const name = names.length > 0 ? names[0] : 'microdns';
    this.rendererDiscoverer = new RendererDiscoverer(this.lib, name);
    if (this.rendererDiscoverer.getHandle() === 0) {
      this.rendererDiscoverer.release();
      this.rendererDiscoverer = null;
      return [];
    }
    this.rendererDiscoverer.start();
    await new Promise<void>((r: () => void) => setTimeout(r, 800));
    return this.rendererDiscoverer.getItems();
  }

  setRenderer(handle: number): boolean {
    if (!this.player) {
      return false;
    }
    const ok = this.player.setRenderer(handle);
    if (ok) {
      this.currentRendererHandle = handle;
    }
    return ok;
  }

  clearRenderer(): boolean {
    if (!this.player) {
      return false;
    }
    const ok = this.player.clearRenderer();
    if (ok) {
      this.currentRendererHandle = -1;
    }
    return ok;
  }

  getCurrentRendererHandle(): number {
    return this.currentRendererHandle;
  }

  hasRenderer(): boolean {
    return this.currentRendererHandle >= 0;
  }

  getMediaPlayer(): MediaPlayer | null {
    return this.player;
  }

  getLibVLC(): LibVLC | null {
    return this.lib;
  }

  addListener(l: PlaybackListener): void {
    if (!this.listeners.includes(l)) {
      this.listeners.push(l);
    }
  }

  removeListener(l: PlaybackListener): void {
    this.listeners = this.listeners.filter((x) => x !== l);
  }

  snapshot(): PlaybackState {
    const cur = this.getCurrent();
    return {
      state: this.state,
      title: cur?.title ?? '',
      artist: cur?.artistName ?? '',
      album: cur?.albumName ?? '',
      artworkPath: cur?.artworkPath ?? '',
      duration: this.duration,
      position: this.position,
      speed: this.speed,
      shuffle: this.shuffle,
      repeatMode: this.repeatMode,
      queueSize: this.queue.length,
      currentIndex: this.currentIndex,
    };
  }

  private notifyChange(): void {
    const s = this.snapshot();
    for (const l of this.listeners) {
      if (l.onChange) {
        l.onChange(s);
      }
    }
  }

  private emitState(): void {
    for (const l of this.listeners) {
      if (l.onStateChange) {
        l.onStateChange(this.state);
      }
    }
    this.notifyChange();
  }

  private emitTime(): void {
    for (const l of this.listeners) {
      if (l.onTimeUpdate) {
        l.onTimeUpdate(this.position, this.duration);
      }
    }
    this.notifyChange();
  }

  private emitQueue(): void {
    for (const l of this.listeners) {
      if (l.onQueueChanged) {
        l.onQueueChanged();
      }
    }
    this.notifyChange();
  }

  private emitVideoSize(): void {
    for (const l of this.listeners) {
      if (l.onVideoSize) {
        l.onVideoSize(this.videoWidth, this.videoHeight);
      }
    }
  }

  private emitTracksChanged(): void {
    for (const l of this.listeners) {
      if (l.onTracksChanged) {
        l.onTracksChanged();
      }
    }
  }

  /** QueueItem[] → MediaWrapper[] 后播放(音频列表入口)。 */
  async playQueueItems(items: QueueItem[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.playList(mws, startIndex, replace);
  }

  async appendQueueItems(items: QueueItem[]): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.append(mws);
  }

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

  async bindAndPlay(xcomponentId: string, fallbackUri?: string, fallbackTitle?: string): Promise<boolean> {
    await this.ensureInit();
    if (!this.inited || !this.player) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] bindAndPlay aborted: not inited');
      return false;
    }
    this.videoOutId = xcomponentId;

    if ((!this.getCurrent() || (fallbackUri && this.getCurrent()?.uri !== fallbackUri)) && fallbackUri) {
      const mw = new MediaWrapper(Date.now(), fallbackTitle ?? fallbackUri, fallbackUri, 0);
      this.queue = [mw];
      this.currentIndex = 0;
      this.emitQueue();
    }

    let bound = false;
    for (let i = 0; i < 30; i++) {
      const hasWin = this.player.hasNativeWindow(xcomponentId);
      bound = this.player.attachViews(xcomponentId);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] setVideoOut try=%{public}d hasWin=%{public}s bound=%{public}s id=%{public}s',
        i, String(hasWin), String(bound), xcomponentId);
      if (bound) {
        break;
      }
      await new Promise<void>((r: () => void) => setTimeout(r, 50));
    }

    await this.loadCurrent();
    return bound;
  }

  private async loadCurrent(): Promise<void> {
    const item = this.getCurrent();
    if (!item || !this.lib || !this.player) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent: empty queue or player');
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent uri=%{public}s videoOut=%{public}s',
      item.uri, this.videoOutId);

    let media: Media | null = null;
    if (needsFdOpen(item.uri)) {
      try {
        const file = fs.openSync(item.uri, fs.OpenMode.READ_ONLY);
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] openSync ok fd=%{public}d uri=%{public}s', file.fd, item.uri);
        media = Media.fromFd(this.lib, file.fd);
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] closeSync after fromFd: %{public}s',
            (closeErr as Error).message ?? String(closeErr));
        }
      } catch (e) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] openSync FAILED uri=%{public}s err=%{public}s',
          item.uri, (e as Error).message ?? String(e));
      }
    } else {
      media = Media.fromMrl(this.lib, item.uri);
    }

    if (!media) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] Media create FAILED uri=%{public}s', item.uri);
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }

    if (!this.player.setMedia(media)) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] setMedia FAILED uri=%{public}s', item.uri);
      media.release();
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }

    this.duration = 0;
    this.position = 0;
    this.videoWidth = 0;
    this.videoHeight = 0;
    if (item.width > 0 && item.height > 0) {
      this.videoWidth = item.width;
      this.videoHeight = item.height;
      this.emitVideoSize();
    }
    this.player.setRate(this.speed);
    this.player.setScale(0);
    this.player.setVolume(this.volume);
    this.player.play();
    this.state = PlayState.PREPARED;
    this.emitState();
  }

  setStopAfterCurrent(v: boolean): void {
    this.stopAfterCurrent = v;
  }

  private onComplete(): void {
    if (this.stopAfterCurrent) {
      this.stopAfterCurrent = false;
      this.stop();
      return;
    }
    if (this.repeatMode === 2) {
      this.player?.setTime(0);
      this.player?.play();
      return;
    }
    this.next(true);
  }

  async play(): Promise<void> {
    await this.ensureInit();
    if (!this.inited || !this.player) {
      return;
    }
    if (this.state === PlayState.IDLE || this.state === PlayState.STOPPED || this.state === PlayState.ERROR) {
      await this.loadCurrent();
      return;
    }
    this.player.play();
  }

  pause(): void {
    this.player?.pause();
  }

  togglePlay(): void {
    if (this.state === PlayState.PLAYING) {
      this.pause();
    } else {
      this.play();
    }
  }

  /**
   * 停止播放(对标 Android PlaybackService.stop(video=true))。
   * NAPI 侧已保证 stop 不持全局锁,可在返回路径上同步调用。
   */
  stop(): void {
    this.player?.stop();
    this.state = PlayState.STOPPED;
    this.emitState();
  }

  /** 解绑视频 Surface(对标 Android cleanUI → detachViews)。 */
  detachViews(): void {
    if (this.player) {
      this.player.detachViews();
    }
    this.videoOutId = '';
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
    this.player?.setTime(ms);
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    this.player?.setRate(rate);
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
    if (this.rendererDiscoverer) {
      this.rendererDiscoverer.stop();
      this.rendererDiscoverer.release();
      this.rendererDiscoverer = null;
    }
    if (this.equalizer) {
      this.equalizer.release();
      this.equalizer = null;
    }
    if (this.player) {
      this.player.release();
      this.player = null;
    }
    if (this.lib) {
      this.lib.release();
      this.lib = null;
    }
    this.inited = false;
    this.videoOutId = '';
    this.currentRendererHandle = -1;
    this.state = PlayState.IDLE;
    this.emitState();
  }

  // ---- 静态门面(兼容 origin/dev 页面调用;底层仍是 libVLC 单例) ----

  static getState(): PlayState {
    return PlaybackService.getInstance().getState();
  }

  static getQueue(): QueueItem[] {
    return PlaybackService.getInstance().getQueue().map((mw: MediaWrapper) => QueueItem.fromMediaWrapper(mw));
  }

  static getCurrentIndex(): number {
    return PlaybackService.getInstance().getCurrentIndex();
  }

  static getCurrent(): QueueItem | null {
    const cur = PlaybackService.getInstance().getCurrent();
    return cur ? QueueItem.fromMediaWrapper(cur) : null;
  }

  static snapshot(): PlaybackState {
    return PlaybackService.getInstance().snapshot();
  }

  static addListener(l: PlaybackListener): void {
    PlaybackService.getInstance().addListener(l);
  }

  static removeListener(l: PlaybackListener): void {
    PlaybackService.getInstance().removeListener(l);
  }

  static async playList(items: QueueItem[], startIndex: number, replace: boolean): Promise<void> {
    await PlaybackService.getInstance().playQueueItems(items, startIndex, replace);
  }

  static async append(items: QueueItem[]): Promise<void> {
    await PlaybackService.getInstance().appendQueueItems(items);
  }

  static async play(): Promise<void> {
    await PlaybackService.getInstance().play();
  }

  static async pause(): Promise<void> {
    PlaybackService.getInstance().pause();
  }

  static async togglePlay(): Promise<void> {
    PlaybackService.getInstance().togglePlay();
  }

  static async stop(): Promise<void> {
    PlaybackService.getInstance().stop();
  }

  static async seek(ms: number): Promise<void> {
    PlaybackService.getInstance().seek(ms);
  }

  static async setSpeed(rate: number): Promise<void> {
    PlaybackService.getInstance().setSpeed(rate);
  }

  static async next(auto: boolean = false): Promise<void> {
    await PlaybackService.getInstance().next(auto);
  }

  static async prev(): Promise<void> {
    await PlaybackService.getInstance().prev();
  }

  static toggleShuffle(): void {
    PlaybackService.getInstance().toggleShuffle();
  }

  static cycleRepeat(): void {
    PlaybackService.getInstance().cycleRepeat();
  }

  static speedToNumber(): number {
    return PlaybackService.getInstance().getSpeed();
  }

  static async release(): Promise<void> {
    PlaybackService.getInstance().release();
  }
}
