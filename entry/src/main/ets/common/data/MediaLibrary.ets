import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { AppContext } from './AppContext';
import {
  Album,
  Artist,
  Folder,
  Genre,
  MediaWrapper,
  Playlist,
  SheetItem,
  Track,
  VideoGroup
} from '../models/MediaModels';
import { BookMark } from '../models/BookmarkModels';
import { QueueItem } from './PlaybackService';
import { Settings } from './Settings';
import { DocumentPermission } from './DocumentPermission';

/** 统一日志:tag=VLC,消息带 [VLC] 前缀,便于 `grep VLC run.log` 过滤出应用日志。 */
const HILog = (msg: string): void => hilog.info(0x0001, 'VLC', '[VLC] %{public}s', msg);

/** parseMedia 返回的 JSON 结构。 */
interface AudioMeta {
  title: string;
  artist: string;
  album: string;
  genre: string;
  trackNumber: string;
  year: string;
  artworkUrl: string;
  albumArtist: string;
  duration: number;
  artworkPath: string;
  videoWidth: number;
  videoHeight: number;
}

/** 持久化存储 key:用户导入的音频轨道 JSON 数组。 */
const KEY_AUDIO_LIBRARY: string = 'audio_library_persisted';
const KEY_VIDEO_LIBRARY: string = 'video_library_persisted';

/** 收藏条目持久化结构。 */
interface FavItem {
  title: string;
  subtitle: string;
  iconType: string;
  uri: string;
  artworkPath: string;
}

/** 持久化用的音频元数据结构(避免匿名对象字面量)。 */
interface PersistedTrack {
  uri: string;
  title: string;
  artistName: string;
  albumName: string;
  genre: string;
  trackNumber: number;
  year: string;
  length: number;
  artworkPath: string;
}

interface PersistedVideo {
  uri: string;
  title: string;
  displayName: string;
  filePath: string;
  length: number;
  width: number;
  height: number;
  size: number;
  artworkUrl: string;
  dateAdded: number;
  dateModified: number;
}

/**
 * MediaLibrary —— Android medialibrary.MediaLibrary 扫描的鸿蒙等价物。
 * 能力替换约定:VLC 原生 medialibrary(C/C++)→ 用 photoAccessHelper(视频)+ fs(音频)扫描真实设备媒体。
 * 【非 mock】:返回设备上真实存在的媒体;无媒体/无权限时返回空列表(UI 按规格显示空态)。
 */
const AUDIO_EXTS: string[] = ['mp3', 'aac', 'flac', 'ogg', 'wav', 'm4a', 'wma', 'opus'];
const VIDEO_EXTS: string[] =
  ['mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'iso', '3gp', 'wmv', 'flv', 'm4v', 'mpg', 'mpeg', 'm2ts', 'vob'];

export class MediaLibrary {
  /** 播放列表变更事件 ID（emitter 全局广播，订阅方应 reload 自身 UI）。 */
  public static readonly EVENT_PLAYLISTS_CHANGED: string = 'vlc_playlists_changed';
  private static videos: MediaWrapper[] = [];
  private static audios: Track[] = [];
  private static artists: Artist[] = [];
  private static albums: Album[] = [];
  private static genres: Genre[] = [];
  private static folders: Folder[] = [];
  private static scanned: boolean = false;
  private static scanning: boolean = false;
  private static scanPromise: Promise<void> | null = null;
  private static readonly KEY_STORAGE_FILES = 'browser_storage_files';
  private static storageItems: SheetItem[] = [];
  private static readonly KEY_FAVORITES: string = 'browser_favorites';
  private static readonly KEY_PLAYLISTS: string = 'vlc_playlists';
  private static playlistCache: StoredPlaylist[] = [];
  private static playlistCacheInited: boolean = false;
  private static readonly KEY_BOOKMARKS: string = 'vlc_bookmarks';
  private static readonly KEY_MEDIA_FAVS: string = 'media_favorites';
  private static mediaFavCache: Set<string> = new Set<string>();
  private static readonly KEY_VIDEO_FAVS: string = 'video_favorites';
  private static videoFavCache: Set<string> = new Set<string>();
  private static readonly KEY_FOLDER_FAVS: string = 'folder_favorites';
  private static folderFavCache: Set<string> = new Set<string>();

  static isScanning(): boolean {
    return MediaLibrary.scanning;
  }

  static hasScanned(): boolean {
    return MediaLibrary.scanned;
  }

  /** 触发媒体库扫描(对应 Medialibrary.getInstance().startTimer/scan)。 */
  static async scan(): Promise<void> {
    // 并发调用(MainPage + 各 Tab 页都会调)复用同一个在途 Promise,避免某调用读到未完成的空结果。
    if (MediaLibrary.scanPromise) {
      return MediaLibrary.scanPromise;
    }
    const p: Promise<void> = MediaLibrary.doScan();
    MediaLibrary.scanPromise = p;
    try {
      await p;
    } finally {
      MediaLibrary.scanPromise = null;
    }
  }

  /** 强制重新扫描(忽略缓存,供下拉刷新使用)。 */
  static async rescan(): Promise<void> {
    if (MediaLibrary.scanPromise !== null) {
      await MediaLibrary.scanPromise;
    }
    await MediaLibrary.scan();
  }

  static getVideos(): MediaWrapper[] {
    return MediaLibrary.videos;
  }

  static getAudios(): Track[] {
    return MediaLibrary.audios;
  }

  static getArtists(): Artist[] {
    return MediaLibrary.artists;
  }

  static getAlbums(): Album[] {
    return MediaLibrary.albums;
  }

  static getGenres(): Genre[] {
    return MediaLibrary.genres;
  }

  /** 将 MediaWrapper[] 转为 QueueItem[](供 PlaybackService.playList 使用)。 */
  static toQueueItems(items: MediaWrapper[]): QueueItem[] {
    return items.map((mw: MediaWrapper) =>
    new QueueItem(mw.id, mw.title, mw.uri, mw.artistName, mw.albumName, mw.artworkPath)
    );
  }

  /** 将 DocumentViewPicker 选中的音频按 URI 引用加入媒体库，不复制媒体文件。 */
  static async importAudioUris(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    HILog(`importAudioUris: received ${uris.length} URI(s)`);
    const uniqueUris = Array.from(new Set(uris));
    const existingUris = new Set(MediaLibrary.audios.map((t: Track) => t.uri));
    const newByUri = uniqueUris.filter((u: string) => !existingUris.has(u));
    HILog(`importAudioUris: after uri dedup: ${newByUri.length} new`);
    if (newByUri.length === 0) {
      return;
    }
    const startIndex = MediaLibrary.audios.length;
    let addedCount = 0;
    for (let i = 0; i < newByUri.length; i++) {
      const pickerUri = newByUri[i];
      HILog(`importAudioUris[${i}]: ${pickerUri}`);
      if (!(await DocumentPermission.persist(pickerUri))) {
        HILog(`importAudioUris[${i}]: persistent permission failed`);
        continue;
      }
      const meta = await MediaLibrary.parseFileMeta(pickerUri);
      HILog(`importAudioUris[${i}]: meta title="${meta.title}" artist="${meta.artist}" album="${meta.album}"`);
      const t = new Track(startIndex + addedCount, meta.title, pickerUri);
      t.displayName = meta.title;
      t.filePath = pickerUri;
      t.length = meta.duration;
      t.artistName = meta.artist;
      t.albumName = meta.album;
      t.genre = meta.genre;
      t.trackNumber = parseInt(meta.trackNumber) || 0;
      t.year = meta.year;
      t.artworkPath = meta.artworkPath;
      MediaLibrary.audios.push(t);
      existingUris.add(pickerUri);
      addedCount++;
    }
    if (addedCount > 0) {
      MediaLibrary.deriveFromMeta();
      await MediaLibrary.saveAudioLibrary();
    }
    HILog(`importAudioUris done, added ${addedCount}, total audios: ${MediaLibrary.audios.length}`);
  }

  /** 将 DocumentViewPicker 选中的视频按 URI 引用加入媒体库，不复制媒体文件。 */
  static async importVideoUris(uris: string[]): Promise<void> {
    const uniqueUris = Array.from(new Set(uris));
    const existingUris = new Set(MediaLibrary.videos.map((v: MediaWrapper) => v.uri));
    let addedCount = 0;
    for (let i = 0; i < uniqueUris.length; i++) {
      const uri = uniqueUris[i];
      if (uri.length === 0 || existingUris.has(uri)) {
        continue;
      }
      if (!(await DocumentPermission.persist(uri))) {
        HILog(`importVideoUris[${i}]: persistent permission failed`);
        continue;
      }
      const meta = await MediaLibrary.parseFileMeta(uri);
      const title = meta.title.length > 0 ? meta.title : MediaLibrary.fileNameTitle(uri);
      const video = new MediaWrapper(MediaLibrary.videos.length, title, uri, 0);
      video.displayName = MediaLibrary.fileNameTitle(uri);
      video.filePath = uri;
      video.length = meta.duration;
      video.width = meta.videoWidth;
      video.height = meta.videoHeight;
      video.resolution = video.width > 0 && video.height > 0 ? `${video.width}x${video.height}` : '';
      video.artworkUrl = meta.artworkPath;
      try {
        const stat = fs.statSync(uri);
        video.size = stat.size;
        video.dateAdded = stat.ctime;
        video.dateModified = stat.mtime;
      } catch (e) {
        // URI 仍可播放；文件提供方不支持 stat 时保留默认值。
      }
      MediaLibrary.videos.push(video);
      existingUris.add(uri);
      addedCount++;
    }
    if (addedCount > 0) {
      await MediaLibrary.saveVideoLibrary();
    }
    HILog(`importVideoUris done, added ${addedCount}, total videos: ${MediaLibrary.videos.length}`);
  }

  /** 从给定的视频列表派生文件夹分组(供 VideoGridPage 按文件夹分组展示)。 */
  static getFoldersFromVideos(videos: MediaWrapper[]): Folder[] {
    const map = new Map<string, Folder>();
    let fid = 0;
    for (const v of videos) {
      const key = v.filePath.includes('/') ? v.filePath.slice(0, v.filePath.lastIndexOf('/')) : '';
      if (!map.has(key)) {
        const folderTitle = key === '' ? '视频' : key.slice(key.lastIndexOf('/') + 1);
        const f = new Folder(fid++, folderTitle, key);
        f.thumbnailUrls = [];
        map.set(key, f);
      }
      const folder = map.get(key) as Folder;
      folder.mediaCount += 1;
      // 收集前 4 个视频缩略图用于 2x2 拼图封面。
      if (folder.thumbnailUrls.length < 4 && v.artworkUrl.length > 0) {
        folder.thumbnailUrls.push(v.artworkUrl);
      }
      // artworkUrl 兜底用第一个有缩略图的视频。
      if (folder.artworkUrl.length === 0 && v.artworkUrl.length > 0) {
        folder.artworkUrl = v.artworkUrl;
      }
    }
    return Array.from(map.values());
  }

  /** 按视频所在目录分组(VideoGroupingType.FOLDER)。 */
  static getVideoFolders(): Folder[] {
    return MediaLibrary.getFoldersFromVideos(MediaLibrary.videos);
  }

  /** 获取指定文件夹路径下的所有视频(供文件夹详情页使用)。 */
  static getVideosByFolder(folderPath: string): MediaWrapper[] {
    return MediaLibrary.videos.filter((v: MediaWrapper) => {
      if (v.filePath.includes('/')) {
        return v.filePath.slice(0, v.filePath.lastIndexOf('/')) === folderPath;
      }
      return folderPath === '';
    });
  }

  static getVideoGroups(): VideoGroup[] {
    const map = new Map<string, VideoGroup>();
    let gid = 0;
    for (const v of MediaLibrary.videos) {
      const letter = v.title.length > 0 ? v.title.charAt(0).toUpperCase() : '#';
      if (!map.has(letter)) {
        map.set(letter, new VideoGroup(gid++, letter));
      }
      (map.get(letter) as VideoGroup).mediaCount += 1;
    }
    return Array.from(map.values());
  }

  /** 仅扫描视频(浏览页使用,不触发慢速音频扫描)。 */
  static async scanVideosOnly(): Promise<void> {
    MediaLibrary.scanning = true;
    try {
      MediaLibrary.videos = [];
      await MediaLibrary.loadVideoLibrary();
      MediaLibrary.scanned = true;
    } finally {
      MediaLibrary.scanning = false;
    }
  }

  // ---- 存储文件管理(浏览页使用,仅追踪通过 picker 导入的音视频) ----

  static getStorageFiles(): SheetItem[] {
    return MediaLibrary.storageItems;
  }

  /** 启动时从持久化恢复存储文件列表(仅恢复元数据,URI 指向沙箱永久副本)。 */
  static async loadStorageFiles(): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_STORAGE_FILES, '[]');
    try {
      const arr: FavItem[] = JSON.parse(raw) as FavItem[];
      const items: SheetItem[] = [];
      for (const item of arr) {
        if (!(await DocumentPermission.activate(item.uri))) {
          continue;
        }
        const icon: Resource = item.iconType === 'video' ? $r('app.media.ic_video') : $r('app.media.ic_song');
        let artworkPath = item.artworkPath || '';
        // 旧数据可能没有 artworkPath,尝试从已有沙箱文件中提取。
        if (artworkPath.length === 0 && item.iconType === 'audio' && item.uri.length > 0) {
          try {
            const meta = await MediaLibrary.parseFileMeta(item.uri);
            artworkPath = meta.artworkPath;
            if (artworkPath.length > 0) {
              HILog(`loadStorageFiles: extracted artwork for "${item.title}": ${artworkPath}`);
            }
          } catch (e) {
            // extraction failed, keep empty
          }
        }
        items.push(new SheetItem(item.title, item.subtitle, icon, item.uri, artworkPath));
      }
      MediaLibrary.storageItems = items;
      // 如果旧数据补全了封面,回写到 prefs 避免下次启动再重复提取。
      const hasNewArtwork = items.some(
        (s: SheetItem) => s.artworkPath.length > 0 && !arr.find((f: FavItem) => f.title === s.title)?.artworkPath);
      if (hasNewArtwork) {
        await MediaLibrary.saveStorageItemsToPrefs();
        HILog('loadStorageFiles: saved re-extracted artwork to prefs');
      }
    } catch (e) {
      MediaLibrary.storageItems = [];
    }
  }

  static async importStorageFiles(uris: string[]): Promise<void> {
    const uniqueUris = Array.from(new Set(uris));
    for (let i = 0; i < uniqueUris.length; i++) {
      const pickerUri = uniqueUris[i];
      HILog(`importStorage: ${pickerUri}`);
      if (!(await DocumentPermission.persist(pickerUri))) {
        HILog(`importStorage: persistent permission failed for ${pickerUri}`);
        continue;
      }
      const lower = pickerUri.toLowerCase();
      const isAudio = AUDIO_EXTS.some(f => lower.endsWith(f));
      const meta = await MediaLibrary.parseFileMeta(pickerUri);
      // 音频文件使用元数据标题+艺术家;视频/iso 等直接使用源文件名。
      const originalName = MediaLibrary.fileNameTitle(pickerUri);
      const title = isAudio ? (meta.title.length > 0 ? meta.title : originalName) : originalName;
      const subtitle = isAudio ? (meta.artist.length > 0 ? meta.artist : '音频') : '视频';
      const icon: Resource = isAudio ? $r('app.media.ic_song') : $r('app.media.ic_video');
      const artworkPath = isAudio ? (meta.artworkPath.length > 0 ? meta.artworkPath : '') : '';
      HILog(`importStorage: title="${title}" isAudio=${isAudio} artworkPath="${artworkPath}"`);
      if (!MediaLibrary.storageItems.some((item: SheetItem) => item.uri === pickerUri)) {
        MediaLibrary.storageItems.push(new SheetItem(title, subtitle, icon, pickerUri, artworkPath));
      }
    }
    const audioUris = uniqueUris.filter((uri: string) => AUDIO_EXTS.some((ext: string) => uri.toLowerCase().endsWith(ext)));
    const videoUris = uniqueUris.filter((uri: string) =>
      VIDEO_EXTS.some((ext: string) => uri.toLowerCase().endsWith(ext)));
    await MediaLibrary.importAudioUris(audioUris);
    await MediaLibrary.importVideoUris(videoUris);
    // 整批持久化当前 storageItems。
    await MediaLibrary.saveStorageItemsToPrefs();
    HILog(`importStorage done: ${MediaLibrary.storageItems.length} items`);
  }

  /** 存储设备列表(浏览页使用)。 */
  static getStorageDevices(): SheetItem[] {
    const result: SheetItem[] = [];
    const folders: Folder[] = MediaLibrary.getVideoFolders();
    result.push(new SheetItem('内部存储',
      `${folders.length} 个文件夹 · ${MediaLibrary.videos.length} 个视频`,
      $r('app.media.ic_folder_usb')));
    return result;
  }

  /** 视频目录列表。 */
  static getVideoDirectories(): SheetItem[] {
    const result: SheetItem[] = [];
    const folders: Folder[] = MediaLibrary.getVideoFolders();
    for (const f of folders) {
      result.push(new SheetItem(f.title, `${f.mediaCount} 个视频`, $r('app.media.ic_folder')));
    }
    return result;
  }

  static async getFavorites(): Promise<SheetItem[]> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_FAVORITES, '[]');
    const result: SheetItem[] = [];
    try {
      const arr: FavItem[] = JSON.parse(raw) as FavItem[];
      for (const item of arr) {
        const icon: Resource = item.iconType === 'video' ? $r('app.media.ic_video') : $r('app.media.ic_song');
        result.push(new SheetItem(item.title, item.subtitle, icon, item.uri, item.artworkPath || ''));
      }
    } catch (e) {
      // parse error
    }
    return result;
  }

  static async addFavorite(item: SheetItem): Promise<void> {
    const cur: FavItem[] = await MediaLibrary.loadFavRaw();
    for (const c of cur) {
      if (c.title === item.title) {
        return;
      }
    }
    const iconType: string = item.subtitle === '视频' ? 'video' : 'audio';
    const newItem: FavItem = {
      title: item.title,
      subtitle: item.subtitle,
      iconType: iconType,
      uri: item.uri,
      artworkPath: item.artworkPath
    };
    cur.push(newItem);
    await MediaLibrary.saveFavRaw(cur);
  }

  static async removeFavorite(title: string): Promise<void> {
    const cur: FavItem[] = await MediaLibrary.loadFavRaw();
    const filtered: FavItem[] = [];
    for (const s of cur) {
      if (s.title !== title) {
        filtered.push(s);
      }
    }
    await MediaLibrary.saveFavRaw(filtered);
  }

  // ---- 收藏管理 ----

  /** 初始化播放列表缓存（从 Settings 加载，幂等）。 */
  static async initPlaylistCache(): Promise<void> {
    if (MediaLibrary.playlistCacheInited) {
      return;
    }
    await MediaLibrary.reloadPlaylistCache();
    MediaLibrary.playlistCacheInited = true;
  }

  /** 强制从 Settings 重新加载播放列表缓存（无视 inited 标记，Tab 切换/下拉刷新时使用）。 */
  static async reloadPlaylistCache(): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_PLAYLISTS, '[]');
    try {
      MediaLibrary.playlistCache = JSON.parse(raw) as StoredPlaylist[];
    } catch (e) {
      MediaLibrary.playlistCache = [];
    }
  }

  /** 获取所有已存储的播放列表（返回 Playlist 视图，供 UI 使用）。 */
  static getPlaylists(): Playlist[] {
    return MediaLibrary.playlistCache.map((s: StoredPlaylist) => {
      const p: Playlist = new Playlist(s.id, s.name);
      p.trackCount = s.uriList.length;
      return p;
    });
  }

  /** 获取原始存储的播放列表数据（含 uriList，供 PlaylistsPage 统计可用曲目数）。 */
  static getStoredPlaylists(): StoredPlaylist[] {
    return MediaLibrary.playlistCache;
  }

  /** 获取某播放列表中的 URI 列表。 */
  static getPlaylistUris(playlistId: number): string[] {
    const pl: StoredPlaylist | undefined = MediaLibrary.playlistCache.find((s: StoredPlaylist) => s.id === playlistId);
    return pl ? pl.uriList : [];
  }

  /** 新建播放列表并持久化。返回新建的 Playlist。 */
  static async createPlaylist(name: string): Promise<Playlist> {
    await MediaLibrary.initPlaylistCache();
    const id: number = Date.now();
    const sp: StoredPlaylist = { id: id, name: name, uriList: [] };
    MediaLibrary.playlistCache.push(sp);
    await MediaLibrary.savePlaylists();
    const p: Playlist = new Playlist(id, name);
    p.trackCount = 0;
    return p;
  }

  // ---- 播放列表管理 ----

  /** 向播放列表追加曲目 URI（去重）并持久化。 */
  static async addToPlaylist(playlistId: number, uri: string): Promise<void> {
    await MediaLibrary.initPlaylistCache();
    const pl: StoredPlaylist | undefined = MediaLibrary.playlistCache.find((s: StoredPlaylist) => s.id === playlistId);
    if (pl && !pl.uriList.includes(uri)) {
      pl.uriList.push(uri);
      await MediaLibrary.savePlaylists();
    }
  }

  /** 替换播放列表的全部 URI 并持久化。 */
  static async replacePlaylist(playlistId: number, uriList: string[]): Promise<void> {
    await MediaLibrary.initPlaylistCache();
    const pl: StoredPlaylist | undefined = MediaLibrary.playlistCache.find((s: StoredPlaylist) => s.id === playlistId);
    if (pl) {
      pl.uriList = uriList;
      await MediaLibrary.savePlaylists();
    }
  }

  /** 重命名播放列表并持久化。 */
  static async renamePlaylist(id: number, newName: string): Promise<void> {
    await MediaLibrary.initPlaylistCache();
    const pl: StoredPlaylist | undefined = MediaLibrary.playlistCache.find((s: StoredPlaylist) => s.id === id);
    if (pl) {
      pl.name = newName;
      await MediaLibrary.savePlaylists();
    }
  }

  /** 删除播放列表并持久化。 */
  static async deletePlaylist(id: number): Promise<void> {
    await MediaLibrary.initPlaylistCache();
    MediaLibrary.playlistCache = MediaLibrary.playlistCache.filter((s: StoredPlaylist) => s.id !== id);
    await MediaLibrary.savePlaylists();
  }

  /** 加载指定视频的所有书签（按时间排序）。 */
  static async loadBookmarks(mediaUri: string): Promise<BookMark[]> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_BOOKMARKS, '{}');
    try {
      const all: Record<string, PersistedBookmark[]> = JSON.parse(raw) as Record<string, PersistedBookmark[]>;
      const arr: PersistedBookmark[] = all[mediaUri] ?? [];
      return arr.map((b: PersistedBookmark) => new BookMark(b.id, b.mediaId, b.timeMs, b.name));
    } catch (e) {
      return [];
    }
  }

  /** 保存指定视频的书签列表。 */
  static async saveBookmarks(mediaUri: string, bookmarks: BookMark[]): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_BOOKMARKS, '{}');
    let all: Record<string, PersistedBookmark[]> = {};
    try {
      all = JSON.parse(raw) as Record<string, PersistedBookmark[]>;
    } catch (e) {
      // ignore
    }
    all[mediaUri] = bookmarks.map((b: BookMark) => ({
      id: b.id,
      mediaId: b.mediaId,
      timeMs: b.timeMs,
      name: b.name,
    } as PersistedBookmark));
    await Settings.put(MediaLibrary.KEY_BOOKMARKS, JSON.stringify(all));
  }

  /** 计算专辑收藏键:空专辑名/歌手名归一化为"未知专辑"/"未知艺术家"。 */
  static albumFavKey(albumName: string, artistName: string): string {
    const a = albumName.length > 0 ? albumName : '未知专辑';
    const ar = artistName.length > 0 ? artistName : '未知艺术家';
    return `${a}|${ar}`;
  }

  static async loadMediaFavs(): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_MEDIA_FAVS, '[]');
    MediaLibrary.mediaFavCache = new Set<string>();
    try {
      const arr: string[] = JSON.parse(raw) as string[];
      for (const k of arr) {
        MediaLibrary.mediaFavCache.add(k);
      }
    } catch (e) {
      // parse error -> empty
    }
  }

  static isMediaFav(key: string): boolean {
    return MediaLibrary.mediaFavCache.has(key);
  }

  /** 切换收藏状态,返回切换后是否已收藏。 */
  static async toggleMediaFav(key: string): Promise<boolean> {
    if (MediaLibrary.mediaFavCache.has(key)) {
      MediaLibrary.mediaFavCache.delete(key);
    } else {
      MediaLibrary.mediaFavCache.add(key);
    }
    const arr: string[] = Array.from(MediaLibrary.mediaFavCache);
    await Settings.put(MediaLibrary.KEY_MEDIA_FAVS, JSON.stringify(arr));
    return MediaLibrary.mediaFavCache.has(key);
  }

  static async loadVideoFavs(): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_VIDEO_FAVS, '[]');
    MediaLibrary.videoFavCache = new Set<string>();
    try {
      const arr: string[] = JSON.parse(raw) as string[];
      for (const k of arr) {
        MediaLibrary.videoFavCache.add(k);
      }
    } catch (e) {
      // parse error -> empty
    }
  }

  static isVideoFav(uri: string): boolean {
    return MediaLibrary.videoFavCache.has(uri);
  }

  /** 切换视频收藏状态,返回切换后是否已收藏。 */
  static async toggleVideoFav(uri: string): Promise<boolean> {
    if (MediaLibrary.videoFavCache.has(uri)) {
      MediaLibrary.videoFavCache.delete(uri);
    } else {
      MediaLibrary.videoFavCache.add(uri);
    }
    const arr: string[] = Array.from(MediaLibrary.videoFavCache);
    await Settings.put(MediaLibrary.KEY_VIDEO_FAVS, JSON.stringify(arr));
    return MediaLibrary.videoFavCache.has(uri);
  }

  static async loadFolderFavs(): Promise<void> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_FOLDER_FAVS, '[]');
    MediaLibrary.folderFavCache = new Set<string>();
    try {
      const arr: string[] = JSON.parse(raw) as string[];
      for (const k of arr) {
        MediaLibrary.folderFavCache.add(k);
      }
    } catch (e) {
      // parse error -> empty
    }
  }

  static isFolderFav(path: string): boolean {
    return MediaLibrary.folderFavCache.has(path);
  }

  /** 切换文件夹收藏状态,返回切换后是否已收藏。 */
  static async toggleFolderFav(path: string): Promise<boolean> {
    if (MediaLibrary.folderFavCache.has(path)) {
      MediaLibrary.folderFavCache.delete(path);
    } else {
      MediaLibrary.folderFavCache.add(path);
    }
    const arr: string[] = Array.from(MediaLibrary.folderFavCache);
    await Settings.put(MediaLibrary.KEY_FOLDER_FAVS, JSON.stringify(arr));
    return MediaLibrary.folderFavCache.has(path);
  }

  // ---- 书签管理 ----

  /** 拉起系统分享面板分享视频文件。 */
  static async shareVideo(uri: string, title: string): Promise<void> {
    try {
      const ctx = AppContext.get();
      // 从 URI 中提取文件后缀，获取精准的 utd 类型(媒体类型族)。
      const fileName: string = uri.substring(uri.lastIndexOf('/') + 1);
      const dotIdx: number = fileName.lastIndexOf('.');
      const extension: string = dotIdx >= 0 ? fileName.substring(dotIdx) : '';
      const utdTypeId: string = extension.length > 0
        ? utd.getUniformDataTypeByFilenameExtension(extension, utd.UniformDataType.MEDIA)
        : utd.UniformDataType.MEDIA;
      // 构造分享数据，uri 字段直接使用文件 URI。
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: uri,
        title: title,
        description: '视频文件'
      });
      // 创建分享控制器并拉起系统分享面板。
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (e) {
      HILog(`shareVideo error: ${(e as Error).message ?? String(e)}`);
    }
  }

  /** 从应用媒体库移除视频引用，不删除用户的源文件。 */
  static async deleteVideo(video: MediaWrapper): Promise<boolean> {
    try {
      const uri = video.uri;
      MediaLibrary.videos = MediaLibrary.videos.filter((v: MediaWrapper) => v.uri !== uri);
      await MediaLibrary.saveVideoLibrary();
      HILog(`deleteVideo: removed library reference ${uri}`);
      return true;
    } catch (e) {
      HILog(`deleteVideo error: ${(e as Error).message ?? String(e)}`);
      return false;
    }
  }

  private static async doScan(): Promise<void> {
    MediaLibrary.scanning = true;
    try {
      HILog('load imported media start');
      MediaLibrary.videos = [];
      MediaLibrary.audios = [];
      await Promise.all([MediaLibrary.loadVideoLibrary(), MediaLibrary.loadAudioLibrary()]);
      MediaLibrary.deriveFromMeta();
      MediaLibrary.scanned = true;
      HILog(
        `scan done: videos=${MediaLibrary.videos.length} audios=${MediaLibrary.audios.length} artists=${MediaLibrary.artists.length} albums=${MediaLibrary.albums.length} genres=${MediaLibrary.genres.length}`);
    } catch (e) {
      HILog(`scan error: ${(e as Error).message ?? String(e)}`);
    } finally {
      MediaLibrary.scanning = false;
    }
  }

  // ---- 媒体收藏(专辑级,键为 "album|artist") ----

  /** 旧版公共媒体扫描实现，当前导入模式不会调用。 */
  private static async scanVideos(): Promise<void> {
    /*
    const list: MediaWrapper[] = [];
    // 关闭缩略图时既不请求系统缩略图，也不写入缓存，避免无意义的扫描开销。
    const loadThumbnails: boolean = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    try {
      const ctx = AppContext.get();
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const predicates = new dataSharePredicates.DataSharePredicates();
      // 先用完整列;若某列非法(13900042)抛错,回退到默认列(仅 uri/file_type)再试一次。
      let assets: photoAccessHelper.PhotoAsset[] = [];
      try {
        const opts: photoAccessHelper.FetchOptions = {
          fetchColumns: ['title', 'duration', 'width', 'height', 'size', 'media_type', 'date_added', 'date_modified'],
          predicates: predicates,
        };
        const result = await helper.getAssets(opts);
        assets = await result.getAllObjects();
      } catch (e1) {
        HILog(`getAssets(fullCols) failed, retry default: ${(e1 as Error).message ?? String(e1)}`);
        const opts2: photoAccessHelper.FetchOptions = {
          fetchColumns: [],
          predicates: new dataSharePredicates.DataSharePredicates(),
        };
        const result2 = await helper.getAssets(opts2);
        assets = await result2.getAllObjects();
      }
      HILog(`getAssets returned ${assets.length} asset(s)`);
      // 探针:确认 assets[0] 类型(排查 getAllObjects 返回空元素)。
      if (assets.length > 0) {
        try {
          HILog(`probe: typeof assets[0]=${typeof assets[0]}`);
        } catch (e2) {
          HILog('probe failed');
        }
      }
      let videoCount = 0;
      for (let i = 0; i < assets.length; i++) {
        try {
          const asset = assets[i];
          // PhotoKeys.PHOTO_TYPE = 'media_type'(非 'file_type');PhotoType.IMAGE=1, VIDEO=2。
          const fileType = Number(asset.get('media_type') ?? 0);
          if (fileType !== 0 && fileType !== 2) {
            continue; // 跳过图片(IMAGE=1)
          }
          const title = (asset.get('title') as string) || asset.displayName || `Video ${i}`;
          const duration = Number(asset.get('duration') ?? 0);
          const width = Number(asset.get('width') ?? 0);
          const height = Number(asset.get('height') ?? 0);
          const size = Number(asset.get('size') ?? 0);
          // uri 是 PhotoAsset 的只读属性(非 get() 列),用 asset.uri。
          const uri: string = asset.uri;
          if (uri.length === 0) {
            continue;
          }
          const mw = new MediaWrapper(videoCount, title, uri, 0);
          mw.length = duration;
          mw.width = width;
          mw.height = height;
          mw.size = size;
          mw.dateAdded = Number(asset.get('date_added') ?? 0);
          mw.dateModified = Number(asset.get('date_modified') ?? 0);
          mw.resolution = width > 0 && height > 0 ? `${width}x${height}` : '';
          // displayName 存原始文件名(含扩展名),供后续文件系统扫描按文件名匹配回填 filePath。
          mw.displayName = asset.displayName || title;
          mw.artworkUrl = '';
          try {
            if (loadThumbnails) {
              const thumbPm = await asset.getThumbnail({ width: 256, height: 256 });
              if (thumbPm) {
                const cacheName = `video_thumb_${videoCount}_${Date.now()}.jpg`;
                const cacheDir = AppContext.get().cacheDir;
                const cachePath = `${cacheDir}/${cacheName}`;
                const packer = image.createImagePacker();
                const buffer = await packer.packToData(thumbPm, { format: 'image/jpeg', quality: 80 });
                const outFile = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
                fs.writeSync(outFile.fd, buffer);
                fs.closeSync(outFile);
                packer.release();
                thumbPm.release();
                mw.artworkUrl = `file://${cachePath}`;
              }
            }
          } catch (thumbErr) {
            // 缩略图提取失败,保留空 artworkUrl,UI 回落占位图。
          }
          // filePath 供按目录分组(getVideoFolders)使用;photoAccessHelper 不暴露真实路径,
          // 留空串 -- 后续文件系统扫描会按文件名匹配回填真实路径;未匹配到的归入"视频"文件夹。
          mw.filePath = '';
          list.push(mw);
          videoCount++;
        } catch (e) {
          if (i < 5) {
            HILog(`asset[${i}] ERROR: ${(e as Error).message ?? String(e)}`);
          }
        }
      }
      HILog(`scanVideos: photoAccessHelper ${list.length} video(s)`);
    } catch (e) {
      HILog(`scanVideos error: ${(e as Error).message ?? String(e)}`);
    }

    // 文件系统遍历:补充 photoAccessHelper 未索引的视频(用户在文件管理器自定义文件夹中的视频)。
    // photoAccessHelper 仅覆盖系统媒体库索引的目录(Movies/DCIM/Pictures 等),
    // 用户在文件管理器中新建文件夹并移入的视频不会被索引,需要通过 fs 递归扫描补充。
    // 同时,文件系统扫描得到的真实路径会按文件名回填给 photoAccessHelper 扫到的视频,
    // 使其也能正确按文件夹分组。
    const nameToVideo = new Map<string, MediaWrapper>();
    for (const v of list) {
      if (v.displayName.length > 0) {
        nameToVideo.set(v.displayName.toLowerCase(), v);
      }
    }
    const fsScannedNames = new Set<string>();
    const videoRoots: string[] = ['/storage/Users/currentUser'];
    for (const root of videoRoots) {
      try {
        fs.statSync(root);
        const found: string[] = [];
        MediaLibrary.collectVideoPaths(root, found, 0, 5);
        HILog(`fs video from ${root}: found ${found.length} file(s)`);
        for (const f of found) {
          // 提取文件名(含扩展名,小写)用于和 photoAccessHelper 的 displayName 匹配。
          const fileName = f.includes('/') ? f.slice(f.lastIndexOf('/') + 1).toLowerCase() : f.toLowerCase();
          if (fsScannedNames.has(fileName)) {
            continue; // 文件系统扫描内同名文件去重
          }
          fsScannedNames.add(fileName);
          const existing = nameToVideo.get(fileName);
          if (existing !== undefined) {
            // photoAccessHelper 已扫到此视频,回填真实路径供文件夹分组使用。
            existing.filePath = f;
            // 补充 photoAccessHelper 可能缺失的文件大小和时间戳。
            if (existing.size === 0) {
              try {
                const vstat = fs.statSync(f);
                existing.size = vstat.size;
                existing.dateAdded = vstat.ctime;
                existing.dateModified = vstat.mtime;
              } catch (e) {
                // stat 失败不影响
              }
            }
            continue;
          }
          // photoAccessHelper 未扫到的新视频(自定义文件夹中的视频),创建新条目。
          const fileUri = f.startsWith('file://') ? f : `file://${f}`;
          const title = MediaLibrary.fileNameTitle(f);
          const mw = new MediaWrapper(list.length, title, fileUri, 0);
          mw.displayName = title;
          mw.filePath = f; // 真实文件系统路径,供按文件夹分组使用
          // 文件大小和时间戳(fs.statSync 快速,不需打开文件)。
          try {
            const vstat = fs.statSync(f);
            mw.size = vstat.size;
            mw.dateAdded = vstat.ctime;
            mw.dateModified = vstat.mtime;
          } catch (e) {
            // stat 失败不影响添加视频
          }
          // 尝试提取时长和缩略图(慢操作,失败则保留默认值)。
          try {
            const meta = await MediaLibrary.parseFileMeta(f);
            if (meta.title.length > 0) {
              mw.title = meta.title;
              mw.displayName = meta.title;
            }
            mw.length = meta.duration;
            if (meta.artworkPath.length > 0) {
              mw.artworkUrl = meta.artworkPath;
            }
          } catch (e) {
            // 元数据提取失败,保留文件名标题和 duration=0
          }
          list.push(mw);
          if (list.length % 50 === 49) {
            await new Promise<void>((r: () => void) => setTimeout(r, 0));
          }
        }
        HILog(`fs video: total after merge: ${list.length}`);
      } catch (e) {
        HILog(`fs video root ${root} not accessible: ${(e as Error).message ?? String(e)}`);
      }
    }
    */
    MediaLibrary.videos = [];
  }

  /** 扫描音频:先恢复持久化数据(保留元数据),再扫描新文件并合并。 */
  private static async scanAudios(): Promise<void> {
    /*
    // 0️⃣ 先恢复用户之前导入的音频(持久化数据,含正确元数据)。
    await MediaLibrary.loadAudioLibrary();
    const existingUriSet = new Set(MediaLibrary.audios.map((t: Track) => t.uri));

    // 1️⃣ 收集新 URI(仅限尚未在 audios 中的)。
    const newUriSet = new Set<string>();

    // photoAccessHelper。
    try {
      const ctx = AppContext.get();
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const predicates = new dataSharePredicates.DataSharePredicates();
      let assets: photoAccessHelper.PhotoAsset[] = [];
      try {
        const opts: photoAccessHelper.FetchOptions = {
          fetchColumns: ['title', 'media_type'],
          predicates: predicates,
        };
        const result = await helper.getAssets(opts);
        assets = await result.getAllObjects();
      } catch (e1) {
        const opts2: photoAccessHelper.FetchOptions = {
          fetchColumns: [],
          predicates: new dataSharePredicates.DataSharePredicates(),
        };
        const result2 = await helper.getAssets(opts2);
        assets = await result2.getAllObjects();
      }
      for (let i = 0; i < assets.length; i++) {
        try {
          const uri: string = assets[i].uri;
          if (uri.length === 0 || existingUriSet.has(uri)) {
            continue;
          }
          const fileType = Number(assets[i].get('media_type') ?? 0);
          if (fileType === 1) {
            continue;
          }
          const title = (assets[i].get('title') as string) || assets[i].displayName || '';
          const ext = title.includes('.') ? title.slice(title.lastIndexOf('.') + 1).toLowerCase() : '';
          if (AUDIO_EXTS.includes(ext)) {
            newUriSet.add(uri);
          }
        } catch (e) {
          // skip bad asset
        }
      }
      HILog(`audio new from photoAccessHelper: ${newUriSet.size}`);
    } catch (e) {
      HILog(`photoAccessHelper audio scan error: ${(e as Error).message ?? String(e)}`);
    }

    // 文件系统遍历。
    const userRoots: string[] = ['/storage/Users/currentUser'];
    for (const root of userRoots) {
      try {
        fs.statSync(root);
        const found: string[] = [];
        MediaLibrary.collectAudioPaths(root, found, 0, 5);
        for (const f of found) {
          if (!existingUriSet.has(f)) {
            newUriSet.add(f);
          }
        }
        HILog(`fs audio from ${root}: ${found.length} (new: ${newUriSet.size})`);
      } catch (e) {
        HILog(`fs root ${root} not accessible: ${(e as Error).message ?? String(e)}`);
      }
    }

    // 2️⃣ 仅解析新的 URI(持久化的数据保留原样,不会被乱码覆盖)。
    if (newUriSet.size > 0) {
      const newUris = Array.from(newUriSet);
      const startIndex = MediaLibrary.audios.length;
      for (let i = 0; i < newUris.length; i++) {
        const rawPath = newUris[i];
        const meta = await MediaLibrary.parseFileMeta(rawPath);
        const t = new Track(startIndex + i, meta.title, rawPath.startsWith('file://') ? rawPath : `file://${rawPath}`);
        t.displayName = meta.title;
        t.filePath = rawPath;
        t.length = meta.duration;
        t.artistName = meta.artist;
        t.albumName = meta.album;
        t.genre = meta.genre;
        t.trackNumber = parseInt(meta.trackNumber) || 0;
        t.year = meta.year;
        t.artworkPath = meta.artworkPath;
        MediaLibrary.audios.push(t);
        if (i % 50 === 49) {
          await new Promise<void>((r: () => void) => setTimeout(r, 0));
        }
      }
      HILog(`added ${newUris.length} new tracks from scan, total: ${MediaLibrary.audios.length}`);
    }

    */
    await MediaLibrary.loadAudioLibrary();
  }

  /** 递归收集目录中的音频文件路径(不解析元数据,仅发现)。 */
  private static collectAudioPaths(dir: string, out: string[], depth: number = 0, maxDepth: number = 5): void {
    if (depth > maxDepth) {
      return;
    }
    let names: string[];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      // 跳过隐藏文件/目录(.开头),避免扫描 .hvigor .git 等无关内容。
      if (name.startsWith('.')) {
        continue;
      }
      const full = `${dir}/${name}`;
      let stat: fs.Stat;
      try {
        stat = fs.statSync(full);
      } catch (e) {
        continue;
      }
      let directory: boolean = false;
      try {
        directory = stat.isDirectory();
      } catch (error) {
        continue;
      }
      if (directory) {
        try {
          MediaLibrary.collectAudioPaths(full, out, depth + 1, maxDepth);
        } catch (error) {
          // Skip directories that become unavailable while scanning.
        }
      } else {
        const ext = name.includes('.') ? name.slice(name.lastIndexOf('.') + 1).toLowerCase() : '';
        if (AUDIO_EXTS.includes(ext)) {
          out.push(full);
        }
      }
    }
  }

  /** 递归收集目录中的视频文件路径(不解析元数据,仅发现)。 */
  private static collectVideoPaths(dir: string, out: string[], depth: number = 0, maxDepth: number = 5): void {
    if (depth > maxDepth) {
      return;
    }
    let names: string[];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      if (name.startsWith('.')) {
        continue;
      }
      const full = `${dir}/${name}`;
      let stat: fs.Stat;
      try {
        stat = fs.statSync(full);
      } catch (e) {
        continue;
      }
      let directory: boolean = false;
      try {
        directory = stat.isDirectory();
      } catch (error) {
        continue;
      }
      if (directory) {
        try {
          MediaLibrary.collectVideoPaths(full, out, depth + 1, maxDepth);
        } catch (error) {
          // Skip directories that become unavailable while scanning.
        }
      } else {
        const ext = name.includes('.') ? name.slice(name.lastIndexOf('.') + 1).toLowerCase() : '';
        if (VIDEO_EXTS.includes(ext)) {
          out.push(full);
        }
      }
    }
  }

  /** 单文件元数据解析:系统 AVMetadataExtractor → libVLC NAPI → 文件名兜底。 */
  private static async parseFileMeta(rawPath: string): Promise<AudioMeta> {
    const titleFromName = MediaLibrary.fileNameTitle(rawPath);

    // 1️⃣ 系统 AVMetadataExtractor(先用原始 URI 试,再用去 file:// 的路径试)。
    let sysMeta = await MediaLibrary.extractMetaWithSystem(rawPath);
    if (sysMeta === null) {
      const fsPath = MediaLibrary.normalizePath(rawPath);
      if (fsPath !== rawPath) {
        sysMeta = await MediaLibrary.extractMetaWithSystem(fsPath);
      }
    }
    if (sysMeta !== null) {
      if (sysMeta.title.length === 0) {
        sysMeta.title = titleFromName;
      }
      HILog(`system ok: ${rawPath} → ${sysMeta.artist} / ${sysMeta.album} / ${sysMeta.genre}`);
      return sysMeta;
    }

    // 2️⃣ 文件名兜底(系统提取器失败时)。
    HILog(`system extractor failed for ${rawPath}, using filename fallback`);
    return MediaLibrary.fallbackMeta(rawPath);
  }

  /** 去除 file:// 前缀,用于 fs API。 */
  private static normalizePath(raw: string): string {
    if (raw.startsWith('file://')) {
      return raw.slice(7); // 'file://' → '/...'
    }
    return raw;
  }

  // ---- 视频收藏(按 uri) ----

  /** 通过系统 AVMetadataExtractor 提取元数据,每次新建实例(避免复用缓存上一文件的元数据)。 */
  private static async extractMetaWithSystem(filePath: string): Promise<AudioMeta | null> {
    let extractor: media.AVMetadataExtractor | null = null;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      HILog(`[sysExtractor] file opened: ${filePath}`);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = file;
      HILog(`[sysExtractor] extractor created, calling fetchMetadata...`);
      const meta: media.AVMetadata = await extractor.fetchMetadata();
      HILog(`[sysExtractor] fetchMetadata done: title="${meta.title}" artist="${meta.artist}" album="${meta.album}"`);
      // ★ 不要在这里 close file,album cover 提取还需要 fd。
      const result: AudioMeta = {
        title: meta.title ?? '',
        artist: meta.artist ?? '',
        album: meta.album ?? '',
        genre: meta.genre ?? '',
        trackNumber: meta.tracks != null ? String(meta.tracks) : '',
        year: '',
        artworkUrl: '',
        albumArtist: '',
        duration: Number(meta.duration ?? 0),
        artworkPath: '',
        videoWidth: Number(meta.videoWidth ?? 0),
        videoHeight: Number(meta.videoHeight ?? 0),
      };
      // 提取专辑封面并缓存到本地(修复:file 保持打开)。
      try {
        HILog(`[art] fetching album cover for ${filePath}...`);
        const pixelMap = await extractor.fetchAlbumCover();
        HILog(`[art] pixelMap obtained: ${pixelMap !== null && pixelMap !== undefined ? 'yes' : 'null'}`);
        if (pixelMap !== null && pixelMap !== undefined) {
          const cacheName = `album_${MediaLibrary.hashCode(filePath)}.jpg`;
          const cacheDir = AppContext.get().cacheDir;
          const cachePath = `${cacheDir}/${cacheName}`;
          HILog(`[art] saving to ${cachePath}`);
          const packer = image.createImagePacker();
          const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 80 };
          const buffer = await packer.packToData(pixelMap, packOpts);
          HILog(`[art] packed ${buffer.byteLength} bytes`);
          const outFile = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
          fs.writeSync(outFile.fd, buffer);
          fs.closeSync(outFile);
          packer.release();
          pixelMap.release();
          result.artworkPath = `file://${cachePath}`;
          HILog(`[art] DONE: ${result.artworkPath}`);
        } else {
          HILog(`[art] pixelMap is null — no cover in this file`);
        }
      } catch (e) {
        HILog(`[art] FAILED: ${(e as Error).message ?? String(e)}`);
      }
      // ★ 在 album cover 提取完成后才关闭文件。
      fs.closeSync(file);
      file = null;
      HILog(
        `sysExtractor ok: artist="${result.artist}" album="${result.album}" genre="${result.genre}" art="${result.artworkPath}"`);
      return result;
    } catch (e) {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e2) { /* ignore */
        }
      }
      HILog(`extractMetaWithSystem failed: ${(e as Error).message ?? String(e)}`);
      return null;
    } finally {
      if (extractor !== null) {
        // ★ release() 返回 Promise<void>,必须 await 确保释放完成,否则下一个 extractor 可能复用内部缓存。
        try {
          await extractor.release();
        } catch (e3) { /* ignore */
        }
      }
    }
  }

  /** 由文件路径推导显示名(去扩展名)。 */
  private static fileNameTitle(filePath: string): string {
    const lastSlash = Math.max(filePath.lastIndexOf('/'), filePath.lastIndexOf('\\'));
    const name = lastSlash >= 0 ? filePath.slice(lastSlash + 1) : filePath;
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.slice(0, dot) : name;
  }

  /** 简单哈希(用于缓存文件名)。 */
  private static hashCode(s: string): number {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h) + s.charCodeAt(i);
      h |= 0; // to 32bit int
    }
    return Math.abs(h);
  }

  /** 无 libVLC / 解析失败时的兜底数据:仅文件名,无艺术家/专辑/流派。 */
  private static fallbackMeta(filePath: string): AudioMeta {
    return {
      title: MediaLibrary.fileNameTitle(filePath),
      artist: '',
      album: '',
      genre: '',
      trackNumber: '',
      year: '',
      artworkUrl: '',
      albumArtist: '',
      duration: 0,
      artworkPath: '',
      videoWidth: 0,
      videoHeight: 0,
    } as AudioMeta;
  }

  /** 由曲目元数据派生 艺术家 / 专辑 / 流派(基于真实 ID3/Vorbis 标签)。 */
  private static deriveFromMeta(): void {
    const artistMap = new Map<string, Artist>();
    const albumMap = new Map<string, Album>();
    const genreMap = new Map<string, Genre>();
    let aid = 0;
    let bid = 0;
    let gid = 0;

    for (const t of MediaLibrary.audios) {
      // 艺术家(未知统一归入 "未知艺术家")。
      const artistKey = t.artistName.length > 0 ? t.artistName : '未知艺术家';
      if (!artistMap.has(artistKey)) {
        const a = new Artist(aid++, artistKey);
        artistMap.set(artistKey, a);
      }
      artistMap.get(artistKey)!.trackCount += 1;

      // 专辑(联合键:albumName + artistName,避免同名专辑冲突)。
      const albumName = t.albumName.length > 0 ? t.albumName : '未知专辑';
      const albumKey = `${albumName}|${t.artistName}`;
      if (!albumMap.has(albumKey)) {
        const al = new Album(bid++, albumName, artistKey);
        albumMap.set(albumKey, al);
      }
      albumMap.get(albumKey)!.trackCount += 1;

      // 流派(逗号/分号/斜杠分隔的多流派取首个,归并空白)。
      const rawGenre = t.genre.length > 0 ? t.genre.split(/[,;/]/)[0].trim() : '';
      const genreKey = rawGenre.length > 0 ? rawGenre : '未知流派';
      if (!genreMap.has(genreKey)) {
        const g = new Genre(gid++, genreKey);
        genreMap.set(genreKey, g);
      }
      // Genre 模型目前没有 trackCount 字段;如有需要后续可加。
    }

    MediaLibrary.artists = Array.from(artistMap.values());
    MediaLibrary.albums = Array.from(albumMap.values());
    MediaLibrary.genres = Array.from(genreMap.values());
  }

  // ---- 文件夹收藏(按 folder path) ----

  private static async saveVideoLibrary(): Promise<void> {
    try {
      const items: PersistedVideo[] = MediaLibrary.videos.map((video: MediaWrapper) => ({
        uri: video.uri,
        title: video.title,
        displayName: video.displayName,
        filePath: video.filePath,
        length: video.length,
        width: video.width,
        height: video.height,
        size: video.size,
        artworkUrl: video.artworkUrl,
        dateAdded: video.dateAdded,
        dateModified: video.dateModified,
      } as PersistedVideo));
      await Settings.put(KEY_VIDEO_LIBRARY, JSON.stringify(items));
    } catch (e) {
      HILog(`saveVideoLibrary error: ${(e as Error).message ?? String(e)}`);
    }
  }

  private static async loadVideoLibrary(): Promise<void> {
    try {
      const raw = await Settings.getString(KEY_VIDEO_LIBRARY, '[]');
      const items = JSON.parse(raw) as PersistedVideo[];
      if (!Array.isArray(items)) {
        return;
      }
      const existing = new Set(MediaLibrary.videos.map((video: MediaWrapper) => video.uri));
      for (const item of items) {
        if (item.uri.length === 0 || existing.has(item.uri) || !(await DocumentPermission.activate(item.uri))) {
          continue;
        }
        const video = new MediaWrapper(MediaLibrary.videos.length, item.title, item.uri, 0);
        video.displayName = item.displayName;
        video.filePath = item.filePath;
        video.length = item.length;
        video.width = item.width;
        video.height = item.height;
        video.size = item.size;
        video.resolution = item.width > 0 && item.height > 0 ? `${item.width}x${item.height}` : '';
        video.artworkUrl = item.artworkUrl;
        video.dateAdded = item.dateAdded;
        video.dateModified = item.dateModified;
        MediaLibrary.videos.push(video);
        existing.add(item.uri);
      }
    } catch (e) {
      HILog(`loadVideoLibrary error: ${(e as Error).message ?? String(e)}`);
    }
  }

  /** 将当前音频列表序列化为 JSON 并持久化到 preferences。 */
  private static async saveAudioLibrary(): Promise<void> {
    try {
      const arr: PersistedTrack[] = MediaLibrary.audios.map((t: Track) => {
        const item: PersistedTrack = {
          uri: t.uri,
          title: t.title,
          artistName: t.artistName,
          albumName: t.albumName,
          genre: t.genre,
          trackNumber: t.trackNumber,
          year: t.year,
          length: t.length,
          artworkPath: t.artworkPath,
        };
        return item;
      });
      await Settings.put(KEY_AUDIO_LIBRARY, JSON.stringify(arr));
      HILog(`saved ${arr.length} tracks to preferences`);
    } catch (e) {
      HILog(`saveAudioLibrary error: ${(e as Error).message ?? String(e)}`);
    }
  }

  /** 从 preferences 恢复持久化的音频列表,解析元数据并合并到 audios(去重)。 */
  private static async loadAudioLibrary(): Promise<void> {
    try {
      const raw = await Settings.getString(KEY_AUDIO_LIBRARY, '');
      if (raw.length === 0) {
        return;
      }
      const arr: PersistedTrack[] = JSON.parse(raw) as PersistedTrack[];
      if (!Array.isArray(arr) || arr.length === 0) {
        return;
      }
      const existing = new Set(MediaLibrary.audios.map((t: Track) => t.uri));
      let added = 0;
      for (const item of arr) {
        if (item.uri.length === 0 || existing.has(item.uri) || !(await DocumentPermission.activate(item.uri))) {
          continue;
        }
        const t = new Track(MediaLibrary.audios.length, item.title, item.uri);
        t.artistName = item.artistName;
        t.albumName = item.albumName;
        t.genre = item.genre;
        t.trackNumber = item.trackNumber;
        t.year = item.year;
        t.length = item.length;
        t.artworkPath = item.artworkPath ?? '';
        t.displayName = item.title;
        t.filePath = item.uri;
        MediaLibrary.audios.push(t);
        added++;
      }
      if (added > 0) {
        MediaLibrary.deriveFromMeta();
        HILog(`loaded ${added} persisted tracks`);
      }
    } catch (e) {
      HILog(`loadAudioLibrary error: ${(e as Error).message ?? String(e)}`);
    }
  }

  private static async saveStorageItemsToPrefs(): Promise<void> {
    const arr: FavItem[] = MediaLibrary.storageItems.map(item => ({
      title: item.title,
      subtitle: item.subtitle,
      iconType: item.uri.toLowerCase().match(/\.(mp3|flac|ogg|wav|aac|m4a|wma|opus)$/i) ? 'audio' : 'video',
      uri: item.uri,
      artworkPath: item.artworkPath,
    } as FavItem));
    await Settings.put(MediaLibrary.KEY_STORAGE_FILES, JSON.stringify(arr));
  }

  private static async loadFavRaw(): Promise<FavItem[]> {
    const raw: string = await Settings.getString(MediaLibrary.KEY_FAVORITES, '[]');
    try {
      return JSON.parse(raw) as FavItem[];
    } catch (e) {
      return [];
    }
  }

  private static async saveFavRaw(items: FavItem[]): Promise<void> {
    await Settings.put(MediaLibrary.KEY_FAVORITES, JSON.stringify(items));
  }

  // ---- 分享与删除 ----

  /** 触发播放列表变更广播（私有辅助:每次持久化后调用）。 */
  private static emitPlaylistsChanged(): void {
    try {
      emitter.emit(MediaLibrary.EVENT_PLAYLISTS_CHANGED);
    } catch (e) {
      hilog.warn(0x0001, 'VLC', `[VLC] emitPlaylistsChanged failed: ${JSON.stringify(e)}`);
    }
  }

  /** 将缓存写入 Settings,并广播变更事件。 */
  private static async savePlaylists(): Promise<void> {
    await Settings.put(MediaLibrary.KEY_PLAYLISTS, JSON.stringify(MediaLibrary.playlistCache));
    MediaLibrary.emitPlaylistsChanged();
  }
}

export interface StoredPlaylist {
  id: number;
  name: string;
  uriList: string[];
}

interface PersistedBookmark {
  id: number;
  mediaId: number;
  timeMs: number;
  name: string;
}
