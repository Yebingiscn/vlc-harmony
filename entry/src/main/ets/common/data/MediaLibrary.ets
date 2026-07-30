import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { dataSharePredicates } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { MediaWrapper, Track, Artist, Album, Folder, VideoGroup } from '../models/MediaModels';

/** 统一日志:tag=VLC,消息带 [VLC] 前缀,便于 `grep VLC run.log` 过滤出应用日志。 */
const HILog = (msg: string): void => hilog.info(0x0001, 'VLC', '[VLC] %{public}s', msg);

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

  private static async doScan(): Promise<void> {
    MediaLibrary.scanning = true;
    try {
      HILog('scan start');
      await Promise.all([MediaLibrary.scanVideos(), MediaLibrary.scanAudios()]);
      MediaLibrary.deriveArtistsAlbums();
      MediaLibrary.scanned = true;
      HILog(`scan done: videos=${MediaLibrary.videos.length} audios=${MediaLibrary.audios.length}`);
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
          fetchColumns: ['title', 'duration', 'width', 'height', 'size', 'media_type'],
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
          mw.displayName = title;
          mw.resolution = width > 0 && height > 0 ? `${width}x${height}` : '';
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

  /** 扫描音频:遍历常见媒体目录的音频文件(fs)。 */
  private static async scanAudios(): Promise<void> {
    const list: Track[] = [];
    const roots: string[] = [
      '/storage/Users/currentUser/Music',
      '/storage/Users/currentUser/Download',
      '/storage/Users/currentUser/Documents',
    ];
    for (const root of roots) {
      try {
        MediaLibrary.walkAudio(root, list);
      } catch (e) {
        // 目录不可访问 → 跳过
      }
    }
    MediaLibrary.audios = list;
  }

  private static walkAudio(dir: string, out: Track[]): void {
    let names: string[];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      const full = `${dir}/${name}`;
      let stat: fs.Stat;
      try {
        stat = fs.statSync(full);
      } catch (e) {
        continue;
      }
      if (stat.isDirectory()) {
        MediaLibrary.walkAudio(full, out);
      } else {
        const ext = name.includes('.') ? name.slice(name.lastIndexOf('.') + 1).toLowerCase() : '';
        if (AUDIO_EXTS.includes(ext)) {
          const title = name.slice(0, name.lastIndexOf('.'));
          const t = new Track(out.length, title, `file://${full}`);
          t.displayName = title;
          t.filePath = full;
          out.push(t);
        }
      }
    }
  }

  /** 由曲目派生 艺术家/专辑(从文件名/目录名近似,无元数据解析库时的保真近似)。 */
  private static deriveArtistsAlbums(): void {
    const artists = new Map<string, Artist>();
    const albums = new Map<string, Album>();
    let aid = 0;
    let bid = 0;
    for (const t of MediaLibrary.audios) {
      const dir = t.filePath.includes('/') ? t.filePath.slice(0, t.filePath.lastIndexOf('/')) : '';
      const artistName = dir.includes('/') ? dir.slice(dir.lastIndexOf('/') + 1) : 'Unknown Artist';
      const albumName = dir.includes('/') ? dir.slice(dir.lastIndexOf('/') + 1) : 'Unknown Album';
      if (!artists.has(artistName)) {
        const a = new Artist(aid++, artistName);
        artists.set(artistName, a);
      }
      (artists.get(artistName) as Artist).trackCount += 1;
      if (!albums.has(albumName)) {
        const al = new Album(bid++, albumName, artistName);
        albums.set(albumName, al);
      }
      (albums.get(albumName) as Album).trackCount += 1;
    }
    MediaLibrary.artists = Array.from(artists.values());
    MediaLibrary.albums = Array.from(albums.values());
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
