import { AppColors } from '../common/constants/AppConstants';

/** 嵌入偏好行:标题 + 副标题 + 右侧 Toggle(Switch)。 */
@ComponentV2
struct VideoControlToggleRow {
  @Param title: Resource = $r('app.string.video');
  @Param summary: string = '';
  @Param checked: boolean = false;
  @Event onToggle: (on: boolean) => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16).fontColor('#FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.summary.length > 0) {
          Text(this.summary).fontSize(12).fontColor(AppColors.grey500).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1).margin({ left: 16, right: 16 })
      Toggle({ type: ToggleType.Switch, isOn: this.checked }).selectedColor(AppColors.orange500)
        .onChange((on: boolean) => this.onToggle(on))
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).alignItems(VerticalAlign.Center)
  }
}

/**
 * VideoControlsSettingsDialog —— 视频手势/控制偏好 BottomSheet。
 * 18fp Medium 标题 + Toggle 行组(显示书签按钮/章节按钮/手势快进延时/竖屏锁定等),橙色 AppColors.orange500 强调。
 * TODO(契约): 具体偏好 key 与默认值由 PreferencesVideoControls 提供;此处用 Toggle 行渲染。
 */
@ComponentV2
export struct VideoControlsSettingsDialog {
  @Event onClose: () => void = () => {};
  @Local showBookmarkButtons: boolean = true;
  @Local showChapterButtons: boolean = false;
  @Local showSeekInCompactNotif: boolean = true;

  build() {
    Column() {
      Text('Video controls')
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .height(56).width('100%').padding({ left: 16, right: 16 }).maxLines(1).textAlign(TextAlign.Start)

      VideoControlToggleRow({
        title: $r('app.string.show_bookmark_buttons'),
        summary: 'Show bookmark overlay buttons',
        checked: this.showBookmarkButtons,
        onToggle: (on: boolean) => {
          this.showBookmarkButtons = on;
          // TODO(契约): 写入对应偏好 key(PreferencesVideoControls),由调用方绑定具体 Settings 键。
        },
      })

      VideoControlToggleRow({
        title: $r('app.string.show_chapter_buttons'),
        summary: 'Show chapter navigation buttons',
        checked: this.showChapterButtons,
        onToggle: (on: boolean) => {
          this.showChapterButtons = on;
          // TODO(契约): 写入对应偏好 key(PreferencesVideoControls),由调用方绑定具体 Settings 键。
        },
      })

      VideoControlToggleRow({
        title: $r('app.string.show_seek_in_compact_notif_title'),
        summary: 'Show seek buttons in compact notification',
        checked: this.showSeekInCompactNotif,
        onToggle: (on: boolean) => {
          this.showSeekInCompactNotif = on;
          // TODO(契约): 写入对应偏好 key(PreferencesVideoControls),由调用方绑定具体 Settings 键。
        },
      })

      Button($r('app.string.ok'))
        .type(ButtonType.Normal).borderRadius(4).backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
        .width('80%').onClick(() => this.onClose()).margin({ top: 16, bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
