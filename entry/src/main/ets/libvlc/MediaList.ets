import {
  mediaListCreate,
  mediaListRelease,
  mediaListCount,
  mediaListAddMedia,
  mediaListRemoveIndex,
  mediaListItemAt,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';
import { LibVLC } from './LibVLC';
import { Media } from './Media';

/**
 * MediaList —— 对齐 org.videolan.libvlc.MediaList。
 */
export class MediaList extends VLCObject {
  private lib: LibVLC;
  private ownsNative: boolean = true;

  constructor(lib: LibVLC, handle?: number, ownsNative: boolean = true) {
    const h = handle !== undefined ? handle : mediaListCreate(lib.getHandle());
    super(h);
    this.lib = lib;
    this.ownsNative = ownsNative;
  }

  /** 包装 discoverer 内部 list(不 release 底层,由 discoverer 管理)。 */
  static wrap(lib: LibVLC, handle: number): MediaList {
    return new MediaList(lib, handle, false);
  }

  count(): number {
    return this.isReleased() ? 0 : mediaListCount(this.handle);
  }

  addMedia(media: Media): boolean {
    return this.isReleased() ? false : mediaListAddMedia(this.handle, media.getHandle());
  }

  removeIndex(index: number): boolean {
    return this.isReleased() ? false : mediaListRemoveIndex(this.handle, index);
  }

  itemAt(index: number): Media | null {
    if (this.isReleased()) {
      return null;
    }
    const h = mediaListItemAt(this.handle, index);
    return Media.fromHandle(this.lib, h);
  }

  protected onNativeRelease(): void {
    if (this.ownsNative && this.handle !== 0) {
      mediaListRelease(this.handle);
    }
  }
}
