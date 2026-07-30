import { AppColors } from '../common/constants/AppConstants';

/**
 * DeviceDialog —— 外接存储设备插入提示弹窗(居中浮层卡片,白底圆角 12)。
 * 居中提示文本(device_dialog_message,14fp 黑)+ 底部 [Cancel][Media library scan?][Browse folder] 文字按钮(橙 #FF8800)。
 * scan==true 时显示扫描按钮;30s 无操作自动关闭。
 * TODO(契约): browse()→push StartActivity(EXTRA_PATH=path);scan()→MedialibraryUtils.addDevice(path)+StartActivity;cancel()→dismiss+finish 宿主。
 *   EXTRA_PATH 常量值不在本页;30s 超时用 setTimeout 在调用方实现。
 */
@ComponentV2
export struct DeviceDialog {
  @Param scan: boolean = false;
  @Event onClose: () => void = () => {};
  @Event onBrowse: () => void = () => {};
  @Event onScan: () => void = () => {};
  @Event onCancel: () => void = () => {};

  build() {
    Column() {
      // 提示文本
      Text($r('app.string.device_dialog_message'))
        .fontSize(14)
        .fontColor(AppColors.black)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ left: 8, right: 8, top: 8 })

      // 按钮行:Cancel | (Scan) | Browse
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .height(36)
          .padding({ left: 12, right: 12 })
          .margin({ left: 8, right: 8 })
          .onClick(() => this.onCancel())

        if (this.scan) {
          Button($r('app.string.medialibrary_scan'))
            .type(ButtonType.Normal)
            .fontSize(14)
            .fontColor(AppColors.orange500)
            .backgroundColor(AppColors.transparent)
            .height(36)
            .padding({ left: 12, right: 12 })
            .onClick(() => this.onScan())
        }

        Button($r('app.string.browse_folder'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .height(36)
          .padding({ left: 12, right: 12 })
          .margin({ right: 8, top: 8 })
          .onClick(() => this.onBrowse())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 8, bottom: 8 })
    }
    .width('86%')
    .backgroundColor(AppColors.white)
    .borderRadius(12)
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
    // 注:本组件为居中浮层内容卡(非贴底 BottomSheet);由调用方 bindSheet/Stack 居中承载 + 遮罩。
  }
}
