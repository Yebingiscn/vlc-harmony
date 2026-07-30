export type VideoPlayerBottomActionId =
  | 'tracks'
  | 'orientation'
  | 'play'
  | 'aspectRatio'
  | 'advanced';

export class VideoPlayerBottomAction {
  id: VideoPlayerBottomActionId;
  icon: Resource;

  constructor(id: VideoPlayerBottomActionId, icon: Resource) {
    this.id = id;
    this.icon = icon;
  }
}

/**
 * The bottom video controls are intentionally ordered to match the Android player.
 * The page owns the action behavior so playback wiring can be added independently.
 */
export function buildVideoPlayerBottomActions(): VideoPlayerBottomAction[] {
  return [
    new VideoPlayerBottomAction('tracks', $r('app.media.ic_player_audiotrack')),
    new VideoPlayerBottomAction('orientation', $r('app.media.ic_player_rotate')),
    new VideoPlayerBottomAction('play', $r('app.media.ic_play_player')),
    new VideoPlayerBottomAction('aspectRatio', $r('app.media.ic_player_ratio')),
    new VideoPlayerBottomAction('advanced', $r('app.media.ic_player_more')),
  ];
}
