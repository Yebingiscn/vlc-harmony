import { AppColors } from '../common/constants/AppConstants';

/**
 * JumpToTimeDialog —— 「跳转至时间」弹窗。
 *
 * 输入模型:从右往左按 2 位切 h/m/s(mm:ss / h:mm:ss)。
 *   30    → 30s
 *   130   → 1m 30s
 *   1230  → 12m 30s
 *   11230 → 1h 12m 30s
 */

@ComponentV2
export struct JumpToTimeDialog {
  @Event onClose: () => void = () => {};
  @Event onConfirm: (timeMs: number) => void = () => {};

  // 主题感知:浅色=白底深字,深色=深底浅字。资源定义见 base/dark element/color.json。
  readonly cPanelBg: Resource = $r('app.color.background_default');
  readonly cHeaderBg: Resource = $r('app.color.background_default');
  readonly cAccent: string = '#FF8800';
  readonly cCardBg: Resource = $r('app.color.card_background');
  readonly cKeyBg: Resource = $r('app.color.background_default_darker');
  readonly cDim: Resource = $r('app.color.list_subtitle');
  readonly cSubtle: Resource = $r('app.color.font_light');

  @Local pickedRawTime: string = '';
  @Local formatTime: string = '';
  readonly maxTimeSize: number = 6;

  private parts(): string[] {
    const raw: string = this.pickedRawTime;
    const seconds: string = raw.length > 2 ? raw.substring(raw.length - 2) : raw;
    const minutes: string = raw.length > 2 ? raw.substring(Math.max(0, raw.length - 4), raw.length - 2) : '';
    const hours: string = raw.length > 4 ? raw.substring(0, raw.length - 4) : '';
    return [hours, minutes, seconds];
  }

  updateValue(value: string): void {
    if (value.length > 0 && this.pickedRawTime.length + value.length > this.maxTimeSize) {
      return;
    }
    if (value.length > 0) {
      this.pickedRawTime = this.pickedRawTime + value;
    }
    const p: string[] = this.parts();
    let out: string = '';
    if (p[0].length > 0) { out = out + `${p[0]}h `; }
    if (p[1].length > 0) { out = out + `${p[1]}m `; }
    if (p[2].length > 0) { out = out + `${p[2]}s`; }
    this.formatTime = out.trim();
  }

  deleteLastNumber(): void {
    if (this.pickedRawTime.length > 0) {
      this.pickedRawTime = this.pickedRawTime.substring(0, this.pickedRawTime.length - 1);
      this.updateValue('');
    }
  }

  getTimeInMillis(): number {
    const p: string[] = this.parts();
    const hours: number = p[0].length > 0 ? parseInt(p[0], 10) : 0;
    const minutes: number = p[1].length > 0 ? parseInt(p[1], 10) : 0;
    const seconds: number = p[2].length > 0 ? parseInt(p[2], 10) : 0;
    return (hours * 3600 + minutes * 60 + seconds) * 1000;
  }

  canConfirm(): boolean {
    return this.pickedRawTime.length > 0 && this.getTimeInMillis() > 0;
  }

  // ── 键盘键 ──────────────────────────────────────
  @Builder
  numKey(label: string, pass: string) {
    Text(label)
      .fontSize(22)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.list_title'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(48)
      .backgroundColor(this.cKeyBg)
      .borderRadius(10)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.updateValue(pass))
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(28).height(28)
          .fillColor($r('app.color.list_title'))
          .padding(2)
          .onClick(() => this.onClose())
        Text('跳转至时间')
          .fontSize(18).fontWeight(600)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Row().width(28)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16, top: 20 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.cHeaderBg)

      // 时间预览卡
      Row() {
        Blank().layoutWeight(1)
        Text(this.formatTime.length > 0 ? this.formatTime : '0s')
          .fontSize(28).fontWeight(FontWeight.Bold)
          .fontColor(this.formatTime.length > 0 ? $r('app.color.list_title') : this.cDim)
        Image($r('app.media.ic_backspace'))
          .width(26).height(26)
          .fillColor(this.pickedRawTime.length > 0 ? $r('app.color.list_title') : $r('app.color.font_light'))
          .margin({ left: 12 })
          .onClick(() => this.deleteLastNumber())
      }
      .width('100%')
      .height(64)
      .padding({ left: 18, right: 18 })
      .backgroundColor(this.cCardBg)
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
      .margin({ left: 20, right: 20, top: 14 })

      // 键盘
      Column({ space: 8 }) {
        Row({ space: 8 }) { this.numKey('1', '1'); this.numKey('2', '2'); this.numKey('3', '3'); }
        .width('100%')
        Row({ space: 8 }) { this.numKey('4', '4'); this.numKey('5', '5'); this.numKey('6', '6'); }
        .width('100%')
        Row({ space: 8 }) { this.numKey('7', '7'); this.numKey('8', '8'); this.numKey('9', '9'); }
        .width('100%')
        Row({ space: 8 }) { this.numKey(':00', '00'); this.numKey('0', '0'); this.numKey(':30', '30'); }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .margin({ top: 14 })

      // 确定按钮
      Button('确定')
        .type(ButtonType.Capsule)
        .fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor(this.cAccent)
        .fontColor('#FFFFFF')
        .width('100%')
        .height(46)
        .enabled(this.canConfirm())
        .opacity(this.canConfirm() ? 1 : 0.4)
        .margin({ left: 20, right: 20, top: 20, bottom: 28 })
        .onClick(() => {
          this.onConfirm(this.getTimeInMillis());
          this.onClose();
        })
    }
    .width('100%')
    .backgroundColor(this.cPanelBg)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }
}
