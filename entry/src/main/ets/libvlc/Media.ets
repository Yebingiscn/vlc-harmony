import {
  mediaCreateLocation,
  mediaCreatePath,
  mediaCreateFd,
  mediaRelease,
  mediaParse,
  mediaGetMeta,
  mediaGetTracksInfo,
  mediaAddSlave,
  VlcMetaInfo,
  VlcMediaTrackInfo,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';
import { LibVLC } from './LibVLC';
import { MediaSlaveType } from './events';

/**
 * Media —— 对齐 org.videolan.libvlc.Media。
 */
export class Media extends VLCObject {
  private lib: LibVLC;

  private constructor(lib: LibVLC, handle: number) {
    super(handle);
    this.lib = lib;
  }

  static fromUri(lib: LibVLC, mrl: string): Media | null {
    const h = mediaCreateLocation(lib.getHandle(), mrl);
    return h === 0 ? null : new Media(lib, h);
  }

  static fromPath(lib: LibVLC, path: string): Media | null {
    const h = mediaCreatePath(lib.getHandle(), path);
    return h === 0 ? null : new Media(lib, h);
  }

  static fromFd(lib: LibVLC, fd: number): Media | null {
    const h = mediaCreateFd(lib.getHandle(), fd);
    return h === 0 ? null : new Media(lib, h);
  }

  /** 包装已有 native media 句柄(如 MediaList.itemAt)。 */
  static fromHandle(lib: LibVLC, handle: number): Media | null {
    return handle === 0 ? null : new Media(lib, handle);
  }

  /** 从 URI 自动选择 location 或 path。 */
  static fromMrl(lib: LibVLC, mrl: string): Media | null {
    if (mrl.indexOf('://') >= 0) {
      return Media.fromUri(lib, mrl);
    }
    let path = mrl;
    if (path.startsWith('file://')) {
      path = path.substring('file://'.length);
    }
    return Media.fromPath(lib, path);
  }

  parse(timeoutMs: number = 5000): boolean {
    if (this.isReleased()) {
      return false;
    }
    return mediaParse(this.handle, timeoutMs);
  }

  getMeta(): VlcMetaInfo | null {
    if (this.isReleased()) {
      return null;
    }
    return mediaGetMeta(this.handle);
  }

  getTracksInfo(): VlcMediaTrackInfo[] {
    if (this.isReleased()) {
      return [];
    }
    return mediaGetTracksInfo(this.handle);
  }

  addSlave(type: MediaSlaveType, uri: string, priority: number = 4): boolean {
    if (this.isReleased()) {
      return false;
    }
    return mediaAddSlave(this.handle, type as number, uri, priority);
  }

  getLibVLC(): LibVLC {
    return this.lib;
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      mediaRelease(this.handle);
    }
  }
}
