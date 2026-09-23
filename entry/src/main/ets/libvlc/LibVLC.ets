import { libvlcCreate, libvlcRelease, setPlaybackDiagnostics } from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';

// 排查播放卡顿时设为 true；发布时改为 false。
// 只需重新打 HAP，不需要重新构建 VLC/FFmpeg 原生库。
const ENABLE_PLAYBACK_DIAGNOSTICS: boolean = true;

/**
 * LibVLC —— 对齐 org.videolan.libvlc.LibVLC。
 */
export class LibVLC extends VLCObject {
  constructor(options?: string[]) {
    setPlaybackDiagnostics(ENABLE_PLAYBACK_DIAGNOSTICS);
    const h = libvlcCreate(options);
    super(h);
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      libvlcRelease(this.handle);
    }
  }
}
