import {
  mediaDiscovererCreate,
  mediaDiscovererMediaList,
  mediaDiscovererRelease,
  mediaDiscovererStart,
  mediaDiscovererStop,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';
import { LibVLC } from './LibVLC';
import { MediaList } from './MediaList';

/**
 * MediaDiscoverer —— 对齐 org.videolan.libvlc.MediaDiscoverer。
 */
export class MediaDiscoverer extends VLCObject {
  private lib: LibVLC;

  constructor(lib: LibVLC, name: string) {
    const h = mediaDiscovererCreate(lib.getHandle(), name);
    super(h);
    this.lib = lib;
  }

  start(): boolean {
    return this.isReleased() ? false : mediaDiscovererStart(this.handle);
  }

  stop(): void {
    if (!this.isReleased()) {
      mediaDiscovererStop(this.handle);
    }
  }

  getMediaList(): MediaList | null {
    if (this.isReleased()) {
      return null;
    }
    const listH = mediaDiscovererMediaList(this.handle);
    if (listH === 0) {
      return null;
    }
    return MediaList.wrap(this.lib, listH);
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      mediaDiscovererRelease(this.handle);
    }
  }
}
