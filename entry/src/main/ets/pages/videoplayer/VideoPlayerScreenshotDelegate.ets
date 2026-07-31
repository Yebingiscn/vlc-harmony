import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoPlayerScreenshotDelegate —— 对齐 Android VideoPlayerScreenshotDelegate。
 */
export class VideoPlayerScreenshotDelegate {
  takeScreenshot(): void {
    hilog.info(0x0001, 'VLC', '[VLC] ScreenshotDelegate.takeScreenshot (stub)');
    promptAction.showToast({ message: 'Screenshot is not available yet' });
  }

  hide(): void {
    hilog.info(0x0001, 'VLC', '[VLC] ScreenshotDelegate.hide (stub)');
  }
}
