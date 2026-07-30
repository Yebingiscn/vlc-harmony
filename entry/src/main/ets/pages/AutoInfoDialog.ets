import { AppColors } from '../common/constants/AppConstants';

/**
 * AutoInfoDialog —— Android Auto 静态信息 BottomSheet。
 * 18fp Medium 标题(android_auto)+ 18fp Medium colorAccent 小节标题(Podcast mode / Voice control)
 * + 16fp 正文(podcast_mode_help %s→podcast_mode_genres;voice_control_help)。无按钮/无交互。
 */
@ComponentV2
export struct AutoInfoDialog {
  @Event onClose: () => void = () => {};

  @Local podcastHelpText: string = '';

  aboutToAppear(): void {
    // podcast_mode_help 的 %s 用 podcast_mode_genres("audiobook(s), podcast, speech, or vocal")格式化。
    this.podcastHelpText =
      'Podcast controls appear when playing a single track which meets one of the following criteria:\n' +
      '\t• Length greater than 60 min\n' +
      '\t• Length greater than 15 min with no album name\n' +
      '\t• Genre is audiobook(s), podcast, speech, or vocal';
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColors.orange500)
      .width('100%')
      .padding({ left: 16, right: 16 })
  }

  @Builder
  body(text: Resource | string) {
    Text(text)
      .fontSize(16)
      .fontColor('#FFFFFF')
      .width('100%')
      .padding({ left: 16, right: 16 })
  }

  build() {
    Column() {
      Text($r('app.string.android_auto'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, top: 16 })

      this.sectionTitle($r('app.string.podcast_mode')).margin({ top: 24 })
      this.body(this.podcastHelpText).margin({ top: 8 })

      this.sectionTitle($r('app.string.voice_control')).margin({ top: 16 })
      this.body($r('app.string.voice_control_help')).margin({ top: 8, bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
