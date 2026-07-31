/**
 * VideoPlayerPage —— 对齐 Android VideoPlayerActivity 的编排层。
 * HUD / 缩放 / 手势等能力下沉到 pages/videoplayer/*Delegate。
 */
import { NavController } from '../common/data/NavController';
import { PlayState } from '../common/models/MediaModels';
import {
  VLC_NAPI_LIBRARY,
  VLC_VIDEO_XCOMPONENT_ID,
  VideoParam,
  VideoPlayerViewModel,
} from './videoplayer/VideoPlayerViewModel';
import {
  VideoPlayerOverlayDelegate,
  VideoPlayerOverlayHud,
  VideoPlayerOverlaySheet,
} from './videoplayer/VideoPlayerOverlayDelegate';
import { VideoPlayerResizeDelegate } from './videoplayer/VideoPlayerResizeDelegate';
import { VideoTouchDelegate } from './videoplayer/VideoTouchDelegate';
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

  private resize: VideoPlayerResizeDelegate = new VideoPlayerResizeDelegate();
  private touch: VideoTouchDelegate = new VideoTouchDelegate();
  private delay: VideoDelayDelegate = new VideoDelayDelegate();
  private orientation: VideoPlayerOrientationDelegate = new VideoPlayerOrientationDelegate();
  private screenshot: VideoPlayerScreenshotDelegate = new VideoPlayerScreenshotDelegate();
  private tips: VideoTipsDelegate = new VideoTipsDelegate();
  private stats: VideoStatsDelegate = new VideoStatsDelegate();
  private surfaceStarted: boolean = false;
  private delegatesBound: boolean = false;

  aboutToAppear(): void {
    this.bindDelegates();
    this.tips.init();
    void this.touch.refreshPrefs();
    this.overlayDelegate.resetHudTimer();
  }

  aboutToDisappear(): void {
    this.overlayDelegate.onDestroy();
    this.stats.stop();
    this.screenshot.hide();
    this.tips.close();
    this.vm.release();
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
    // 对齐 Android touchDelegate：单击 HUD、双击暂停/seek
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
    });
  }

  build() {
    NavDestination() {
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

        // 全屏手势层：单击显隐 HUD；双击中间暂停/播放，左右边缘快退/快进（对齐 Android）。
        Column()
          .width('100%')
          .height('100%')
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              TapGesture({ count: 2 })
                .onAction((event: GestureEvent) => {
                  let x: number = 0;
                  if (event.fingerList.length > 0) {
                    x = event.fingerList[0].localX;
                  }
                  this.touch.onDoubleTap(x);
                }),
              TapGesture({ count: 1 })
                .onAction(() => {
                  this.touch.onSingleTap();
                })
            )
          )

        if (this.vm.state === PlayState.IDLE) {
          LoadingProgress().width(48).height(48).color('#FFFFFF')
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
        }

        if (this.vm.hudVisible) {
          VideoPlayerOverlayHud({ overlayDelegate: this.overlayDelegate, vm: this.vm })
        }
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
  sheetBuilder() {
    VideoPlayerOverlaySheet({ overlayDelegate: this.overlayDelegate })
  }
}
