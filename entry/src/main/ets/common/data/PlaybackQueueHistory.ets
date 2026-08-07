import { Settings } from './Settings';
import { MediaWrapper } from '../models/MediaModels';

export type PlaybackQueueHistoryType = 'audio' | 'video';

class StoredQueueItem {
  id: number;
  title: string;
  uri: string;
  artistName: string;
  albumName: string;
  artworkPath: string;

  constructor(item: MediaWrapper) {
    this.id = item.id;
    this.title = item.title;
    this.uri = item.uri;
    this.artistName = item.artistName;
    this.albumName = item.albumName;
    this.artworkPath = item.artworkPath;
  }
}

/** Persists the last playable queue independently for audio and video. */
export class PlaybackQueueHistory {
  static async save(type: PlaybackQueueHistoryType, queue: MediaWrapper[], currentIndex: number): Promise<void> {
    if (!await PlaybackQueueHistory.isEnabled(type)) {
      return;
    }
    const key = type === 'audio' ? Settings.KEY_AUDIO_LAST_PLAYLIST : Settings.KEY_MEDIA_LAST_PLAYLIST;
    const currentKey = type === 'audio' ? Settings.KEY_CURRENT_AUDIO : Settings.KEY_CURRENT_MEDIA;
    const items: StoredQueueItem[] = queue.map((item: MediaWrapper) => new StoredQueueItem(item));
    await Settings.put(key, JSON.stringify(items));
    await Settings.put(currentKey, currentIndex);
  }

  private static async isEnabled(type: PlaybackQueueHistoryType): Promise<boolean> {
    if (!await Settings.getBoolean(Settings.ENABLE_PLAYBACK_HISTORY, true)) {
      return false;
    }
    const key = type === 'audio' ? Settings.AUDIO_PLAY_QUEUE_HISTORY : Settings.VIDEO_PLAY_QUEUE_HISTORY;
    return Settings.getBoolean(key, true);
  }
}
