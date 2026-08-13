import { UiFeedback } from '../../common/utils/UiFeedback';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * VideoPlayerScreenshotDelegate —— 对齐 Android VideoPlayerScreenshotDelegate。
 */
export class VideoPlayerScreenshotDelegate {
  takeScreenshot(): void {
    hilog.info(0x0001, 'VLC', '[VLC] ScreenshotDelegate.takeScreenshot (stub)');
    UiFeedback.showToast({ message: 'Screenshot is not available yet' });
  }

  hide(): void {
    hilog.info(0x0001, 'VLC', '[VLC] ScreenshotDelegate.hide (stub)');
  }
}
