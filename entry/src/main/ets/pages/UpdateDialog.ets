import { AppColors } from '../common/constants/AppConstants';

/**
 * UpdateDialog —— 应用更新提示 BottomSheet。
 * 18fp Medium 标题(update_nightly)+ 14fp 正文(update_nightly_summary)+ 进度条(下载/安装进度)
 * + [Later][Download/Install] 按钮(橙色强调)。进度态时禁用按钮。
 * TODO(契约): 下载/安装由调用方驱动 progress(0..100);完成态切按钮文案为 Install。
 */
@ComponentV2
export struct UpdateDialog {
  @Event onClose: () => void = () => {};
  @Event onDownload: () => void = () => {};

  @Local progress: number = 0; // 0..100,0=未开始
  @Local downloading: boolean = false;

  build() {
    Column() {
      Text($r('app.string.update_nightly'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .height(56).width('100%').padding({ left: 16, right: 16 }).maxLines(1).textAlign(TextAlign.Start)

      Text($r('app.string.update_nightly_summary'))
        .fontSize(14).fontColor('#FFFFFF').width('100%')
        .padding({ left: 16, right: 16 })

      if (this.downloading) {
        // 进度条
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .color(AppColors.orange500).trackColor(AppColors.grey800)
          .width('100%').margin({ left: 16, right: 16, top: 16 })
        Text(`${this.progress}%`).fontSize(12).fontColor(AppColors.grey500).margin({ top: 8 })
      }

      // 按钮行
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal).fontColor(AppColors.orange500).backgroundColor(AppColors.transparent)
          .margin({ right: 16 })
          .enabled(!this.downloading)
          .onClick(() => this.onClose())
        Button(this.downloading ? 'Installing…' : $r('app.string.install'))
          .type(ButtonType.Normal).fontColor('#FFFFFF').backgroundColor(AppColors.orange500)
          .enabled(!this.downloading)
          .onClick(() => {
            this.downloading = true;
            this.onDownload();
          })
      }
      .width('100%').justifyContent(FlexAlign.End)
      .margin({ top: 24, right: 16, bottom: 16 }).alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
