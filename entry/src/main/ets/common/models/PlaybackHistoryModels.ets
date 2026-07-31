/** 一条可持久化的本地视频播放历史。 */
export class PlaybackHistoryEntry {
  uri: string;
  title: string;
  length: number;
  artworkUrl: string;
  playedAt: number;

  constructor(uri: string, title: string, length: number, artworkUrl: string, playedAt: number) {
    this.uri = uri;
    this.title = title;
    this.length = length;
    this.artworkUrl = artworkUrl;
    this.playedAt = playedAt;
  }
}

/** 播放历史清空确认弹窗所需的固定文案。 */
export class HistoryClearPrompt {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;

  constructor(title: string, message: string, cancelLabel: string, confirmLabel: string) {
    this.title = title;
    this.message = message;
    this.cancelLabel = cancelLabel;
    this.confirmLabel = confirmLabel;
  }
}

export function historyClearPrompt(): HistoryClearPrompt {
  return new HistoryClearPrompt(
    '清除播放历史记录',
    '您将会丢失播放历史、当前播放列表以及播放进度。',
    '取消',
    '清除历史',
  );
}

/** 将刚播放的媒体置顶，并按 URI 去重以避免同一视频重复出现。 */
export function prependPlaybackHistory(
  entries: PlaybackHistoryEntry[],
  entry: PlaybackHistoryEntry,
  limit: number = 50,
): PlaybackHistoryEntry[] {
  const result: PlaybackHistoryEntry[] = [entry];
  for (const item of entries) {
    if (item.uri !== entry.uri && result.length < limit) {
      result.push(item);
    }
  }
  return result;
}

/** 无痕模式开启时，任何新播放都不能写入历史。 */
export function shouldRecordPlaybackHistory(incognito: boolean): boolean {
  return !incognito;
}

/** 仅在媒体首次进入播放态时写入；暂停后继续播放不重复刷新历史。 */
export function shouldRecordPlaybackStart(state: string, lastRecordedUri: string, uri: string): boolean {
  return state === 'playing' && uri.length > 0 && lastRecordedUri !== uri;
}
