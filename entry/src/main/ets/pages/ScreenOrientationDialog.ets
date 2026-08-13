import { AppColors } from '../common/constants/AppConstants';

/**
 * 视频屏幕方向选项(对齐 VLC Android Constants.SCREEN_ORIENTATION_*)。
 * 值:99=自动(传感器感应) 102=纵向 101=横向 103=横向旋转180° 98=上次锁定的方向。
 */
export const SCREEN_ORIENTATION_DEFAULT: string = '99';

export const SCREEN_ORIENTATION_VALUES: string[] = ['99', '102', '101', '103', '98'];

export const SCREEN_ORIENTATION_LABELS: string[] = [
  '自动（传感器感应）',
  '纵向',
  '横向',
  '横向旋转180°',
  '上次锁定的方向',
];

/** 值 → 中文文案(用于设置行摘要;未知值回退默认)。 */
export function screenOrientationLabel(value: string): string {
  const idx: number = SCREEN_ORIENTATION_VALUES.indexOf(value);
  return idx >= 0 ? SCREEN_ORIENTATION_LABELS[idx] : SCREEN_ORIENTATION_LABELS[0];
}

/**
 * ScreenOrientationDialog —— 「视频屏幕方向」单选框对话框。
 * 由设置首页/播放器通过 UIContext.openCustomDialog 承载;点击任一选项即回调并由宿主持久化。
 */
@ComponentV2
export struct ScreenOrientationDialog {
  @Param title: ResourceStr = '视频屏幕方向';
  @Param labels: string[] = SCREEN_ORIENTATION_LABELS;
  @Param values: string[] = SCREEN_ORIENTATION_VALUES;
  @Param selectedValue: string = SCREEN_ORIENTATION_DEFAULT;
  @Event onSelect: (value: string) => void = () => {
  };
  @Event onCancel: () => void = () => {
  };

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .margin({ bottom: 12 })

      ForEach(this.labels, (label: string, index: number) => {
        Row() {
          Radio({ value: this.valueAt(index), group: 'screen_orientation' })
            .checked(this.selectedValue === this.valueAt(index))
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((on: boolean) => {
              if (on) {
                this.onSelect(this.valueAt(index));
              }
            })
          Text(label)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: 4,
          right: 4,
          top: 16,
          bottom: 16
        })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onSelect(this.valueAt(index)))
      }, (label: string, index: number) => `${index}`)

      Button($r('app.string.cancel'))
        .type(ButtonType.Normal)
        .fontSize(15)
        .fontColor(AppColors.orange500)
        .backgroundColor(Color.Transparent)
        .alignSelf(ItemAlign.End)
        .margin({ top: 8 })
        .onClick(() => this.onCancel())
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius(16)
  }

  private valueAt(index: number): string {
    return index >= 0 && index < this.values.length ? this.values[index] : '';
  }
}
