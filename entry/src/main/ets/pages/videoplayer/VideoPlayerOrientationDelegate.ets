import { UiFeedback } from '../../common/utils/UiFeedback';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * VideoPlayerOrientationDelegate —— 对齐 Android VideoPlayerOrientationDelegate。
 */
export class VideoPlayerOrientationDelegate {
  isShowing: boolean = false;

  displayOrientation(): void {
    hilog.info(0x0001, 'VLC', '[VLC] OrientationDelegate.displayOrientation (stub)');
    UiFeedback.showToast({ message: 'Screen orientation is not available yet' });
  }

  hideOrientationOverlay(): void {
    this.isShowing = false;
  }
}
