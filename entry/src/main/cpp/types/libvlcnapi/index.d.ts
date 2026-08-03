/**
 * libVLC NAPI 桥(句柄式,对齐 libvlcjni 对象生命周期)。
 * import from 'libvlcnapi.so'
 */

export type VlcEventName =
  | 'playing' | 'paused' | 'stopped' | 'ended' | 'error'
  | 'lengthChanged' | 'timeChanged' | 'positionChanged' | 'vout'
  | 'buffering' | 'esAdded' | 'esDeleted' | 'esSelected'
  | 'rendererItemAdded' | 'rendererItemDeleted';

/** (playerHandle, event, value) */
export type VlcPlayerEventListener = (playerHandle: number, event: VlcEventName, value: number) => void;

export interface VlcTrackInfo {
  id: number;
  name: string;
}

export interface VlcChapterInfo {
  name: string;
  timeOffset: number;
  duration: number;
}

export interface VlcVideoSize {
  width: number;
  height: number;
}

export interface VlcRendererInfo {
  handle: number;
  name: string;
  type: string;
}

export interface VlcMetaInfo {
  title: string;
  artist: string;
  album: string;
  duration: number;
}

/** libvlc_media_track_t 解码后的元数据(对应 libvlc_track_type_t: 0=audio, 1=video, 2=text)。 */
export interface VlcMediaTrackInfo {
  id: number;
  /** libvlc_track_type_t 枚举值 */
  type: number;
  /** FOURCC 编码标识 */
  codecFourcc: number;
  /** 编码描述(如 'H264 - MPEG-4 AVC (part 10) (avc1)') */
  codecDesc: string;
  /** 语言标签(BCP-47,如 'en', 'zh-Hans'),空表示无 */
  language: string;
  /** 平均码率(bits/s) */
  bitrate: number;
  /** 仅 audio:声道数(2=立体声, 6=5.1 等) */
  channels?: number;
  /** 仅 audio:采样率(Hz,如 48000) */
  sampleRate?: number;
  /** 仅 video:像素宽度(若为 0 则 libVLC 未填充,回落到 MediaPlayerGetVideoSize) */
  videoWidth?: number;
  /** 仅 video:像素高度 */
  videoHeight?: number;
  /** 仅 video:帧率分子 */
  frameRateNum?: number;
  /** 仅 video:帧率分母 */
  frameRateDen?: number;
}

// —— LibVLC ——
export const libvlcCreate: (options?: string[]) => number;
export const libvlcRelease: (libHandle: number) => void;

// —— Media ——
export const mediaCreateLocation: (libHandle: number, mrl: string) => number;
export const mediaCreatePath: (libHandle: number, path: string) => number;
export const mediaCreateFd: (libHandle: number, fd: number) => number;
export const mediaRelease: (mediaHandle: number) => void;
export const mediaParse: (mediaHandle: number, timeoutMs?: number) => boolean;
export const mediaGetMeta: (mediaHandle: number) => VlcMetaInfo | null;
export const mediaGetTracksInfo: (mediaHandle: number) => VlcMediaTrackInfo[];
export const mediaAddSlave: (mediaHandle: number, type: number, uri: string, priority?: number) => boolean;

// —— MediaPlayer ——
export const mediaPlayerCreate: (libHandle: number) => number;
export const mediaPlayerRelease: (playerHandle: number) => void;
export const mediaPlayerSetEventListener: (playerHandle: number, listener: VlcPlayerEventListener) => boolean;
export const mediaPlayerSetMedia: (playerHandle: number, mediaHandle: number) => boolean;
export const mediaPlayerSetVideoOut: (playerHandle: number, xcomponentId: string) => boolean;
export const mediaPlayerDetachViews: (playerHandle: number) => void;
export const hasNativeWindow: (xcomponentId: string) => boolean;
export const mediaPlayerPlay: (playerHandle: number) => void;
export const mediaPlayerPause: (playerHandle: number) => void;
export const mediaPlayerStop: (playerHandle: number) => void;
export const mediaPlayerGetTime: (playerHandle: number) => number;
export const mediaPlayerSetTime: (playerHandle: number, ms: number) => void;
export const mediaPlayerGetLength: (playerHandle: number) => number;
export const mediaPlayerSetRate: (playerHandle: number, rate: number) => void;
export const mediaPlayerGetRate: (playerHandle: number) => number;
export const mediaPlayerSetVolume: (playerHandle: number, volume: number) => void;
export const mediaPlayerGetVolume: (playerHandle: number) => number;
export const mediaPlayerGetState: (playerHandle: number) => number;
export const mediaPlayerGetPosition: (playerHandle: number) => number;
export const mediaPlayerGetVideoSize: (playerHandle: number) => VlcVideoSize | null;
export const mediaPlayerSetScale: (playerHandle: number, factor: number) => void;
export const mediaPlayerAddSlave: (playerHandle: number, type: number, uri: string, select?: boolean) => boolean;

export const mediaPlayerGetAudioTracks: (playerHandle: number) => VlcTrackInfo[];
export const mediaPlayerGetSpuTracks: (playerHandle: number) => VlcTrackInfo[];
export const mediaPlayerGetVideoTracks: (playerHandle: number) => VlcTrackInfo[];
export const mediaPlayerGetAudioTrack: (playerHandle: number) => number;
export const mediaPlayerGetSpuTrack: (playerHandle: number) => number;
export const mediaPlayerGetVideoTrack: (playerHandle: number) => number;
export const mediaPlayerSetAudioTrack: (playerHandle: number, id: number) => boolean;
export const mediaPlayerSetSpuTrack: (playerHandle: number, id: number) => boolean;
export const mediaPlayerSetVideoTrack: (playerHandle: number, id: number) => boolean;
export const mediaPlayerSetSpuDelay: (playerHandle: number, us: number) => boolean;

export const mediaPlayerGetChapters: (playerHandle: number, titleIndex?: number) => VlcChapterInfo[];
export const mediaPlayerGetChapter: (playerHandle: number) => number;
export const mediaPlayerSetChapter: (playerHandle: number, index: number) => void;

export const mediaPlayerSetRenderer: (playerHandle: number, rendererHandle: number) => boolean;
export const mediaPlayerClearRenderer: (playerHandle: number) => boolean;
export const mediaPlayerSetEqualizer: (playerHandle: number, eqHandle: number) => boolean;
export const mediaPlayerClearEqualizer: (playerHandle: number) => boolean;

// —— Equalizer ——
export const equalizerGetPresetCount: () => number;
export const equalizerGetPresetName: (index: number) => string;
export const equalizerGetBandCount: () => number;
export const equalizerGetBandFrequency: (index: number) => number;
export const equalizerCreate: () => number;
export const equalizerCreateFromPreset: (index: number) => number;
export const equalizerRelease: (eqHandle: number) => void;
export const equalizerSetPreAmp: (eqHandle: number, preamp: number) => boolean;
export const equalizerGetPreAmp: (eqHandle: number) => number;
export const equalizerSetAmp: (eqHandle: number, band: number, amp: number) => boolean;
export const equalizerGetAmp: (eqHandle: number, band: number) => number;

// —— MediaList ——
export const mediaListCreate: (libHandle: number) => number;
export const mediaListRelease: (listHandle: number) => void;
export const mediaListCount: (listHandle: number) => number;
export const mediaListAddMedia: (listHandle: number, mediaHandle: number) => boolean;
export const mediaListRemoveIndex: (listHandle: number, index: number) => boolean;
export const mediaListItemAt: (listHandle: number, index: number) => number;

// —— MediaDiscoverer ——
export const mediaDiscovererCreate: (libHandle: number, name: string) => number;
export const mediaDiscovererRelease: (discovererHandle: number) => void;
export const mediaDiscovererStart: (discovererHandle: number) => boolean;
export const mediaDiscovererStop: (discovererHandle: number) => void;
export const mediaDiscovererMediaList: (discovererHandle: number) => number;

// —— RendererDiscoverer ——
export const rendererDiscovererList: (libHandle: number) => string[];
export const rendererDiscovererCreate: (libHandle: number, name: string) => number;
export const rendererDiscovererRelease: (rdHandle: number) => void;
export const rendererDiscovererStart: (rdHandle: number) => boolean;
export const rendererDiscovererStop: (rdHandle: number) => void;
export const rendererDiscovererGetItems: (rdHandle: number) => VlcRendererInfo[];
export const rendererItemRelease: (rendererHandle: number) => void;
