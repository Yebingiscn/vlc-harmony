import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../common/data/Settings';

/** Page / Activity 注入的触摸回调（对齐 Android VideoPlayerActivity）。 */
export interface VideoTouchHost {
  /** 对齐 doPlayPause。 */
  doPlayPause: () => void;
  /** 单击：显隐 HUD。 */
  onSingleTap: () => void;
  /** 双击左右边缘：相对当前进度跳转（ms，可负）。 */
  seekDelta: (deltaMs: number) => void;
  /** 容器宽度（vp），用于左右 1/4 边缘判定。 */
  getContainerWidth: () => number;
}

/**
 * VideoTouchDelegate —— 对齐 Android VideoTouchDelegate。
 * 本阶段落地双击：中间暂停/恢复；左右边缘快退/快进（受偏好开关控制）。
 */
export class VideoTouchDelegate {
  isSeeking: boolean = false;

  private host: VideoTouchHost | null = null;
  /** 对齐 TOUCH_FLAG_PLAY / ENABLE_DOUBLE_TAP_PLAY，默认开。 */
  enableDoubleTapPlay: boolean = true;
  /** 对齐 TOUCH_FLAG_DOUBLE_TAP_SEEK / ENABLE_DOUBLE_TAP_SEEK，默认开。 */
  enableDoubleTapSeek: boolean = true;
  /** 对齐 Settings.videoDoubleTapJumpDelay（秒）。 */
  jumpDelaySec: number = 10;

  bind(host: VideoTouchHost): void {
    this.host = host;
  }

  async refreshPrefs(): Promise<void> {
    this.enableDoubleTapPlay = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_PLAY, true);
    this.enableDoubleTapSeek = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_SEEK, true);
    this.jumpDelaySec = await Settings.getInt(Settings.KEY_VIDEO_DOUBLE_TAP_JUMP_DELAY, 10);
    hilog.info(0x0001, 'VLC',
      '[VLC] TouchDelegate prefs play=%{public}s seek=%{public}s jump=%{public}ds',
      String(this.enableDoubleTapPlay), String(this.enableDoubleTapSeek), this.jumpDelaySec);
  }

  /**
   * 对齐 Android ACTION_UP 中 numberOfTaps > 1 分支：
   * 左 1/4 → 快退；右 1/4 → 快进；其余 → doPlayPause。
   */
  onDoubleTap(localX: number): void {
    if (this.host === null) {
      return;
    }
    const range: number = this.host.getContainerWidth();
    hilog.info(0x0001, 'VLC', '[VLC] TouchDelegate.onDoubleTap x=%{public}s range=%{public}s',
      String(Math.round(localX)), String(Math.round(range)));

    if (this.enableDoubleTapSeek && range > 0 && localX < range / 4) {
      this.host.seekDelta(-this.jumpDelaySec * 1000);
      return;
    }
    if (this.enableDoubleTapSeek && range > 0 && localX > range * 0.75) {
      this.host.seekDelta(this.jumpDelaySec * 1000);
      return;
    }
    if (this.enableDoubleTapPlay) {
      this.host.doPlayPause();
    }
  }

  onSingleTap(): void {
    this.host?.onSingleTap();
  }

  onTouchEvent(_event: TouchEvent): boolean {
    // 滑动/亮度等后续扩展；单击双击由 TapGesture 处理。
    return false;
  }

  seekDelta(deltaMs: number): void {
    this.host?.seekDelta(deltaMs);
  }

  clearTouchAction(): void {
    this.isSeeking = false;
  }

  hideSeekOverlay(): void {
    // seek HUD 尚未落地
  }
}
