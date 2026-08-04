/**
 * 媒体数据模型 —— 对应 Android org.videolan.medialibrary.MediaLibraryItem 体系。
 * ArkTS 名义类型:数据载体一律 class + 构造函数(禁结构化类型/对象字面量赋 interface)。
 */

/** 媒体类型(对应 TYPE_* 标志位)。 */
export enum MediaItemType {
  MEDIA = 0,
  FOLDER = 1,
  ALBUM = 2,
  ARTIST = 4,
  GENRE = 8,
  PLAYLIST = 16,
  VIDEO_GROUP = 64,
}

/** 视频分组类型(KeyGroupVideos)。 */
export enum VideoGroupingType {
  NONE = 'NONE',
  FOLDER = 'FOLDER',
  NAME = 'NAME',
}

/** 空态/加载态枚举(EmptyLoadingState)。 */
export enum EmptyLoadingState {
  LOADING = 0,
  EMPTY = 1,
  EMPTY_SEARCH = 2,
  EMPTY_FAVORITES = 3,
  MISSING_PERMISSION = 4,
  MISSING_VIDEO_PERMISSION = 5,
  NONE = 6,
}

/** 播放器状态(对齐 AVPlayer 状态机 + VLC PlaybackState)。 */
export enum PlayState {
  IDLE = 0,
  PREPARED = 1,
  PLAYING = 2,
  PAUSED = 3,
  STOPPED = 4,
  ERROR = 5,
}

/** 基类:带 id/title 的媒体项(对应 MediaLibraryItem 抽象基类)。 */
export class MediaLibraryItem {
  id: number;
  itemType: MediaItemType;
  title: string;
  description: string = '';
  artworkUrl: string = '';
  isFavorite: boolean = false;
  isPresent: boolean = true;
  isNetwork: boolean = false;
  isSD: boolean = false;
  isOTG: boolean = false;
  seen: number = 0;
  progress: number = 0;
  maxProgress: number = 0;
  showItemProgress: boolean = false;

  constructor(id: number, title: string, itemType: MediaItemType) {
    this.id = id;
    this.title = title;
    this.itemType = itemType;
  }
}

/** 单个媒体(视频/音频)。 */
export class MediaWrapper extends MediaLibraryItem {
  uri: string;
  length: number = 0; // ms
  width: number = 0;
  height: number = 0;
  type: number = 0; // 0=video 1=audio
  filePath: string = '';
  displayName: string = '';
  size: number = 0;
  resolution: string = '';
  artistName: string = '';
  albumName: string = '';
  artworkPath: string = '';
  dateAdded: number = 0;
  dateModified: number = 0;

  constructor(id: number, title: string, uri: string, type: number) {
    super(id, title, MediaItemType.MEDIA);
    this.uri = uri;
    this.type = type;
    this.itemType = MediaItemType.MEDIA;
  }

  isVideo(): boolean {
    return this.type === 0;
  }
}

/** 文件夹(按目录分组)。 */
export class Folder extends MediaLibraryItem {
  path: string;
  mediaCount: number = 0;

  constructor(id: number, title: string, path: string) {
    super(id, title, MediaItemType.FOLDER);
    this.path = path;
    this.itemType = MediaItemType.FOLDER;
  }
}

/** 视频分组(按名称)。 */
export class VideoGroup extends MediaLibraryItem {
  mediaCount: number = 0;

  constructor(id: number, title: string) {
    super(id, title, MediaItemType.VIDEO_GROUP);
    this.itemType = MediaItemType.VIDEO_GROUP;
  }
}

/** 艺术家。 */
export class Artist extends MediaLibraryItem {
  trackCount: number = 0;
  albumCount: number = 0;

  constructor(id: number, title: string) {
    super(id, title, MediaItemType.ARTIST);
    this.itemType = MediaItemType.ARTIST;
  }
}

/** 专辑。 */
export class Album extends MediaLibraryItem {
  artistName: string = '';
  releaseYear: string = '';
  trackCount: number = 0;

  constructor(id: number, title: string, artistName: string) {
    super(id, title, MediaItemType.ALBUM);
    this.artistName = artistName;
    this.itemType = MediaItemType.ALBUM;
  }
}

/** 曲目(音频)。 */
export class Track extends MediaLibraryItem {
  uri: string;
  length: number = 0;
  artistName: string = '';
  albumName: string = '';
  genre: string = '';
  trackNumber: number = 0;
  year: string = '';
  displayName: string = '';
  filePath: string = '';
  artworkPath: string = '';

  constructor(id: number, title: string, uri: string) {
    super(id, title, MediaItemType.MEDIA);
    this.uri = uri;
    this.itemType = MediaItemType.MEDIA;
  }
}

/** 流派。 */
export class Genre extends MediaLibraryItem {
  constructor(id: number, title: string) {
    super(id, title, MediaItemType.GENRE);
    this.itemType = MediaItemType.GENRE;
  }
}

/** 播放列表。 */
export class Playlist extends MediaLibraryItem {
  trackCount: number = 0;

  constructor(id: number, title: string) {
    super(id, title, MediaItemType.PLAYLIST);
    this.itemType = MediaItemType.PLAYLIST;
  }
}

/** Secondary 宿主页(KEY_FRAGMENT)导航参数。 */
export interface SecondaryParam {
  fragment: string;
  title?: string;
}

/** PreferencesPage(screenKey 入参)导航参数。 */
export interface PreferencesScreenParam {
  screenKey: string;
}

/** FileBrowserPage(mode 入参)导航参数。 */
export interface FileBrowserParam {
  mode: string;
}

/** VideoPlayerPage(uri/title 入参)导航参数。 */
export interface VideoNavParam {
  uri: string;
  title: string;
  /** 历史/更多入口带回的真实视频缩略图，播放器写入历史时继续复用。 */
  artworkUrl?: string;
}

/** 存储设备(Browse tab 的本地存储卡片)。 */
export class StorageItem {
  name: string;
  path: string;
  isFavorite: boolean = false;

  constructor(name: string, path: string) {
    this.name = name;
    this.path = path;
  }
}

/** 网络共享(Browse tab 的局域网卡片)。 */
export class NetworkShare {
  name: string;
  uri: string;

  constructor(name: string, uri: string) {
    this.name = name;
    this.uri = uri;
  }
}

/** 历史记录项(More → History)。 */
export class HistoryItem extends MediaLibraryItem {
  uri: string;
  lastPlayed: number = 0;

  constructor(id: number, title: string, uri: string) {
    super(id, title, MediaItemType.MEDIA);
    this.uri = uri;
    this.itemType = MediaItemType.MEDIA;
  }
}

/** 媒体轨道信息(Info 页轨道 List 行)。 */
export class MediaInfoItem {
  title: string;
  subtitle: string;

  constructor(title: string, subtitle: string) {
    this.title = title;
    this.subtitle = subtitle;
  }
}

/** 均衡器预设。 */
export class EqualizerPreset {
  id: number;
  name: string;
  bands: number[]; // 各频段增益 dB

  constructor(id: number, name: string, bands: number[]) {
    this.id = id;
    this.name = name;
    this.bands = bands;
  }
}

/** BottomSheet 弹窗载体。 */
export class SheetItem {
  title: string;
  subtitle: string;
  icon: Resource | null;
  uri: string;
  artworkPath: string;

  constructor(title: string, subtitle: string = '', icon: Resource | null = null, uri: string = '', artworkPath: string = '') {
    this.title = title;
    this.subtitle = subtitle;
    this.icon = icon;
    this.uri = uri;
    this.artworkPath = artworkPath;
  }
}

/** Tab 子项(Audio browser 4 子 Tab / Video browser 2 子 Tab)。 */
export class SubTab {
  title: Resource;
  key: string;

  constructor(title: Resource, key: string) {
    this.title = title;
    this.key = key;
  }
}

/** 毫秒 → mm:ss / h:mm:ss 时长串(对齐 VLC.Tools.millisToString)。 */
export function formatDuration(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  if (h > 0) {
    return `${h}:${mm}:${ss}`;
  }
  return `${m}:${ss}`;
}

/** 字节数 → 人类可读文件大小。 */
export function formatSize(bytes: number): string {
  if (bytes <= 0) {
    return '';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${i <= 1 ? Math.round(v) : v.toFixed(2)} ${units[i]}`;
}
