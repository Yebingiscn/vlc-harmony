/** 纯手势策略：位移/速度单位均为 vp，便于不同屏幕密度下保持相同手感。 */
export class MiniPlayerDrag {
  static distance(height: number): number {
    return Math.max(100, Math.min(320, height * 0.55));
  }

  static progress(offsetY: number, height: number): number {
    return Math.max(0, Math.min(1, -offsetY / MiniPlayerDrag.distance(height)));
  }

  static shouldOpen(offsetY: number, velocityY: number, height: number): boolean {
    // 明确向下甩动代表撤销，即便曾经上拉超过阈值也不展开。
    if (offsetY >= -12 || velocityY > 650) { return false; }
    return MiniPlayerDrag.progress(offsetY, height) >= 0.35 || velocityY < -650;
  }
}
