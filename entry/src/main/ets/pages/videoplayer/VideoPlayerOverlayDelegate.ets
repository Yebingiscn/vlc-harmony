import { UiFeedback } from '../../common/utils/UiFeedback';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../../common/data/NavController';
import { PlaybackService } from '../../common/data/PlaybackService';
import { Settings } from '../../common/data/Settings';
import { PlayState } from '../../common/models/MediaModels';
import { JumpToTimeDialog } from '../JumpToTimeDialog';
import { SleepTimerDialog } from '../SleepTimerDialog';
import { SelectChapterDialog } from '../SelectChapterDialog';
import { VideoTracksDialog } from '../VideoTracksDialog';
import { RenderersDialog } from '../RenderersDialog';
import {
  buildPlayerAdvancedOptions,
  PlayerAdvancedOptionId,
  PlayerAdvancedOptions,
} from '../../common/components/PlayerAdvancedOptions';
import {
  buildVideoPlayerBottomActions,
  VideoPlayerBottomAction,
  VideoPlayerBottomActionId,
} from './VideoPlayerControls';
import { VideoPlayerViewModel } from './VideoPlayerViewModel';
import { fmtTime } from './VideoPlayerModels';

/** Page 注入的底部动作扩展（orientation / aspectRatio）。 */
export interface VideoPlayerOverlayActions {
  onOrientation: () => void;
  onAspectRatio: () => void;
}

/**
 * 睡眠倒计时时长 → 中文可读文案。
 * 不把分钟换算成小时 —— 与弹窗预览保持一致。
 */
function fmtSleepSpan(ms: number): string {
  const totalMin: number = Math.floor(ms / 60000);
  const h: number = Math.floor(totalMin / 60);
  const m: number = totalMin % 60;
  if (h > 0 && m > 0) {
    return `${h}小时${m}分`;
  }
  if (h > 0) {
    return `${h}小时`;
  }
  return `${m}分钟`;
}

/**
 * VideoPlayerOverlayDelegate —— 对齐 Android VideoPlayerOverlayDelegate。
 * 负责 HUD 显隐计时、seek、sheet/睡眠定时、高级菜单编排。
 */
@ObservedV2
export class VideoPlayerOverlayDelegate {
  @Trace seeking: boolean = false;
  @Trace seekPercent: number = 0;
  private lastSliderSeekMs: number = -1;
  private lastSliderSeekAt: number = 0;
  @Trace sleepArmed: boolean = false;
  @Trace sheetOpen: boolean = false;
  @Trace sheetKind: string = '';
  @Trace advancedOptionsOpen: boolean = false;
  sleepMillis: number = 0;
  sleepWaitMediaEnd: boolean = false;
  sleepResetOnInteraction: boolean = false;
  private hudTimer: number = -1;
  private sleepTimer: number = -1;
  private pendingAdvancedAction: PlayerAdvancedOptionId | null = null;
  private vm: VideoPlayerViewModel | null = null;
  private actions: VideoPlayerOverlayActions | null = null;

  bind(vm: VideoPlayerViewModel, actions: VideoPlayerOverlayActions): void {
    this.vm = vm;
    this.actions = actions;
  }

  /** 对齐 Android showOverlay。 */
  showOverlay(): void {
    this.resetHudTimer();
  }

  /** 对齐 Android hideOverlay。 */
  hideOverlay(): void {
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    this.requireVm().hudVisible = false;
  }

  /** 对齐 Android toggleOverlay / 点击画面。 */
  toggleOverlay(): void {
    if (this.requireVm().hudVisible) {
      this.hideOverlay();
    } else {
      this.showOverlay();
    }
  }

  openOptions(): void {
    this.advancedOptionsOpen = true;
    this.resetHudTimer();
  }

  openSub(kind: string): void {
    this.sheetKind = kind;
    this.sheetOpen = true;
  }

  closeSheet(): void {
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  onJumpConfirm(timeMs: number): void {
    this.requireVm().seekTo(timeMs);
    this.closeSheet();
  }

  onSleepConfirm(millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean): void {
    this.clearSleepTimer();
    this.sleepMillis = millis;
    this.sleepWaitMediaEnd = waitForMediaEnd;
    this.sleepResetOnInteraction = resetOnInteraction;
    this.armSleepTimer();
    Settings.put(Settings.SLEEP_TIMER_MILLIS, millis);
    Settings.put(Settings.SLEEP_TIMER_WAIT_MEDIA_END, waitForMediaEnd);
    Settings.put(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, resetOnInteraction);
    hilog.info(0x0001, 'VLC', '[VLC] sleep timer armed: %{public}d ms wait=%{public}s reset=%{public}s',
      millis, String(waitForMediaEnd), String(resetOnInteraction));
    const span: string = fmtSleepSpan(millis);
    UiFeedback.showToast({
      message: waitForMediaEnd
        ? $r('app.string.sleep_timer_set_wait', span)
        : $r('app.string.sleep_timer_set', span),
    });
    this.closeSheet();
  }

  armSleepTimer(): void {
    if (this.sleepMillis <= 0) {
      return;
    }
    if (this.sleepTimer !== -1) {
      clearTimeout(this.sleepTimer);
    }
    this.sleepArmed = true;
    this.sleepTimer = setTimeout(() => {
      this.sleepTimer = -1;
      if (this.sleepWaitMediaEnd) {
        this.requireVm().setStopAfterCurrent(true);
      } else {
        this.requireVm().pauseForSleep();
        this.sleepArmed = false;
        UiFeedback.showToast({ message: $r('app.string.sleep_timer_fired') });
      }
    }, this.sleepMillis);
  }

  clearSleepTimer(fromUser: boolean = false): void {
    const wasArmed: boolean = this.sleepArmed;
    if (this.sleepTimer !== -1) {
      clearTimeout(this.sleepTimer);
      this.sleepTimer = -1;
    }
    this.sleepArmed = false;
    if (this.vm !== null) {
      this.vm.setStopAfterCurrent(false);
    }
    if (fromUser && wasArmed) {
      UiFeedback.showToast({ message: $r('app.string.sleep_timer_cancelled') });
    }
  }

  onChapterSelect(index: number): void {
    PlaybackService.getInstance().setChapter(index);
    this.closeSheet();
  }

  onTrackSelect(id: number, type: string): void {
    const svc = PlaybackService.getInstance();
    if (type === 'audio') {
      svc.setAudioTrack(id);
    } else if (type === 'spu') {
      svc.setSpuTrack(id);
    } else if (type === 'video') {
      svc.setVideoTrack(id);
    }
    this.closeSheet();
  }

  onRendererConnect(id: number): void {
    PlaybackService.getInstance().setRenderer(id);
    this.closeSheet();
  }

  onRendererDisconnect(): void {
    PlaybackService.getInstance().clearRenderer();
    this.closeSheet();
  }

  /** 显示 HUD 并重置 4s 自动隐藏计时。 */
  resetHudTimer(): void {
    if (this.sleepResetOnInteraction && this.sleepArmed) {
      this.armSleepTimer();
    }
    const vm = this.requireVm();
    vm.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      this.hudTimer = -1;
      if (vm.state === PlayState.PLAYING && !this.seeking && !this.sheetOpen && !this.advancedOptionsOpen) {
        vm.hudVisible = false;
      }
    }, 4000);
  }

  displayPosition(): number {
    const vm = this.requireVm();
    if (this.seeking && vm.duration > 0) {
      return Math.floor(vm.duration * this.seekPercent / 100);
    }
    return vm.position;
  }

  commitSliderSeek(percent: number): void {
    const vm = this.requireVm();
    const targetMs: number = Math.floor(vm.duration * percent / 100);
    const now: number = Date.now();
    if (targetMs === this.lastSliderSeekMs && now - this.lastSliderSeekAt < 250) {
      return;
    }
    this.lastSliderSeekMs = targetMs;
    this.lastSliderSeekAt = now;
    vm.seekTo(targetMs);
  }

  bottomActionIcon(action: VideoPlayerBottomAction): Resource {
    if (action.id === 'play') {
      return this.requireVm().state === PlayState.PLAYING
        ? $r('app.media.ic_pause_player')
        : $r('app.media.ic_play_player');
    }
    return action.icon;
  }

  onBottomAction(id: VideoPlayerBottomActionId): void {
    if (id === 'tracks') {
      this.openSub('tracks');
    } else if (id === 'play') {
      this.requireVm().toggle();
    } else if (id === 'orientation') {
      if (this.actions !== null) {
        this.actions.onOrientation();
      }
    } else if (id === 'aspectRatio') {
      if (this.actions !== null) {
        this.actions.onAspectRatio();
      }
    }
    this.resetHudTimer();
  }

  runPendingAdvancedAction(): void {
    const id: PlayerAdvancedOptionId | null = this.pendingAdvancedAction;
    this.pendingAdvancedAction = null;
    if (id === null) {
      return;
    }
    if (id === 'sleep') {
      this.openSub('sleep');
      return;
    }
    UiFeedback.showToast({ message: '该功能暂未实现' });
  }

  setPendingAdvancedAction(id: PlayerAdvancedOptionId): void {
    this.pendingAdvancedAction = id;
    this.advancedOptionsOpen = false;
  }

  onDestroy(): void {
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    this.clearSleepTimer();
  }

  leaveAndPop(): void {
    this.requireVm().leaveEarly();
    NavController.pop();
  }

  private requireVm(): VideoPlayerViewModel {
    return this.vm as VideoPlayerViewModel;
  }
}

/**
 * HUD 顶栏 + 底栏组件（仅在 hudVisible 时由 Page 挂载）。
 */
@ComponentV2
export struct VideoPlayerOverlayHud {
  /** 勿命名为 overlay：与 CustomComponent.overlay 冲突。 */
  @Param @Require overlayDelegate: VideoPlayerOverlayDelegate;
  @Param @Require vm: VideoPlayerViewModel;

  build() {
    Column() {
      this.topBar()
      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    // Transparent：顶/底栏按钮可点；中间空白穿透到下方 tap 层，用于隐藏 HUD。
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  topBar() {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(24).height(24).fillColor('#FFFFFF')
        .onClick(() => this.overlayDelegate.leaveAndPop())
      Text(this.vm.title)
        .fontSize(18)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
        .margin({ left: 12, right: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.overlayDelegate.sleepArmed) {
        Image($r('app.media.ic_sleep'))
          .width(22)
          .height(22)
          .fillColor('#FF8800')
          .margin({ right: 16 })
          .onClick(() => {
            this.overlayDelegate.clearSleepTimer(true);
            this.overlayDelegate.resetHudTimer();
          })
      }
      Image($r('app.media.ic_player_more'))
        .width(24).height(24).fillColor('#FFFFFF')
        .onClick(() => {
          this.overlayDelegate.resetHudTimer();
          this.overlayDelegate.openOptions();
        })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 44,
      bottom: 16
    })
    .alignItems(VerticalAlign.Center)
    .linearGradient({ angle: 180, colors: [['#cb000000', 0.0], ['#00000000', 1.0]] })
    // 顶栏必须 Default，否则 Transparent 父层会把返回/菜单点透下去
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        Text(fmtTime(this.overlayDelegate.displayPosition()))
          .fontSize(12).fontColor('#FFFFFF').width(52)
        Slider({
          value: this.overlayDelegate.seeking
            ? this.overlayDelegate.seekPercent
            : (this.vm.duration > 0 ? this.vm.position * 100 / this.vm.duration : 0),
          min: 0,
          max: 100,
          step: 0.1,
          style: SliderStyle.OutSet,
        })
          .layoutWeight(1)
          .blockColor('#FF8800')
          .selectedColor('#FF8800')
          .trackColor('#61FFFFFF')
          .enabled(this.vm.duration > 0)
          .onChange((v: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin) {
              this.overlayDelegate.seeking = true;
              this.overlayDelegate.seekPercent = v;
            } else if (mode === SliderChangeMode.Moving) {
              this.overlayDelegate.seekPercent = v;
            } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.overlayDelegate.seekPercent = v;
              this.overlayDelegate.seeking = false;
              this.overlayDelegate.commitSliderSeek(v);
            }
            this.overlayDelegate.resetHudTimer();
          })
        Text(fmtTime(this.vm.duration))
          .fontSize(12).fontColor('#FFFFFF').width(52).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Repeat(buildVideoPlayerBottomActions()).each((actionRepeatItem: RepeatItem<VideoPlayerBottomAction>) => {
          if (actionRepeatItem.item.id === 'advanced') {
            Image(actionRepeatItem.item.icon)
              .width(32)
              .height(32)
              .fillColor('#FFFFFF')
              .onClick(() => this.overlayDelegate.openOptions())
              .bindMenu(this.overlayDelegate.advancedOptionsOpen!!, this.advancedOptionsMenu(), {
                placement: Placement.TopRight,
                showInSubWindow: true,
                backgroundColor: '#FFFFFF',
                onDisappear: () => this.overlayDelegate.runPendingAdvancedAction(),
              })
          } else {
            Image(this.overlayDelegate.bottomActionIcon(actionRepeatItem.item))
              .width(actionRepeatItem.item.id === 'play' ? 56 : 32)
              .height(actionRepeatItem.item.id === 'play' ? 56 : 32)
              .fillColor('#FFFFFF')
              .onClick(() => this.overlayDelegate.onBottomAction(actionRepeatItem.item.id))
          }
        }).key((action: VideoPlayerBottomAction): string => action.id)
      }
      .width('100%')
      .padding({
        left: 18,
        right: 18,
        top: 12,
        bottom: 12
      })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .linearGradient({ angle: 180, colors: [['#00000000', 0.0], ['#cb000000', 1.0]] })
    // 底栏必须 Default，否则 Transparent 父层会把进度条/按钮点透下去
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  advancedOptionsMenu() {
    PlayerAdvancedOptions({
      items: buildPlayerAdvancedOptions('video'),
      onSelect: (id: PlayerAdvancedOptionId): void => {
        this.overlayDelegate.setPendingAdvancedAction(id);
      },
    })
  }
}

/**
 * bindSheet 内容：按 sheetKind 路由到各 Dialog。
 */
@ComponentV2
export struct VideoPlayerOverlaySheet {
  @Param @Require overlayDelegate: VideoPlayerOverlayDelegate;

  build() {
    Column() {
      if (this.overlayDelegate.sheetKind === '') {
        this.optionsList()
      } else if (this.overlayDelegate.sheetKind === 'jump') {
        JumpToTimeDialog({
          onClose: () => this.overlayDelegate.closeSheet(),
          onConfirm: (timeMs: number) => this.overlayDelegate.onJumpConfirm(timeMs),
        }).width('100%')
      } else if (this.overlayDelegate.sheetKind === 'sleep') {
        SleepTimerDialog({
          initialMillis: this.overlayDelegate.sleepMillis,
          initialWaitMediaEnd: this.overlayDelegate.sleepWaitMediaEnd,
          initialResetOnInteraction: this.overlayDelegate.sleepResetOnInteraction,
          onClose: () => this.overlayDelegate.closeSheet(),
          onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) =>
          this.overlayDelegate.onSleepConfirm(millis, waitForMediaEnd, resetOnInteraction),
        }).width('100%')
      } else if (this.overlayDelegate.sheetKind === 'chapter') {
        SelectChapterDialog({
          onClose: () => this.overlayDelegate.closeSheet(),
          onSelectChapter: (index: number) => this.overlayDelegate.onChapterSelect(index),
        }).width('100%')
      } else if (this.overlayDelegate.sheetKind === 'tracks') {
        VideoTracksDialog({
          onClose: () => this.overlayDelegate.closeSheet(),
          onTrackSelect: (id: number, type: string) => this.overlayDelegate.onTrackSelect(id, type),
        }).width('100%')
      } else if (this.overlayDelegate.sheetKind === 'renderer') {
        RenderersDialog({
          onClose: () => this.overlayDelegate.closeSheet(),
          onConnect: (id: number) => this.overlayDelegate.onRendererConnect(id),
          onDisconnect: () => this.overlayDelegate.onRendererDisconnect(),
        }).width('100%')
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
  }

  @Builder
  optionsList() {
    Column() {
      Text($r('app.string.more'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, right: 16 })
        .height(56)
        .textAlign(TextAlign.Start)

      this.optionRow('Jump to time', () => this.overlayDelegate.openSub('jump'))
      this.optionRow('Sleep timer', () => this.overlayDelegate.openSub('sleep'))
      this.optionRow($r('app.string.go_to_chapter'), () => this.overlayDelegate.openSub('chapter'))
      this.optionRow('Audio & Subtitles tracks', () => this.overlayDelegate.openSub('tracks'))
      this.optionRow('Displays', () => this.overlayDelegate.openSub('renderer'))
    }
    .width('100%')
    .padding({ bottom: 16 })
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  optionRow(title: ResourceStr, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(20).height(20)
        .fillColor('#9E9E9E')
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onTap())
  }
}
