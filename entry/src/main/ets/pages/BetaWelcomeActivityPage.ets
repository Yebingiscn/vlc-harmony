import { NavController } from '../common/data/NavController';
import { AppColors } from '../common/constants/AppConstants';

/**
 * BetaWelcomeActivityPage —— Beta 欢迎说明对话框(BetaWelcomeActivity)。
 * 角色:弹窗(dialog-style Activity,固定宽 300vp,无标题栏)。
 * 结构:图标(32vp) + 标题 + 三段说明 + 右下角 OK 文字按钮(透明背景、文字色 orange500)。
 * 唯一交互:OK → NavController.pop()(对应 finish())。
 */
@ComponentV2
export struct BetaWelcomeActivityPage {
  build() {
    NavDestination() {
      // 对话框卡片容器(固定宽 300vp,高度撑满)。
      Column() {
        // —— 顶部:图标 + 标题(packed 横链)——
        Row() {
          Image($r('app.media.icon'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .margin({ left: 16, top: 16 })
          Text($r('app.string.welcome_beta_title')) // "VLC Beta"
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .margin({ left: 8, right: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // —— 第一段 ——
        Text($r('app.string.welcome_beta_description'))
          .margin({ top: 24, left: 16, right: 16 })

        // —— 第二段 ——
        Text($r('app.string.welcome_beta_description_bugs'))
          .margin({ top: 8, left: 16, right: 16 })

        // —— 第三段(加粗 16fp)——
        Text($r('app.string.welcome_beta_description_crashes'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 8, left: 16, right: 16 })

        // —— OK 按钮(右靠齐)——
        Row() {
          Button($r('app.string.ok')) // "OK"
            .type(ButtonType.Normal)
            .fontSize(14)
            .fontColor(AppColors.orange500)
            .backgroundColor(AppColors.transparent)
            .margin({ right: 8 })
            .onClick(() => {
              // 对应 betaOkButton.onClick { finish() }
              NavController.pop();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 24 })
      }
      .width(300)
      .height('100%')
      .backgroundColor(AppColors.white)
      .alignItems(HorizontalAlign.Start)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
