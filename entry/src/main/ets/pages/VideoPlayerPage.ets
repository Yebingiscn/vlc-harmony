/**
 * VideoPlayerPage —— 对齐 Android VideoPlayerActivity 的编排层。
 *
 * 手势层（顶层 Transparent Column）：
 * - onTouch：竖滑音量/亮度、横滑 seek、Up 延迟单击显隐 HUD
 * - TapGesture(count:2)：双击播放/暂停或左右跳转
 * - HUD 在手势层之下；顶/底栏 Default 可点，单击死区避免抢按钮
 */
import { NavController } from '../common/data/NavController';
import { AppContext } from '../common/data/AppContext';
import { Settings } from '../common/data/Settings';
import { PlayState } from '../common/models/MediaModels';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import {
  VLC_NAPI_LIBRARY,
  VLC_VIDEO_XCOMPONENT_ID,
  VideoParam,
  VideoPlayerViewModel,
  fmtTime,
} from './videoplayer/VideoPlayerViewModel';
import {
  VideoPlayerOverlayDelegate,
  VideoPlayerOverlayHud,
  VideoPlayerOverlaySheet,
} from './videoplayer/VideoPlayerOverlayDelegate';
import { VideoPlayerResizeDelegate } from './videoplayer/VideoPlayerResizeDelegate';
import { VideoPanMode, VideoTouchDelegate } from './videoplayer/VideoTouchDelegate';
import { VideoDelayDelegate } from './videoplayer/VideoDelayDelegate';
import { VideoPlayerOrientationDelegate } from './videoplayer/VideoPlayerOrientationDelegate';
import { VideoPlayerScreenshotDelegate } from './videoplayer/VideoPlayerScreenshotDelegate';
import { VideoTipsDelegate } from './videoplayer/VideoTipsDelegate';
import { VideoStatsDelegate } from './videoplayer/VideoStatsDelegate';

export {
  VLC_VIDEO_XCOMPONENT_ID,
  VLC_NAPI_LIBRARY,
  VideoPlayItem,
  VideoParam,
  fitContain,
} from './videoplayer/index';

@ComponentV2
export struct VideoPlayerPage {
  @Local vm: VideoPlayerViewModel = new VideoPlayerViewModel();
  @Param param: VideoParam = { uri: '', title: '' };
  /** 勿命名为 overlay：与 CustomComponent.overlay 冲突。 */
  @Local overlayDelegate: VideoPlayerOverlayDelegate = new VideoPlayerOverlayDelegate();

  @Local volumeLevel: number = 0;
  @Local volumeMin: number = 0;
  @Local volumeMax: number = 15;
  /** 窗口亮度 0..1（勿命名 brightness：与组件属性冲突）。 */
  @Local brightnessLevel: number = 0.5;
  @Local brightnessHudVisible: boolean = false;
  @Local volumeHudVisible: boolean = false;
  @Local seekHudVisible: boolean = false;
  @Local seekHudText: string = '';
  private pendingSeekTarget: number = -1;

  private resize: VideoPlayerResizeDelegate = new VideoPlayerResizeDelegate();
  private touch: VideoTouchDelegate = new VideoTouchDelegate();
  private delay: VideoDelayDelegate = new VideoDelayDelegate();
  private orientation: VideoPlayerOrientationDelegate = new VideoPlayerOrientationDelegate();
  private screenshot: VideoPlayerScreenshotDelegate = new VideoPlayerScreenshotDelegate();
  private tips: VideoTipsDelegate = new VideoTipsDelegate();
  private stats: VideoStatsDelegate = new VideoStatsDelegate();
  private surfaceStarted: boolean = false;
  private delegatesBound: boolean = false;
  private mainWindow: window.Window | null = null;
  private brightnessHudTimer: number = -1;
  private volumeHudTimer: number = -1;
  private seekHudTimer: number = -1;
  private saveBrightness: boolean = false;
  private volumeAcc: number = 0;

  aboutToAppear(): void {
    this.bindDelegates();
    this.tips.init();
    void this.initVolumeAndBrightness();
    void this.touch.refreshPrefs();
    this.overlayDelegate.resetHudTimer();
  }

  aboutToDisappear(): void {
    if (this.brightnessHudTimer !== -1) {
      clearTimeout(this.brightnessHudTimer);
      this.brightnessHudTimer = -1;
    }
    if (this.volumeHudTimer !== -1) {
      clearTimeout(this.volumeHudTimer);
      this.volumeHudTimer = -1;
    }
    if (this.seekHudTimer !== -1) {
      clearTimeout(this.seekHudTimer);
      this.seekHudTimer = -1;
    }
    void this.restoreSystemBrightnessIfNeeded();
    this.touch.clearTouchAction();
    this.overlayDelegate.onDestroy();
    this.stats.stop();
    this.screenshot.hide();
    this.tips.close();
    this.vm.release();
  }

  private async initVolumeAndBrightness(): Promise<void> {
    try {
      const volMgr = audio.getAudioManager().getVolumeManager();
      const group = await volMgr.getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
      this.volumeMin = await group.getMinVolume(audio.AudioVolumeType.MEDIA);
      this.volumeMax = await group.getMaxVolume(audio.AudioVolumeType.MEDIA);
      this.volumeLevel = await group.getVolume(audio.AudioVolumeType.MEDIA);
      this.volumeAcc = this.volumeLevel;
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] init volume failed %{public}s', JSON.stringify(e));
    }
    try {
      this.mainWindow = await window.getLastWindow(AppContext.get());
      this.saveBrightness = await Settings.getBoolean(Settings.SAVE_BRIGHTNESS, false);
      if (this.saveBrightness) {
        const saved: number = await Settings.getFloat(Settings.BRIGHTNESS_VALUE, 0.5);
        this.brightnessLevel = Math.max(0, Math.min(1, saved));
        await this.mainWindow.setWindowBrightness(this.brightnessLevel);
      } else {
        this.brightnessLevel = 0.5;
      }
      await this.mainWindow.setWindowKeepScreenOn(true);
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] init brightness failed %{public}s', JSON.stringify(e));
    }
  }

  private async restoreSystemBrightnessIfNeeded(): Promise<void> {
    if (this.mainWindow === null) {
      return;
    }
    try {
      await this.mainWindow.setWindowKeepScreenOn(false);
      if (!this.saveBrightness) {
        await this.mainWindow.setWindowBrightness(-1);
      }
    } catch (_e) {
      // ignore
    }
  }

  private bindDelegates(): void {
    if (this.delegatesBound) {
      return;
    }
    this.delegatesBound = true;
    this.vm.attachResize(this.resize);
    this.overlayDelegate.bind(this.vm, {
      onOrientation: (): void => {
        this.orientation.displayOrientation();
      },
      onAspectRatio: (): void => {
        this.resize.showResizeOverlay();
      },
    });
    this.touch.bind({
      doPlayPause: (): void => {
        this.vm.toggle();
        this.overlayDelegate.showOverlay();
      },
      onSingleTap: (): void => {
        this.overlayDelegate.toggleOverlay();
      },
      seekDelta: (deltaMs: number): void => {
        const next: number = this.vm.position + deltaMs;
        const clamped: number = this.vm.duration > 0
          ? Math.max(0, Math.min(this.vm.duration, next))
          : Math.max(0, next);
        this.vm.seekTo(clamped);
        this.overlayDelegate.showOverlay();
      },
      getContainerWidth: (): number => {
        return this.vm.containerWidth;
      },
      getContainerHeight: (): number => {
        return this.vm.containerHeight;
      },
      getPosition: (): number => {
        return this.vm.position;
      },
      getDuration: (): number => {
        return this.vm.duration;
      },
      isHudVisible: (): boolean => {
        return this.vm.hudVisible;
      },
      onPanBegan: (): void => {
        this.overlayDelegate.hideOverlay();
        this.volumeAcc = this.volumeLevel;
      },
      onVolumePan: (deltaNorm: number): void => {
        const span: number = Math.max(1, this.volumeMax - this.volumeMin);
        this.volumeAcc = Math.max(this.volumeMin, Math.min(this.volumeMax, this.volumeAcc + deltaNorm * span));
        const next: number = Math.round(this.volumeAcc);
        if (next !== this.volumeLevel) {
          this.volumeLevel = next;
          hilog.info(0x0001, 'VLC', '[VLC] volumeLevel -> %{public}d', next);
        }
        this.volumeHudVisible = true;
        this.brightnessHudVisible = false;
        this.seekHudVisible = false;
        this.armVolumeHudTimer();
      },
      onBrightnessPan: (deltaNorm: number): void => {
        this.brightnessLevel = Math.max(0, Math.min(1, this.brightnessLevel + deltaNorm));
        this.brightnessHudVisible = true;
        this.volumeHudVisible = false;
        this.seekHudVisible = false;
        void this.applyBrightness(this.brightnessLevel);
        hilog.info(0x0001, 'VLC', '[VLC] brightnessLevel -> %{public}s',
          this.brightnessLevel.toFixed(2));
        this.armBrightnessHudTimer();
      },
      onSeekPan: (jumpMs: number, targetMs: number): void => {
        this.pendingSeekTarget = targetMs;
        const sign: string = jumpMs >= 0 ? '+' : '';
        this.seekHudText = `${sign}${fmtTime(Math.abs(jumpMs))} (${fmtTime(targetMs)})`;
        this.seekHudVisible = true;
        this.volumeHudVisible = false;
        this.brightnessHudVisible = false;
        if (this.seekHudTimer !== -1) {
          clearTimeout(this.seekHudTimer);
          this.seekHudTimer = -1;
        }
      },
      onPanEnded: (mode: VideoPanMode): void => {
        if (mode === VideoPanMode.Brightness && this.saveBrightness) {
          void Settings.put(Settings.BRIGHTNESS_VALUE, this.brightnessLevel);
        }
        if (mode === VideoPanMode.Brightness) {
          this.armBrightnessHudTimer();
        }
        if (mode === VideoPanMode.Volume) {
          this.volumeAcc = this.volumeLevel;
          this.armVolumeHudTimer();
        }
        if (mode === VideoPanMode.Seek) {
          if (this.pendingSeekTarget >= 0) {
            this.vm.seekTo(this.pendingSeekTarget);
            hilog.info(0x0001, 'VLC', '[VLC] swipe seek -> %{public}d', this.pendingSeekTarget);
            this.pendingSeekTarget = -1;
          }
          this.armSeekHudTimer();
        }
      },
    });
  }

  private async applyBrightness(value: number): Promise<void> {
    try {
      if (this.mainWindow === null) {
        this.mainWindow = await window.getLastWindow(AppContext.get());
      }
      await this.mainWindow.setWindowBrightness(value);
    } catch (e) {
      hilog.warn(0x0001, 'VLC', '[VLC] setWindowBrightness failed %{public}s', JSON.stringify(e));
    }
  }

  private armBrightnessHudTimer(): void {
    if (this.brightnessHudTimer !== -1) {
      clearTimeout(this.brightnessHudTimer);
    }
    this.brightnessHudTimer = setTimeout(() => {
      this.brightnessHudTimer = -1;
      this.brightnessHudVisible = false;
    }, 1200);
  }

  private armVolumeHudTimer(): void {
    if (this.volumeHudTimer !== -1) {
      clearTimeout(this.volumeHudTimer);
    }
    this.volumeHudTimer = setTimeout(() => {
      this.volumeHudTimer = -1;
      this.volumeHudVisible = false;
    }, 1200);
  }

  private armSeekHudTimer(): void {
    if (this.seekHudTimer !== -1) {
      clearTimeout(this.seekHudTimer);
    }
    this.seekHudTimer = setTimeout(() => {
      this.seekHudTimer = -1;
      this.seekHudVisible = false;
    }, 1200);
  }

  build() {
    NavDestination() {
      /**
       * z 序对齐 LiveStreaming FullScreenLayer（自下而上）：
       * XComponent → 单击层 → HUD → Transparent 手势层(最顶=CanvasLike)
       * 日志证实：手势在 HUD 之下时无任何 pan/tap 回调。
       */
      Stack({ alignContent: Alignment.Center }) {
        XComponent({
          id: VLC_VIDEO_XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: VLC_NAPI_LIBRARY,
        })
          .onLoad(() => {
            if (this.surfaceStarted) {
              return;
            }
            this.surfaceStarted = true;
            this.vm.setup(this.param, VLC_VIDEO_XCOMPONENT_ID);
          })
          .onDestroy(() => {
            this.vm.cleanUI();
            this.surfaceStarted = false;
          })
          .width(this.vm.surfaceWidth > 0 ? this.vm.surfaceWidth : '100%')
          .height(this.vm.surfaceHeight > 0 ? this.vm.surfaceHeight : '100%')
          .hitTestBehavior(HitTestMode.None)

        AVVolumePanel({ volumeLevel: this.volumeLevel })
          .hitTestBehavior(HitTestMode.None)

        if (this.brightnessHudVisible) {
          this.brightnessHud()
        }
        if (this.volumeHudVisible) {
          this.volumeHud()
        }
        if (this.seekHudVisible) {
          this.seekHud()
        }

        if (this.vm.state === PlayState.IDLE) {
          LoadingProgress()
            .width(48).height(48).color('#FFFFFF')
            .hitTestBehavior(HitTestMode.None)
        } else if (this.vm.state === PlayState.ERROR) {
          Column() {
            Text($r('app.string.encountered_error_message'))
              .fontSize(16).fontColor('#FFFFFF').textAlign(TextAlign.Center)
            if (this.vm.errorMsg !== '') {
              Text(this.vm.errorMsg)
                .fontSize(12).fontColor('#9E9E9E').margin({ top: 8 }).textAlign(TextAlign.Center)
            }
          }
          .padding(24)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        }

        // ② HUD 在手势层之下
        if (this.vm.hudVisible) {
          VideoPlayerOverlayHud({ overlayDelegate: this.overlayDelegate, vm: this.vm })
        }

        // ③ 最顶手势层（对齐 CanvasLike 最后声明 + Transparent）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#01000000')
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch((event: TouchEvent) => {
            // 竖滑走 onTouch（日志证实 PanGesture 不触发；Move 正常）
            this.touch.onTouchEvent(event);
          })
          .gesture(
            // 双击；单击由 onTouch Up 延迟触发（见 VideoTouchDelegate）
            TapGesture({ count: 2 })
              .onAction((event: GestureEvent) => {
                let x: number = 0;
                if (event.fingerList.length > 0) {
                  x = event.fingerList[0].localX;
                }
                this.touch.onDoubleTap(x);
              })
          )
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onAreaChange((_old: Area, area: Area) => {
        this.vm.onContainerSize(Number(area.width), Number(area.height));
      })
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      if (this.overlayDelegate.sheetOpen) {
        this.overlayDelegate.closeSheet();
        return true;
      }
      if (this.delay.playbackSetting.length > 0) {
        this.delay.endPlaybackSetting();
        return true;
      }
      if (this.orientation.isShowing) {
        this.orientation.hideOrientationOverlay();
        return true;
      }
      if (this.resize.isShowing) {
        this.resize.hideResizeOverlay();
        return true;
      }
      this.vm.leaveEarly();
      NavController.pop();
      return true;
    })
    .bindSheet(this.overlayDelegate.sheetOpen, this.sheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: $r('app.color.background_default'),
      onDisappear: () => {
        this.overlayDelegate.closeSheet();
        this.overlayDelegate.resetHudTimer();
      },
    })
  }

  @Builder
  seekHud() {
    Column({ space: 6 }) {
      Text('进度')
        .fontSize(14).fontColor('#FFFFFF')
      Text(this.seekHudText)
        .fontSize(16).fontColor('#FF8800').fontWeight(FontWeight.Medium)
    }
    .padding({ left: 24, right: 24, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  brightnessHud() {
    Column({ space: 8 }) {
      Text('亮度')
        .fontSize(14).fontColor('#FFFFFF')
      Progress({
        value: this.brightnessLevel * 100,
        total: 100,
        type: ProgressType.Linear,
      })
        .width(140)
        .height(4)
        .color('#FF8800')
        .backgroundColor('#61FFFFFF')
      Text(`${Math.round(this.brightnessLevel * 100)}%`)
        .fontSize(12).fontColor('#FFFFFF')
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  volumeHud() {
    Column({ space: 8 }) {
      Text('音量')
        .fontSize(14).fontColor('#FFFFFF')
      Progress({
        value: this.volumeMax > this.volumeMin
          ? ((this.volumeLevel - this.volumeMin) * 100 / (this.volumeMax - this.volumeMin))
          : 0,
        total: 100,
        type: ProgressType.Linear,
      })
        .width(140)
        .height(4)
        .color('#FF8800')
        .backgroundColor('#61FFFFFF')
      Text(`${this.volumeLevel}`)
        .fontSize(12).fontColor('#FFFFFF')
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor('#99000000')
    .borderRadius(12)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  sheetBuilder() {
    VideoPlayerOverlaySheet({ overlayDelegate: this.overlayDelegate })
  }
}
