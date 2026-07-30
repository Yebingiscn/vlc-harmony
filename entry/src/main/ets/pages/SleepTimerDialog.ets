import { AppColors } from '../common/constants/AppConstants';

/**
 * SleepTimerDialog —— 睡眠定时器数字键盘 BottomSheet(showTimeOnly=false,含复选项;showDeleteCurrent=true)。
 * 18fp Medium 标题(sleep_in,minHeight 56vp)+ 24fp Bold 时间预览(仅时:分)+ 退格键 + 4×3 数字键盘
 * + 两个复选项(wait_before_sleep / reset_on_interaction)+ 底部 [Remove current][OK] 双按钮。
 * maxTimeSize=4(仅 hhmm,无秒)。TODO(契约): executeAction→写定时器(waitChecked/resetChecked)+dismiss;onDeleteCurrent→清除定时+dismiss。
 */
@ComponentV2
export struct SleepTimerDialog {
  @Event onClose: () => void = () => {};
  @Event onDeleteCurrent: () => void = () => {};

  @Local pickedRawTime: string = '';
  @Local formatTime: string = '';
  @Local waitChecked: boolean = false;
  @Local resetChecked: boolean = false;
  readonly maxTimeSize: number = 4;

  updateValue(value: string): void {
    if (this.pickedRawTime.length >= this.maxTimeSize && value.length > 0) {
      return;
    }
    if (value.length > 0) {
      this.pickedRawTime = this.pickedRawTime + value;
    }
    const raw: string = this.pickedRawTime;
    const minutes: string = raw.length > 2 ? raw.substring(raw.length - 2) : '';
    const hours: string = raw.length > 2 ? raw.substring(0, raw.length - 2) : '';
    let out: string = '';
    if (hours.length > 0) out = out + `${hours}h `;
    if (minutes.length > 0) out = out + `${minutes}m `;
    this.formatTime = out.trim();
  }

  deleteLastNumber(): void {
    if (this.pickedRawTime.length > 0) {
      this.pickedRawTime = this.pickedRawTime.substring(0, this.pickedRawTime.length - 1);
      this.updateValue('');
    }
  }

  @Builder
  keyCell(label: string, pass: string) {
    Text(label)
      .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      .layoutWeight(1).height('100%').textAlign(TextAlign.Center)
      .onClick(() => this.updateValue(pass))
  }

  build() {
    Column() {
      // 标题
      Text($r('app.string.sleep_in'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .height(56).width('100%').margin({ top: 8 }).textAlign(TextAlign.Start)

      // 时间预览 + 退格
      Row() {
        Blank().layoutWeight(1)
        Text(this.formatTime).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        Image($r('app.media.ic_backspace')).width(28).height(28).fillColor('#FFFFFF')
          .margin({ left: 8, right: 16 }).onClick(() => this.deleteLastNumber())
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ top: 8 })

      // 数字键盘
      Row() { this.keyCell('1', '1'); this.keyCell('2', '2'); this.keyCell('3', '3'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyCell('4', '4'); this.keyCell('5', '5'); this.keyCell('6', '6'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyCell('7', '7'); this.keyCell('8', '8'); this.keyCell('9', '9'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyCell(':00', '00'); this.keyCell('0', '0'); this.keyCell(':30', '30'); }
      .width('100%').height(44)

      // 复选项
      Row() {
        Toggle({ type: ToggleType.Checkbox, isOn: this.waitChecked }).selectedColor(AppColors.orange500)
          .onChange((on: boolean) => this.waitChecked = on)
        Text($r('app.string.wait_before_sleep')).fontSize(14).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
      }
      .width('100%').margin({ top: 16 }).alignItems(VerticalAlign.Center)

      Row() {
        Toggle({ type: ToggleType.Checkbox, isOn: this.resetChecked }).selectedColor(AppColors.orange500)
          .onChange((on: boolean) => this.resetChecked = on)
        Text($r('app.string.reset_on_interaction')).fontSize(14).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
      }
      .width('100%').margin({ top: 4 }).alignItems(VerticalAlign.Center)

      // 底部按钮行
      Row() {
        Text($r('app.string.remove_current'))
          .fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1).textAlign(TextAlign.Center)
          .margin({ right: 8 })
          .onClick(() => { this.onDeleteCurrent(); this.onClose(); })
        Text($r('app.string.ok'))
          .fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1).textAlign(TextAlign.Center)
          .onClick(() => {
            // TODO(契约): 写定时器(waitChecked=waitForMediaEnd,resetChecked=resetOnInteraction)+dismiss。
            this.onClose();
          })
      }
      .width('100%').margin({ top: 24, bottom: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
