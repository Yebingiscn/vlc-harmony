import { AppColors } from '../common/constants/AppConstants';

/**
 * NotificationPermissionDialog —— 通知权限说明 BottomSheet(也覆盖 NorificationPermissionDialog spec)。
 * 64vp ic_permission_notification 图标 + 18fp Medium 标题(notification_permission,minHeight 56vp)+ 14fp 正文说明
 * (notification_permission_explanation,含 \n)+ 右对齐 OK 按钮(marginTop 24 / marginEnd 16 / marginBottom 16)。
 * 点 OK / 遮罩 / 返回 → dismiss → onDismiss 内写 notification_permission_asked=true 并发起系统通知权限请求。
 * TODO(契约): onDismiss → Settings.put(KEY_NOTIFICATION_PERMISSION_ASKED,true)+ 发起系统通知权限请求(权限请求在弹窗关闭后才发起)。
 */
@ComponentV2
export struct NotificationPermissionDialog {
  @Event onClose: () => void = () => {};

  build() {
    Column() {
      // 图标 + 标题行
      Row() {
        Image($r('app.media.ic_permission_notification'))
          .width(64).height(64)
          .margin({ left: 8, top: 8 })
        Text($r('app.string.notification_permission'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .constraintSize({ minHeight: 56 })
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .maxLines(1)
          .textOverflow(TextOverflow.Ellipsis)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 正文
      Text($r('app.string.notification_permission_explanation'))
        .fontSize(14)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ left: 16, right: 16, top: 16 })

      // OK 按钮(右对齐)
      Row() {
        Button($r('app.string.ok'))
          .type(ButtonType.Normal)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ top: 24, right: 16, bottom: 16 })
          .onClick(() => this.onClose())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
