import { AppColors } from '../common/constants/AppConstants';

export const VIDEO_RATIO_BEST_FIT: string = '0';
export const VIDEO_RATIO_FIT_SCREEN: string = '1';
export const VIDEO_RATIO_FILL: string = '2';
export const VIDEO_RATIO_16_9: string = '3';
export const VIDEO_RATIO_4_3: string = '4';
export const VIDEO_RATIO_ORIGINAL: string = '5';

export const VIDEO_RATIO_VALUES: string[] = [
  VIDEO_RATIO_BEST_FIT,
  VIDEO_RATIO_FIT_SCREEN,
  VIDEO_RATIO_FILL,
  VIDEO_RATIO_16_9,
  VIDEO_RATIO_4_3,
  VIDEO_RATIO_ORIGINAL,
];

export const VIDEO_RATIO_LABELS: string[] = [
  '最佳适配',
  '适应屏幕',
  '拉伸填充',
  '16:9',
  '4:3',
  '原始尺寸',
];

export function videoRatioLabel(value: string): string {
  const index: number = VIDEO_RATIO_VALUES.indexOf(value);
  return index >= 0 ? VIDEO_RATIO_LABELS[index] : VIDEO_RATIO_LABELS[0];
}

@ComponentV2
export struct VideoAspectRatioDialog {
  @Param selectedValue: string = VIDEO_RATIO_BEST_FIT;
  @Event onSelect: (value: string) => void = () => {
  };
  @Event onCancel: () => void = () => {
  };

  build() {
    Column() {
      Text('画面比例')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .margin({ bottom: 12 })

      Repeat(VIDEO_RATIO_LABELS).each((labelRepeatItem: RepeatItem<string>) => {
        Row() {
          Radio({ value: this.valueAt(labelRepeatItem.index), group: 'video_aspect_ratio' })
            .checked(this.selectedValue === this.valueAt(labelRepeatItem.index))
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((checked: boolean) => {
              if (checked) {
                this.onSelect(this.valueAt(labelRepeatItem.index));
              }
            })
          Text(labelRepeatItem.item)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 14, bottom: 14 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onSelect(this.valueAt(labelRepeatItem.index)))
      }).key((_label: string, index: number) => `${index}`)

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
    return index >= 0 && index < VIDEO_RATIO_VALUES.length ? VIDEO_RATIO_VALUES[index] : VIDEO_RATIO_BEST_FIT;
  }
}
