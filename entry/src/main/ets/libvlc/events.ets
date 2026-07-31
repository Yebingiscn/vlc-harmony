/**
 * MediaPlayer 事件名(对齐 org.videolan.libvlc.MediaPlayer.Event)。
 * NAPI 侧以字符串传递,此处提供常量便于对照。
 */
export class MediaPlayerEvent {
  static readonly Playing: string = 'playing';
  static readonly Paused: string = 'paused';
  static readonly Stopped: string = 'stopped';
  static readonly EndReached: string = 'ended';
  static readonly EncounteredError: string = 'error';
  static readonly TimeChanged: string = 'timeChanged';
  static readonly PositionChanged: string = 'positionChanged';
  static readonly LengthChanged: string = 'lengthChanged';
  static readonly Vout: string = 'vout';
  static readonly Buffering: string = 'buffering';
  static readonly ESAdded: string = 'esAdded';
  static readonly ESDeleted: string = 'esDeleted';
  static readonly ESSelected: string = 'esSelected';
}

/** 外挂轨类型(libvlc_media_slave_type_t)。 */
export enum MediaSlaveType {
  Subtitle = 0,
  Audio = 1,
}

export type MediaPlayerEventListener = (event: string, value: number) => void;
