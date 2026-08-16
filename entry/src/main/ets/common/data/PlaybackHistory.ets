import { Settings } from './Settings';
import { MediaLibrary } from './MediaLibrary';
import { MediaWrapper, Track } from '../models/MediaModels';
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
  artistName?: string;
  albumName?: string;
}

const AUDIO_EXTENSIONS: string[] = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];

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
    await PlaybackHistory.hydrateMetadata();
    return PlaybackHistory.snapshot();
  }

  static async refresh(): Promise<PlaybackHistoryEntry[]> {
    PlaybackHistory.loaded = false;
    await PlaybackHistory.ensureLoaded();
    await PlaybackHistory.hydrateMetadata();
    PlaybackHistory.notify();
    return PlaybackHistory.snapshot();
  }

  static async record(
    uri: string,
    title: string,
    length: number = 0,
    artworkUrl: string = '',
    artistName: string = '',
    albumName: string = '',
  ): Promise<void> {
    await PlaybackHistory.ensureLoaded();
    const historyEnabled = await Settings.getBoolean(Settings.ENABLE_PLAYBACK_HISTORY, true);
    if (!historyEnabled) {
      return;
    }
    const incognito = await Settings.getBoolean(Settings.KEY_INCOGNITO, Settings.incognitoMode);
    if (!shouldRecordPlaybackHistory(incognito)) {
      return;
    }
    const resolvedArtworkUrl: string = artworkUrl.length > 0 ? artworkUrl : PlaybackHistory.artworkForUri(uri);
    const entry = new PlaybackHistoryEntry(
      uri,
      title,
      length,
      resolvedArtworkUrl,
      Date.now(),
      artistName,
      albumName,
    );
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

  static async removeEntry(uri: string): Promise<void> {
    await PlaybackHistory.ensureLoaded();
    const before = PlaybackHistory.entries.length;
    PlaybackHistory.entries = PlaybackHistory.entries.filter((entry: PlaybackHistoryEntry) => entry.uri !== uri);
    if (PlaybackHistory.entries.length !== before) {
      await PlaybackHistory.persist();
      PlaybackHistory.notify();
    }
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
      PlaybackHistory.listeners =
        PlaybackHistory.listeners.filter((item: PlaybackHistoryListener) => item !== listener);
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
                typeof item.artistName === 'string' ? item.artistName : '',
                typeof item.albumName === 'string' ? item.albumName : '',
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

  /**
   * 早期历史记录没有保存音频元数据，按 URI 从当前媒体库补齐。
   * 补齐后立即持久化，后续从历史恢复队列时可直接带回艺术家、专辑和封面。
   */
  private static async hydrateMetadata(): Promise<void> {
    const hasMissingArtwork: boolean = PlaybackHistory.entries.some((entry: PlaybackHistoryEntry) =>
    entry.artworkUrl.length === 0);
    const hasMissingAudioMetadata: boolean = PlaybackHistory.entries.some((entry: PlaybackHistoryEntry) =>
    PlaybackHistory.isAudioUri(entry.uri) && (entry.artistName.length === 0 || entry.albumName.length === 0));
    if (!hasMissingArtwork && !hasMissingAudioMetadata) {
      return;
    }
    // 关闭缩略图时不会请求系统缩略图。之后重新开启时，媒体库虽已扫描过，
    // 内存中的 artworkUrl 仍会是空，因此只看 hasScanned() 会永远无法补齐历史。
    // scan() 会复用正在进行的扫描；已有封面的记录会在方法开头直接返回。
    const thumbnailsEnabled: boolean = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    if (!MediaLibrary.hasScanned() ||
      (hasMissingAudioMetadata && MediaLibrary.getAudios().length === 0) ||
      (hasMissingArtwork && thumbnailsEnabled && MediaLibrary.getVideos().length === 0)) {
      await MediaLibrary.scan();
    }
    let changed: boolean = false;
    for (const entry of PlaybackHistory.entries) {
      const audio: Track | undefined = MediaLibrary.getAudios().find((item: Track) => item.uri === entry.uri);
      if (audio !== undefined) {
        if (entry.artistName.length === 0 && audio.artistName.length > 0) {
          entry.artistName = audio.artistName;
          changed = true;
        }
        if (entry.albumName.length === 0 && audio.albumName.length > 0) {
          entry.albumName = audio.albumName;
          changed = true;
        }
        if (entry.artworkUrl.length === 0 && audio.artworkPath.length > 0) {
          entry.artworkUrl = audio.artworkPath;
          changed = true;
        }
      }
      if (entry.artworkUrl.length === 0) {
        const artworkUrl: string = PlaybackHistory.artworkForUri(entry.uri);
        if (artworkUrl.length > 0) {
          entry.artworkUrl = artworkUrl;
          changed = true;
        }
      }
    }
    if (changed) {
      await PlaybackHistory.persist();
    }
  }

  private static artworkForUri(uri: string): string {
    const audio = MediaLibrary.getAudios().find((item: Track) => item.uri === uri);
    if (audio && audio.artworkPath.length > 0) {
      return audio.artworkPath;
    }
    const video = MediaLibrary.getVideos().find((item: MediaWrapper) => item.uri === uri);
    return video && video.artworkUrl.length > 0 ? video.artworkUrl : '';
  }

  private static isAudioUri(uri: string): boolean {
    const lower: string = uri.toLowerCase();
    return AUDIO_EXTENSIONS.some((extension: string) => lower.endsWith(extension));
  }

  private static snapshot(): PlaybackHistoryEntry[] {
    return PlaybackHistory.entries.map((item: PlaybackHistoryEntry) => new PlaybackHistoryEntry(
      item.uri,
      item.title,
      item.length,
      item.artworkUrl,
      item.playedAt,
      item.artistName,
      item.albumName,
    ));
  }

  private static notify(): void {
    const entries = PlaybackHistory.snapshot();
    for (const listener of PlaybackHistory.listeners) {
      listener(entries);
    }
  }
}
