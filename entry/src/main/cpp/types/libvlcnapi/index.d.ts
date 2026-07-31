/**
 * libVLC NAPI 桥 ArkTS 声明。
 * 模块名 libvlcnapi(对应 vlc_napi.cpp 的 nm_modname),import 路径 'libvlcnapi.so'。
 */

/** 播放器事件名(init 后 setEventListener 回调的首参)。 */
export type VlcEventName =
  | 'playing' | 'paused' | 'stopped' | 'ended' | 'error'
  | 'lengthChanged' | 'timeChanged' | 'positionChanged' | 'vout';

/** 事件回调:(eventName, value) —— value 对 lengthChanged/timeChanged 为 ms,positionChanged 为 0..1,vout 为 count,其余为 0。 */
export type VlcEventListener = (event: VlcEventName, value: number) => void;

export const init: () => boolean;
/** 注册事件回调(状态/进度)。事件来自 VLC 线程,经 threadsafe function 回到 JS 线程。 */
export const setEventListener: (listener: VlcEventListener) => boolean;
/**
 * 将 XComponent(id) 的 OHNativeWindow 绑到 libVLC。
 * 返回 true 表示当时 window 已就绪并完成绑定;false 表示 Surface 尚未创建(会在 OnSurfaceCreated 自动补绑)。
 */
export const setVideoOut: (xcomponentId: string) => boolean;
/** 查询指定 XComponent id 的 NativeWindow 是否已由 OnSurfaceCreated 登记。 */
export const hasNativeWindow: (xcomponentId: string) => boolean;
/** 设置媒体(含 "://" 当网络 MRL,否则本地路径)。 */
export const setMedia: (mrl: string) => boolean;
/**
 * 用已打开的文件描述符设置媒体。
 * 用于鸿蒙相册 URI(file://media/Photo/...),先 fs.openSync(uri) 再传 fd。
 * Native 会 dup(fd),ArkTS 侧可立即 close File。
 */
export const setMediaFd: (fd: number) => boolean;
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
/** 视频原始像素尺寸;vout 未就绪时可能为 null。 */
export const getVideoSize: () => { width: number; height: number } | null;
/** 缩放因子;0=按输出窗口自适应保持比例。 */
export const setScale: (factor: number) => void;
/** 释放实例与播放器(退出时调用)。 */
export const release: () => void;
