import { Settings } from './Settings';
import {
  PlaybackHistoryEntry,
  prependPlaybackHistory,
  shouldRecordPlaybackHistory,
} from '../models/PlaybackHistoryModels';

interface PersistedPlaybackHistoryEntry {
  uri: string;
  title: string;
  length: number;
  artworkUrl: string;
  playedAt: number;
}

type PlaybackHistoryListener = (entries: PlaybackHistoryEntry[]) => void;

/**
 * 独立于媒体库的视频播放历史：负责持久化、进程内通知和无痕保护。
 */
export class PlaybackHistory {
  private static readonly MAX_ENTRIES: number = 50;
  private static entries: PlaybackHistoryEntry[] = [];
  private static loaded: boolean = false;
  private static loading: Promise<void> | null = null;
  private static listeners: PlaybackHistoryListener[] = [];

  static async load(): Promise<PlaybackHistoryEntry[]> {
    await PlaybackHistory.ensureLoaded();
    return PlaybackHistory.snapshot();
  }

  static async refresh(): Promise<PlaybackHistoryEntry[]> {
    PlaybackHistory.loaded = false;
    await PlaybackHistory.ensureLoaded();
    PlaybackHistory.notify();
    return PlaybackHistory.snapshot();
  }

  static async record(uri: string, title: string, length: number = 0, artworkUrl: string = ''): Promise<void> {
    await PlaybackHistory.ensureLoaded();
    const incognito = await Settings.getBoolean(Settings.KEY_INCOGNITO, Settings.incognitoMode);
    if (!shouldRecordPlaybackHistory(incognito)) {
      return;
    }
    const entry = new PlaybackHistoryEntry(uri, title, length, artworkUrl, Date.now());
    PlaybackHistory.entries = prependPlaybackHistory(PlaybackHistory.entries, entry, PlaybackHistory.MAX_ENTRIES);
    await PlaybackHistory.persist();
    PlaybackHistory.notify();
  }

  static async clear(): Promise<void> {
    await PlaybackHistory.ensureLoaded();
    PlaybackHistory.entries = [];
    await PlaybackHistory.persist();
    PlaybackHistory.notify();
  }

  static async setIncognito(enabled: boolean): Promise<void> {
    await Settings.put(Settings.KEY_INCOGNITO, enabled);
    PlaybackHistory.notify();
  }

  static subscribe(listener: PlaybackHistoryListener): () => void {
    if (!PlaybackHistory.listeners.includes(listener)) {
      PlaybackHistory.listeners.push(listener);
    }
    return () => {
      PlaybackHistory.listeners = PlaybackHistory.listeners.filter((item: PlaybackHistoryListener) => item !== listener);
    };
  }

  private static async ensureLoaded(): Promise<void> {
    if (PlaybackHistory.loaded) {
      return;
    }
    if (PlaybackHistory.loading) {
      await PlaybackHistory.loading;
      return;
    }
    PlaybackHistory.loading = PlaybackHistory.readPersisted();
    try {
      await PlaybackHistory.loading;
    } finally {
      PlaybackHistory.loading = null;
    }
  }

  private static async readPersisted(): Promise<void> {
    const raw = await Settings.getString(Settings.PLAYBACK_HISTORY, '');
    const restored: PlaybackHistoryEntry[] = [];
    if (raw.length > 0) {
      try {
        const items = JSON.parse(raw) as PersistedPlaybackHistoryEntry[];
        if (Array.isArray(items)) {
          for (const item of items) {
            if (typeof item.uri === 'string' && item.uri.length > 0 && typeof item.title === 'string') {
              restored.push(new PlaybackHistoryEntry(
                item.uri,
                item.title,
                typeof item.length === 'number' ? item.length : 0,
                typeof item.artworkUrl === 'string' ? item.artworkUrl : '',
                typeof item.playedAt === 'number' ? item.playedAt : 0,
              ));
            }
          }
        }
      } catch (error) {
        restored.length = 0;
      }
    }
    PlaybackHistory.entries = restored.slice(0, PlaybackHistory.MAX_ENTRIES);
    PlaybackHistory.loaded = true;
  }

  private static async persist(): Promise<void> {
    await Settings.put(Settings.PLAYBACK_HISTORY, JSON.stringify(PlaybackHistory.entries));
  }

  private static snapshot(): PlaybackHistoryEntry[] {
    return PlaybackHistory.entries.map((item: PlaybackHistoryEntry) => new PlaybackHistoryEntry(
      item.uri,
      item.title,
      item.length,
      item.artworkUrl,
      item.playedAt,
    ));
  }

  private static notify(): void {
    const entries = PlaybackHistory.snapshot();
    for (const listener of PlaybackHistory.listeners) {
      listener(entries);
    }
  }
}
