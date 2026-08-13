import { UiFeedback } from '../common/utils/UiFeedback';
import { AppColors } from '../common/constants/AppConstants';

/** 字幕搜索结果行：语言标题 + 副标题，整行可点下载。 */
@ComponentV2
struct SubtitleResultRow {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Event onDownload: () => void = () => {
  };

  build() {
    Row() {
      Image($r('app.media.ic_subtitles')).width(24).height(24).fillColor('#FFFFFF')
      Column() {
        Text(this.title).fontSize(16).fontColor('#FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(AppColors.grey500)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1).margin({ left: 16, right: 16 })

      Image($r('app.media.ic_download')).width(24).height(24).fillColor(AppColors.orange500)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onDownload())
  }
}

/**
 * Select 控件要求的选项元素类型。arkts-no-untyped-obj-literals 禁未类型化对象字面量，
 * 必须显式声明，不能直接用 { value: v }。
 */
class LangOption {
  value: string;

  constructor(v: string) {
    this.value = v;
  }
}

/**
 * SubtitleDownloaderDialog —— 字幕下载面板。
 *
 * 布局：
 *   顶栏（← 返回 + "字幕下载" 标题 + 占位）
 *   Scroll 主体：
 *     语言下拉 / 搜索框 / 搜索按钮 / 结果列表（空态文案）/ 底部登录链接
 *
 * 搜索 / 下载 / 登录三个 action 都用 promptAction 占位提示「需要接入字幕数据源」，
 *   二期接真实服务时按 TODO 提示替换实现。
 */
@ComponentV2
export struct SubtitleDownloaderDialog {
  readonly languages: string[] = ['English', 'Chinese', 'French', 'Spanish', 'Auto'];
  @Local langIndex: number = 0;
  @Local query: string = '';
  @Local results: string[] = [];

  /** 完全关闭 sheet(由下拉关闭手势 / 蒙层触发)。 */
  @Event onClose: () => void = () => {
  };

  /** 返回上一级 sheet(切回 AudioSubtitlePanelDialog,不关闭 sheet)。 */
  @Event onBack: () => void = () => {
  };

  build() {
    Column() {
      // 顶栏：← 返回上一级 + 标题 + 占位（与 AudioSubtitlePanelDialog 顶栏模式一致）
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(28)
          .height(28)
          .fillColor($r('app.color.list_title'))
          .padding(2)
          .onClick(() => this.onBack())
        Text('字幕下载')
          .fontSize(18)
          .fontWeight(600)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Row().width(28)
      }
      .width('100%').height(56).padding({ left: 16, right: 16, top: 20 })
      .alignItems(VerticalAlign.Center)

      // Scroll 主体
      Scroll() {
        Column() {
          // 语言下拉
          Row() {
            Text('语言').fontSize(14).fontColor(AppColors.grey500)
            Select(this.languageOptions())
              .selected(this.langIndex)
              .value(this.languages[this.langIndex])
              .margin({ left: 16 })
              .layoutWeight(1)
              .onSelect((idx: number) => this.langIndex = idx)
          }
          .width('100%').padding({ left: 16, right: 16, top: 4 })
          .alignItems(VerticalAlign.Center)

          // 搜索框
          TextInput({ text: this.query, placeholder: '搜索字幕…' })
            .width('100%')
            .margin({ left: 16, right: 16, top: 12 })
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(AppColors.grey850)
            .padding(10)
            .borderRadius(6)
            .onChange((v: string) => this.query = v)

          // 搜索按钮
          Button('搜索')
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor(AppColors.orange500)
            .fontColor('#FFFFFF')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .height(44)
            .margin({ left: 16, right: 16, top: 12 })
            .onClick(() => {
              // TODO(契约)：接入字幕数据源（OpenSubtitles / 自建）后调搜索接口把结果塞 this.results
              UiFeedback.showToast({ message: '需要接入字幕数据源' });
            })

          // 结果列表 / 空态
          if (this.results.length === 0) {
            Column() {
              Image($r('app.media.ic_subtitles')).width(40).height(40)
                .fillColor(AppColors.grey500).opacity(0.5)
              Text('暂无搜索结果').fontSize(13).fontColor(AppColors.grey500)
                .margin({ top: 8 })
              Text('点击「搜索」开始查找字幕').fontSize(11).fontColor(AppColors.grey500)
                .margin({ top: 4 })
            }
            .width('100%')
            .padding({ top: 48, bottom: 48 })
            .alignItems(HorizontalAlign.Center)
          } else {
            List({ space: 0 }) {
              ForEach(this.results, (item: string, index: number) => {
                ListItem() {
                  SubtitleResultRow({
                    title: item,
                    subtitle: '',
                    onDownload: () => {
                      // TODO(契约)：接入字幕数据源后调用下载接口并 addSubtitleSlave(uri)
                      UiFeedback.showToast({ message: '需要接入字幕数据源' });
                    },
                  })
                }
              }, (item: string, index: number) => index.toString())
            }
            .width('100%').margin({ top: 12 })
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
          }

          // 把登录链接推到底部
          Blank().layoutWeight(1)

          // 底部登录链接（轻量样式）
          Row() {
            Text('登录 OpenSubtitles')
              .fontSize(13).fontColor(AppColors.orange500)
              .padding({
                left: 12,
                right: 12,
                top: 10,
                bottom: 10
              })
            Image($r('app.media.ic_arrow_right')).width(16).height(16)
              .fillColor(AppColors.orange500)
          }
          .width('100%').justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 16 })
          .onClick(() => {
            // TODO(契约)：接入 OpenSubtitles 登录后跳登录页
            UiFeedback.showToast({ message: '需要接入字幕数据源' });
          })
        }
        .width('100%').alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** arkts 严格模式禁止未类型化对象字面量，Select 必须接 LangOption[]。 */
  private languageOptions(): LangOption[] {
    return this.languages.map((v: string): LangOption => new LangOption(v));
  }
}
