/**
 * libVLC NAPI 桥 ArkTS 声明。
 * 模块名 libvlcnapi(对应 vlc_napi.cpp 的 nm_modname),import 路径 'libvlcnapi'。
 */

/** 播放器事件名(init 后 setEventListener 回调的首参)。 */
export type VlcEventName =
  | 'playing' | 'paused' | 'stopped' | 'ended' | 'error'
  | 'lengthChanged' | 'timeChanged' | 'positionChanged';

/** 事件回调:(eventName, value) —— value 对 lengthChanged/timeChanged 为 ms,positionChanged 为 0..1,其余为 0。 */
export type VlcEventListener = (event: VlcEventName, value: number) => void;

export const init: () => boolean;
/** 注册事件回调(状态/进度)。事件来自 VLC 线程,经 threadsafe function 回到 JS 线程。 */
export const setEventListener: (listener: VlcEventListener) => boolean;
/** 设置媒体(含 "://" 当网络 MRL,否则本地路径)。 */
export const setMedia: (mrl: string) => boolean;
export const play: () => void;
export const pause: () => void;
export const resume: () => void;
export const stop: () => void;
/** 当前播放位置 ms(-1 表示无媒体)。 */
export const getTime: () => number;
export const setTime: (ms: number) => void;
/** 媒体总时长 ms。 */
export const getLength: () => number;
export const setRate: (rate: number) => void;
export const getRate: () => number;
/** 音量 0..100(部分后端可超)。 */
export const setVolume: (volume: number) => void;
export const getVolume: () => number;
export const getState: () => number;
export const getPosition: () => number;
/** 释放实例与播放器(退出时调用)。 */
export const release: () => void;
