import { UiFeedback } from '../common/utils/UiFeedback';

/**
 * RenameDialog —— 重命名 BottomSheet(对齐 Android RenameDialog)。
 * 文本输入框 + 确认/取消按钮。
 */
@ComponentV2
export struct RenameDialog {
  @Param currentName: string = '';
  @Local name: string = '';

  @Event onConfirm: (newName: string) => void = () => {
  };

  @Event onCancel: () => void = () => {
  };

  aboutToAppear(): void {
    this.name = this.currentName;
  }

  build() {
    Column() {
      Text($r('app.string.rename'))
        .fontSize(18)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 12 })
        .width('100%')
        .textAlign(TextAlign.Center)

      Row() {
        TextInput({ text: this.name, placeholder: $r('app.string.playlist_name_hint') })
          .fontSize(14)
          .fontColor($r('app.color.list_title'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(4)
          .layoutWeight(1)
          .border({ width: 0.5, color: $r('app.color.card_border') })
          .onChange((v: string) => {
            this.name = v;
          })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 })

      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => {
            this.onCancel();
          })
        Button($r('app.string.ok'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor('#FF8800')
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .onClick(() => {
            if (this.name.trim().length === 0) {
              UiFeedback.showToast({ message: '名称不能为空' });
              return;
            }
            this.onConfirm(this.name);
          })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 })

      Blank().height(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
