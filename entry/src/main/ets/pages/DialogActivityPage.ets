import { UiFeedback } from '../common/utils/UiFeedback';
import { NavController } from '../common/data/NavController';

/**
 * DialogActivityPage —— 透明无 UI 派发壳(DialogActivity)。
 * NavDestination 空白透明;aboutToAppear 按 @Param action 派发(showToast 后 pop)。
 * 原始:按 intent.action(serverDialog/subsdlDialog/deviceDialog/vlcDialog)派发到对话框/子流程后销毁。
 * 鸿蒙无 libvlc/DeviceDialog/NetworkServerDialog 等独立弹窗契约 → 仅还原「派发即 pop」语义,外部契约标 TODO。
 */
@ComponentV2
export struct DialogActivityPage {
  /** 入参 action(对应原始 intent.action)。 */
  @Param action: string = '';
  /** 入参 mediaUri(对应 EXTRA_MEDIA / EXTRA_PATH,展示用)。 */
  @Param mediaUri: string = '';

  aboutToAppear(): void {
    // 步骤 2:无 action → 立即 finish()。
    if (this.action.length === 0) {
      NavController.pop();
      return;
    }
    let msg: string = '';
    switch (this.action) {
      case 'serverDialog':
        // TODO(契约): NetworkServerDialog.setServer(media).show("fragment_edit_network")
        msg = 'Network server dialog';
        break;
      case 'subsdlDialog':
        // TODO(契约): MediaUtils.getSubs(context, media) 字幕下载流程
        msg = 'Subtitles download';
        break;
      case 'deviceDialog':
        // TODO(契约): DeviceDialog.setDevice(path, uuid, scan).show("device_dialog")
        msg = 'Device dialog';
        break;
      case 'vlcDialog':
        // TODO(契约): showVlcDialog(companion.dialog) libvlc 登录/错误对话框
        msg = 'VLC dialog';
        break;
      default:
      // 未知 action → finish()。
        NavController.pop();
        return;
    }
    UiFeedback.showToast({ message: msg, duration: 1500 });
    // 派发后销毁自身。
    NavController.pop();
  }

  build() {
    NavDestination() {
      Stack() {
        // 空 —— 全透明,无任何子组件(对应 transparent.xml 全透明 FrameLayout)。
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
