import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoTipsDelegate —— 对齐 Android VideoTipsDelegate（首次手势引导骨架）。
 */
export class VideoTipsDelegate {
  currentTip: number = -1;

  init(): void {
    hilog.info(0x0001, 'VLC', '[VLC] TipsDelegate.init (stub)');
  }

  next(): void {
    hilog.info(0x0001, 'VLC', '[VLC] TipsDelegate.next (stub)');
  }

  close(): void {
    this.currentTip = -1;
  }

  /** 调试入口：提示尚未实现。 */
  showUnavailable(): void {
    promptAction.showToast({ message: 'Player tips are not available yet' });
  }
}
