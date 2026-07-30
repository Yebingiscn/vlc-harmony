// ============================================================================
// PlaybackService 的 libVLC 换芯版本(参考实现,待工程目录去连字符后启用)。
//
// 为什么是 .libvlc.ets 后缀(不参与编译):当前工程路径 `D:\...\vlc-android\vlc-android07291`
// 含连字符,触发 hvigor bug —— 外部 NAPI 类型 d.ts 的 OHM-url 解析失败(报 hvigor_ignore_<path>),
// 导致 `import { ... } from 'libvlcnapi'` 无法编译。原生侧(vlc_napi.cpp/libvlc.so/插件)已全部
// 编译打包通过,仅 ArkTS import 被路径连字符卡住。
//
// 激活步骤:
//   1. 把工程目录改名为不含连字符(如 vlc-android → vlc_android;或把 harmonyos_project 移到
//      无连字符路径),清掉 .hvigor / entry/build / entry/oh_modules 后重建。
//   2. 删除当前生效的 PlaybackService.ets(AVPlayer 版),把本文件重命名为 PlaybackService.ets。
//   3. hvigor 即可解析 `import { ... } from 'libvlcnapi'`(经 cpp/types/libvlcnapi d.ts)。
//   4. 重新编译 → 音频播放走真 libVLC。
// ============================================================================
import {
  init as vlcInit,
  setEventListener as vlcSetEventListener,
  setMedia as vlcSetMedia,
  play as vlcPlay,
  pause as vlcPause,
  stop as vlcStop,
  setTime as vlcSetTime,
  setRate as vlcSetRate,
  release as vlcRelease,
} from 'libvlcnapi.so';
import { MediaWrapper, PlayState } from '../models/MediaModels';

export interface PlaybackListener {
  onStateChange(state: PlayState): void;
  onTimeUpdate(current: number, duration: number): void;
  onQueueChanged(): void;
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
      if (vlcInit()) {
        vlcSetEventListener((event: string, value: number) => this.onNativeEvent(event, value));
        this.inited = true;
      }
    } catch (e) {
    } finally {
      this.initializing = false;
    }
  }

  private onNativeEvent(event: string, value: number): void {
    switch (event) {
      case 'playing': this.state = PlayState.PLAYING; this.emitState(); break;
      case 'paused': this.state = PlayState.PAUSED; this.emitState(); break;
      case 'stopped': this.state = PlayState.STOPPED; this.emitState(); break;
      case 'ended': this.onComplete(); break;
      case 'error': this.state = PlayState.ERROR; this.emitState(); break;
      case 'timeChanged': this.position = value; this.emitTime(); break;
      case 'lengthChanged': this.duration = value; this.emitTime(); break;
      default: break;
    }
  }

  getState(): PlayState { return this.state; }
  getDuration(): number { return this.duration; }
  getPosition(): number { return this.position; }
  getQueue(): MediaWrapper[] { return this.queue; }
  getCurrentIndex(): number { return this.currentIndex; }
  getCurrent(): MediaWrapper | null {
    return this.currentIndex >= 0 && this.currentIndex < this.queue.length ? this.queue[this.currentIndex] : null;
  }
  getSpeed(): number { return this.speed; }
  getShuffle(): boolean { return this.shuffle; }
  getRepeatMode(): number { return this.repeatMode; }

  addListener(l: PlaybackListener): void {
    if (!this.listeners.includes(l)) { this.listeners.push(l); }
  }

  removeListener(l: PlaybackListener): void {
    this.listeners = this.listeners.filter((x) => x !== l);
  }

  private emitState(): void { for (const l of this.listeners) { l.onStateChange(this.state); } }
  private emitTime(): void { for (const l of this.listeners) { l.onTimeUpdate(this.position, this.duration); } }
  private emitQueue(): void { for (const l of this.listeners) { l.onQueueChanged(); } }

  async playList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    if (items.length === 0) { return; }
    await this.ensureInit();
    if (!this.inited) { return; }
    this.queue = replace ? items.slice() : this.queue.concat(items);
    this.currentIndex = replace ? startIndex : this.queue.length - items.length + startIndex;
    this.emitQueue();
    await this.loadCurrent();
  }

  append(items: MediaWrapper[]): Promise<void> { return this.playList(items, 0, false); }

  private async loadCurrent(): Promise<void> {
    const item = this.getCurrent();
    if (!item) { return; }
    if (!vlcSetMedia(item.uri)) {
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }
    this.duration = 0;
    this.position = 0;
    vlcSetRate(this.speed);
    vlcPlay();
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
    if (!this.inited) { return; }
    if (this.state === PlayState.IDLE || this.state === PlayState.STOPPED || this.state === PlayState.ERROR) {
      await this.loadCurrent();
      return;
    }
    vlcPlay();
  }

  pause(): void { vlcPause(); }

  togglePlay(): void {
    if (this.state === PlayState.PLAYING) { this.pause(); } else { this.play(); }
  }

  stop(): void {
    vlcStop();
    this.state = PlayState.STOPPED;
    this.emitState();
  }

  async next(auto: boolean = false): Promise<void> {
    if (this.queue.length === 0) { return; }
    let nextIdx: number;
    if (this.shuffle) {
      nextIdx = Math.floor(Math.random() * this.queue.length);
    } else {
      nextIdx = this.currentIndex + 1;
      if (nextIdx >= this.queue.length) {
        if (this.repeatMode === 1 || !auto) { nextIdx = 0; } else { this.stop(); return; }
      }
    }
    this.currentIndex = nextIdx;
    this.emitQueue();
    await this.loadCurrent();
  }

  async prev(): Promise<void> {
    if (this.queue.length === 0) { return; }
    let prevIdx = this.currentIndex - 1;
    if (prevIdx < 0) { prevIdx = this.queue.length - 1; }
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

  toggleShuffle(): void { this.shuffle = !this.shuffle; this.emitQueue(); }
  cycleRepeat(): void { this.repeatMode = (this.repeatMode + 1) % 3; this.emitQueue(); }

  release(): void {
    vlcRelease();
    this.inited = false;
    this.state = PlayState.IDLE;
    this.emitState();
  }
}
