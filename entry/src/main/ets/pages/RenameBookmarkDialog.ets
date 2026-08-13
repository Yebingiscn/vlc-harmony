import { AppColors } from '../common/constants/AppConstants';

/**
 * RenameBookmarkDialog —— 书签改名弹窗。
 * 单行输入框 + [取消][保存]。空名字允许(显示成 "书签 N")。
 */
@ComponentV2
export struct RenameBookmarkDialog {
  @Param initialName: string = '';
  @Local input: string = '';
  readonly cCardBg: string = '#1C1C1C';
  readonly cInputBg: string = '#262626';
  readonly cSubtle: string = '#9E9E9E';
  readonly cCancelBg: string = '#2A2A2A';

  @Event onClose: () => void = () => {
  };

  @Event onConfirm: (newName: string) => void = () => {
  };

  aboutToAppear(): void {
    this.input = this.initialName;
  }

  canConfirm(): boolean {
    // 允许"清空名字"(用默认 "书签 N"),所以永远可点;
    // 唯一限制是 trimmed 空 —— 这里我们让"全空"也保存,显示成"书签 N"。
    return true;
  }

  build() {
    Column() {
      // 标题
      Text('重命名书签')
        .fontSize(19)
        .fontWeight(600)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({
          left: 20,
          right: 20,
          top: 16,
          bottom: 12
        })
        .textAlign(TextAlign.Start)

      Text('留空将显示为「书签 N」')
        .fontSize(12).fontColor(this.cSubtle)
        .width('100%')
        .padding({ left: 20, right: 20 })

      // 输入框
      TextInput({ text: this.input, placeholder: '书签名' })
        .fontSize(16)
        .fontColor('#FFFFFF')
        .placeholderColor(this.cSubtle)
        .caretColor(AppColors.orange500)
        .backgroundColor(this.cInputBg)
        .borderRadius(10)
        .height(48)
        .width('100%')
        .padding({ left: 14, right: 14 })
        .margin({ top: 14 })
        .onChange((v: string) => this.input = v)
        .onSubmit(() => this.confirm())

      // 按钮
      Row({ space: 10 }) {
        Button('取消')
          .type(ButtonType.Capsule)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.cCancelBg)
          .fontColor('#E0E0E0')
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.onClose())
        Button('保存')
          .type(ButtonType.Capsule)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(AppColors.orange500)
          .fontColor('#FFFFFF')
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.confirm())
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: 20,
        bottom: 24
      })
    }
    .width('100%')
    .backgroundColor(this.cCardBg)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  private confirm(): void {
    this.onConfirm(this.input.trim());
  }
}
