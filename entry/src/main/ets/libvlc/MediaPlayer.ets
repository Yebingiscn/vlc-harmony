import {
  hasNativeWindow,
  mediaPlayerAddSlave,
  mediaPlayerClearEqualizer,
  mediaPlayerClearRenderer,
  mediaPlayerCreate,
  mediaPlayerDetachViews,
  mediaPlayerGetAudioDelay,
  mediaPlayerGetAudioTrack,
  mediaPlayerGetAudioTracks,
  mediaPlayerGetChapter,
  mediaPlayerGetChapters,
  mediaPlayerGetFps,
  mediaPlayerGetLength,
  mediaPlayerGetPosition,
  mediaPlayerGetRate,
  mediaPlayerGetSpuDelay,
  mediaPlayerGetSpuTrack,
  mediaPlayerGetSpuTracks,
  mediaPlayerGetState,
  mediaPlayerGetTime,
  mediaPlayerGetVideoSize,
  mediaPlayerGetVideoTrack,
  mediaPlayerGetVideoTracks,
  mediaPlayerGetVolume,
  mediaPlayerPause,
  mediaPlayerPlay,
  mediaPlayerRelease,
  mediaPlayerReleaseAsync,
  mediaPlayerSetAudioDelay,
  mediaPlayerSetAudioTrack,
  mediaPlayerSetChapter,
  mediaPlayerSetEqualizer,
  mediaPlayerSetEventListener,
  mediaPlayerSetMedia,
  mediaPlayerSetPosition,
  mediaPlayerSetRate,
  mediaPlayerSetRenderer,
  mediaPlayerSetScale,
  mediaPlayerSetAspectRatio,
  mediaPlayerSetSpuDelay,
  mediaPlayerSetSpuTrack,
  mediaPlayerSetTime,
  mediaPlayerSetVideoOut,
  mediaPlayerSetOsdVideoOut,
  mediaPlayerSetVideoTrack,
  mediaPlayerSetVolume,
  mediaPlayerStop,
  VlcChapterInfo,
  VlcTrackInfo,
  VlcVideoSize,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';
import { LibVLC } from './LibVLC';
import { Media } from './Media';
import { MediaPlayerEventListener, MediaSlaveType } from './events';
import { Equalizer } from './Equalizer';

/**
 * MediaPlayer —— 对齐 org.videolan.libvlc.MediaPlayer。
 * attachViews(xcomponentId) 对应 Android IVLCVout/AWindow。
 */
export class MediaPlayer extends VLCObject {
  private lib: LibVLC;
  private currentMedia: Media | null = null;
  private listener: MediaPlayerEventListener | null = null;

  constructor(lib: LibVLC) {
    const h = mediaPlayerCreate(lib.getHandle());
    super(h);
    this.lib = lib;
  }

  setEventListener(listener: MediaPlayerEventListener | null): boolean {
    this.listener = listener;
    if (this.isReleased()) {
      return false;
    }
    if (listener === null) {
      return mediaPlayerSetEventListener(this.handle, (_h: number, _e: string, _v: number) => {
      });
    }
    return mediaPlayerSetEventListener(this.handle, (_h: number, event: string, value: number) => {
      if (this.listener) {
        this.listener(event, value);
      }
    });
  }

  setMedia(media: Media | null): boolean {
    if (this.isReleased()) {
      return false;
    }
    if (media === null) {
      const prev = this.currentMedia;
      this.currentMedia = null;
      if (prev !== null) {
        prev.release();
      }
      return false;
    }
    const ok = mediaPlayerSetMedia(this.handle, media.getHandle());
    if (ok) {
      const prev = this.currentMedia;
      this.currentMedia = media;
      if (prev !== null && prev !== media) {
        prev.release();
      }
    }
    return ok;
  }

  getMedia(): Media | null {
    return this.currentMedia;
  }

  /** 绑定 XComponent 出画(对标 attachViews)。 */
  attachViews(xcomponentId: string): boolean {
    if (this.isReleased()) {
      return false;
    }
    return mediaPlayerSetVideoOut(this.handle, xcomponentId);
  }

  /** 绑定透明 OSD XComponent；视频帧仍由主 Surface 零拷贝显示。 */
  attachOsdView(xcomponentId: string): boolean {
    if (this.isReleased()) {
      return false;
    }
    return mediaPlayerSetOsdVideoOut(this.handle, xcomponentId);
  }

  /** 解绑出画(对标 Android MediaPlayer.detachViews / cleanUI)。 */
  detachViews(): void {
    if (!this.isReleased()) {
      mediaPlayerDetachViews(this.handle);
    }
  }

  hasNativeWindow(xcomponentId: string): boolean {
    return hasNativeWindow(xcomponentId);
  }

  play(): void {
    if (!this.isReleased()) {
      mediaPlayerPlay(this.handle);
    }
  }

  pause(): void {
    if (!this.isReleased()) {
      mediaPlayerPause(this.handle);
    }
  }

  /**
   * 停止播放(对标 Android MediaPlayer.stop)。
   * 注意:libVLC 的 stop 在解码线程卡在输出队列时可能永久阻塞主线程(AppFreeze),
   * NAPI 侧已改为后台线程异步执行 stop+release 并摘除原生 player。调用后本对象即失效
   * (isReleased()==true),上层(PlaybackService)在下次加载前通过 ensureLivePlayer 重建。
   */
  stop(): void {
    if (!this.isReleased()) {
      const prev = this.currentMedia;
      this.currentMedia = null;
      if (prev !== null) {
        prev.release();
      }
      mediaPlayerStop(this.handle);
      this.markReleased();
    }
  }

  getTime(): number {
    return this.isReleased() ? -1 : mediaPlayerGetTime(this.handle);
  }

  setTime(ms: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetTime(this.handle, ms);
    }
  }

  /** 按 0.0-1.0 位置 seek(bluray/dvdnav 下比 setTime 可靠,避免 navigator 弹回)。 */
  setPosition(pos: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetPosition(this.handle, pos);
    }
  }

  getLength(): number {
    return this.isReleased() ? -1 : mediaPlayerGetLength(this.handle);
  }

  setRate(rate: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetRate(this.handle, rate);
    }
  }

  getRate(): number {
    return this.isReleased() ? 1.0 : mediaPlayerGetRate(this.handle);
  }

  setVolume(volume: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetVolume(this.handle, volume);
    }
  }

  getVolume(): number {
    return this.isReleased() ? -1 : mediaPlayerGetVolume(this.handle);
  }

  getState(): number {
    return this.isReleased() ? 0 : mediaPlayerGetState(this.handle);
  }

  getPosition(): number {
    return this.isReleased() ? 0 : mediaPlayerGetPosition(this.handle);
  }

  getVideoSize(): VlcVideoSize | null {
    return this.isReleased() ? null : mediaPlayerGetVideoSize(this.handle);
  }

  getFps(): number {
    return this.isReleased() ? 0 : mediaPlayerGetFps(this.handle);
  }

  setScale(factor: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetScale(this.handle, factor);
    }
  }

  setAspectRatio(aspect: string): void {
    if (!this.isReleased()) {
      mediaPlayerSetAspectRatio(this.handle, aspect);
    }
  }

  addSlave(type: MediaSlaveType, uri: string, select: boolean = true): boolean {
    if (this.isReleased()) {
      return false;
    }
    return mediaPlayerAddSlave(this.handle, type as number, uri, select);
  }

  getAudioTracks(): VlcTrackInfo[] {
    return this.isReleased() ? [] : mediaPlayerGetAudioTracks(this.handle);
  }

  getSpuTracks(): VlcTrackInfo[] {
    return this.isReleased() ? [] : mediaPlayerGetSpuTracks(this.handle);
  }

  getVideoTracks(): VlcTrackInfo[] {
    return this.isReleased() ? [] : mediaPlayerGetVideoTracks(this.handle);
  }

  getAudioTrack(): number {
    return this.isReleased() ? -1 : mediaPlayerGetAudioTrack(this.handle);
  }

  getSpuTrack(): number {
    return this.isReleased() ? -1 : mediaPlayerGetSpuTrack(this.handle);
  }

  getVideoTrack(): number {
    return this.isReleased() ? -1 : mediaPlayerGetVideoTrack(this.handle);
  }

  setAudioTrack(id: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetAudioTrack(this.handle, id);
  }

  setSpuTrack(id: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetSpuTrack(this.handle, id);
  }

  setVideoTrack(id: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetVideoTrack(this.handle, id);
  }

  setSpuDelay(us: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetSpuDelay(this.handle, us);
  }

  /** SPU 延迟反查:找不到 player 或 libvlc 返回错误时为 -1。 */
  getSpuDelay(): number {
    return this.isReleased() ? -1 : mediaPlayerGetSpuDelay(this.handle);
  }

  setAudioDelay(us: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetAudioDelay(this.handle, us);
  }

  /** 音频延迟反查:找不到 player 或 libvlc 返回错误时为 -1。 */
  getAudioDelay(): number {
    return this.isReleased() ? -1 : mediaPlayerGetAudioDelay(this.handle);
  }

  getChapters(titleIndex: number = -1): VlcChapterInfo[] {
    return this.isReleased() ? [] : mediaPlayerGetChapters(this.handle, titleIndex);
  }

  getChapter(): number {
    return this.isReleased() ? -1 : mediaPlayerGetChapter(this.handle);
  }

  setChapter(index: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetChapter(this.handle, index);
    }
  }

  setRenderer(rendererHandle: number): boolean {
    return this.isReleased() ? false : mediaPlayerSetRenderer(this.handle, rendererHandle);
  }

  clearRenderer(): boolean {
    return this.isReleased() ? false : mediaPlayerClearRenderer(this.handle);
  }

  setEqualizer(eq: Equalizer | null): boolean {
    if (this.isReleased()) {
      return false;
    }
    if (eq === null) {
      return mediaPlayerClearEqualizer(this.handle);
    }
    return mediaPlayerSetEqualizer(this.handle, eq.getHandle());
  }

  getLibVLC(): LibVLC {
    return this.lib;
  }

  /** Non-blocking release: libVLC stop+release runs on a detached native thread. */
  releaseAsync(): void {
    if (this.isReleased()) {
      return;
    }
    if (this.handle !== 0) {
      mediaPlayerReleaseAsync(this.handle);
    }
    this.currentMedia = null;
    this.markReleased();
  }

  protected onNativeRelease(): void {
    if (this.currentMedia !== null) {
      this.currentMedia.release();
      this.currentMedia = null;
    }
    if (this.handle !== 0) {
      mediaPlayerRelease(this.handle);
    }
  }
}
