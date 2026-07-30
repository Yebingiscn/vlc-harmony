import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayState } from '../models/MediaModels';

const TAG = 'VLC_Playback';

// ---- 数据模型 ----

/** 播放队列条目(精简,仅含最少必要字段)。 */
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
}

/** 播放器 VM 暴露的可观察状态。 */
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
  repeatMode: number; // 0=off 1=all 2=one
  queueSize: number;
  currentIndex: number;
}

/** 状态变化监听器。 */
export interface PlaybackListener {
  onChange(s: PlaybackState): void;
}

// ---- 播放器 ViewModel(单例) ----

class PlaybackViewModel {
  // 播放器实例
  private avPlayer: media.AVPlayer | null = null;
  // 队列
  private queue: QueueItem[] = [];
  private currentIndex: number = -1;
  // 状态
  private state: PlayState = PlayState.IDLE;
  private speed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  private shuffle: boolean = false;
  private repeatMode: number = 0;
  private duration: number = 0;
  private position: number = 0;
  private title: string = '';
  private artist: string = '';
  private album: string = '';
  private artworkPath: string = '';
  // 监听器
  private listeners: PlaybackListener[] = [];
  // 是否已初始化(registerCallbacks 已调用)
  private callbacksReady: boolean = false;
  // 等待 initialized 状态的 Promise resolver(一次性)。
  private initResolve: (() => void) | null = null;

  // ---- 公开访问器 ----

  getState(): PlayState { return this.state; }
  getQueue(): QueueItem[] { return this.queue; }
  getCurrentIndex(): number { return this.currentIndex; }
  getCurrent(): QueueItem | null {
    return this.currentIndex >= 0 && this.currentIndex < this.queue.length ? this.queue[this.currentIndex] : null;
  }

  snapshot(): PlaybackState {
    return {
      state: this.state,
      title: this.title,
      artist: this.artist,
      album: this.album,
      artworkPath: this.artworkPath,
      duration: this.duration,
      position: this.position,
      speed: this.speedToNumber(),
      shuffle: this.shuffle,
      repeatMode: this.repeatMode,
      queueSize: this.queue.length,
      currentIndex: this.currentIndex,
    };
  }

  addListener(l: PlaybackListener): void { if (!this.listeners.includes(l)) { this.listeners.push(l); } }
  removeListener(l: PlaybackListener): void { this.listeners = this.listeners.filter((x) => x !== l); }

  private notify(): void {
    const s = this.snapshot();
    for (const l of this.listeners) { l.onChange(s); }
  }

  // ---- 播放器生命周期 ----

  /** 释放旧播放器并创建新实例(保证干净的 idle 状态)。 */
  private async createNewPlayer(): Promise<media.AVPlayer> {
    // 先释放旧播放器。
    if (this.avPlayer) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('durationUpdate');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('seekDone');
        this.avPlayer.off('speedDone');
        await this.avPlayer.release();
      } catch (e) {
        hilog.info(0x0001, TAG, `release old player: ${(e as Error).message ?? String(e)}`);
      }
      this.avPlayer = null;
      this.callbacksReady = false;
    }
    const player = await media.createAVPlayer();
    hilog.info(0x0001, TAG, 'new AVPlayer created');
    this.avPlayer = player;
    this.registerCallbacks(player);
    this.callbacksReady = true;
    return player;
  }

  /** 在 idle 状态注册回调(必须在 setSource 之前)。 */
  private registerCallbacks(player: media.AVPlayer): void {
    player.on('stateChange', (state: string, _reason: media.StateChangeReason) => {
      hilog.info(0x0001, TAG, `[stateChange] ${state}`);
      // 等待 initialized 的一次性 Promise。
      if (state === 'initialized' && this.initResolve) {
        this.initResolve();
        this.initResolve = null;
      }
      switch (state) {
        case 'playing':
          this.state = PlayState.PLAYING;
          break;
        case 'paused':
          this.state = PlayState.PAUSED;
          break;
        case 'stopped':
          this.state = PlayState.STOPPED;
          break;
        case 'completed':
          this.onComplete();
          return;
        case 'error':
          this.state = PlayState.ERROR;
          hilog.error(0x0001, TAG, 'AVPlayer state=error');
          break;
        default:
          return;
      }
      this.notify();
    });
    player.on('durationUpdate', (duration: number) => {
      hilog.info(0x0001, TAG, `[durationUpdate] ${duration}ms`);
      this.duration = duration;
      this.notify();
    });
    player.on('timeUpdate', (time: number) => {
      this.position = time;
      this.notify();
    });
    player.on('error', (err: BusinessError) => {
      hilog.error(0x0001, TAG, `[error] code=${err.code} msg=${err.message}`);
      this.state = PlayState.ERROR;
      this.notify();
    });
    player.on('seekDone', (seekTime: number) => {
      this.position = seekTime;
      this.notify();
    });
    player.on('speedDone', (speed: number) => {
      hilog.info(0x0001, TAG, `[speedDone] ${speed}`);
    });
    hilog.info(0x0001, TAG, 'callbacks registered');
  }

  // ---- 播放操作 ----

  /** 加载并播放。每次创建新播放器,等待 initialized 后再 prepare。 */
  private async loadAndPlay(item: QueueItem): Promise<void> {
    hilog.info(0x0001, TAG, `=== loadAndPlay START: title="${item.title}" uri="${item.uri}" ===`);
    try {
      // 1. 创建新播放器。
      const player = await this.createNewPlayer();
      hilog.info(0x0001, TAG, 'step1: player created');

      // 2. 设置播放源,等待 initialized 状态。
      const initialized = new Promise<void>((resolve) => {
        this.initResolve = resolve;
      });
      const ok = await this.setSource(player, item.uri);
      if (!ok) {
        this.initResolve = null;
        throw new Error('setSource failed');
      }
      hilog.info(0x0001, TAG, 'step2: source set, waiting initialized...');
      await initialized;
      hilog.info(0x0001, TAG, 'step2: initialized ok');

      // 3. 更新 UI。
      this.title = item.title;
      this.artist = item.artistName;
      this.album = item.albumName;
      this.artworkPath = item.artworkPath;
      this.duration = 0;
      this.position = 0;
      this.notify();

      // 4. prepare。
      hilog.info(0x0001, TAG, 'step4: calling prepare()...');
      await player.prepare();
      hilog.info(0x0001, TAG, 'step4: prepare() done');

      // 5. play。
      hilog.info(0x0001, TAG, 'step5: calling play()...');
      await player.play();
      hilog.info(0x0001, TAG, 'step5: play() done — PLAYING');
      this.state = PlayState.PLAYING;
      this.notify();
    } catch (e) {
      hilog.error(0x0001, TAG, `loadAndPlay EXCEPTION: ${(e as Error).message ?? String(e)}`);
      this.state = PlayState.ERROR;
      this.notify();
    }
  }

  /** 设置播放源。file://docs/ URI → fs.openSync → fd:// 路径 → player.url。 */
  private async setSource(player: media.AVPlayer, uri: string): Promise<boolean> {
    hilog.info(0x0001, TAG, `setSource: trying uri="${uri}"`);

    // 方式1: fs.openSync(原始 URI) → fd:// 路径(官方推荐)。
    try {
      hilog.info(0x0001, TAG, `setSource: fs.openSync("${uri}")...`);
      const fdFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      hilog.info(0x0001, TAG, `setSource: fs.openSync ok, fd=${fdFile.fd}`);
      const fdPath = `fd://${fdFile.fd}`;
      hilog.info(0x0001, TAG, `setSource: player.url = "${fdPath}"`);
      player.url = fdPath;
      return true;
    } catch (e1) {
      hilog.info(0x0001, TAG, `setSource fd:// failed: ${(e1 as Error).message ?? String(e1)}`);
    }

    // 方式2: 去 file:// 前缀 → fdSrc。
    const cleanPath = uri.startsWith('file://') ? uri.slice(7) : uri;
    if (cleanPath !== uri) {
      try {
        hilog.info(0x0001, TAG, `setSource: trying clean path "${cleanPath}"`);
        const stat = fs.statSync(cleanPath);
        const fdFile = fs.openSync(cleanPath, fs.OpenMode.READ_ONLY);
        const avFd: media.AVFileDescriptor = { fd: fdFile.fd, offset: 0, length: stat.size };
        player.fdSrc = avFd;
        hilog.info(0x0001, TAG, `setSource: fdSrc ok, fd=${fdFile.fd}`);
        return true;
      } catch (e2) {
        hilog.info(0x0001, TAG, `setSource clean path failed: ${(e2 as Error).message ?? String(e2)}`);
      }
    }

    // 方式3: url(网络流)。
    try {
      hilog.info(0x0001, TAG, `setSource: trying player.url = "${uri}"`);
      player.url = uri;
      hilog.info(0x0001, TAG, `setSource: url ok`);
      return true;
    } catch (e3) {
      hilog.error(0x0001, TAG, `setSource ALL FAILED: ${(e3 as Error).message ?? String(e3)}`);
      return false;
    }
  }

  private onComplete(): void {
    if (this.repeatMode === 2) {
      // 单曲循环。
      this.seek(0);
      setTimeout(() => {
        if (this.avPlayer) { try { this.avPlayer.play(); } catch (e) { /* ignore */ } }
      }, 100);
      return;
    }
    this.next(true);
  }

  // ---- 队列操作 ----

  async playList(items: QueueItem[], startIndex: number, replace: boolean): Promise<void> {
    if (items.length === 0) { return; }
    this.queue = replace ? [...items] : [...this.queue, ...items];
    this.currentIndex = replace ? startIndex : this.queue.length - items.length + startIndex;
    const item = this.queue[this.currentIndex];
    await this.loadAndPlay(item);
  }

  async append(items: QueueItem[]): Promise<void> {
    await this.playList(items, 0, false);
  }

  async play(): Promise<void> {
    if (this.avPlayer) {
      try { await this.avPlayer.play(); } catch (e) { /* ignore */ }
    } else {
      const item = this.getCurrent();
      if (item) { await this.loadAndPlay(item); }
    }
  }

  async pause(): Promise<void> {
    if (this.avPlayer) { try { await this.avPlayer.pause(); } catch (e) { /* ignore */ } }
  }

  async togglePlay(): Promise<void> {
    if (this.state === PlayState.PLAYING) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  async stop(): Promise<void> {
    if (this.avPlayer) {
      try { await this.avPlayer.stop(); } catch (e) { /* ignore */ }
    }
    this.state = PlayState.STOPPED;
    this.notify();
  }

  async seek(ms: number): Promise<void> {
    this.position = ms;
    if (this.avPlayer) {
      try { await this.avPlayer.seek(ms, media.SeekMode.SEEK_CLOSEST); } catch (e) { /* ignore */ }
    }
    this.notify();
  }

  async setSpeed(rate: number): Promise<void> {
    // 映射数值倍速到枚举。
    const map: Record<number, media.PlaybackSpeed> = {
      0.5: media.PlaybackSpeed.SPEED_FORWARD_0_50_X,
      0.75: media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
      1.0: media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
      1.25: media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
      1.5: media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
      1.75: media.PlaybackSpeed.SPEED_FORWARD_1_75_X,
      2.0: media.PlaybackSpeed.SPEED_FORWARD_2_00_X,
    };
    this.speed = map[rate] ?? media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (this.avPlayer) {
      try { await this.avPlayer.setSpeed(this.speed); } catch (e) { /* ignore */ }
    }
  }

  async next(auto: boolean = false): Promise<void> {
    if (this.queue.length === 0) { return; }
    let nextIdx: number;
    if (this.shuffle) {
      nextIdx = Math.floor(Math.random() * this.queue.length);
    } else {
      nextIdx = this.currentIndex + 1;
      if (nextIdx >= this.queue.length) {
        if (this.repeatMode === 1 || !auto) { nextIdx = 0; } else { await this.stop(); return; }
      }
    }
    this.currentIndex = nextIdx;
    await this.loadAndPlay(this.queue[nextIdx]);
  }

  async prev(): Promise<void> {
    if (this.queue.length === 0) { return; }
    let prevIdx = this.currentIndex - 1;
    if (prevIdx < 0) { prevIdx = this.queue.length - 1; }
    this.currentIndex = prevIdx;
    await this.loadAndPlay(this.queue[prevIdx]);
  }

  toggleShuffle(): void { this.shuffle = !this.shuffle; this.notify(); }
  cycleRepeat(): void { this.repeatMode = (this.repeatMode + 1) % 3; this.notify(); }

  speedToNumber(): number {
    const map = new Map<media.PlaybackSpeed, number>([
      [media.PlaybackSpeed.SPEED_FORWARD_0_50_X, 0.5],
      [media.PlaybackSpeed.SPEED_FORWARD_0_75_X, 0.75],
      [media.PlaybackSpeed.SPEED_FORWARD_1_00_X, 1.0],
      [media.PlaybackSpeed.SPEED_FORWARD_1_25_X, 1.25],
      [media.PlaybackSpeed.SPEED_FORWARD_1_50_X, 1.5],
      [media.PlaybackSpeed.SPEED_FORWARD_1_75_X, 1.75],
      [media.PlaybackSpeed.SPEED_FORWARD_2_00_X, 2.0],
    ]);
    return map.get(this.speed) ?? 1.0;
  }

  async release(): Promise<void> {
    if (this.avPlayer) {
      try {
        this.avPlayer.off('stateChange');
        this.avPlayer.off('durationUpdate');
        this.avPlayer.off('timeUpdate');
        this.avPlayer.off('error');
        this.avPlayer.off('seekDone');
        this.avPlayer.off('speedDone');
        await this.avPlayer.release();
      } catch (e) { /* ignore */ }
      this.avPlayer = null;
      this.callbacksReady = false;
    }
    this.state = PlayState.IDLE;
    this.notify();
  }
}

// ---- 单例出口 ----

export class PlaybackService {
  private static vm: PlaybackViewModel = new PlaybackViewModel();

  static getState(): PlayState { return PlaybackService.vm.getState(); }
  static getQueue(): QueueItem[] { return PlaybackService.vm.getQueue(); }
  static getCurrentIndex(): number { return PlaybackService.vm.getCurrentIndex(); }
  static getCurrent(): QueueItem | null { return PlaybackService.vm.getCurrent(); }
  static snapshot(): PlaybackState { return PlaybackService.vm.snapshot(); }

  static addListener(l: PlaybackListener): void { PlaybackService.vm.addListener(l); }
  static removeListener(l: PlaybackListener): void { PlaybackService.vm.removeListener(l); }

  static async playList(items: QueueItem[], startIndex: number, replace: boolean): Promise<void> {
    await PlaybackService.vm.playList(items, startIndex, replace);
  }
  static async append(items: QueueItem[]): Promise<void> { await PlaybackService.vm.append(items); }
  static async play(): Promise<void> { await PlaybackService.vm.play(); }
  static async pause(): Promise<void> { await PlaybackService.vm.pause(); }
  static async togglePlay(): Promise<void> { await PlaybackService.vm.togglePlay(); }
  static async stop(): Promise<void> { await PlaybackService.vm.stop(); }
  static async seek(ms: number): Promise<void> { await PlaybackService.vm.seek(ms); }
  static async setSpeed(rate: number): Promise<void> { await PlaybackService.vm.setSpeed(rate); }
  static async next(auto?: boolean): Promise<void> { await PlaybackService.vm.next(auto); }
  static async prev(): Promise<void> { await PlaybackService.vm.prev(); }
  static toggleShuffle(): void { PlaybackService.vm.toggleShuffle(); }
  static cycleRepeat(): void { PlaybackService.vm.cycleRepeat(); }
  static speedToNumber(): number { return PlaybackService.vm.speedToNumber(); }
  static async release(): Promise<void> { await PlaybackService.vm.release(); }
}
