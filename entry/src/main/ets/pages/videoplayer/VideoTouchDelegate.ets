import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../common/data/Settings';

/** 手势模式（对齐 Android TOUCH_VOLUME / TOUCH_BRIGHTNESS / TOUCH_TAP_SEEK）。 */
export enum VideoPanMode {
  None = 0,
  Volume = 1,
  Brightness = 2,
  Seek = 3,
}

/** Page / Activity 注入的触摸回调。 */
export interface VideoTouchHost {
  doPlayPause: () => void;
  onSingleTap: () => void;
  seekDelta: (deltaMs: number) => void;
  getContainerWidth: () => number;
  getContainerHeight: () => number;
  getPosition: () => number;
  getDuration: () => number;

  /** HUD 可见时顶/底栏区域不触发单击显隐，避免与按钮抢点。 */
  isHudVisible: () => boolean;
  onVolumePan: (deltaNorm: number) => void;
  onBrightnessPan: (deltaNorm: number) => void;
  onSeekPan: (jumpMs: number, targetMs: number) => void;
  onPanBegan: () => void;
  onPanEnded: (mode: VideoPanMode) => void;
}

/**
 * VideoTouchDelegate
 * - 单击：onTouch Up 延迟触发（下层 onClick 会被顶层 Transparent + 微动吃掉）
 * - 双击：TapGesture(count:2)，会取消待触发单击
 * - 竖/横滑：onTouch
 */
export class VideoTouchDelegate {
  isSeeking: boolean = false;
  enableDoubleTapPlay: boolean = true;
  enableDoubleTapSeek: boolean = true;
  enableVolumeGesture: boolean = true;
  enableBrightnessGesture: boolean = true;
  enableSwipeSeek: boolean = true;
  jumpDelaySec: number = 10;
  private host: VideoTouchHost | null = null;
  private panMode: VideoPanMode = VideoPanMode.None;
  private tracking: boolean = false;
  private initX: number = 0;
  private initY: number = 0;
  private lastY: number = 0;
  private moved: boolean = false;
  private seekStartPos: number = 0;
  private lastJumpMs: number = 0;
  private singleTapTimer: number = -1;
  private readonly panSlop: number = 18;
  private readonly tapSlop: number = 28;
  private readonly doubleTapTimeoutMs: number = 280;
  /** HUD 顶/底栏近似高度，单击死区。 */
  private readonly hudTopReserve: number = 100;
  private readonly hudBottomReserve: number = 140;

  bind(host: VideoTouchHost): void {
    this.host = host;
  }

  async refreshPrefs(): Promise<void> {
    this.enableDoubleTapPlay = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_PLAY, true);
    this.enableDoubleTapSeek = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_SEEK, true);
    this.enableVolumeGesture = await Settings.getBoolean(Settings.ENABLE_VOLUME_GESTURE, true);
    this.enableBrightnessGesture = await Settings.getBoolean(Settings.ENABLE_BRIGHTNESS_GESTURE, true);
    this.enableSwipeSeek = await Settings.getBoolean(Settings.ENABLE_SWIPE_SEEK, true);
    this.jumpDelaySec = await Settings.getInt(Settings.KEY_VIDEO_DOUBLE_TAP_JUMP_DELAY, 10);
    hilog.info(0x0001, 'VLC',
      '[VLC] TouchDelegate prefs play=%{public}s dseek=%{public}s swipe=%{public}s vol=%{public}s bri=%{public}s',
      String(this.enableDoubleTapPlay), String(this.enableDoubleTapSeek),
      String(this.enableSwipeSeek),
      String(this.enableVolumeGesture), String(this.enableBrightnessGesture));
  }

  onDoubleTap(localX: number): void {
    if (this.host === null || this.panMode !== VideoPanMode.None) {
      return;
    }
    this.cancelSingleTap();
    const range: number = this.host.getContainerWidth();
    hilog.info(0x0001, 'VLC', '[VLC] doubleTap x=%{public}s range=%{public}s',
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
    if (this.panMode !== VideoPanMode.None) {
      return;
    }
    hilog.info(0x0001, 'VLC', '[VLC] singleTap');
    this.host?.onSingleTap();
  }

  onTouchEvent(event: TouchEvent): void {
    if (this.host === null) {
      return;
    }
    let x: number = this.initX;
    let y: number = this.initY;
    let hasPoint: boolean = false;
    if (event.changedTouches !== undefined && event.changedTouches.length > 0) {
      x = event.changedTouches[0].x;
      y = event.changedTouches[0].y;
      hasPoint = true;
    } else if (event.touches !== undefined && event.touches.length > 0) {
      x = event.touches[0].x;
      y = event.touches[0].y;
      hasPoint = true;
    }

    if (event.type === TouchType.Down) {
      if (!hasPoint) {
        return;
      }
      // 第二次按下取消待触发单击，留给双击窗口
      this.cancelSingleTap();
      this.tracking = true;
      this.initX = x;
      this.initY = y;
      this.lastY = y;
      this.moved = false;
      this.panMode = VideoPanMode.None;
      this.isSeeking = false;
      this.lastJumpMs = 0;
      return;
    }

    if (!this.tracking) {
      return;
    }

    if (event.type === TouchType.Move) {
      if (!hasPoint) {
        return;
      }
      const dx: number = x - this.initX;
      const dy: number = y - this.initY;
      if (!this.moved && (Math.abs(dx) > this.panSlop || Math.abs(dy) > this.panSlop)) {
        this.moved = true;
        this.cancelSingleTap();
        if (Math.abs(dx) > Math.abs(dy)) {
          this.beginSeekPan();
        } else {
          this.beginVerticalPan(this.initX);
        }
      }
      if (this.panMode === VideoPanMode.Seek) {
        this.applySeekPan(dx);
      } else if (this.panMode === VideoPanMode.Volume || this.panMode === VideoPanMode.Brightness) {
        this.applyVerticalDelta(y - this.lastY);
        this.lastY = y;
      }
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.tracking = false;
      if (this.panMode !== VideoPanMode.None) {
        const mode = this.panMode;
        this.panMode = VideoPanMode.None;
        this.isSeeking = false;
        this.host.onPanEnded(mode);
        hilog.info(0x0001, 'VLC', '[VLC] pan end mode=%{public}d jump=%{public}d', mode, this.lastJumpMs);
        this.lastJumpMs = 0;
        return;
      }

      // 未形成滑动 → 延迟单击（给双击留窗口；对齐 Android postDelayed）
      const dxUp: number = x - this.initX;
      const dyUp: number = y - this.initY;
      if (Math.abs(dxUp) < this.tapSlop && Math.abs(dyUp) < this.tapSlop) {
        if (this.shouldIgnoreSingleTapAt(this.initY)) {
          return;
        }
        this.scheduleSingleTap();
      }
    }
  }

  isPanning(): boolean {
    return this.panMode !== VideoPanMode.None;
  }

  onPanStart(_localX: number): void {
  }

  onPanUpdate(_offsetY: number): void {
  }

  onPanEnd(): void {
  }

  seekDelta(deltaMs: number): void {
    this.host?.seekDelta(deltaMs);
  }

  clearTouchAction(): void {
    this.isSeeking = false;
    this.panMode = VideoPanMode.None;
    this.tracking = false;
    this.lastJumpMs = 0;
    this.cancelSingleTap();
  }

  hideSeekOverlay(): void {
  }

  private shouldIgnoreSingleTapAt(localY: number): boolean {
    if (this.host === null || !this.host.isHudVisible()) {
      return false;
    }
    const h: number = this.host.getContainerHeight();
    if (h <= 0) {
      return false;
    }
    return localY < this.hudTopReserve || localY > h - this.hudBottomReserve;
  }

  private scheduleSingleTap(): void {
    this.cancelSingleTap();
    this.singleTapTimer = setTimeout(() => {
      this.singleTapTimer = -1;
      this.onSingleTap();
    }, this.doubleTapTimeoutMs);
  }

  private cancelSingleTap(): void {
    if (this.singleTapTimer !== -1) {
      clearTimeout(this.singleTapTimer);
      this.singleTapTimer = -1;
    }
  }

  private beginVerticalPan(localX: number): void {
    if (this.host === null || this.panMode !== VideoPanMode.None) {
      return;
    }
    let width: number = this.host.getContainerWidth();
    if (width <= 0) {
      width = Math.max(localX * 2, 1);
    }
    if (localX < width * 0.5 && this.enableVolumeGesture) {
      this.panMode = VideoPanMode.Volume;
    } else if (localX >= width * 0.5 && this.enableBrightnessGesture) {
      this.panMode = VideoPanMode.Brightness;
    } else {
      return;
    }
    this.cancelSingleTap();
    this.host.onPanBegan();
    hilog.info(0x0001, 'VLC',
      '[VLC] pan start mode=%{public}d x=%{public}s w=%{public}s',
      this.panMode, String(Math.round(localX)), String(Math.round(width)));
  }

  private beginSeekPan(): void {
    if (this.host === null || this.panMode !== VideoPanMode.None || !this.enableSwipeSeek) {
      return;
    }
    if (this.host.getDuration() <= 0) {
      hilog.info(0x0001, 'VLC', '[VLC] seek pan ignored: no duration');
      return;
    }
    this.panMode = VideoPanMode.Seek;
    this.isSeeking = true;
    this.seekStartPos = this.host.getPosition();
    this.lastJumpMs = 0;
    this.cancelSingleTap();
    this.host.onPanBegan();
    hilog.info(0x0001, 'VLC', '[VLC] pan start mode=Seek pos=%{public}d', this.seekStartPos);
  }

  private applySeekPan(dx: number): void {
    if (this.host === null || this.panMode !== VideoPanMode.Seek) {
      return;
    }
    let width: number = this.host.getContainerWidth();
    if (width <= 0) {
      width = 400;
    }
    const gestureCm: number = (dx / width) * 8;
    if (Math.abs(gestureCm) < 0.3) {
      return;
    }
    const absG: number = Math.abs(gestureCm);
    const ratio: number = absG / 8;
    // 2 次方曲线 + 30 分钟上限:小幅度滑动也有合理跳转,大幅度可达几十分钟(对齐原版 VLC)。
    const jumpMag: number = 1800000 * Math.pow(ratio, 2) + 3000;
    let jump: number = (gestureCm >= 0 ? 1 : -1) * Math.round(jumpMag);

    const duration: number = this.host.getDuration();
    const time: number = this.seekStartPos;
    if (jump > 0 && time + jump > duration) {
      jump = Math.floor(duration - time);
    }
    if (jump < 0 && time + jump < 0) {
      jump = -Math.floor(time);
    }
    this.lastJumpMs = jump;
    const target: number = Math.max(0, Math.min(duration, time + jump));
    this.host.onSeekPan(jump, target);
  }

  private applyVerticalDelta(dy: number): void {
    if (this.host === null) {
      return;
    }
    let height: number = this.host.getContainerHeight();
    if (height <= 0) {
      height = 600;
    }
    const deltaNorm: number = (-dy / height) * 1.25;
    if (Math.abs(deltaNorm) < 0.0001) {
      return;
    }
    if (this.panMode === VideoPanMode.Volume) {
      this.host.onVolumePan(deltaNorm);
    } else if (this.panMode === VideoPanMode.Brightness) {
      this.host.onBrightnessPan(deltaNorm);
    }
  }
}
