import { AppColors } from '../common/constants/AppConstants';

/**
 * WidgetMigrationDialog —— 旧版小组件迁移提示静态信息 BottomSheet。
 * 标题1(widget_old_text,"We updated our widgets!",18fp Medium,minHeight 56vp)+ 说明文1(widget_old_description_start)
 * + 预览图(widget_preview_mini,高 128vp,centerInside)+ 标题2(whats_next)+ 说明文2(widget_old_description_end)。
 * 无按钮/无交互/无状态/无业务逻辑。
 */
@ComponentV2
export struct WidgetMigrationDialog {
  @Event onClose: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        // 标题1
        Text($r('app.string.widget_old_text'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16 }).width('100%')

        // 说明文1
        Text($r('app.string.widget_old_description_start'))
          .fontSize(14).fontColor('#FFFFFF')
          .margin({ left: 16, top: 8, right: 16 }).width('100%')

        // 预览图(高 128vp)
        Image($r('app.media.widget_preview_mini'))
          .height(128).objectFit(ImageFit.Contain).width('100%').margin({ top: 16 })

        // 标题2
        Text($r('app.string.whats_next'))
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16 }).width('100%')

        // 说明文2
        Text($r('app.string.widget_old_description_end'))
          .fontSize(14).fontColor('#FFFFFF')
          .margin({ left: 16, top: 8, right: 16, bottom: 16 }).width('100%')
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
