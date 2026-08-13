import { UiFeedback } from '../../common/utils/UiFeedback';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * VideoDelayDelegate —— 对齐 Android VideoDelayDelegate（音轨/字幕延迟骨架）。
 */
export class VideoDelayDelegate {
  playbackSetting: string = '';

  showDelayControls(): void {
    hilog.info(0x0001, 'VLC', '[VLC] DelayDelegate.showDelayControls (stub)');
    UiFeedback.showToast({ message: 'Audio/SPU delay is not available yet' });
  }

  showAudioDelaySetting(): void {
    this.playbackSetting = 'audio';
    this.showDelayControls();
  }

  showSubsDelaySetting(): void {
    this.playbackSetting = 'spu';
    this.showDelayControls();
  }

  endPlaybackSetting(): void {
    this.playbackSetting = '';
  }

  delayAudioOrSpu(_delta: number): void {
    hilog.info(0x0001, 'VLC', '[VLC] DelayDelegate.delayAudioOrSpu (stub)');
  }

  delayChanged(): void {
    hilog.info(0x0001, 'VLC', '[VLC] DelayDelegate.delayChanged (stub)');
  }
}
