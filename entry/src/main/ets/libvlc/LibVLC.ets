import { libvlcCreate, libvlcRelease } from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';

/**
 * LibVLC —— 对齐 org.videolan.libvlc.LibVLC。
 */
export class LibVLC extends VLCObject {
  constructor(options?: string[]) {
    const h = libvlcCreate(options);
    super(h);
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      libvlcRelease(this.handle);
    }
  }
}
