import { EmbeddedLyrics, LyricsDocument } from './EmbeddedLyrics';

/** 复用播放进度通知，不增加定时器；仅保留当前曲目的内嵌歌词。 */
@ObservedV2
export class MiniPlayerLyrics {
  @Trace line: string = '';

  private active: boolean = false;
  private uri: string = '';
  private position: number = 0;
  private generation: number = 0;
  private document: LyricsDocument | null = null;

  start(): void {
    if (this.active) { return; }
    this.active = true;
    this.generation++;
  }

  update(uri: string, position: number): void {
    if (!this.active) { return; }
    this.position = position;
    if (this.uri === uri) {
      this.refreshLine();
      return;
    }
    this.uri = uri;
    const generation: number = ++this.generation;
    this.document = null;
    this.line = '';
    if (uri.length > 0) {
      void this.load(uri, generation);
    }
  }

  /** 只交接当前曲目已加载的只读文档，不在打开页面时额外读取文件。 */
  snapshot(uri: string): LyricsDocument | null {
    return this.active && uri === this.uri ? this.document : null;
  }

  dispose(): void {
    this.active = false;
    this.generation++;
    this.uri = '';
    this.position = 0;
    this.document = null;
    this.line = '';
  }

  private async load(uri: string, generation: number): Promise<void> {
    let document: LyricsDocument;
    try {
      document = await EmbeddedLyrics.load(uri);
    } catch (_error) {
      document = new LyricsDocument();
    }
    if (!this.active || this.generation !== generation || this.uri !== uri) {
      return;
    }
    this.document = document;
    this.refreshLine();
  }

  private refreshLine(): void {
    if (this.document === null) {
      this.line = '';
      return;
    }
    const index: number = EmbeddedLyrics.compactLineIndex(this.document, this.position);
    this.line = index >= 0 ? this.document.lines[index].text.trim() : '';
  }
}
