import { PlayState, VideoNavParam } from '../models/MediaModels';
import { PlaybackHistoryEntry } from '../models/PlaybackHistoryModels';
import { UiFeedback } from '../utils/UiFeedback';
import { NavController } from './NavController';
import { PlaybackHistory } from './PlaybackHistory';
import { PlaybackService, QueueItem } from './PlaybackService';

/** 最近播放和历史卡片共用入口，不能用当前页签推断媒体类型。 */
export class HistoryPlayback {
  static async open(item: PlaybackHistoryEntry, resumeCurrent: boolean = false): Promise<void> {
    try {
      if (!PlaybackHistory.isAudio(item)) {
        const param: VideoNavParam = { uri: item.uri, title: item.title, artworkUrl: item.artworkUrl };
        NavController.push('VideoPlayer', param);
        return;
      }

      const player = PlaybackService.getInstance();
      const current = player.getCurrent();
      const state = player.getState();
      const canResume = resumeCurrent && current !== null && current.uri === item.uri &&
        (!current.isVideo() || player.getPlayAsAudio()) &&
        (state === PlayState.PLAYING || state === PlayState.PAUSED);
      if (canResume) {
        if (state === PlayState.PAUSED) {
          await player.play();
        }
      } else {
        const track = new QueueItem(0, item.title, item.uri, item.artistName, item.albumName, item.artworkUrl);
        await PlaybackService.playList([track], 0, true);
      }
      NavController.push('AudioPlayer');
    } catch (error) {
      UiFeedback.showToast({ message: $r('app.string.playback_history_open_failed') });
    }
  }
}
