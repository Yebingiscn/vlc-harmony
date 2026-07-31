import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { Folder, MediaWrapper } from '../models/MediaModels';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

/** 打进 rawfile 的应用内媒体项。 */
export class BundledMediaEntry {
  /** 列表展示名。 */
  title: string;
  /** rawfile 相对路径(如 test_dvd.iso)。 */
  rawName: string;
  /** 副标题。 */
  subtitle: string;

  constructor(title: string, rawName: string, subtitle: string = '') {
    this.title = title;
    this.rawName = rawName;
    this.subtitle = subtitle;
  }
}

/**
 * BundledMedia —— 应用内打包媒体(rawfile)。
 * rawfile 在 HAP 内带 offset,不能直接给 libVLC 的 fd/path,需解压到 filesDir 再播。
 */
export class BundledMedia {
  private static readonly DIR_NAME: string = 'bundled';

  /** 内置媒体清单(随 rawfile 同步维护)。 */
  static readonly ENTRIES: BundledMediaEntry[] = [
    new BundledMediaEntry('test_dvd.iso', 'test_dvd.iso', 'DVD ISO'),
    new BundledMediaEntry('test_bd.iso', 'test_bd.iso', 'Blu-ray ISO'),
    new BundledMediaEntry('test_vcd.iso', 'test_vcd.iso', 'VCD ISO'),
  ];

  static listEntries(): BundledMediaEntry[] {
    return BundledMedia.ENTRIES;
  }

  /** Browse 根卡片用的文件夹视图(进入后列出 ENTRIES)。 */
  static asRootFolder(): Folder {
    const f = new Folder(0, 'VLC', 'bundled://');
    f.mediaCount = BundledMedia.ENTRIES.length;
    f.description = `${BundledMedia.ENTRIES.length} video${BundledMedia.ENTRIES.length > 1 ? 's' : ''}`;
    return f;
  }

  /** FileBrowser(bundled) 列表行。 */
  static asFolders(): Folder[] {
    return BundledMedia.ENTRIES.map((e: BundledMediaEntry, i: number) => {
      const f = new Folder(i, e.title, `bundled://${e.rawName}`);
      f.mediaCount = 1;
      f.description = e.subtitle;
      return f;
    });
  }

  /** 解压到沙箱并返回可播的 MediaWrapper(uri=file://...)。 */
  static async resolveMedia(rawName: string, title?: string): Promise<MediaWrapper | null> {
    try {
      const path = await BundledMedia.ensureExtracted(rawName);
      if (path.length === 0) {
        return null;
      }
      const display = title && title.length > 0 ? title : rawName;
      const mw = new MediaWrapper(Date.now(), display, `file://${path}`, 0);
      mw.filePath = path;
      mw.displayName = display;
      return mw;
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] BundledMedia.resolveMedia failed: %{public}s',
        (e as Error).message ?? String(e));
      return null;
    }
  }

  /** 若沙箱无文件或大小不符则从 rawfile 拷贝;返回绝对路径。 */
  static async ensureExtracted(rawName: string): Promise<string> {
    const ctx = AppContext.get();
    const dir = `${ctx.filesDir}/${BundledMedia.DIR_NAME}`;
    const dest = `${dir}/${rawName}`;

    let needCopy = true;
    try {
      const st = fs.statSync(dest);
      if (st.isFile() && st.size > 0) {
        needCopy = false;
      }
    } catch (_e) {
      needCopy = true;
    }

    if (!needCopy) {
      return dest;
    }

    try {
      fs.mkdirSync(dir, true);
    } catch (_e) {
      // 已存在则忽略
    }

    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] BundledMedia extract raw=%{public}s → %{public}s',
      rawName, dest);
    const content: Uint8Array = await ctx.resourceManager.getRawFileContent(rawName);
    // slice 保证写出整段 rawfile(避免 SharedArrayBuffer 视图偏移问题)
    const bytes: ArrayBuffer = content.buffer.slice(content.byteOffset,
      content.byteOffset + content.byteLength);
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes);
    } finally {
      fs.closeSync(file);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] BundledMedia extract done size=%{public}d',
      content.byteLength);
    return dest;
  }

  /** 从 bundled://name 取 rawName;非 bundled URI 返回空串。 */
  static rawNameFromUri(uri: string): string {
    const prefix = 'bundled://';
    if (uri.startsWith(prefix)) {
      return uri.substring(prefix.length);
    }
    return '';
  }
}
