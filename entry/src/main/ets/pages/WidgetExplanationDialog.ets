import { AppColors } from '../common/constants/AppConstants';

/**
 * WidgetExplanationDialog —— VLC 小组件 3 步向导 BottomSheet。
 * Step1(尺寸):标题 "VLC widgets" + 副标题 + widget 尺寸预览图(轮播 mini/micro/pill/macro);
 * Step2(缩放):标题改 "To change the widget type, long press…" + 缩放预览 + 长按手指图标;
 * Step3(结束):标题改 "Widgets are heavily customizable…" + 主题图标 + 结束语,按钮变 "Close"。
 * 右下角 Next/Close 按钮按 currentStep(1→2→3→关闭)推进。
 * TODO(契约): 尺寸图轮播(2000ms 切换)、缩放手柄/长按动画由调用方驱动;此处用静态条件渲染还原 3 步结构。
 */
@ComponentV2
export struct WidgetExplanationDialog {
  @Event onClose: () => void = () => {};
  @Local currentStep: number = 1; // 1 / 2 / 3

  nextStep(): void {
    if (this.currentStep >= 3) {
      this.onClose();
    } else {
      this.currentStep = this.currentStep + 1;
    }
  }

  get titleText(): string {
    if (this.currentStep === 1) return 'VLC widgets';
    if (this.currentStep === 2) return 'To change the widget type, long press the widget, then drag the handles.';
    return 'Widgets are heavily customizable.';
  }

  get buttonText(): string {
    return this.currentStep >= 3 ? 'Close' : 'Next';
  }

  build() {
    Scroll() {
      Column() {
        // 标题(恒显示)
        Text(this.titleText)
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16 })

        // Step1:尺寸
        if (this.currentStep === 1) {
          Text($r('app.string.widget_explanation_size'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.orange500)
            .width('100%').padding({ left: 16, right: 16 })
          Image($r('app.media.vlc_widget_macro'))
            .width('100%').height(256).objectFit(ImageFit.Contain).padding(16)
        }

        // Step2:缩放
        if (this.currentStep === 2) {
          Text($r('app.string.widget_explanation_resize'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.orange500)
            .width('100%').padding({ left: 16, right: 16 })
          Stack() {
            Image($r('app.media.widget_preview_mini'))
              .width('100%').height(200).objectFit(ImageFit.Contain).padding(8)
          }
          .width('100%').margin({ bottom: 16 })
        }

        // Step3:结束
        if (this.currentStep === 3) {
          Row() {
            Image($r('app.media.ic_theme')).width(48).height(48).fillColor(AppColors.orange500)
            Text($r('app.string.widget_explanation_end'))
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              .margin({ left: 16 }).layoutWeight(1)
          }
          .width('100%').margin({ top: 16 }).alignItems(VerticalAlign.Center)
        }

        // 右下角按钮
        Row() {
          Button(this.buttonText)
            .type(ButtonType.Normal).borderRadius(4)
            .backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
            .margin({ right: 16, bottom: 16 })
            .onClick(() => this.nextStep())
        }
        .width('100%').justifyContent(FlexAlign.End)
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
