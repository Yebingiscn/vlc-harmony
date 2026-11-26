import { PlaybackMode, PlaybackService } from '../data/PlaybackService';
import { UiFeedback } from '../utils/UiFeedback';
import { PlayerControlButton } from './PlayerControlButton';

@ComponentV2
export struct PlayerModeButton {
  @Param mode: PlaybackMode = PlaybackMode.Sequence;
  @Event onModeChange: (mode: PlaybackMode) => void = () => {};

  private icon(): Resource {
    switch (this.mode) {
      case PlaybackMode.RepeatAll:
        return $r('sys.symbol.repeat');
      case PlaybackMode.RepeatOne:
        return $r('sys.symbol.repeat_1');
      case PlaybackMode.Shuffle:
        return $r('sys.symbol.shuffle');
      default:
        return $r('sys.symbol.order_play');
    }
  }

  private modeLabel(mode: PlaybackMode): Resource {
    switch (mode) {
      case PlaybackMode.RepeatAll:
        return $r('app.string.player_repeat_all');
      case PlaybackMode.RepeatOne:
        return $r('app.string.player_repeat_one');
      case PlaybackMode.Shuffle:
        return $r('app.string.player_order_shuffle');
      default:
        return $r('app.string.player_order_sequential');
    }
  }

  build() {
    PlayerControlButton({
      icon: this.icon(),
      iconColor: $r('app.color.orange500'),
      label: $r('app.string.player_playback_mode'),
      description: this.modeLabel(this.mode),
      onPress: () => {
        const mode = PlaybackService.getInstance().cyclePlaybackMode();
        this.onModeChange(mode);
        UiFeedback.showToast({ message: this.modeLabel(mode), duration: 1500 });
      },
    })
  }
}
