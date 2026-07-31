import { PreferenceItem } from '../common/models/PreferenceModels';

/**
 * PreferenceNumberPickerDialog —— NumberPickerPreference 弹窗(@ComponentV2 + 纯展示 bindSheet 风格)。
 * 来源:NumberPickerPreferenceDialog(pref_number_picker.xml)+ NumberPickerPreference(MIN=1,MAX=100)。
 * 内容:居中数字选择器(ArkUI 用 TextPicker 近似 NumberPicker,range=min..max)+ 底部 取消/确定 按钮。
 * 确定 → onConfirm(newValue);取消 → onDismiss。
 * 持久化与 summary 刷新由调用方(Settings.put + PreferenceRow summary)处理,本弹窗仅回传选中值。
 */
@ComponentV2
export struct PreferenceNumberPickerDialog {
  @Param title: ResourceStr = '';
  @Param item: PreferenceItem = new PreferenceItem({});
  @Param currentValue: number = 0;
  /** 下限(NumberPickerPreference.MIN_VALUE=1)。 */
  @Param min: number = 1;
  /** 上限(NumberPickerPreference.MAX_VALUE=100)。 */
  @Param max: number = 100;
  @Event onConfirm: (value: number) => void = () => {};
  @Event onDismiss: () => void = () => {};

  @Local picked: number = 0;
  @Local initialized: boolean = false;

  aboutToAppear(): void {
    this.picked = this.currentValue;
    this.initialized = true;
  }

  build(): void {
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.list_title'))
        .margin({ bottom: 16 })

      // 数字选择器(+/- 步进,显示当前值;近似 NumberPicker)。
      Row() {
        Text('-')
          .fontSize(22).fontColor($r('app.color.list_subtitle')).padding(12)
          .onClick(() => {
            if (this.picked > this.min) {
              this.picked = this.picked - 1;
            }
          })
        Text(`${this.picked}`)
          .fontSize(28).fontColor($r('app.color.orange500')).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('+')
          .fontSize(22).fontColor($r('app.color.list_subtitle')).padding(12)
          .onClick(() => {
            if (this.picked < this.max) {
              this.picked = this.picked + 1;
            }
          })
      }
      .width('70%')
      .margin({ bottom: 16 })

      Row() {
        Text($r('app.string.cancel'))
          .fontSize(14)
          .fontColor($r('app.color.list_subtitle'))
          .padding(8)
          .onClick(() => this.onDismiss())
        Text($r('app.string.ok'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.orange500'))
          .margin({ left: 24 })
          .padding(8)
          .onClick(() => {
            this.onConfirm(this.picked);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius(12)
  }

  buildRange(): string[] {
    const arr: string[] = [];
    for (let i = this.min; i <= this.max; i++) {
      arr.push(`${i}`);
    }
    return arr;
  }

  clampedIndex(value: number): number {
    const idx: number = value - this.min;
    if (idx < 0) {
      return 0;
    }
    const last: number = this.max - this.min;
    return idx > last ? last : idx;
  }
}
