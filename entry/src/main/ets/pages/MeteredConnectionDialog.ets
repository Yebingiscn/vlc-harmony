import { AppColors } from '../common/constants/AppConstants';

/** 按流量计费的网络下对串流的处理:0=不执行任何操作 1=停止播放 2=警告我。 */
export const METERED_CONNECTION_DEFAULT: string = '0';

export const METERED_CONNECTION_VALUES: string[] = ['0', '1', '2'];

export const METERED_CONNECTION_LABELS: string[] = [
  '不执行任何操作',
  '停止播放',
  '警告我（播放音频时可能不会注意到警告文字）',
];

/** 选项值 → 设置首页摘要文案。 */
export function meteredConnectionLabel(value: string): string {
  const idx: number = METERED_CONNECTION_VALUES.indexOf(value);
  return idx >= 0 ? METERED_CONNECTION_LABELS[idx] : METERED_CONNECTION_LABELS[0];
}

/**
 * MeteredConnectionDialog ——「按流量计费的网络下对串流的处理」单选对话框。
 * 由设置首页通过 UIContext.openCustomDialog 承载;点击任一选项即回调并由页面持久化。
 */
@ComponentV2
export struct MeteredConnectionDialog {
  @Param title: ResourceStr = '按流量计费的网络下对串流的处理';
  @Param labels: string[] = METERED_CONNECTION_LABELS;
  @Param values: string[] = METERED_CONNECTION_VALUES;
  @Param selectedValue: string = METERED_CONNECTION_DEFAULT;
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
          Radio({ value: this.valueAt(labelRepeatItem.index), group: 'metered_connection' })
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
