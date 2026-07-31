import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { dataSharePredicates } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { MediaWrapper, Track, Artist, Album, Genre, Folder, VideoGroup } from '../models/MediaModels';
import { QueueItem } from './PlaybackService';
import { Settings } from './Settings';

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
}

/** 持久化存储 key:用户导入的音频轨道 JSON 数组。 */
const KEY_AUDIO_LIBRARY: string = 'audio_library_persisted';

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

/**
 * MediaLibrary —— Android medialibrary.MediaLibrary 扫描的鸿蒙等价物。
 * 能力替换约定:VLC 原生 medialibrary(C/C++)→ 用 photoAccessHelper(视频)+ fs(音频)扫描真实设备媒体。
 * 【非 mock】:返回设备上真实存在的媒体;无媒体/无权限时返回空列表(UI 按规格显示空态)。
 */
const AUDIO_EXTS: string[] = ['mp3', 'aac', 'flac', 'ogg', 'wav', 'm4a', 'wma', 'opus'];

export class MediaLibrary {
  private static videos: MediaWrapper[] = [];
  private static audios: Track[] = [];
  private static artists: Artist[] = [];
  private static albums: Album[] = [];
  private static genres: Genre[] = [];
  private static folders: Folder[] = [];
  private static scanned: boolean = false;
  private static scanning: boolean = false;
  private static scanPromise: Promise<void> | null = null;

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
    MediaLibrary.scanPromise = null;
    await MediaLibrary.scan();
  }

  private static async doScan(): Promise<void> {
    MediaLibrary.scanning = true;
    try {
      HILog('scan start');
      await Promise.all([MediaLibrary.scanVideos(), MediaLibrary.scanAudios()]);
      MediaLibrary.deriveFromMeta();
      MediaLibrary.scanned = true;
      HILog(`scan done: videos=${MediaLibrary.videos.length} audios=${MediaLibrary.audios.length} artists=${MediaLibrary.artists.length} albums=${MediaLibrary.albums.length} genres=${MediaLibrary.genres.length}`);
    } catch (e) {
      HILog(`scan error: ${(e as Error).message ?? String(e)}`);
    } finally {
      MediaLibrary.scanning = false;
    }
  }

  /** 扫描视频:photoAccessHelper PhotoType.VIDEO。 */
  private static async scanVideos(): Promise<void> {
    const list: MediaWrapper[] = [];
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
        try { HILog(`probe: typeof assets[0]=${typeof assets[0]}`); } catch (e2) { HILog('probe failed'); }
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
          mw.displayName = title;
          mw.resolution = width > 0 && height > 0 ? `${width}x${height}` : '';
          // 缩略图:photoAccessHelper 的 uri 可直接交给 Image 组件渲染(有读权限即可),
          // 否则网格里每张卡都是同一张 ic_no_thumbnail_1610 占位图。
          mw.artworkUrl = uri;
          // filePath 供按目录分组(getVideoFolders)使用;media uri 无真实路径时退化为 uri。
          mw.filePath = uri;
          list.push(mw);
          videoCount++;
        } catch (e) {
          if (i < 5) {
            HILog(`asset[${i}] ERROR: ${(e as Error).message ?? String(e)}`);
          }
        }
      }
      HILog(`scanVideos: ${list.length} video(s)`);
    } catch (e) {
      HILog(`scanVideos error: ${(e as Error).message ?? String(e)}`);
    }
    MediaLibrary.videos = list;
  }

  /** 扫描音频:先恢复持久化数据(保留元数据),再扫描新文件并合并。 */
  private static async scanAudios(): Promise<void> {
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

    await MediaLibrary.saveAudioLibrary();
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
      if (stat.isDirectory()) {
        MediaLibrary.collectAudioPaths(full, out, depth + 1, maxDepth);
      } else {
        const ext = name.includes('.') ? name.slice(name.lastIndexOf('.') + 1).toLowerCase() : '';
        if (AUDIO_EXTS.includes(ext)) {
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

  /** 通过系统 AVMetadataExtractor 提取元数据,每次新建实例(避免复用缓存上一文件的元数据)。 */
  private static async extractMetaWithSystem(filePath: string): Promise<AudioMeta | null> {
    let extractor: media.AVMetadataExtractor | null = null;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = file;
      const meta: media.AVMetadata = await extractor.fetchMetadata();
      fs.closeSync(file);
      file = null;
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
      };
      // 提取专辑封面并缓存到本地。
      try {
        HILog(`[art] fetching album cover...`);
        const pixelMap = await extractor.fetchAlbumCover();
        HILog(`[art] pixelMap obtained, checking...`);
        if (pixelMap !== null && pixelMap !== undefined) {
          const cacheName = `album_${MediaLibrary.hashCode(filePath)}.jpg`;
          const cacheDir = AppContext.get().cacheDir;
          const cachePath = `${cacheDir}/${cacheName}`;
          HILog(`[art] saving to ${cachePath}`);
          const packer = image.createImagePacker();
          const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 80 };
          const buffer = await packer.packing(pixelMap, packOpts);
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
      HILog(`sysExtractor ok: artist="${result.artist}" album="${result.album}" genre="${result.genre}" art="${result.artworkPath}"`);
      return result;
    } catch (e) {
      if (file !== null) {
        try { fs.closeSync(file); } catch (e2) { /* ignore */ }
      }
      HILog(`extractMetaWithSystem failed: ${(e as Error).message ?? String(e)}`);
      return null;
    } finally {
      if (extractor !== null) {
        try { extractor.release(); } catch (e3) { /* ignore */ }
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

  /** 将用户通过 DocumentViewPicker 挑选的音频 URI 加入库中,复制到沙箱持久化,解析元数据并重新派生分类。 */
  static async importAudioUris(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    HILog(`importAudioUris: received ${uris.length} URI(s)`);
    const uniqueUris = Array.from(new Set(uris));
    const existing = new Set(MediaLibrary.audios.map((t: Track) => t.uri));
    const newUris = uniqueUris.filter((u: string) => !existing.has(u));
    HILog(`importAudioUris: after dedup: ${newUris.length} new`);
    if (newUris.length === 0) {
      return;
    }
    // 确保沙箱音频目录存在。
    const ctx = AppContext.get();
    const audioDir = `${ctx.filesDir}/audio`;
    try { fs.mkdirSync(audioDir, true); } catch (e) { /* may exist */ }

    const startIndex = MediaLibrary.audios.length;
    for (let i = 0; i < newUris.length; i++) {
      const pickerUri = newUris[i];
      HILog(`importAudioUris[${i}]: ${pickerUri}`);
      // 复制到沙箱(持久化,不受临时权限影响)。
      let permUri = pickerUri;
      try {
        const srcFile = fs.openSync(pickerUri, fs.OpenMode.READ_ONLY);
        const ext = pickerUri.includes('.') ? pickerUri.slice(pickerUri.lastIndexOf('.')) : '.mp3';
        const destName = `import_${Date.now()}_${i}${ext}`;
        const destPath = `${audioDir}/${destName}`;
        const stat = fs.statSync(pickerUri);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(srcFile.fd, buf);
        fs.closeSync(srcFile);
        const destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(destFile.fd, buf);
        fs.closeSync(destFile);
        permUri = `file://${destPath}`;
        HILog(`importAudioUris[${i}]: copied to sandbox: ${permUri}`);
      } catch (e) {
        HILog(`importAudioUris[${i}]: copy failed, keeping picker URI: ${(e as Error).message ?? String(e)}`);
      }
      const meta = await MediaLibrary.parseFileMeta(permUri);
      HILog(`importAudioUris[${i}]: meta title="${meta.title}" artist="${meta.artist}" album="${meta.album}"`);
      const t = new Track(startIndex + i, meta.title, permUri);
      t.displayName = meta.title;
      t.filePath = permUri;
      t.length = meta.duration;
      t.artistName = meta.artist;
      t.albumName = meta.album;
      t.genre = meta.genre;
      t.trackNumber = parseInt(meta.trackNumber) || 0;
      t.year = meta.year;
      t.artworkPath = meta.artworkPath;
      MediaLibrary.audios.push(t);
    }
    MediaLibrary.deriveFromMeta();
    await MediaLibrary.saveAudioLibrary();
    HILog(`importAudioUris done, total audios: ${MediaLibrary.audios.length}`);
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
        if (item.uri.length === 0 || existing.has(item.uri)) {
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

  /** 按视频所在目录分组(VideoGroupingType.FOLDER)。 */
  static getVideoFolders(): Folder[] {
    const map = new Map<string, Folder>();
    let fid = 0;
    for (const v of MediaLibrary.videos) {
      const key = v.filePath.includes('/') ? v.filePath.slice(0, v.filePath.lastIndexOf('/')) : '';
      if (!map.has(key)) {
        const f = new Folder(fid++, key === '' ? 'Videos' : key.slice(key.lastIndexOf('/') + 1), key);
        map.set(key, f);
      }
      (map.get(key) as Folder).mediaCount += 1;
    }
    return Array.from(map.values());
  }

  /** 按名称首字母分组(VideoGroupingType.NAME)。 */
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
}
