import { AppColors } from '../common/constants/AppConstants';

/** 数字键盘键:18fp Bold 居中,获焦橙色。 */
@ComponentV2
struct TimeKey {
  @Param label: string = '';
  @Param passValue: string = '';
  @Event onKey: (v: string) => void = () => {};

  build() {
    Text(this.label)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .layoutWeight(1)
      .height('100%')
      .textAlign(TextAlign.Center)
      .onClick(() => this.onKey(this.passValue))
  }
}

/**
 * JumpToTimeDialog —— 「Jump to Time」数字键盘跳转 BottomSheet(showTimeOnly=true)。
 * 18fp Medium 标题 + 24fp Bold 时间预览 + 退格键(ic_backspace)+ 4×3 数字键盘(1-9/:00/0/:30)
 * + OK 按钮(全宽)。showTimeOnly=true 故隐藏 wait/reset CheckBox 与 Remove current;maxTimeSize=6。
 * TODO(契约): executeAction() → getTimeInMillis() → PlaybackService.seek(newTime)+ 刷新进度,然后 dismiss。
 */
@ComponentV2
export struct JumpToTimeDialog {
  @Event onClose: () => void = () => {};
  /** 确认跳转:回调传入目标时间(ms);宿主据此 seek。 */
  @Event onConfirm: (timeMs: number) => void = () => {};

  @Local pickedRawTime: string = '';
  @Local formatTime: string = '';
  readonly maxTimeSize: number = 6;

  updateValue(value: string): void {
    if (this.pickedRawTime.length >= this.maxTimeSize && value.length > 0) {
      return;
    }
    if (value.length === 0) {
      // 重解析(退格后)
    } else {
      this.pickedRawTime = this.pickedRawTime + value;
    }
    // 从右到左按 2 位切片解析 seconds/minutes/hours
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

  /** pickedRawTime → 毫秒(从右到左按 2 位切 seconds/minutes/hours)。 */
  getTimeInMillis(): number {
    const raw: string = this.pickedRawTime;
    const seconds: number = raw.length > 4 ? parseInt(raw.substring(raw.length - 2), 10) : 0;
    const minutes: number = raw.length > 2 ? parseInt(raw.substring(Math.max(0, raw.length - 4), raw.length - 2), 10) : 0;
    const hours: number = raw.length > 4 ? parseInt(raw.substring(0, raw.length - 4), 10) : 0;
    return (hours * 3600 + minutes * 60 + seconds) * 1000;
  }

  build() {
    Column() {
      // 标题
      Text('Jump to Time')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .height(56)
        .width('100%')
        .margin({ left: 16, right: 16, top: 8 })
        .maxLines(1)
        .textAlign(TextAlign.Start)

      // 时间预览 + 退格
      Row() {
        Blank().layoutWeight(1)
        Text(this.formatTime)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Image($r('app.media.ic_backspace'))
          .width(28).height(28)
          .fillColor('#FFFFFF')
          .margin({ left: 8, right: 16 })
          .onClick(() => this.deleteLastNumber())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8, left: 16, right: 16 })

      // 数字键盘
      Row() {
        TimeKey({ label: '1', passValue: '1', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '2', passValue: '2', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '3', passValue: '3', onKey: (v) => this.updateValue(v) })
      }
      .width('100%').height(44).margin({ top: 8, left: 16, right: 16 })

      Row() {
        TimeKey({ label: '4', passValue: '4', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '5', passValue: '5', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '6', passValue: '6', onKey: (v) => this.updateValue(v) })
      }
      .width('100%').height(44).margin({ top: 8, left: 16, right: 16 })

      Row() {
        TimeKey({ label: '7', passValue: '7', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '8', passValue: '8', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '9', passValue: '9', onKey: (v) => this.updateValue(v) })
      }
      .width('100%').height(44).margin({ top: 8, left: 16, right: 16 })

      Row() {
        TimeKey({ label: ':00', passValue: '00', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: '0', passValue: '0', onKey: (v) => this.updateValue(v) })
        TimeKey({ label: ':30', passValue: '30', onKey: (v) => this.updateValue(v) })
      }
      .width('100%').height(44).margin({ left: 16, right: 16 })

      // OK 按钮(全宽)
      Button($r('app.string.ok'))
        .type(ButtonType.Capsule)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(AppColors.orange500)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ top: 24, left: 16, right: 16, bottom: 16 })
        .onClick(() => {
          // AVPlayer seek:宿主据 onConfirm(timeMs) 调 vm.seekTo。libVLC 刷新进度契约在此之上叠加。
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
