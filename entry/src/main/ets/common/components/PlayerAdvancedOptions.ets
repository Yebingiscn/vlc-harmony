export type PlayerAdvancedMenuMode = 'audio' | 'video';

export type PlayerAdvancedOptionId =
  | 'lock'
  | 'sleep'
  | 'speed'
  | 'jumpToTime'
  | 'equalizer'
  | 'playAsAudio'
  | 'popupPlayer'
  | 'repeat'
  | 'videoInfo'
  | 'bookmark'
  | 'abRepeat'
  | 'savePlaylist'
  | 'videoControls'
  | 'videoTips'
  | 'shareTrack'
  | 'audioControls'
  | 'audioTips'
  | 'playlistTips';

export class PlayerAdvancedOption {
  id: PlayerAdvancedOptionId;
  title: string;
  icon: Resource;

  constructor(id: PlayerAdvancedOptionId, title: string, icon: Resource) {
    this.id = id;
    this.title = title;
    this.icon = icon;
  }
}

/**
 * Returns visual-only advanced options. The player page owns action handling.
 */
export function buildPlayerAdvancedOptions(mode: PlayerAdvancedMenuMode): PlayerAdvancedOption[] {
  const shared: PlayerAdvancedOption[] = [
    new PlayerAdvancedOption('sleep', '睡眠定时器', $r('app.media.ic_sleep')),
    new PlayerAdvancedOption('speed', '播放速度', $r('app.media.ic_speed')),
    new PlayerAdvancedOption('jumpToTime', '跳转至时间', $r('app.media.ic_jumpto')),
    new PlayerAdvancedOption('equalizer', '均衡器', $r('app.media.ic_equalizer')),
  ];

  if (mode === 'video') {
    return [
      new PlayerAdvancedOption('lock', '锁定', $r('app.media.ic_lock_player')),
      ...shared,
      new PlayerAdvancedOption('playAsAudio', '仅播放音频', $r('app.media.ic_playasaudio_on')),
      new PlayerAdvancedOption('popupPlayer', '弹出式播放器', $r('app.media.ic_popup_dim')),
      new PlayerAdvancedOption('repeat', '循环模式', $r('app.media.ic_repeat')),
      new PlayerAdvancedOption('videoInfo', '视频信息', $r('app.media.ic_video_stats')),
      new PlayerAdvancedOption('bookmark', '书签', $r('app.media.ic_bookmark')),
      new PlayerAdvancedOption('abRepeat', 'A-B 循环', $r('app.media.ic_abrepeat')),
      new PlayerAdvancedOption('savePlaylist', '保存播放列表', $r('app.media.ic_addtoplaylist')),
      new PlayerAdvancedOption('videoControls', '控制设置', $r('app.media.ic_video_controls')),
      new PlayerAdvancedOption('videoTips', '视频播放器提示', $r('app.media.ic_videotips')),
    ];
  }

  return [
    ...shared,
    new PlayerAdvancedOption('bookmark', '书签', $r('app.media.ic_bookmark')),
    new PlayerAdvancedOption('abRepeat', 'A-B 循环', $r('app.media.ic_abrepeat')),
    new PlayerAdvancedOption('savePlaylist', '保存播放列表', $r('app.media.ic_addtoplaylist')),
    new PlayerAdvancedOption('shareTrack', '分享曲目信息', $r('app.media.ic_share')),
    new PlayerAdvancedOption('audioControls', '控制设置', $r('app.media.ic_audio_controls')),
    new PlayerAdvancedOption('audioTips', '音频播放器提示', $r('app.media.ic_audiotips')),
    new PlayerAdvancedOption('playlistTips', '播放列表提示', $r('app.media.ic_playlisttips')),
  ];
}

@ComponentV2
export struct PlayerAdvancedOptions {
  @Param items: PlayerAdvancedOption[] = [];
  @Event onSelect: (id: PlayerAdvancedOptionId) => void = () => {};

  build() {
    List({ space: 0 }) {
      ForEach(this.items, (item: PlayerAdvancedOption) => {
        ListItem() {
          Row() {
            Image(item.icon)
              .width(26)
              .height(26)
              .fillColor('#333333')
              .margin({ left: 18, right: 18 })
            Text(item.title)
              .fontSize(17)
              .fontColor('#333333')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ right: 18 })
          }
          .width('100%')
          .height(40)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => this.onSelect(item.id))
        }
      }, (item: PlayerAdvancedOption): string => item.id)
    }
    .width(268)
    .height(560)
    .scrollBar(BarState.Off)
    .backgroundColor('#FFFFFF')
    .borderRadius(0)
  }
}
