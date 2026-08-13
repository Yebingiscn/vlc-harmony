import { AppColors } from '../common/constants/AppConstants';

/**
 * VideoResumeDialog —— 续播确认居中弹窗(AlertDialog body)。
 * 18fp Medium 媒体标题(confirmation.title)+ 16fp Medium 提示横幅(confirm_resume,"Resume from last position?")
 * + 复选框 apply_playqueue(橙色 #FF8800,14fp 副文字)+ [No][Resume] 按钮(setCancelable=false,返回键 finish)。
 * TODO(契约): Resume → PlaybackService.seek(lastPosition);No → 从头播放;applyForAllQueue 写偏好。
 */
@ComponentV2
export struct VideoResumeDialog {
  @Param mediaTitle: string = '';
  @Local applyForAllQueue: boolean = false;

  @Event onClose: () => void = () => {
  };

  @Event onResume: () => void = () => {
  };

  @Event onCancel: () => void = () => {
  };

  build() {
    Column() {
      // AlertDialog 标题(媒体标题)
      Text(this.mediaTitle)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ left: 24, top: 24, right: 16 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 提示横幅
      Text($r('app.string.confirm_resume'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ left: 24, top: 24, right: 16 })

      // 复选框
      Row() {
        Checkbox().select(this.applyForAllQueue).selectedColor(AppColors.orange500)
          .onChange((v: boolean) => this.applyForAllQueue = v)
        Text($r('app.string.apply_playqueue'))
          .fontSize(14).fontColor('#CCCCCC').margin({ left: 8 })
      }
      .width('100%')
      .margin({
        left: 16,
        top: 8,
        right: 16,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)

      // 按钮行
      Row() {
        Button($r('app.string.no'))
          .type(ButtonType.Normal)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.onCancel();
            this.onClose();
          })
        Button($r('app.string.resume'))
          .type(ButtonType.Normal)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.onResume();
            this.onClose();
          })
      }
      .width('100%').justifyContent(FlexAlign.End).alignItems(VerticalAlign.Center)
    }
    .width('86%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)

    // 注:居中浮层内容卡;由调用方 Stack 居中承载 + #80000000 遮罩(setCancelable=false,点击外部不关闭)。
  }
}
