import { util } from '@kit.ArkTS';
import { AppContext } from './AppContext';

/** libraries.json -> libraries[] 单条(对应原生 LibraryWithLicense 的库部分)。 */
export class LibEntry {
  title: string;
  copyright: string;
  /** license id(用于 join licenses[].id),如 'apache2.0'/'gpl2'。 */
  license: string;

  constructor(title: string, copyright: string, license: string) {
    this.title = title;
    this.copyright = copyright;
    this.license = license;
  }
}

/** libraries.json -> licenses[] 单条(许可全文描述)。 */
export class LicenseInfo {
  /** 许可 id,如 'apache2.0'。 */
  id: string;
  /** 许可证正文(name + description 合并展示文案)。 */
  description: string;
  /** 许可名称(如 'Apache 2.0 license'),用于标题展示。 */
  name: string;
  /** 许可官网链接(可能为空)。 */
  link: string;

  constructor(id: string, description: string, name: string, link: string) {
    this.id = id;
    this.description = description;
    this.name = name;
    this.link = link;
  }
}

/**
 * RawData —— 从 rawfile 读取真实数据(authors.json / libraries.json / vlc_license.txt)。
 * 读取流程:getRawFileContent(name) → TextDecoder('utf-8').decode → JSON.parse as Record<string,Object> → 防御式取字段。
 */
export class RawData {
  /** 防御式字符串取值:非 string 一律回退默认值。 */
  private static str(v: Object, fallback: string = ''): string {
    return typeof v === 'string' ? v : fallback;
  }

  /** 读 rawfile 文本文件返回字符串(vlc_license.txt 等)。 */
  private static async readText(name: string): Promise<string> {
    const ua: Uint8Array = await AppContext.get().resourceManager.getRawFileContent(name);
    return new util.TextDecoder('utf-8').decode(ua);
  }

  /** 读 rawfile JSON 并解析为通用对象树。 */
  private static async readJson(name: string): Promise<Record<string, Object>> {
    const text: string = await RawData.readText(name);
    return JSON.parse(text) as Record<string, Object>;
  }

  /** authors.json:30 项 String 数组 → string[]。 */
  static async loadAuthors(): Promise<string[]> {
    try {
      const text: string = await RawData.readText('authors.json');
      const arr: Object = JSON.parse(text);
      if (arr instanceof Array) {
        const list: Object[] = arr as Object[];
        const names: string[] = [];
        for (let i = 0; i < list.length; i++) {
          const item: Object = list[i];
          if (typeof item === 'string') {
            names.push(item as string);
          }
        }
        return names;
      }
    } catch (e) {
      // 解析失败回退空数组,UI 显示空列表。
    }
    return [];
  }

  /** libraries.json:libraries[{title,copyright,license}] → LibEntry[]。 */
  static async loadLibraries(): Promise<LibEntry[]> {
    try {
      const root: Record<string, Object> = await RawData.readJson('libraries.json');
      const libs: Object | undefined = root['libraries'];
      if (libs instanceof Array) {
        const list: LibEntry[] = [];
        const libArr: Object[] = libs as Object[];
        for (let i = 0; i < libArr.length; i++) {
          const item: Object = libArr[i];
          if (item instanceof Object) {
            const rec: Record<string, Object> = item as Record<string, Object>;
            list.push(new LibEntry(
              RawData.str(rec['title']),
              RawData.str(rec['copyright']),
              RawData.str(rec['license']),
            ));
          }
        }
        return list;
      }
    } catch (e) {
      // 解析失败回退空列表。
    }
    return [];
  }

  /** libraries.json:licenses[{id,name,description,link}] → LicenseInfo[]。 */
  static async loadLicenses(): Promise<LicenseInfo[]> {
    try {
      const root: Record<string, Object> = await RawData.readJson('libraries.json');
      const lics: Object | undefined = root['licenses'];
      if (lics instanceof Array) {
        const list: LicenseInfo[] = [];
        const licArr: Object[] = lics as Object[];
        for (let i = 0; i < licArr.length; i++) {
          const item: Object = licArr[i];
          if (item instanceof Object) {
            const rec: Record<string, Object> = item as Record<string, Object>;
            list.push(new LicenseInfo(
              RawData.str(rec['id']),
              RawData.str(rec['description']),
              RawData.str(rec['name']),
              RawData.str(rec['link']),
            ));
          }
        }
        return list;
      }
    } catch (e) {
      // 解析失败回退空列表。
    }
    return [];
  }

  /** vlc_license.txt:GPLv2 全文 → string(用于无匹配许可 id 时的回退展示)。 */
  static async loadLicenseText(): Promise<string> {
    try {
      return await RawData.readText('vlc_license.txt');
    } catch (e) {
      return '';
    }
  }
}
