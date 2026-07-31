import {
  mediaPlayerCreate,
  mediaPlayerRelease,
  mediaPlayerSetEventListener,
  mediaPlayerSetMedia,
  mediaPlayerSetVideoOut,
  mediaPlayerDetachViews,
  hasNativeWindow,
  mediaPlayerPlay,
  mediaPlayerPause,
  mediaPlayerStop,
  mediaPlayerGetTime,
  mediaPlayerSetTime,
  mediaPlayerGetLength,
  mediaPlayerSetRate,
  mediaPlayerGetRate,
  mediaPlayerSetVolume,
  mediaPlayerGetVolume,
  mediaPlayerGetState,
  mediaPlayerGetPosition,
  mediaPlayerGetVideoSize,
  mediaPlayerSetScale,
  mediaPlayerAddSlave,
  mediaPlayerGetAudioTracks,
  mediaPlayerGetSpuTracks,
  mediaPlayerGetVideoTracks,
  mediaPlayerGetAudioTrack,
  mediaPlayerGetSpuTrack,
  mediaPlayerGetVideoTrack,
  mediaPlayerSetAudioTrack,
  mediaPlayerSetSpuTrack,
  mediaPlayerSetVideoTrack,
  mediaPlayerSetSpuDelay,
  mediaPlayerGetChapters,
  mediaPlayerGetChapter,
  mediaPlayerSetChapter,
  mediaPlayerSetRenderer,
  mediaPlayerClearRenderer,
  mediaPlayerSetEqualizer,
  mediaPlayerClearEqualizer,
  VlcTrackInfo,
  VlcChapterInfo,
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

  stop(): void {
    if (!this.isReleased()) {
      mediaPlayerStop(this.handle);
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

  setScale(factor: number): void {
    if (!this.isReleased()) {
      mediaPlayerSetScale(this.handle, factor);
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
