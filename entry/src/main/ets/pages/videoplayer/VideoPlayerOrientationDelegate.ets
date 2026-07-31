import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoPlayerOrientationDelegate —— 对齐 Android VideoPlayerOrientationDelegate。
 */
export class VideoPlayerOrientationDelegate {
  isShowing: boolean = false;

  displayOrientation(): void {
    hilog.info(0x0001, 'VLC', '[VLC] OrientationDelegate.displayOrientation (stub)');
    promptAction.showToast({ message: 'Screen orientation is not available yet' });
  }

  hideOrientationOverlay(): void {
    this.isShowing = false;
  }
}
