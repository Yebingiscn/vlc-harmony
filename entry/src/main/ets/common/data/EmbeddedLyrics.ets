import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class LyricLine {
  time: number;
  text: string;

  constructor(time: number, text: string) {
    this.time = time;
    this.text = text;
  }
}

export class LyricsDocument {
  lines: LyricLine[] = [];
  timed: boolean = false;
}

/** 独立文件描述符，只异步读取标签区域，不复制音频或读取完整媒体文件。 */
class TagReader {
  private budget: number = 8 * 1024 * 1024;
  readonly fd: number;
  readonly size: number;

  constructor(fd: number, size: number) {
    this.fd = fd;
    this.size = size;
  }

  async read(position: number, length: number): Promise<Uint8Array> {
    if (position < 0 || length < 0 || position + length > this.size || length > this.budget) {
      throw new Error('Invalid or oversized lyrics tag');
    }
    this.budget -= length;
    const buffer: ArrayBuffer = new ArrayBuffer(length);
    let completed: number = 0;
    while (completed < length) {
      // 显式定位，避免相对 offset 和 fd 文件指针的差异；此 fd 不与播放器共享。
      fs.lseek(this.fd, position + completed, fs.WhenceType.SEEK_SET);
      const remaining: ArrayBuffer = new ArrayBuffer(length - completed);
      const count: number = await fs.read(this.fd, remaining);
      if (count <= 0) {
        throw new Error('Truncated lyrics tag');
      }
      new Uint8Array(buffer).set(new Uint8Array(remaining, 0, count), completed);
      completed += count;
    }
    return new Uint8Array(buffer);
  }
}

/** MP3/ID3、FLAC/Vorbis、Ogg/Opus 和 M4A 的内嵌歌词。 */
export class EmbeddedLyrics {
  private static readonly MAX_TEXT: number = 1024 * 1024;

  static async load(uri: string): Promise<LyricsDocument> {
    let file: fs.File | null = null;
    try {
      if (!uri.length || /^(https?|rtsp|mms):/i.test(uri)) {
        return new LyricsDocument();
      }
      // picker URI 保留 host；只有沙箱 file:/// 路径才去掉协议前缀。
      file = await fs.open(uri.startsWith('file:///') ? uri.slice(7) : uri, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(file.fd);
      const reader: TagReader = new TagReader(file.fd, stat.size);
      const header: Uint8Array = await reader.read(0, Math.min(12, stat.size));
      if (EmbeddedLyrics.ascii(header, 0, 3) === 'ID3') {
        const size: number = EmbeddedLyrics.syncsafe(header, 6);
        return EmbeddedLyrics.id3(await reader.read(0, size + 10));
      }
      if (EmbeddedLyrics.ascii(header, 0, 4) === 'fLaC') {
        let position: number = 4;
        for (let i: number = 0; i < 256 && position + 4 <= stat.size; i++) {
          const block: Uint8Array = await reader.read(position, 4);
          const size: number = block[1] * 65536 + block[2] * 256 + block[3];
          if ((block[0] & 0x7f) === 4) {
            return EmbeddedLyrics.comments(await reader.read(position + 4, size));
          }
          position += size + 4;
          if ((block[0] & 0x80) !== 0) {
            break;
          }
        }
      } else if (EmbeddedLyrics.ascii(header, 0, 4) === 'OggS') {
        return await EmbeddedLyrics.ogg(reader);
      } else if (EmbeddedLyrics.ascii(header, 4, 4) === 'ftyp') {
        return await EmbeddedLyrics.mp4(reader, 0, stat.size, 0);
      } else if (EmbeddedLyrics.ascii(header, 0, 4) === 'RIFF') {
        let position: number = 12;
        for (let i: number = 0; i < 512 && position + 8 <= stat.size; i++) {
          const chunk: Uint8Array = await reader.read(position, 8);
          const size: number = EmbeddedLyrics.uint32(chunk, 4, true);
          if (EmbeddedLyrics.ascii(chunk, 0, 4).toLowerCase() === 'id3 ') {
            return EmbeddedLyrics.id3(await reader.read(position + 8, size));
          }
          position += 8 + size + (size % 2);
        }
      }
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[Lyrics] embedded tag read failed: %{public}s', (e as Error).message);
    } finally {
      if (file !== null) {
        try { await fs.close(file); } catch (_e) {}
      }
    }
    return new LyricsDocument();
  }

  static parse(text: string): LyricsDocument {
    const document: LyricsDocument = new LyricsDocument();
    const raw: string[] = text.slice(0, EmbeddedLyrics.MAX_TEXT).replace(/\u0000/g, '').split(/\r\n|\n|\r/);
    let offset: number = 0;
    const plain: LyricLine[] = [];
    for (const line of raw.slice(0, 5000)) {
      const offsetMatch: RegExpMatchArray | null = line.match(/\[offset:([+-]?\d+)\]/i);
      if (offsetMatch !== null) {
        offset = Number(offsetMatch[1]);
      }
      const timestamps: RegExpMatchArray | null = line.match(/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/g);
      const content: string = line.replace(/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/g, '')
        .replace(/<\d{1,3}:\d{2}(?:\.\d{1,3})?>/g, '').trim();
      if (timestamps !== null) {
        for (const stamp of timestamps) {
          if (document.lines.length >= 5000) { break; }
          const parts: RegExpMatchArray | null = stamp.match(/\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]/);
          if (parts !== null && Number(parts[2]) < 60) {
            const fraction: number = parts[3] ? Number(`0.${parts[3]}`) : 0;
            document.lines.push(new LyricLine((Number(parts[1]) * 60 + Number(parts[2]) + fraction) * 1000, content));
          }
        }
      } else if (content.length > 0 && !/^\[(ar|ti|al|by|offset|length|re|ve):.*\]$/i.test(content)) {
        plain.push(new LyricLine(-1, content));
      }
    }
    document.timed = document.lines.some((line: LyricLine) => line.text.length > 0);
    if (document.timed) {
      document.lines.forEach((line: LyricLine) => line.time = Math.max(0, Math.round(line.time + offset)));
      document.lines.sort((a: LyricLine, b: LyricLine) => a.time - b.time);
      document.lines = EmbeddedLyrics.mergeLines(document.lines);
    } else {
      document.lines = plain;
    }
    return document;
  }

  /** 二分查找，暂停、跳转和倍速均以播放器的真实毫秒进度为准。 */
  static activeLine(document: LyricsDocument, position: number): number {
    if (!document.timed) { return -1; }
    let low: number = 0;
    let high: number = document.lines.length - 1;
    let result: number = -1;
    while (low <= high) {
      const middle: number = Math.floor((low + high) / 2);
      if (document.lines[middle].time <= position) {
        result = middle;
        low = middle + 1;
      } else { high = middle - 1; }
    }
    return result;
  }

  /** 悬浮栏和封面页共用同一句：时间轴空白不提前显示，无时间戳取首个非空行。 */
  static compactLineIndex(document: LyricsDocument, position: number): number {
    if (document.timed) {
      const index: number = EmbeddedLyrics.activeLine(document, position);
      return index >= 0 && document.lines[index].text.trim().length > 0 ? index : -1;
    }
    return document.lines.findIndex((line: LyricLine) => line.text.trim().length > 0);
  }

  private static mergeLines(lines: LyricLine[]): LyricLine[] {
    const merged: LyricLine[] = [];
    for (const line of lines) {
      const last: LyricLine | undefined = merged[merged.length - 1];
      if (last && last.time === line.time) {
        if (line.text.length > 0 && last.text !== line.text) {
          last.text = last.text.length > 0 ? `${last.text}\n${line.text}` : line.text;
        }
      } else { merged.push(new LyricLine(line.time, line.text)); }
    }
    return merged;
  }

  private static decode(data: Uint8Array, encoding: number = 3): string {
    if (!data.length || data.length > EmbeddedLyrics.MAX_TEXT) { return ''; }
    let name: string = encoding === 0 ? 'iso-8859-1' : encoding === 2 ? 'utf-16be' : 'utf-8';
    if (encoding === 1) {
      name = data[0] === 0xfe && data[1] === 0xff ? 'utf-16be' : 'utf-16le';
    }
    return util.TextDecoder.create(name).decodeToString(data).replace(/^\uFEFF/, '').replace(/\u0000+$/, '');
  }

  private static textEnd(data: Uint8Array, start: number, encoding: number): number {
    const step: number = encoding === 1 || encoding === 2 ? 2 : 1;
    for (let i: number = start; i < data.length; i += step) {
      if (data[i] === 0 && (step === 1 || data[i + 1] === 0)) { return i; }
    }
    return data.length;
  }

  private static unsync(data: Uint8Array): Uint8Array {
    const result: number[] = [];
    for (let i: number = 0; i < data.length; i++) {
      result.push(data[i]);
      if (data[i] === 0xff && data[i + 1] === 0) { i++; }
    }
    return new Uint8Array(result);
  }

  static id3(tag: Uint8Array): LyricsDocument {
    if (tag.length < 10 || EmbeddedLyrics.ascii(tag, 0, 3) !== 'ID3') { return new LyricsDocument(); }
    const version: number = tag[3];
    if (version < 2 || version > 4 || (version === 2 && (tag[5] & 0x40) !== 0)) { return new LyricsDocument(); }
    let data: Uint8Array = tag.slice(10, Math.min(tag.length, 10 + EmbeddedLyrics.syncsafe(tag, 6)));
    if (version < 4 && (tag[5] & 0x80) !== 0) { data = EmbeddedLyrics.unsync(data); }
    let position: number = 0;
    if (version >= 3 && (tag[5] & 0x40) !== 0) {
      position = version === 4 ? EmbeddedLyrics.syncsafe(data, 0) : EmbeddedLyrics.uint32(data, 0) + 4;
    }
    let fallback: LyricsDocument = new LyricsDocument();
    const headerSize: number = version === 2 ? 6 : 10;
    for (let i: number = 0; i < 4096 && position + headerSize <= data.length; i++) {
      const id: string = EmbeddedLyrics.ascii(data, position, version === 2 ? 3 : 4);
      const size: number = version === 2 ? data[position + 3] * 65536 + data[position + 4] * 256 + data[position + 5]
        : version === 4 ? EmbeddedLyrics.syncsafe(data, position + 4) : EmbeddedLyrics.uint32(data, position + 4);
      if (!/^[A-Z0-9]{3,4}$/.test(id) || size <= 0 || position + headerSize + size > data.length) { break; }
      const flags: number = version === 2 ? 0 : data[position + 9];
      let payload: Uint8Array = data.subarray(position + headerSize, position + headerSize + size);
      position += headerSize + size;
      if (size > EmbeddedLyrics.MAX_TEXT || (version === 3 && (flags & 0xc0) !== 0)
        || (version === 4 && (flags & 0x0c) !== 0)) { continue; }
      if (version === 4 && ((flags & 2) !== 0 || (tag[5] & 0x80) !== 0)) { payload = EmbeddedLyrics.unsync(payload); }
      if ((version === 3 && (flags & 0x20) !== 0) || (version === 4 && (flags & 0x40) !== 0)) { payload = payload.slice(1); }
      if (version === 4 && (flags & 1) !== 0) { payload = payload.slice(4); }
      const encoding: number = payload[0];
      if (encoding > 3) { continue; }
      const terminator: number = encoding === 1 || encoding === 2 ? 2 : 1;
      let document: LyricsDocument = new LyricsDocument();
      if (id === 'USLT' || id === 'ULT') {
        const end: number = EmbeddedLyrics.textEnd(payload, 4, encoding);
        document = EmbeddedLyrics.parse(EmbeddedLyrics.decode(payload.slice(end + terminator), encoding));
      } else if (id === 'TXXX' || id === 'TXX') {
        const end: number = EmbeddedLyrics.textEnd(payload, 1, encoding);
        const key: string = EmbeddedLyrics.decode(payload.slice(1, end), encoding);
        if (EmbeddedLyrics.isLyricsKey(key)) {
          document = EmbeddedLyrics.parse(EmbeddedLyrics.decode(payload.slice(end + terminator), encoding));
        }
      } else if ((id === 'SYLT' || id === 'SLT') && payload[4] === 2) {
        let cursor: number = EmbeddedLyrics.textEnd(payload, 6, encoding) + terminator;
        while (cursor < payload.length && document.lines.length < 5000) {
          const end: number = EmbeddedLyrics.textEnd(payload, cursor, encoding);
          if (end + terminator + 4 > payload.length) { break; }
          document.lines.push(new LyricLine(EmbeddedLyrics.uint32(payload, end + terminator),
            EmbeddedLyrics.decode(payload.slice(cursor, end), encoding).trim()));
          cursor = end + terminator + 4;
        }
        document.lines.sort((a: LyricLine, b: LyricLine) => a.time - b.time);
        document.lines = EmbeddedLyrics.mergeLines(document.lines);
        document.timed = document.lines.length > 0;
      }
      if (document.timed) { return document; }
      if (document.lines.length > 0) { fallback = document; }
    }
    return fallback;
  }

  static comments(data: Uint8Array): LyricsDocument {
    if (data.length < 8) { return new LyricsDocument(); }
    let position: number = 4 + EmbeddedLyrics.uint32(data, 0, true);
    if (position + 4 > data.length) { return new LyricsDocument(); }
    const count: number = EmbeddedLyrics.uint32(data, position, true);
    position += 4;
    let fallback: LyricsDocument = new LyricsDocument();
    for (let i: number = 0; i < Math.min(count, 4096) && position + 4 <= data.length; i++) {
      const size: number = EmbeddedLyrics.uint32(data, position, true);
      position += 4;
      if (position + size > data.length) { break; }
      const value: string = EmbeddedLyrics.decode(data.slice(position, position + size));
      position += size;
      const equals: number = value.indexOf('=');
      if (equals >= 0 && EmbeddedLyrics.isLyricsKey(value.slice(0, equals))) {
        const document: LyricsDocument = EmbeddedLyrics.parse(value.slice(equals + 1));
        if (document.timed) { return document; }
        if (document.lines.length) { fallback = document; }
      }
    }
    return fallback;
  }

  private static isLyricsKey(key: string): boolean {
    return /^(lyrics?|unsyncedlyrics|syncedlyrics|synchronizedlyrics)$/i.test(key.replace(/[ _-]/g, ''));
  }

  private static async ogg(reader: TagReader): Promise<LyricsDocument> {
    let position: number = 0;
    let serial: number = -1;
    let parts: Uint8Array[] = [];
    let packetSize: number = 0;
    for (let page: number = 0; page < 128 && position + 27 <= reader.size; page++) {
      const header: Uint8Array = await reader.read(position, 27);
      if (EmbeddedLyrics.ascii(header, 0, 4) !== 'OggS') { break; }
      const segments: Uint8Array = await reader.read(position + 27, header[26]);
      const size: number = segments.reduce((sum: number, item: number) => sum + item, 0);
      const pageSerial: number = EmbeddedLyrics.uint32(header, 14, true);
      if (serial === -1) { serial = pageSerial; }
      if (pageSerial === serial) {
        const body: Uint8Array = await reader.read(position + 27 + segments.length, size);
        let offset: number = 0;
        for (const length of segments) {
          packetSize += length;
          if (packetSize > EmbeddedLyrics.MAX_TEXT) { return new LyricsDocument(); }
          parts.push(body.slice(offset, offset + length));
          offset += length;
          if (length < 255) {
            const packet: Uint8Array = new Uint8Array(packetSize);
            let copied: number = 0;
            for (const part of parts) { packet.set(part, copied); copied += part.length; }
            parts = [];
            packetSize = 0;
            if (EmbeddedLyrics.ascii(packet, 0, 8) === 'OpusTags') { return EmbeddedLyrics.comments(packet.slice(8)); }
            if (packet[0] === 3 && EmbeddedLyrics.ascii(packet, 1, 6) === 'vorbis') {
              return EmbeddedLyrics.comments(packet.slice(7));
            }
          }
        }
      }
      position += 27 + segments.length + size;
    }
    return new LyricsDocument();
  }

  private static async mp4(reader: TagReader, start: number, end: number, depth: number): Promise<LyricsDocument> {
    if (depth > 8) { return new LyricsDocument(); }
    let position: number = start;
    for (let i: number = 0; i < 4096 && position + 8 <= end; i++) {
      const header: Uint8Array = await reader.read(position, 8);
      let size: number = EmbeddedLyrics.uint32(header, 0);
      const type: string = EmbeddedLyrics.ascii(header, 4, 4);
      let headerSize: number = 8;
      if (size === 1) {
        const large: Uint8Array = await reader.read(position + 8, 8);
        size = EmbeddedLyrics.uint32(large, 0) * 4294967296 + EmbeddedLyrics.uint32(large, 4);
        headerSize = 16;
      } else if (size === 0) { size = end - position; }
      if (!Number.isSafeInteger(size) || size < headerSize || position + size > end) { break; }
      const body: number = position + headerSize;
      const atomEnd: number = position + size;
      if (type === '©lyr') {
        let cursor: number = body;
        while (cursor + 16 <= atomEnd) {
          const child: Uint8Array = await reader.read(cursor, 16);
          const childSize: number = EmbeddedLyrics.uint32(child, 0);
          if (childSize < 16 || cursor + childSize > atomEnd) { break; }
          if (EmbeddedLyrics.ascii(child, 4, 4) === 'data' && childSize - 16 <= EmbeddedLyrics.MAX_TEXT) {
            const encoding: number = EmbeddedLyrics.uint32(child, 8) & 0xffffff;
            return EmbeddedLyrics.parse(EmbeddedLyrics.decode(await reader.read(cursor + 16, childSize - 16),
              encoding === 2 ? 2 : 3));
          }
          cursor += childSize;
        }
      } else if (type === 'moov' || type === 'udta' || type === 'meta' || type === 'ilst') {
        const document: LyricsDocument = await EmbeddedLyrics.mp4(reader, body + (type === 'meta' ? 4 : 0), atomEnd, depth + 1);
        if (document.lines.length) { return document; }
      }
      position = atomEnd;
    }
    return new LyricsDocument();
  }

  private static ascii(data: Uint8Array, start: number, length: number): string {
    let text: string = '';
    for (let i: number = start; i < Math.min(data.length, start + length); i++) { text += String.fromCharCode(data[i]); }
    return text;
  }

  private static uint32(data: Uint8Array, start: number, little: boolean = false): number {
    if (start + 4 > data.length) { return 0; }
    return new DataView(data.buffer, data.byteOffset, data.byteLength).getUint32(start, little);
  }

  private static syncsafe(data: Uint8Array, start: number): number {
    if (start + 4 > data.length) { return 0; }
    return (data[start] & 0x7f) * 2097152 + (data[start + 1] & 0x7f) * 16384
      + (data[start + 2] & 0x7f) * 128 + (data[start + 3] & 0x7f);
  }
}
