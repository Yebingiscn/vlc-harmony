import { AppColors } from '../common/constants/AppConstants';

/**
 * PermissionsDialog —— 权限选择 BottomSheet(覆盖 PermissionListDialog / PermissionsDialog / NotificationPermission 列表 spec)。
 * 18fp Medium 主标题(permissions)+ 16fp colorAccent 小节标题(Notification permission / File permissions)
 * + 通知权限行(32vp ic_permission_check_checked + 16fp 文字,48vp 行)+ 文件访问说明框(18fp,grey200 圆角底)
 * + 单选组(No file access / Access to standard media / Access to all files)。橙色 AppColors.orange500 强调。
 * TODO(契约): 单选态由调用方注入 selected;权限申请动作由宿主页发起。
 */
@ComponentV2
export struct PermissionsDialog {
  @Event onClose: () => void = () => {};
  @Local selected: number = 1; // 0=no_access, 1=media, 2=all

  build() {
    Scroll() {
      Column() {
        // 主标题
        Text($r('app.string.permissions'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width('100%')
          .margin({ left: 16, top: 16 })

        // 通知权限小标题
        Text($r('app.string.notification_permission'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({ left: 16, top: 24 })

        // 通知权限容器行
        Row() {
          Image($r('app.media.ic_permission_check_checked')).width(32).height(32)
          Text($r('app.string.notification_permission'))
            .fontSize(16)
            .fontColor('#FFFFFF')
            .margin({ left: 24, right: 16 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 16, right: 16, top: 8 })

        // 文件权限小标题
        Text($r('app.string.manage_storage_permission'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({ left: 16, top: 8 })

        // 文件访问说明框(grey200 圆角底)
        Text($r('app.string.permission_onboarding_perm_all'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width('100%')
          .padding(16)
          .backgroundColor(AppColors.grey200)
          .borderRadius(8)
          .margin({ left: 16, right: 16, top: 8 })

        // 单选组
        Row() {
          Radio({ value: '0', group: 'perms' }).checked(this.selected === 0)
            .selectedColor(AppColors.orange500)
            .onChange((on: boolean) => { if (on) this.selected = 0; })
          Text($r('app.string.permission_no_access'))
            .fontSize(16).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })
        .alignItems(VerticalAlign.Center)

        Row() {
          Radio({ value: '1', group: 'perms' }).checked(this.selected === 1)
            .selectedColor(AppColors.orange500)
            .onChange((on: boolean) => { if (on) this.selected = 1; })
          Text($r('app.string.permission_media_title'))
            .fontSize(16).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
        .alignItems(VerticalAlign.Center)

        Row() {
          Radio({ value: '2', group: 'perms' }).checked(this.selected === 2)
            .selectedColor(AppColors.orange500)
            .onChange((on: boolean) => { if (on) this.selected = 2; })
          Text($r('app.string.permission_all_title'))
            .fontSize(16).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 16 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
