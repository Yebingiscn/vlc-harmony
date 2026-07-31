import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoStatsDelegate —— 对齐 Android VideoStatsDelegate（码率/轨道统计骨架）。
 */
export class VideoStatsDelegate {
  private running: boolean = false;

  initPlotView(): void {
    hilog.info(0x0001, 'VLC', '[VLC] StatsDelegate.initPlotView (stub)');
  }

  start(): void {
    this.running = true;
    hilog.info(0x0001, 'VLC', '[VLC] StatsDelegate.start (stub)');
    promptAction.showToast({ message: 'Video stats are not available yet' });
  }

  stop(): void {
    this.running = false;
    hilog.info(0x0001, 'VLC', '[VLC] StatsDelegate.stop (stub)');
  }

  onConfigurationChanged(): void {
    hilog.info(0x0001, 'VLC', '[VLC] StatsDelegate.onConfigurationChanged (stub)');
  }

  isRunning(): boolean {
    return this.running;
  }
}
