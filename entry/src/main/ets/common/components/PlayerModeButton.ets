import { PlaybackService } from '../data/PlaybackService';

@ComponentV2
export struct PlayerModeButton {
  @Param shuffle: boolean = false;
  @Param repeatMode: number = 0;
  @Param iconSize: number = 28;
  @Param iconColor: ResourceColor = $r('app.color.list_title');
  @Event onMenuVisibility: (visible: boolean) => void = () => {};
  @Local menuOpen: boolean = false;

  private icon(): Resource {
    if (this.repeatMode === 2) {
      return $r('app.media.ic_repeat_one_audio');
    }
    if (this.shuffle) {
      return $r('app.media.ic_shuffle_audio');
    }
    return this.repeatMode === 1 ? $r('app.media.ic_repeat_all_audio') : $r('app.media.ic_shuffle_audio');
  }

  private setMenuOpen(open: boolean): void {
    this.menuOpen = open;
    this.onMenuVisibility(open);
  }

  @Builder
  option(label: Resource, selected: boolean, select: () => void) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(16)
        .fontColor(selected ? $r('app.color.orange500') : $r('app.color.list_title'))
        .layoutWeight(1)
      if (selected) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.orange500'))
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .accessibilitySelected(selected)
    .onClick(() => {
      select();
      this.setMenuOpen(false);
    })
  }

  @Builder
  modeMenu() {
    Column() {
      this.option($r('app.string.player_order_sequential'), !this.shuffle, () => PlaybackService.setShuffle(false))
      this.option($r('app.string.player_order_shuffle'), this.shuffle, () => PlaybackService.setShuffle(true))
      Divider().color($r('app.color.divider')).margin({ top: 4, bottom: 4 })
      this.option($r('app.string.player_repeat_off'), this.repeatMode === 0,
        () => PlaybackService.getInstance().setRepeatMode(0))
      this.option($r('app.string.player_repeat_all'), this.repeatMode === 1,
        () => PlaybackService.getInstance().setRepeatMode(1))
      this.option($r('app.string.player_repeat_one'), this.repeatMode === 2,
        () => PlaybackService.getInstance().setRepeatMode(2))
    }
    .width(180)
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Image(this.icon())
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.shuffle || this.repeatMode !== 0 ? $r('app.color.orange500') : this.iconColor)
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText($r('app.string.player_playback_mode'))
    .onClick(() => this.setMenuOpen(true))
    .bindMenu(this.menuOpen!!, this.modeMenu(), {
      placement: Placement.TopLeft,
      showInSubWindow: true,
      onDisappear: () => this.setMenuOpen(false),
    })
  }
}
