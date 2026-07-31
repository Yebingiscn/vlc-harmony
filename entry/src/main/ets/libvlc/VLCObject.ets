/**
 * VLCObject —— 对齐 org.videolan.libvlc.VLCObject 的句柄持有与释放语义。
 */
export class VLCObject {
  protected handle: number = 0;
  private released: boolean = false;

  constructor(handle: number = 0) {
    this.handle = handle;
  }

  getHandle(): number {
    return this.handle;
  }

  isReleased(): boolean {
    return this.released || this.handle === 0;
  }

  protected markReleased(): void {
    this.released = true;
    this.handle = 0;
  }

  release(): void {
    if (this.released) {
      return;
    }
    this.onNativeRelease();
    this.markReleased();
  }

  protected onNativeRelease(): void {
    // subclass
  }
}
