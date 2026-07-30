/**
 * PreferenceConfirmDialog —— 通用「确认修改偏好」底部弹窗(@ComponentV2 纯展示 bindSheet 风格)。
 * 来源:ConfirmPreferenceChangeDialog(dialog_confirm_audio_playqueue.xml,BottomSheet STATE_EXPANDED)。
 * 警告图标(54vp, grey400 #BDBDBD)+ 标题(22fp Bold #212121)+ 正文(16fp)+ [Cancel][OK] 文字按钮。
 * 注入 preferenceKey/titleText/warningText;OK → onAccept()(外部回写 + setFragmentResult 语义);
 * Cancel → onCancel()。正文含 \n/\t 必须保留。
 * 遮罩 scrim rgba(0,0,0,0.4),卡片顶部圆角 16,宽度随屏宽(平板 maxWidth 512vp)。
 */
@ComponentV2
export struct PreferenceConfirmDialog {
  @Param preferenceKey: string = '';
  @Param titleText: ResourceStr = '';
  @Param warningText: ResourceStr = '';
  @Event onAccept: () => void = () => {};
  @Event onCancel: () => void = () => {};

  build(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景遮罩(外部点击关闭)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .onClick(() => this.onCancel())

      // 弹窗卡片(底部贴边,顶部圆角)
      Column() {
        // 第一行:警告图标 + 标题
        Row() {
          Image($r('app.media.ic_warning'))
            .width(54)
            .height(54)
            .objectFit(ImageFit.Contain)
            .fillColor('#BDBDBD')
          Text(this.titleText)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#212121')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 16, right: 16 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, top: 16 })

        // 正文
        Text(this.warningText)
          .fontSize(16)
          .fontColor('#212121')
          .width('100%')
          .margin({ left: 16, right: 16, top: 24 })
          .textAlign(TextAlign.Start)

        // 按钮行:[Cancel] [OK] 靠右
        Row() {
          Text($r('app.string.cancel'))
            .fontSize(14)
            .fontColor('#FF7043')
            .padding(8)
            .margin({ right: 16 })
            .onClick(() => this.onCancel())
          Text($r('app.string.ok'))
            .fontSize(14)
            .fontColor('#FF7043')
            .padding(8)
            .margin({ right: 8 })
            .onClick(() => this.onAccept())
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 72 })
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0 })
      .padding({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
  }
}
