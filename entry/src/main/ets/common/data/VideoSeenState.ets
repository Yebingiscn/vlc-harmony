import { Settings } from './Settings';
import { MediaWrapper } from '../models/MediaModels';

/** 视频“已看”状态的轻量持久化。
 *
 * 媒体库每次扫描都会重新构建 MediaWrapper，不能只改内存里的 seen 字段；
 * 因此按媒体 URI 的稳定散列保存标记，重新扫描后再回填到列表项。
 */
export class VideoSeenState {
  private static readonly KEY_PREFIX: string = 'video_seen_';

  /** 播放器收到媒体正常结束事件时调用。 */
  static markSeen(uri: string): Promise<void> {
    if (uri.length === 0) {
      return Promise.resolve();
    }
    return Settings.put(VideoSeenState.keyFor(uri), true);
  }

  /** 手动标记为未播放。 */
  static markUnseen(uri: string): Promise<void> {
    if (uri.length === 0) {
      return Promise.resolve();
    }
    return Settings.put(VideoSeenState.keyFor(uri), false);
  }

  /** 将持久化状态回填给本次扫描得到的视频列表。 */
  static async hydrate(items: MediaWrapper[]): Promise<void> {
    for (const item of items) {
      item.seen = await Settings.getBoolean(VideoSeenState.keyFor(item.uri), false) ? 1 : 0;
    }
  }

  private static keyFor(uri: string): string {
    let hash: number = 0;
    for (let index: number = 0; index < uri.length; index++) {
      hash = (hash * 31 + uri.charCodeAt(index)) | 0;
    }
    return `${VideoSeenState.KEY_PREFIX}${hash}`;
  }
}
