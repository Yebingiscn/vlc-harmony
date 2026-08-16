import { AppColors } from '../common/constants/AppConstants';

/**
 * 硬件加速单选对话框(对应 VLC Android 设置-视频-硬件加速)。
 * 值:-1=自动(不干预,OHOS 默认优先硬解,失败自动回退软解) 0=禁用(强制软解)
 *      1=解码加速(硬解但关闭直渲) 2=完全加速(硬解+直渲)。
 */
export const HARDWARE_ACCELERATION_DEFAULT: string = '-1';

export const HARDWARE_ACCELERATION_VALUES: string[] = ['-1', '0', '1', '2'];

export const HARDWARE_ACCELERATION_LABELS: string[] = ['自动', '禁用', '解码加速', '完全加速'];

/** 值 → 中文文案(未知值回退默认)。 */
export function hardwareAccelerationLabel(value: string): string {
  const idx: number = HARDWARE_ACCELERATION_VALUES.indexOf(value);
  return idx >= 0 ? HARDWARE_ACCELERATION_LABELS[idx] : HARDWARE_ACCELERATION_LABELS[0];
}

/**
 * HardwareAccelerationDialog ——「硬件加速」单选对话框。
 * 由设置首页通过 UIContext.openCustomDialog 承载;点击任一选项即回调并由宿主持久化。
 */
@ComponentV2
export struct HardwareAccelerationDialog {
  @Param title: ResourceStr = '硬件加速';
  @Param labels: string[] = HARDWARE_ACCELERATION_LABELS;
  @Param values: string[] = HARDWARE_ACCELERATION_VALUES;
  @Param selectedValue: string = HARDWARE_ACCELERATION_DEFAULT;
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

      Repeat(this.labels).each((labelRepeatItem: RepeatItem<string>) => {
        Row() {
          Radio({ value: this.valueAt(labelRepeatItem.index), group: 'hardware_acceleration' })
            .checked(this.selectedValue === this.valueAt(labelRepeatItem.index))
            .radioStyle({ checkedBackgroundColor: AppColors.orange500 })
            .onChange((on: boolean) => {
              if (on) {
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
        .padding({
          left: 4,
          right: 4,
          top: 16,
          bottom: 16
        })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.onSelect(this.valueAt(labelRepeatItem.index)))
      }).key((label: string, index: number) => `${index}`)

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
