import { AppColors } from '../common/constants/AppConstants';

/**
 * VlcConfirmDialog —— 通用确认/警告 BottomSheet 组件。
 * 警告图标(ic_warning,54vp,grey400)+ 22fp Bold 标题 + 16fp 正文 + [Cancel][OK] 文字按钮(右对齐)。
 *
 * 映射(各 spec 内容接近,通过 @Param 注入不同文案/图标,不单独建文件):
 * - ConfirmDeleteDialog      : title=删除文案(默认 confirm_delete), message=confirm_delete_message,
 *                              okText=delete_forever, onOk=onDeleteConfirmed 回传 mediaList+resultType。
 * - ConfirmPreferenceChangeDialog / ConfirmAudioPlayqueueDialog: title=audio_resume_playback_title,
 *                              message=audio_resume_playback_warning(含 \n\t), onOk 回传 preferenceKey + listener.invoke()。
 * - FeatureFlagWarningDialog : title=optional_features_warning, message=功能旗标警告正文, icon=ic_warning。
 * - DuplicationWarningDialog : title=重复媒体警告, message=重复导入说明正文, icon=ic_warning。
 *
 * 外部运行时契约(fragment result 回传 / PIN 校验 showPinIfNeeded / anim_delete 循环动画 / 主题 accent 按钮色)
 * 标 TODO(契约),由调用方(宿主页)处理;本组件仅做 1:1 结构/文案/尺寸/颜色还原。
 */
@ComponentV2
export struct VlcConfirmDialog {
  /** 标题文案(22fp Bold)。 */
  @Param title: string = '';
  /** 正文文案(16fp,可含 \n\t 多行)。 */
  @Param message: string = '';
  /** 警告图标资源名(默认 ic_warning);为空时不显示图标。 */
  @Param icon: Resource = $r('app.media.ic_warning');
  /** 确认按钮文案(默认 "OK")。 */
  @Param okText: Resource = $r('app.string.ok');
  /** 取消按钮文案(默认 "Cancel")。 */
  @Param cancelText: Resource = $r('app.string.cancel');
  /** OK 按钮 onClick。 */
  @Event onOk: () => void = () => {
  };
  /** Cancel 按钮 / 遮罩 / 返回 onClick。 */
  @Event onCancel: () => void = () => {
  };
  /** 关闭意图(等同 onCancel,供 bindSheet 关闭用)。 */
  @Event onClose: () => void = () => {
  };

  build() {
    Column() {
      // ── 标题行:警告图标 + 标题(垂直居中)──
      Row() {
        Image(this.icon)
          .width(54)
          .height(54)
          .fillColor(AppColors.grey400)
          .objectFit(ImageFit.Contain)
          .margin({ left: 16, top: 16 })

        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow(TextOverflow.Ellipsis)
          .layoutWeight(1)
          .margin({ left: 16, right: 16, top: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ── 正文 ──
      Text(this.message)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ left: 16, right: 16, top: 24 })

      // ── 按钮行:Cancel(左) + OK(右),右下对齐 ──
      Row() {
        Button(this.cancelText)
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ top: 72, right: 16, bottom: 16 })
          .onClick(() => {
            this.onCancel();
            this.onClose();
          })

        Button(this.okText)
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ right: 8, bottom: 16 })
          .onClick(() => {
            this.onOk();
            this.onClose();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)

    // TODO(契约): anim_delete 循环 AVD(非 BAN_FOLDER 时无限循环)→ 鸿蒙转帧序列/GIF/Lottie,暂用静态 ic_warning。
    // TODO(契约): confirm_delete 动态标题 6 分支(mediaList/Album/Playlist 类型)由调用方计算后注入 title @Param。
    // TODO(契约): onOk 内 setFragmentResult 回传 mediaList+resultType(ConfirmDelete)/ preferenceKey(ConfirmPreference)→ 由调用方用 emitter/回调实现。
    // TODO(契约): 进入时 showPinIfNeeded() PIN 校验,需 PIN 则 dismiss —— 由调用方在 bindSheet 触发前处理。
  }
}
