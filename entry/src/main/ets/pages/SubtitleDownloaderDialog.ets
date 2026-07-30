import { AppColors } from '../common/constants/AppConstants';

/** 字幕搜索结果行:语言标题 + 副标题,整行可点下载。 */
@ComponentV2
struct SubtitleResultRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Event onDownload: () => void = () => {};

  build() {
    Row() {
      Image($r('app.media.ic_subtitles')).width(24).height(24).fillColor('#FFFFFF')
      Column() {
        Text(this.title).fontSize(16).fontColor('#FFFFFF').maxLines(1).textOverflow(TextOverflow.Ellipsis)
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(12).fontColor(AppColors.grey500).maxLines(1).textOverflow(TextOverflow.Ellipsis)
        }
      }
      .layoutWeight(1).margin({ left: 16, right: 16 })
      Image($r('app.media.ic_download')).width(24).height(24).fillColor(AppColors.orange500)
    }
    .width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)
    .onClick(() => this.onDownload())
  }
}

/**
 * SubtitleDownloaderDialog —— 字幕下载 BottomSheet(三态:下载/历史/登录,简化为搜索表单 + 结果 List)。
 * 18fp Medium 标题 + 语言 Select + 搜索 TextInput + 搜索按钮 + 结果列表 + 底部登录入口。
 * TODO(契约): 搜索走 OpenSubtitles/VideoLAN 字幕服务(网络);登录态由调用方注入;三态切换由 tab 体现(此处简化为单下载态)。
 */
@ComponentV2
export struct SubtitleDownloaderDialog {
  @Event onClose: () => void = () => {};

  readonly languages: string[] = ['English', 'Chinese', 'French', 'Spanish', 'Auto'];
  @Local langIndex: number = 0;
  @Local query: string = '';
  @Local results: string[] = [];

  build() {
    Column() {
      Text($r('app.string.subtitles'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .height(56).width('100%').padding({ left: 16, right: 16 }).maxLines(1).textAlign(TextAlign.Start)

      // 语言下拉
      Row() {
        Text('Language').fontSize(14).fontColor(AppColors.grey500)
        Select(this.languages.map((v: string) => ({ value: v })))
          .selected(this.langIndex).value(this.languages[this.langIndex])
          .margin({ left: 16 }).layoutWeight(1)
          .onSelect((idx: number) => this.langIndex = idx)
      }
      .width('100%').padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      // 搜索框
      TextInput({ text: this.query, placeholder: 'Search subtitles' })
        .width('100%').margin({ left: 16, right: 16, top: 8 })
        .fontSize(14).fontColor('#FFFFFF').backgroundColor(AppColors.grey850)
        .onChange((v: string) => this.query = v)

      // 搜索按钮
      Button('Search')
        .type(ButtonType.Normal).borderRadius(4).backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
        .width('100%').margin({ left: 16, right: 16, top: 8 })
        .onClick(() => {
          // TODO(契约): 调字幕服务搜索 → results = [...]; 此处仅占位。
        })

      // 结果列表
      List({ space: 0 }) {
        ForEach(this.results, (item: string, index: number) => {
          ListItem() {
            SubtitleResultRow({
              title: item,
              subtitle: '',
              onDownload: () => {
                // TODO(契约): 下载字幕文件并应用。
              },
            })
          }
        }, (item: string, index: number) => index.toString())
      }
      .width('100%').layoutWeight(1).margin({ top: 8 }).scrollBar(BarState.Auto)

      // 登录入口
      Button('Sign in to OpenSubtitles')
        .type(ButtonType.Normal).fontColor(AppColors.orange500).backgroundColor(AppColors.transparent)
        .margin({ bottom: 16 })
        .onClick(() => {})
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
