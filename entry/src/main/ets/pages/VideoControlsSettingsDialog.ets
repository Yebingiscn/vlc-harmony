import { AppColors } from '../common/constants/AppConstants';

/**
 * VideoControlsSettingsDialog —— 视频"控制设置"弹窗(BottomSheet)。
 * 对应 VLC Android 的 video_controls 页面;参照 photos/config.png。
 * 9 项 + 一段标题(手势) + 底部 [取消][保存] 双按钮。
 *
 * 本次需求:**暂不持久化** —— 状态 in-memory,关闭即丢;仅 UI 验证用。
 */

export interface ControlsState {
  audioBoost: boolean;
  volGesture: boolean;
  brightGesture: boolean;
  swipeSeek: boolean;
  pinchZoom: boolean;
  doubleTapSeek: boolean;
  doubleTapSeekDelay: number; // 秒
  doubleTapPlayPause: boolean;
  fastPlayback: boolean;
}

@ComponentV2
export struct VideoControlsSettingsDialog {
  // 主题感知:浅色=白底深字,深色=深底浅字。资源定义见 base/dark element/color.json。
  readonly cSubtle: Resource = $r('app.color.font_light');
  readonly cDivider: Resource = $r('app.color.divider');
  // ── 视觉常量 ───────────────────────────────────────────
  readonly cCancelBg: Resource = $r('app.color.background_default_darker');
  // 默认值:与参考图一致 —— 手势类全开,音频增强和快放默认关。
  @Local state: ControlsState = {
    audioBoost: false,
    volGesture: true,
    brightGesture: true,
    swipeSeek: true,
    pinchZoom: true,
    doubleTapSeek: true,
    doubleTapSeekDelay: 10,
    doubleTapPlayPause: true,
    fastPlayback: false,
  };

  @Event onClose: () => void = () => {
  };

  /** 保存:回调传出当前全部开关状态。 */
  @Event onConfirm: (s: ControlsState) => void = () => {
  };

  /** 0.5px 分隔线 —— 1px 在低 dpi 屏有时会粗,0.5 更细。 */
  @Builder
  thinDivider() {
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.cDivider)
  }

  /** 复选项行 —— 自绘 checkbox(避坑 @Builder 响应式),整行可点。 */
  @Builder
  toggleRow(title: string, summary: string, checked: boolean, onTap: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.list_title'))
        if (summary.length > 0) {
          Text(summary)
            .fontSize(12)
            .fontColor(this.cSubtle)
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 12 })

      Stack() {
        Row()
          .width(20)
          .height(20)
          .borderRadius(4)
          .backgroundColor(checked ? AppColors.orange500 : Color.Transparent)
          .border({
            width: checked ? 0 : 1.5,
            color: checked ? AppColors.orange500 : this.cSubtle,
          })
        if (checked) {
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
    .onClick(() => onTap())
  }

  /** 不可点的行(灰色 + 不可交互)。 */
  @Builder
  disabledRow(title: string, summary: string) {
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
        Text('轻按两下可进退')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.list_title'))
        Text('在屏幕边缘轻按两下,可快进/快退 10 秒')
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
        Text(`${this.state.doubleTapSeekDelay} 秒`)
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
    // 整行可点切换开关;「10 秒」在视觉上是入口但本期不做二级弹窗(用户没要求)。
    .onClick(() => this.state.doubleTapSeek = !this.state.doubleTapSeek)
  }

  build() {
    Column() {
      // ── 标题 ──────────────────────────────────────────
      Text('控制设置')
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
      this.toggleRow('音频增强', '允许音量放大到 200%', this.state.audioBoost,
        () => this.state.audioBoost = !this.state.audioBoost)
      this.thinDivider()

      // ── 手势段标题(橙色) ─────────────────────────────
      Text('手势')
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

      this.toggleRow('音量手势', '在视频回放过程中,通过手势控制音量', this.state.volGesture,
        () => this.state.volGesture = !this.state.volGesture)
      this.thinDivider()

      this.toggleRow('亮度手势', '在视频回放过程中,通过手势控制显示亮度', this.state.brightGesture,
        () => this.state.brightGesture = !this.state.brightGesture)
      this.thinDivider()

      this.toggleRow('滑动可进退', '左右滑动手指可控制进度条', this.state.swipeSeek,
        () => this.state.swipeSeek = !this.state.swipeSeek)
      this.thinDivider()

      this.toggleRow('双指缩放', '用两根手指进行放大/缩小操作', this.state.pinchZoom,
        () => this.state.pinchZoom = !this.state.pinchZoom)
      this.thinDivider()

      this.doubleTapSeekRow()
      this.thinDivider()

      this.toggleRow('轻按两下可播放/暂停', '在屏幕中央轻按两下可播放/暂停', this.state.doubleTapPlayPause,
        () => this.state.doubleTapPlayPause = !this.state.doubleTapPlayPause)
      this.thinDivider()

      this.disabledRow('抓取截图', '已禁用')
      this.thinDivider()

      this.toggleRow('启用「快放」功能', '长按按钮快进/快退,可加快播放速度', this.state.fastPlayback,
        () => this.state.fastPlayback = !this.state.fastPlayback)

      // ── 底部 [取消][保存] ────────────────────────────
      Blank().layoutWeight(1)

      Row({ space: 10 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.cCancelBg)
          .fontColor($r('app.color.list_title'))
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.onClose())
        Button('保存')
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
