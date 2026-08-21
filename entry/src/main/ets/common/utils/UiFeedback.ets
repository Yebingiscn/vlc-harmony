import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * UI feedback entry point shared by pages and services.
 *
 * `openToast` replaces the deprecated global `showToast` API and returns a
 * Promise. Handling both synchronous and asynchronous failures here keeps
 * callers fire-and-forget without leaking rejected Promises.
 */
export class UiFeedback {
  static showToast(options: promptAction.ShowToastOptions): void {
    try {
      promptAction.openToast(options).catch((error: Error) => {
        hilog.warn(0x0001, 'VLC', '[VLC] openToast failed: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(0x0001, 'VLC', '[VLC] openToast failed: %{public}s', String(error));
    }
  }
}
