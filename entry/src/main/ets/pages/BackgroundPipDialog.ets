import { AppColors } from '../common/constants/AppConstants';

/**
 * 背景/画中画模式单选对话框(对应 VLC Android 设置-视频-背景/画中画模式)。
 * 值:0=停止播放 1=在后台播放视频(视频切音频) 2=以画中画模式播放视频。
 * 存储 key 复用 Settings.KEY_VIDEO_APP_SWITCH(与附加设置页一致)。
 */
export const BACKGROUND_PIP_DEFAULT: string = '0';

export const BACKGROUND_PIP_VALUES: string[] = ['0', '1', '2'];

export const BACKGROUND_PIP_LABELS: string[] = ['停止', '在后台播放视频', '以画中画模式播放视频'];

/**
 * BackgroundPipDialog ——「背景/画中画模式」单选对话框。
 * 由设置首页通过 UIContext.openCustomDialog 承载;点击任一选项即回调并由宿主持久化。
 */
@ComponentV2
export struct BackgroundPipDialog {
  @Param title: ResourceStr = '背景/画中画模式';
  @Param labels: string[] = BACKGROUND_PIP_LABELS;
  @Param values: string[] = BACKGROUND_PIP_VALUES;
  @Param selectedValue: string = BACKGROUND_PIP_DEFAULT;
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
          Radio({ value: this.valueAt(index), group: 'background_pip' })
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
