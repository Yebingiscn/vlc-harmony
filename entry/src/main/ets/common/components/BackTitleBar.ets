import { NavController } from '../data/NavController';

/**
 * BackTitleBar —— 子页面统一顶部标题栏(@ComponentV2)。
 * 返回箭头 + 标题,内置状态栏避让 padding(top:32)。
 * 需要右侧额外按钮的页面可在外部自行拼装 Row。
 */
@ComponentV2
export struct BackTitleBar {
  @Param title: string = '';
  @Event onBack: () => void = () => {
    NavController.pop();
  };

  build() {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.list_title'))
        .margin({ left: 4 })
        .onClick(() => this.onBack())
      Text(this.title)
        .fontSize(20)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(1)
    }
    .width('100%')
    .height(56)
    .padding({
      left: 4,
      right: 4,
      top: 32,
      bottom: 8
    })
    .backgroundColor($r('app.color.background_actionbar'))
    .alignItems(VerticalAlign.Center)
  }
}
