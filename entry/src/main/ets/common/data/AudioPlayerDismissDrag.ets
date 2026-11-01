/** 播放页下滑收回策略，位移单位为 vp，速度单位为 vp/s。 */
export class AudioPlayerDismissDrag {
  static offset(offsetY: number): number {
    if (!Number.isFinite(offsetY)) { return 0; }
    return Math.max(0, Math.min(360, offsetY));
  }

  static shouldClose(offsetY: number, velocityY: number): boolean {
    if (!Number.isFinite(offsetY) || !Number.isFinite(velocityY)
      || offsetY <= 12 || velocityY < -650) { return false; }
    return offsetY >= 120 || velocityY > 850;
  }
}
