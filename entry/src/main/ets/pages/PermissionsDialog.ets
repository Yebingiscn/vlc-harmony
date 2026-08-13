import { AppColors } from '../common/constants/AppConstants';
import { PermissionCoordinator } from '../common/data/PermissionCoordinator';

/**
 * PermissionsDialog —— 权限管理 BottomSheet(对齐安卓 PermissionListDialog + dialog_permissions.xml)。
 *
 * UI:18fp Medium 主标题(permissions)+ 文件权限说明框(按授权状态切换 图标+文案)
 * + 阻止变更时的红色警告框(滑入动画)+ 三态单选
 * (没有文件权限 / 仅有常规媒体权限 / 完整访问权限)。
 *
 * 功能(全部真实,单选逻辑逐字对齐安卓 PermissionListDialog.updateStorageState):
 *  - 打开时查询鸿蒙运行时权限:音频 READ_AUDIO / 视频 READ_IMAGEVIDEO /
 *    完整访问 READ_MEDIA(受限权限,普通应用默认未授予)。
 *  - 「没有文件权限」:已有任意权限 → 不可选(回弹 + 红色警告);无权限 → 选中。
 *  - 「仅有常规媒体权限」:完整访问 → 不可选 + 警告;已有媒体权限 → 跳系统设置页;
 *    无权限 → requestPermissionsFromUser(READ_IMAGEVIDEO + READ_AUDIO)。
 *  - 「完整访问权限」:已有媒体权限 → 不可选 + 警告;无任何权限 → 跳系统设置页引导。
 *
 * 单选选中态 100% 由 @Local selected 驱动:每个 Radio 用独立 group(禁掉同组自动互斥),
 * 让「阻止切换」时(如 完整访问下点常规媒体)能保持原选中项不被系统自动换走。
 * blockVersion 每次阻止时自增,强制重渲染回弹 Radio(防止 warnVisible 已为 true 时
 * Radio 内部选中态残留)。
 */
@ComponentV2
export struct PermissionsDialog {
  /** 当前选中:0=没有文件权限,1=仅有常规媒体权限,2=完整访问权限。 */
  @Local selected: number = 0;
  /** 音频读取权限(READ_AUDIO)。 */
  @Local audioGranted: boolean = false;
  /** 视频读取权限(READ_IMAGEVIDEO)。 */
  @Local videoGranted: boolean = false;
  /** 完整文件访问(READ_MEDIA 受限权限)。 */
  @Local allAccess: boolean = false;
  /** 警告框是否可见(变更被阻止时弹出)。 */
  @Local warnVisible: boolean = false;
  /** 警告框文案(基于当前授权状态,对齐安卓 permission_media_warning / permission_all_warning)。 */
  @Local warnText: Resource = $r('app.string.permission_all_warning');
  /** 说明框状态:0=完整访问,1=常规媒体,2=无权限(对齐安卓 explanation 三态)。 */
  @Local explanationState: number = 2;
  /** 阻止变更次数:每次 showWarning 自增,强制重渲染回弹 Radio 内部选中态。 */
  @Local blockVersion: number = 0;

  private get hasMedia(): boolean {
    return this.audioGranted || this.videoGranted;
  }

  @Event onClose: () => void = () => {
  };

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  build() {
    Scroll() {
      Column() {
        // 主标题
        Text($r('app.string.permissions'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.list_title'))
          .width('100%')
          .margin({ left: 16, top: 16 })

        // ── 文件权限小节 ──
        Text($r('app.string.manage_storage_permission'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .width('100%')
          .margin({ left: 16, top: 24 })

        // 文件访问说明框(图标 + 文案按授权状态三态切换)
        Row() {
          Image(this.explanationState === 0
            ? $r('app.media.ic_perm_all')
            : (this.explanationState === 1 ? $r('app.media.ic_perm_media') : $r('app.media.ic_perm_none')))
            .width(28).height(28)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 16 })
          Text(this.explanationState === 0
            ? $r('app.string.permission_onboarding_perm_all')
            : (this.explanationState === 1
              ? $r('app.string.permission_onboarding_perm_media')
              : $r('app.string.permission_expanation_no_allow')))
            .fontSize(14)
            .fontColor($r('app.color.list_title'))
            .layoutWeight(1)
            .lineHeight(20)
        }
        .width('100%')
        .padding(16)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(8)
        .margin({ left: 16, right: 16, top: 8 })

        // 警告框(变更被阻止时滑入,对齐安卓 rounded_corners_permissions_warning + showWarning)
        if (this.warnVisible) {
          Text(this.warnText)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .width('100%')
            .padding(12)
            .backgroundColor('#40ff0000')
            .borderRadius(8)
            .margin({
              left: 16,
              right: 16,
              top: 16,
              bottom: 8
            })
            .transition(TransitionEffect.translate({ y: 40 })
              .combine(TransitionEffect.opacity(0))
              .animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 单选:没有文件权限
        // key 含 blockVersion:被阻止(showWarning)时强制重建 Radio,回弹选中态。
        Row() {
          Radio({ value: 'no', group: `perms_${this.blockVersion}` })
            .checked(this.selected === 0)
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((on: boolean) => {
              if (on) {
                this.onNoAccessClick();
              }
            })
          Text($r('app.string.permission_no_access'))
            .fontSize(16).fontColor($r('app.color.list_title')).margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })
        .alignItems(VerticalAlign.Center)

        // 单选:仅有常规媒体权限
        Row() {
          Radio({ value: 'media', group: `perms_${this.blockVersion}` })
            .checked(this.selected === 1)
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((on: boolean) => {
              if (on) {
                this.onMediaClick();
              }
            })
          Text($r('app.string.permission_media_title'))
            .fontSize(16).fontColor($r('app.color.list_title')).margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
        .alignItems(VerticalAlign.Center)

        // 单选:完整访问权限
        Row() {
          Radio({ value: 'all', group: `perms_${this.blockVersion}` })
            .checked(this.selected === 2)
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((on: boolean) => {
              if (on) {
                this.onAllClick();
              }
            })
          Text($r('app.string.permission_all_title'))
            .fontSize(16).fontColor($r('app.color.list_title')).margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 4,
          bottom: 16
        })
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

  /** 刷新所有权限状态并推导 选中态 / 说明框 / 警告文案。 */
  private async refresh(): Promise<void> {
    this.audioGranted = await PermissionCoordinator.hasAudioPermission();
    this.videoGranted = await PermissionCoordinator.hasVideoPermission();
    this.allAccess = await PermissionCoordinator.hasAllAccess();
    // 选中态推导(对齐安卓 updateStorageState 的 radio 分支)
    if (this.allAccess) {
      this.selected = 2;
      this.explanationState = 0;
    } else if (this.hasMedia) {
      this.selected = 1;
      this.explanationState = 1;
    } else {
      this.selected = 0;
      this.explanationState = 2;
    }
    // 警告文案:按当前授权状态(对齐安卓 allAccessWarning.text 三态)
    this.warnText = this.allAccess
      ? $r('app.string.permission_media_warning')
      : $r('app.string.permission_all_warning');
  }

  /** 显示红色警告框(对齐安卓 showWarning:阻止越权切换时滑入)。
   *  同时自增 blockVersion 强制重渲染:防止 warnVisible 已为 true 时不再触发渲染,
   *  Radio 内部选中态残留(如「没有文件权限」在有权限时被点选后仍显示已选中)。 */
  private showWarning(): void {
    this.warnVisible = true;
    this.blockVersion++;
  }

  private async requestAndRefresh(request: () => Promise<boolean>): Promise<void> {
    await request();
    await this.refresh();
  }

  /** 点击「没有文件权限」:已有权限 → 阻止 + 警告;否则选中。 */
  private onNoAccessClick(): void {
    if (this.allAccess || this.hasMedia) {
      this.showWarning();
    } else {
      this.selected = 0;
    }
  }

  /** 点击「仅有常规媒体权限」(对齐安卓 manageMediaPermsCheck):
   *  完整访问 → 阻止 + 警告;已有媒体权限 → 跳系统设置页(安卓 showAppSettingsPage);
   *  无权限 → 请求 READ_IMAGEVIDEO + READ_AUDIO。 */
  private onMediaClick(): void {
    if (this.allAccess) {
      this.showWarning();
    } else if (this.hasMedia) {
      void PermissionCoordinator.openAppSettingsPage();
    } else {
      void this.requestAndRefresh(() => PermissionCoordinator.requestMediaPermission());
    }
  }

  /** 点击「完整访问权限」:常规媒体 → 阻止 + 警告;无权限 → 跳系统设置页;否则选中。 */
  private onAllClick(): void {
    if (!this.allAccess && this.hasMedia) {
      this.showWarning();
    } else if (!this.allAccess) {
      // 无任何权限:安卓拉起 ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION → 鸿蒙跳应用信息页
      void PermissionCoordinator.openAppSettingsPage();
    } else {
      this.selected = 2;
    }
  }
}
