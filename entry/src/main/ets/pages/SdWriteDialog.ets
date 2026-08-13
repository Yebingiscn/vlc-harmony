/**
 * SdWriteDialog —— SD 卡写入授权引导静态图示弹窗。
 * 仅一张 img_tips_sdcard 图(320×420vp,objectFit=Contain,高质量插值),无按钮/无文字/无状态/无业务逻辑。
 * 关闭由宿主点击蒙层或返回键触发(原生 dialog 默认行为)。
 */
@ComponentV2
export struct SdWriteDialog {
  @Event onClose: () => void = () => {
  };

  build() {
    Column() {
      Image($r('app.media.img_tips_sdcard'))
        .width(320)
        .height(420)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .onClick(() => this.onClose())
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
