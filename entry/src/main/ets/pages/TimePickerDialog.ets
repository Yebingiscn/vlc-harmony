import { AppColors } from '../common/constants/AppConstants';

/**
 * TimePickerDialog —— 通用数字键盘时间选择器(PickTimeFragment 父类布局 dialog_time_picker.xml)。
 * 与 JumpToTime/SleepTimer 共用 4×3 键盘 + 退格 + OK(maxTimeSize=6 含秒)。本组件为通用态,
 * 不带 wait/reset 复选项与 Remove current(由子类决定显示与否)。
 * TODO(契约): executeAction 由调用方注入(跳转/定时等)。
 */
@ComponentV2
export struct TimePickerDialog {
  @Param title: Resource = $r('app.string.tips_title');
  @Param maxTimeSize: number = 6;
  @Event onClose: () => void = () => {};
  @Event onConfirm: (millis: number) => void = () => {};

  @Local pickedRawTime: string = '';
  @Local formatTime: string = '';

  updateValue(value: string): void {
    if (this.pickedRawTime.length >= this.maxTimeSize && value.length > 0) {
      return;
    }
    if (value.length > 0) {
      this.pickedRawTime = this.pickedRawTime + value;
    }
    const raw: string = this.pickedRawTime;
    const seconds: string = raw.length > 4 ? raw.substring(raw.length - 2) : '';
    const minutes: string = raw.length > 2 ? raw.substring(Math.max(0, raw.length - 4), raw.length - 2) : '';
    const hours: string = raw.length > 4 ? raw.substring(0, raw.length - 4) : '';
    let out: string = '';
    if (hours.length > 0) out = out + `${hours}h `;
    if (minutes.length > 0) out = out + `${minutes}m `;
    if (seconds.length > 0) out = out + `${seconds}s`;
    this.formatTime = out.trim();
  }

  deleteLastNumber(): void {
    if (this.pickedRawTime.length > 0) {
      this.pickedRawTime = this.pickedRawTime.substring(0, this.pickedRawTime.length - 1);
      this.updateValue('');
    }
  }

  getTimeInMillis(): number {
    const raw: string = this.pickedRawTime;
    const seconds: number = raw.length > 4 ? parseInt(raw.substring(raw.length - 2), 10) : 0;
    const minutes: number = raw.length > 2 ? parseInt(raw.substring(Math.max(0, raw.length - 4), raw.length - 2), 10) : 0;
    const hours: number = raw.length > 4 ? parseInt(raw.substring(0, raw.length - 4), 10) : 0;
    return hours * 3600000 + minutes * 60000 + seconds * 1000;
  }

  @Builder
  keyItem(label: string, pass: string) {
    Text(label)
      .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      .layoutWeight(1).height('100%').textAlign(TextAlign.Center)
      .onClick(() => this.updateValue(pass))
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        .height(56).width('100%').margin({ top: 8 }).textAlign(TextAlign.Start)

      Row() {
        Blank().layoutWeight(1)
        Text(this.formatTime).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        Image($r('app.media.ic_backspace')).width(28).height(28).fillColor('#FFFFFF')
          .margin({ left: 8, right: 16 }).onClick(() => this.deleteLastNumber())
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ top: 8 })

      Row() { this.keyItem('1', '1'); this.keyItem('2', '2'); this.keyItem('3', '3'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyItem('4', '4'); this.keyItem('5', '5'); this.keyItem('6', '6'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyItem('7', '7'); this.keyItem('8', '8'); this.keyItem('9', '9'); }
      .width('100%').height(44).margin({ top: 8 })
      Row() { this.keyItem(':00', '00'); this.keyItem('0', '0'); this.keyItem(':30', '30'); }
      .width('100%').height(44)

      Button($r('app.string.ok'))
        .type(ButtonType.Capsule).fontWeight(FontWeight.Bold)
        .backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
        .width('100%')
        .margin({ top: 24, left: 16, right: 16, bottom: 16 })
        .onClick(() => {
          this.onConfirm(this.getTimeInMillis());
          this.onClose();
        })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
