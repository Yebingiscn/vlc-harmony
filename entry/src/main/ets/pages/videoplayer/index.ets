/**
 * videoplayer 模块再导出 —— 对齐 Android gui/video 包边界。
 */
export {
  VLC_VIDEO_XCOMPONENT_ID,
  VLC_NAPI_LIBRARY,
  VideoPlayItem,
  VideoParam,
  fmtTime,
  VideoPlayerViewModel,
} from './VideoPlayerViewModel';

export { fitContain, VideoPlayerResizeDelegate } from './VideoPlayerResizeDelegate';

export {
  VideoPlayerOverlayDelegate,
  VideoPlayerOverlayHud,
  VideoPlayerOverlaySheet,
} from './VideoPlayerOverlayDelegate';

export {
  VideoPlayerBottomActionId,
  VideoPlayerBottomAction,
  buildVideoPlayerBottomActions,
} from './VideoPlayerControls';

export { VideoTouchDelegate } from './VideoTouchDelegate';
export { VideoDelayDelegate } from './VideoDelayDelegate';
export { VideoPlayerOrientationDelegate } from './VideoPlayerOrientationDelegate';
export { VideoPlayerScreenshotDelegate } from './VideoPlayerScreenshotDelegate';
export { VideoTipsDelegate } from './VideoTipsDelegate';
export { VideoStatsDelegate } from './VideoStatsDelegate';
