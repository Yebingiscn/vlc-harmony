/**
 * 书签条目。in-memory 持有,由 VideoPlayerPage 维护;关闭弹框不丢,退出 app 才丢。
 */
export class BookMark {
  id: number;
  /** 媒体标识 —— 同一书签只在当前视频有效(后期可考虑持久化到 MediaWrapper.id 上)。 */
  mediaId: number;
  /** 书签时间点(毫秒)。 */
  timeMs: number;
  /** 用户名(可空:为空时显示 "书签 N")。 */
  name: string;

  constructor(id: number, mediaId: number, timeMs: number, name: string = '') {
    this.id = id;
    this.mediaId = mediaId;
    this.timeMs = timeMs;
    this.name = name;
  }
}
