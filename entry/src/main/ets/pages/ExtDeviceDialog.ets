import { AppColors } from '../common/constants/AppConstants';

/**
 * ExtDeviceDialog —— 外接设备提示弹窗(居中浮层卡片,grey850 #323232 底,圆角 3)。
 * 居中提示文本(device_dialog_message,14fp 白)+ 居中按钮行 [Cancel][Media library scan?][Browse folder](橙文字)。
 * scan==true 显示扫描按钮;open 默认 requestFocus;30s 超时自动关闭;onDestroy finish 宿主 Activity。
 * TODO(契约): browse()→StartActivity(EXTRA_PATH);scan()→MedialibraryUtils.addDevice(path)+StartActivity;cancel()→dismiss。
 *   EXTRA_PATH 常量值不在本页;30s 超时用 setTimeout 由调用方实现。
 */
@ComponentV2
export struct ExtDeviceDialog {
  @Param scan: boolean = false;
  @Event onClose: () => void = () => {
  };
  @Event onBrowse: () => void = () => {
  };
  @Event onScan: () => void = () => {
  };
  @Event onCancel: () => void = () => {
  };

  build() {
    Column() {
      // 提示文本(白字,深底)
      Text($r('app.string.device_dialog_message'))
        .fontSize(14)
        .fontColor(AppColors.white)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ left: 8, right: 8, top: 8 })

      // 按钮行(居中)
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ left: 8, right: 8, top: 8 })
          .onClick(() => this.onCancel())

        if (this.scan) {
          Button($r('app.string.medialibrary_scan'))
            .type(ButtonType.Normal)
            .fontSize(14)
            .fontColor(AppColors.orange500)
            .backgroundColor(AppColors.transparent)
            .margin({ top: 8 })
            .onClick(() => this.onScan())
        }

        Button($r('app.string.browse_folder'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ right: 8, top: 8 })
          .defaultFocus(true)
          .onClick(() => this.onBrowse())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .backgroundColor(AppColors.grey850)
    .borderRadius(3)
    .padding({ top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Center)

    // 注:居中浮层内容卡;由调用方 Stack 居中承载 + #99000000 遮罩。
  }
}
