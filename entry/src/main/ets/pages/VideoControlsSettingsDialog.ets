import { AppColors } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';

/**
 * VideoControlsSettingsDialog —— 视频"控制设置"弹窗(BottomSheet)。
 * 对应 VLC Android 的 video_controls 页面;参照 photos/config.png。
 * 9 项 + 一段标题(手势) + 底部 [取消][保存] 双按钮。
 * 打开时从 Settings 读取已保存值,保存时回写全部开关。
 */

@ObservedV2
export class ControlsState {
  @Trace audioBoost: boolean = false;
  @Trace volGesture: boolean = true;
  @Trace brightGesture: boolean = true;
  @Trace swipeSeek: boolean = true;
  @Trace pinchZoom: boolean = true;
  @Trace doubleTapSeek: boolean = true;
  @Trace doubleTapSeekDelay: number = 10;
  @Trace doubleTapPlayPause: boolean = true;
}

type ToggleField = 'audioBoost' | 'volGesture' | 'brightGesture' | 'swipeSeek' | 'pinchZoom' | 'doubleTapPlayPause';

@ComponentV2
export struct VideoControlsSettingsDialog {
  // 主题感知:浅色=白底深字,深色=深底浅字。资源定义见 base/dark element/color.json。
  readonly cSubtle: Resource = $r('app.color.font_light');
  readonly cDivider: Resource = $r('app.color.divider');
  // ── 视觉常量 ───────────────────────────────────────────
  readonly cCancelBg: Resource = $r('app.color.background_default_darker');
  // 默认值:与参考图一致 —— 手势类全开,音频增强默认关。
  @Local state: ControlsState = new ControlsState();

  @Event onClose: () => void = () => {
  };

  /** 保存:回调传出当前全部开关状态。 */
  @Event onConfirm: (s: ControlsState) => void = () => {
  };

  async aboutToAppear(): Promise<void> {
    this.state.audioBoost = await Settings.getBoolean(Settings.KEY_AUDIO_BOOST, false);
    this.state.volGesture = await Settings.getBoolean(Settings.ENABLE_VOLUME_GESTURE, true);
    this.state.brightGesture = await Settings.getBoolean(Settings.ENABLE_BRIGHTNESS_GESTURE, true);
    this.state.swipeSeek = await Settings.getBoolean(Settings.ENABLE_SWIPE_SEEK, true);
    this.state.pinchZoom = await Settings.getBoolean(Settings.ENABLE_SCALE_GESTURE, true);
    this.state.doubleTapSeek = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_SEEK, true);
    this.state.doubleTapSeekDelay = await Settings.getInt(Settings.KEY_VIDEO_DOUBLE_TAP_JUMP_DELAY, 10);
    this.state.doubleTapPlayPause = await Settings.getBoolean(Settings.ENABLE_DOUBLE_TAP_PLAY, true);
  }

  private isChecked(field: ToggleField): boolean {
    switch (field) {
      case 'audioBoost':
        return this.state.audioBoost;
      case 'volGesture':
        return this.state.volGesture;
      case 'brightGesture':
        return this.state.brightGesture;
      case 'swipeSeek':
        return this.state.swipeSeek;
      case 'pinchZoom':
        return this.state.pinchZoom;
      case 'doubleTapPlayPause':
        return this.state.doubleTapPlayPause;
    }
  }

  private toggleField(field: ToggleField): void {
    switch (field) {
      case 'audioBoost':
        this.state.audioBoost = !this.state.audioBoost;
        break;
      case 'volGesture':
        this.state.volGesture = !this.state.volGesture;
        break;
      case 'brightGesture':
        this.state.brightGesture = !this.state.brightGesture;
        break;
      case 'swipeSeek':
        this.state.swipeSeek = !this.state.swipeSeek;
        break;
      case 'pinchZoom':
        this.state.pinchZoom = !this.state.pinchZoom;
        break;
      case 'doubleTapPlayPause':
        this.state.doubleTapPlayPause = !this.state.doubleTapPlayPause;
        break;
    }
  }

  /** 0.5px 分隔线 —— 1px 在低 dpi 屏有时会粗,0.5 更细。 */
  @Builder
  thinDivider() {
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.cDivider)
  }

  /** 复选项行 —— 自绘 checkbox,整行可点。builder 内直接读 this.state 保证响应式。 */
  @Builder
  toggleRow(title: Resource, summary: Resource, field: ToggleField) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.list_title'))
        Text(summary)
          .fontSize(12)
          .fontColor(this.cSubtle)
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 12 })

      Stack() {
        Row()
          .width(20)
          .height(20)
          .borderRadius(4)
          .backgroundColor(this.isChecked(field) ? AppColors.orange500 : Color.Transparent)
          .border({
            width: this.isChecked(field) ? 0 : 1.5,
            color: this.isChecked(field) ? AppColors.orange500 : this.cSubtle,
          })
        if (this.isChecked(field)) {
          Image($r('app.media.ic_check'))
            .width(14).height(14).fillColor('#FFFFFF')
        }
      }
      .width(20).height(20)
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 14,
      bottom: 14
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.toggleField(field))
  }

  /** 不可点的行(灰色 + 不可交互)。 */
  @Builder
  disabledRow(title: Resource, summary: Resource) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.font_light'))
        Text(summary)
          .fontSize(12).fontColor(this.cSubtle)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Stack() {
        Row()
          .width(20).height(20)
          .borderRadius(4)
          .border({ width: 1.5, color: $r('app.color.divider') })
      }
      .width(20).height(20)
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 14,
      bottom: 14
    })
    .alignItems(VerticalAlign.Center)
  }

  /** 「轻按两下可进退」特殊行:左侧可点切换,右侧「10 秒」二级入口(箭头)。 */
  @Builder
  doubleTapSeekRow() {
    Row() {
      Column() {
        Text($r('app.string.double_tap_seek_title'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.list_title'))
        Text($r('app.string.double_tap_seek_summary'))
          .fontSize(12)
          .fontColor(this.cSubtle)
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 12 })

      Row() {
        Text(`${this.state.doubleTapSeekDelay}s`)
          .fontSize(13).fontColor(this.cSubtle)
        Image($r('app.media.ic_arrow_right'))
          .width(16).height(16).fillColor(this.cSubtle)
          .margin({ left: 4 })
      }
      .alignItems(VerticalAlign.Center)
      .padding({ right: 8 })
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 14,
      bottom: 14
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.state.doubleTapSeek = !this.state.doubleTapSeek)
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ── 标题 ──────────────────────────────────────────
          Text($r('app.string.video_controls_settings'))
            .fontSize(19)
            .fontWeight(600)
            .fontColor($r('app.color.list_title'))
            .width('100%')
            .padding({
              left: 20,
              right: 20,
              top: 16,
              bottom: 12
            })
            .textAlign(TextAlign.Start)

          this.thinDivider()

          // ── 音频增强 ──────────────────────────────────────
          this.toggleRow($r('app.string.audio_boost_title'), $r('app.string.audio_boost_summary'), 'audioBoost')
          this.thinDivider()

          // ── 手势段标题(橙色) ─────────────────────────────
          Text($r('app.string.gesture_section'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.orange500)
            .width('100%')
            .padding({
              left: 20,
              right: 20,
              top: 18,
              bottom: 8
            })

          this.toggleRow($r('app.string.volume_gesture_title'), $r('app.string.volume_gesture_summary'), 'volGesture')
          this.thinDivider()

          this.toggleRow($r('app.string.brightness_gesture_title'), $r('app.string.brightness_gesture_summary'), 'brightGesture')
          this.thinDivider()

          this.toggleRow($r('app.string.swipe_seek_title'), $r('app.string.swipe_seek_summary'), 'swipeSeek')
          this.thinDivider()

          this.toggleRow($r('app.string.pinch_zoom_title'), $r('app.string.pinch_zoom_summary'), 'pinchZoom')
          this.thinDivider()

          this.doubleTapSeekRow()
          this.thinDivider()

          this.toggleRow($r('app.string.double_tap_play_pause_title'), $r('app.string.double_tap_play_pause_summary'), 'doubleTapPlayPause')
          this.thinDivider()

          this.disabledRow($r('app.string.screenshot_disabled_title'), $r('app.string.screenshot_disabled_summary'))
          this.thinDivider()

        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // ── 底部 [取消][保存] ────────────────────────────
      Row({ space: 10 }) {
        Button($r('app.string.cancel'))
          .type(ButtonType.Capsule)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.cCancelBg)
          .fontColor($r('app.color.list_title'))
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.onClose())
        Button($r('app.string.save'))
          .type(ButtonType.Capsule)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(AppColors.orange500)
          .fontColor('#FFFFFF')
          .height(46)
          .layoutWeight(1)
          .onClick(() => {
            this.onConfirm(this.state);
            this.onClose();
          })
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        bottom: 24,
        top: 12
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
  }
}
