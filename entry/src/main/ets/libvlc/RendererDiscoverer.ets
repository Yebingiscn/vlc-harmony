import {
  rendererDiscovererList,
  rendererDiscovererCreate,
  rendererDiscovererRelease,
  rendererDiscovererStart,
  rendererDiscovererStop,
  rendererDiscovererGetItems,
  VlcRendererInfo,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';
import { LibVLC } from './LibVLC';

/**
 * RendererDiscoverer —— 对齐 org.videolan.libvlc.RendererDiscoverer。
 */
export class RendererDiscoverer extends VLCObject {
  constructor(lib: LibVLC, name: string) {
    const h = rendererDiscovererCreate(lib.getHandle(), name);
    super(h);
  }

  static listNames(lib: LibVLC): string[] {
    return rendererDiscovererList(lib.getHandle());
  }

  start(): boolean {
    return this.isReleased() ? false : rendererDiscovererStart(this.handle);
  }

  stop(): void {
    if (!this.isReleased()) {
      rendererDiscovererStop(this.handle);
    }
  }

  getItems(): VlcRendererInfo[] {
    return this.isReleased() ? [] : rendererDiscovererGetItems(this.handle);
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      rendererDiscovererRelease(this.handle);
    }
  }
}
