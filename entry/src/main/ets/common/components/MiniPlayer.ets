import { PlayState } from '../models/MediaModels';
import { PlaybackListener, PlaybackService, PlaybackState } from '../data/PlaybackService';
import { AudioPlayerRoute, NavController } from '../data/NavController';
import { MiniPlayerDrag } from '../data/MiniPlayerDrag';
import { MiniPlayerLyrics } from '../data/MiniPlayerLyrics';
import { curves } from '@kit.ArkUI';

const AUDIO_EXTS = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];
const MINI_PLAYER_HEIGHT: number = 64;

@ObservedV2
class MiniPlayerVM implements PlaybackListener {
  @Trace title: string = '';
  @Trace artist: string = '';
  @Trace lyrics: MiniPlayerLyrics = new MiniPlayerLyrics();
  @Trace artworkPath: string = '';
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace state: PlayState = PlayState.IDLE;
  @Trace hasCurrent: boolean = false;

  onChange(s: PlaybackState): void {
    const cur = PlaybackService.getCurrent();
    const lower = cur?.uri?.toLowerCase() ?? '';
    const isAudio = AUDIO_EXTS.some(e => lower.endsWith(e));
    this.title = s.title;
    this.artist = s.artist.length > 0 ? s.artist : (cur?.artistName ?? '');
    this.artworkPath = s.artworkPath;
    this.duration = s.duration;
    this.position = s.position;
    this.state = s.state;
    this.hasCurrent = s.queueSize > 0 && s.currentIndex >= 0 && (isAudio || s.playAsAudio);
    this.lyrics.update(this.hasCurrent ? (cur?.uri ?? '') : '', s.position);
  }
}

@ComponentV2
export struct MiniPlayer {
  @Param expansionHeight: number = 420;
  @Local vm: MiniPlayerVM = new MiniPlayerVM();
  @Local expansion: number = 0;
  @Local availableWidth: number = 360;
  @Local opening: boolean = false;
  private dragging: boolean = false;
  private ignoreClickUntil: number = 0;

  private panelWidth(): number {
    const collapsed: number = Math.min(328, Math.max(0, this.availableWidth - 32));
    return collapsed + (this.availableWidth - collapsed) * this.expansion;
  }

  private panelHeight(): number {
    return MINI_PLAYER_HEIGHT + (this.expansionHeight - MINI_PLAYER_HEIGHT) * this.expansion;
  }

  private coverSize(): number {
    const expanded: number = Math.max(32, Math.min(220, this.availableWidth * 0.64, this.expansionHeight - 150));
    return 40 + (expanded - 40) * this.expansion;
  }

  private textWidth(): number {
    // 为两个独立的 44vp 控制按钮留出空间，长标题/歌词不能覆盖点击区域。
    return Math.max(0, this.panelWidth() - 168 + 128 * this.expansion);
  }

  private controlSize(): number {
    return 44 + 12 * this.expansion;
  }

  private controlX(next: boolean): number {
    const collapsed: number = this.panelWidth() - (next ? 52 : 100);
    const expanded: number = this.panelWidth() / 2 + (next ? 24 : -48);
    return collapsed + (expanded - collapsed) * this.expansion;
  }

  private controlY(): number {
    return this.panelHeight() - MINI_PLAYER_HEIGHT / 2 - this.controlSize() / 2 - 8 * this.expansion;
  }

  private resetDrag(): void {
    this.expansion = 0;
    this.dragging = false;
    this.opening = false;
  }

  private collapse(): void {
    this.dragging = false;
    this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => {
      this.expansion = 0;
    });
  }

  private openPlayer(): void {
    if (this.opening) { return; }
    // 同步当前队列后再交接，避免切歌通知尚未到达时把上一首歌手配给新 URI。
    this.vm.onChange(PlaybackService.snapshot());
    if (!this.vm.hasCurrent) { return; }
    this.dragging = false;
    this.opening = true;
    const route: AudioPlayerRoute = new AudioPlayerRoute();
    route.uri = PlaybackService.getCurrent()?.uri ?? '';
    route.title = this.vm.title;
    route.artist = this.vm.artist;
    route.artworkPath = this.vm.artworkPath;
    route.lyrics = this.vm.lyrics.snapshot(route.uri);
    // 保留松手瞬间的几何位置作为共享转场起点，转场完成后再复位隐藏的悬浮栏。
    if (!NavController.openAudioPlayer(this.getUIContext(), route, () => this.resetDrag())) {
      this.opening = false;
      this.collapse();
    }
  }

  private canClick(): boolean {
    return !this.dragging && !this.opening && Date.now() >= this.ignoreClickUntil;
  }

  private togglePlayback(): void {
    if (this.canClick()) {
      void PlaybackService.togglePlay();
    }
  }

  private nextTrack(): void {
    if (this.canClick()) {
      void PlaybackService.next();
    }
  }

  aboutToAppear(): void {
    this.vm.lyrics.start();
    this.vm.onChange(PlaybackService.snapshot());
    PlaybackService.addListener(this.vm);
  }

  aboutToDisappear(): void {
    PlaybackService.removeListener(this.vm);
    this.vm.lyrics.dispose();
    this.resetDrag();
  }

  build() {
    if (this.vm.hasCurrent) {
      Column() {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
            .borderRadius(22 + 6 * this.expansion)
            .clip(true)
            .geometryTransition('audio-player-surface', { follow: true })
            .transition(TransitionEffect.OPACITY)
            .id('audio-mini-surface')
          Image(this.vm.artworkPath.length > 0 ? this.vm.artworkPath : $r('app.media.ic_song_big'))
            .width(this.coverSize())
            .height(this.coverSize())
            .borderRadius(6 + 6 * this.expansion)
            .objectFit(ImageFit.Cover)
            .autoResize(false)
            .clip(true)
            .geometryTransition('audio-player-cover', { follow: true })
            .transition(TransitionEffect.OPACITY)
            .id('audio-mini-cover')
            .position({
              x: 12 * (1 - this.expansion) + (this.panelWidth() - this.coverSize()) / 2 * this.expansion,
              y: 12 + 8 * this.expansion
            })
            .fillColor(this.vm.artworkPath.length > 0 ? Color.Transparent : $r('app.color.list_subtitle'))
          Text(this.vm.title)
            .fontSize(13 + 5 * this.expansion)
            .fontColor($r('app.color.list_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(this.textWidth())
            .textAlign(TextAlign.Start)
            .position({ x: 60 - 40 * this.expansion, y: 7 * (1 - this.expansion) + (this.coverSize() + 33) * this.expansion })
            .geometryTransition('audio-player-title', { follow: true })
            .transition(TransitionEffect.OPACITY)
            .id('audio-mini-title')
          Text(this.vm.artist.length > 0 ? this.vm.artist : $r('app.string.unknown_artist'))
            .fontSize(11 + 2 * this.expansion)
            .fontColor($r('app.color.list_subtitle'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(this.textWidth())
            .position({ x: 60 - 40 * this.expansion, y: 25 * (1 - this.expansion) + (this.coverSize() + 54) * this.expansion })
            .geometryTransition('audio-player-artist', { follow: true })
            .transition(TransitionEffect.OPACITY)
            .id('audio-mini-artist')
          if (this.vm.lyrics.line.length > 0) {
            Text(this.vm.lyrics.line)
              .fontSize(11 + 2 * this.expansion)
              .fontColor($r('app.color.orange500'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(this.textWidth())
              .position({ x: 60 - 40 * this.expansion, y: 43 * (1 - this.expansion) + (this.coverSize() + 74) * this.expansion })
              .opacity(this.expansionHeight < 240 ? 1 - this.expansion : 1)
              .geometryTransition('audio-player-lyric', { follow: true })
              .transition(TransitionEffect.OPACITY)
              .id('audio-mini-lyric')
          }
          Button() {
            Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
              .width(32 + 8 * this.expansion)
              .height(32 + 8 * this.expansion)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.list_title'))
              .geometryTransition('audio-player-play', { follow: true })
              .transition(TransitionEffect.OPACITY)
              .id('audio-mini-play')
          }
          .type(ButtonType.Circle)
          .width(this.controlSize())
          .height(this.controlSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .hoverEffect(HoverEffect.None)
          .position({ x: this.controlX(false), y: this.controlY() })
          .accessibilityText(this.vm.state === PlayState.PLAYING ? $r('app.string.pause') : $r('app.string.play'))
          .onClick(() => this.togglePlayback())
          .id('audio-mini-play-button')
          Button() {
            Image($r('app.media.ic_player_next'))
              .width(32 + 8 * this.expansion)
              .height(32 + 8 * this.expansion)
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.list_title'))
              .geometryTransition('audio-player-next', { follow: true })
              .transition(TransitionEffect.OPACITY)
              .id('audio-mini-next')
          }
          .type(ButtonType.Circle)
          .width(this.controlSize())
          .height(this.controlSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .hoverEffect(HoverEffect.None)
          .position({ x: this.controlX(true), y: this.controlY() })
          .accessibilityText($r('app.string.next'))
          .onClick(() => this.nextTrack())
          .id('audio-mini-next-button')
        }
        .width(this.panelWidth())
        .height(this.panelHeight())
        .enabled(!this.opening)
        .onClick(() => { if (this.canClick()) { this.openPlayer(); } })
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart(() => {
              this.dragging = true;
              this.ignoreClickUntil = Date.now() + 350;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.opening) {
                this.expansion = MiniPlayerDrag.progress(event.offsetY, this.expansionHeight);
              }
            })
            .onActionEnd((event: GestureEvent) => {
              this.ignoreClickUntil = Date.now() + 350;
              if (MiniPlayerDrag.shouldOpen(event.offsetY, event.velocityY, this.expansionHeight)) {
                this.openPlayer();
              } else {
                this.collapse();
              }
            })
            .onActionCancel(() => {
              this.ignoreClickUntil = Date.now() + 350;
              this.collapse();
            })
        )
        .onDisAppear(() => { if (!this.opening) { this.resetDrag(); } })
      }
      .width('100%')
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.availableWidth = Number(area.width);
      })
    }
  }
}
