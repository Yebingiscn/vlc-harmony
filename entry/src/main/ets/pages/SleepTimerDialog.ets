import { AppColors } from '../common/constants/AppConstants';

/**
 * SleepTimerDialog —— 睡眠倒计时数字键盘 BottomSheet。
 *
 * 【输入模型】数字键 = 小时,`:00` / `:30` = 分钟(0 或 30 两档)。
 *   5        → 5小时
 *   5 :30    → 5小时30分
 *   12       → 12小时
 *   90 :30   → 90小时30分(约 3.8 天)
 *   :30      → 0小时30分
 *   :00      → 0小时0分(无效 → 确定键置灰)
 * 小时最多 2 位(99 小时 ≈ 4 天),不换算成天,忠实显示输入值。
 *
 * 按键以 token 序列记录(数字 token = '0'-'9',分钟 token = 'm0'/'m30'),
 * 退格严格按压入顺序弹出,分钟键重复按则替换旧值。
 *
 * 持久化:`initialMillis` 传入上次设定的值(可来自 PlayerService 内存或 Settings),
 * token 序列从该毫秒反推得到 —— 避免每次打开都从 0 开始。
 */
@ComponentV2
export struct SleepTimerDialog {
  @Event onClose: () => void = () => {};
  /** 确认设定:回调传入倒计时毫秒 + 两个选项;宿主据此起定时器并持久化。 */
  @Event onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) => void = () => {};

  /** 上次已设的值(毫秒)。0 = 从未设过。 */
  @Param initialMillis: number = 0;
  @Param initialWaitMediaEnd: boolean = false;
  @Param initialResetOnInteraction: boolean = false;

  /** 按键序列。private:UI 重绘由下面几个 @Local 派生值驱动。 */
  private tokens: string[] = [];

  @Local dispHours: number = 0;
  @Local dispMinutes: number = 0;
  @Local totalMillis: number = 0;
  @Local hasInput: boolean = false;
  @Local waitChecked: boolean = false;
  @Local resetChecked: boolean = false;

  readonly maxHourDigits: number = 2;

  aboutToAppear(): void {
    this.waitChecked = this.initialWaitMediaEnd;
    this.resetChecked = this.initialResetOnInteraction;
    this.tokens = millisToTokens(this.initialMillis);
    this.recompute();
  }

  /** 由 token 序列重算显示值与毫秒值。 */
  private recompute(): void {
    let digits: string = '';
    let min: number = 0;
    for (const t of this.tokens) {
      if (t.charAt(0) === 'm') {
        min = parseInt(t.substring(1), 10);
      } else {
        digits = digits + t;
      }
    }
    this.dispHours = digits.length > 0 ? parseInt(digits, 10) : 0;
    this.dispMinutes = min;
    this.totalMillis = this.dispHours * 3600000 + min * 60000;
    this.hasInput = this.tokens.length > 0;
  }

  /** 已按下的小时位数(分钟 token 不计入)。 */
  private digitCount(): number {
    let n: number = 0;
    for (const t of this.tokens) {
      if (t.charAt(0) !== 'm') {
        n++;
      }
    }
    return n;
  }

  /** 数字键 → 追加一位小时。 */
  private pressDigit(d: string): void {
    if (this.digitCount() >= this.maxHourDigits) {
      return;
    }
    if (this.digitCount() === 0 && d === '0') {
      return;
    }
    this.tokens.push(d);
    this.recompute();
  }

  /** `:00` / `:30` → 设定分钟。重复按替换旧值。 */
  private pressMinutes(min: string): void {
    this.tokens = this.tokens.filter((t: string) => t.charAt(0) !== 'm');
    this.tokens.push(`m${min}`);
    this.recompute();
  }

  /** 退格。 */
  private deleteLast(): void {
    if (this.tokens.length === 0) {
      return;
    }
    this.tokens.pop();
    this.recompute();
  }

  canConfirm(): boolean {
    return this.totalMillis > 0;
  }

  // ── 视觉常量 ───────────────────────────────────────────────
  readonly cKeyBg: string = '#232323';
  readonly cMinKeyBg: string = '#2A2011';
  readonly cCardBg: string = '#1C1C1C';
  readonly cCancelBg: string = '#2A2A2A';
  readonly cSubtle: string = '#9E9E9E';
  readonly cDim: string = '#61FFFFFF';

  /** 数字键(小时)。 */
  @Builder
  digitKey(label: string) {
    Text(label)
      .fontSize(22)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(48)
      .backgroundColor(this.cKeyBg)
      .borderRadius(10)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.pressDigit(label))
  }

  /** 分钟键(0 / 30)。 */
  @Builder
  minuteKey(label: string, min: string) {
    Text(label)
      .fontSize(20)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColors.orange500)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(48)
      .backgroundColor(this.cMinKeyBg)
      .borderRadius(10)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.pressMinutes(min))
  }

  build() {
    Column() {
      // ── 标题 ──────────────────────────────────────────────
      Row() {
        Image($r('app.media.ic_sleep'))
          .width(22).height(22).fillColor(AppColors.orange500)
        Text($r('app.string.sleep_in'))
          .fontSize(19).fontWeight(600).fontColor('#FFFFFF')
          .margin({ left: 10 })
      }
      .width('100%').height(40).alignItems(VerticalAlign.Center)

      Text($r('app.string.sleep_timer_input_hint'))
        .fontSize(12).fontColor(this.cSubtle)
        .width('100%').textAlign(TextAlign.Start).margin({ top: 2 })

      // ── 时间预览卡 ────────────────────────────────────────
      Row() {
        Row() {
          if (!this.hasInput || this.totalMillis === 0) {
            Text('0')
              .fontSize(34).fontWeight(FontWeight.Bold).fontColor(this.cDim)
            Text('小时')
              .fontSize(15).fontColor(this.cDim).margin({ left: 2, bottom: 5 })
          } else {
            if (this.dispHours > 0) {
              Text(`${this.dispHours}`)
                .fontSize(34).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              Text('小时')
                .fontSize(15).fontColor(this.cSubtle).margin({ left: 2, bottom: 5 })
            }
            if (this.dispMinutes > 0) {
              Text(`${this.dispMinutes}`)
                .fontSize(34).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                .margin({ left: this.dispHours > 0 ? 8 : 0 })
              Text('分')
                .fontSize(15).fontColor(this.cSubtle).margin({ left: 2, bottom: 5 })
            }
          }
        }
        .alignItems(VerticalAlign.Bottom)

        Blank()
        Image($r('app.media.ic_backspace'))
          .width(26).height(26)
          .fillColor(this.hasInput ? '#FFFFFF' : this.cDim)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => this.deleteLast())
      }
      .width('100%')
      .height(72)
      .padding({ left: 18, right: 18 })
      .backgroundColor(this.cCardBg)
      .borderRadius(12)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })

      // ── 键盘 ──────────────────────────────────────────────
      Column({ space: 8 }) {
        Row({ space: 8 }) { this.digitKey('1'); this.digitKey('2'); this.digitKey('3'); }
        .width('100%')
        Row({ space: 8 }) { this.digitKey('4'); this.digitKey('5'); this.digitKey('6'); }
        .width('100%')
        Row({ space: 8 }) { this.digitKey('7'); this.digitKey('8'); this.digitKey('9'); }
        .width('100%')
        Row({ space: 8 }) { this.minuteKey(':00', '0'); this.digitKey('0'); this.minuteKey(':30', '30'); }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 14 })

      // ── 复选项(内联,响应式实时刷新) ──────────────────────
      Divider()
        .color($r('app.color.divider')).strokeWidth(0.5)
        .margin({ top: 14 })

      Row() {
        Stack() {
          Row()
            .width('100%').height('100%')
            .borderRadius(4)
            .backgroundColor(this.waitChecked ? AppColors.orange500 : Color.Transparent)
            .border({
              width: this.waitChecked ? 0 : 1.5,
              color: this.waitChecked ? AppColors.orange500 : this.cSubtle,
            })
          if (this.waitChecked) {
            Image($r('app.media.ic_check'))
              .width(14).height(14).fillColor('#FFFFFF')
          }
        }
        .width(20).height(20)
        .onClick(() => this.waitChecked = !this.waitChecked)

        Text($r('app.string.wait_before_sleep'))
          .fontSize(15).fontColor('#E0E0E0')
          .layoutWeight(1).margin({ left: 12 })
          .onClick(() => this.waitChecked = !this.waitChecked)
      }
      .width('100%').height(48)
      .alignItems(VerticalAlign.Center)

      Row() {
        Stack() {
          Row()
            .width('100%').height('100%')
            .borderRadius(4)
            .backgroundColor(this.resetChecked ? AppColors.orange500 : Color.Transparent)
            .border({
              width: this.resetChecked ? 0 : 1.5,
              color: this.resetChecked ? AppColors.orange500 : this.cSubtle,
            })
          if (this.resetChecked) {
            Image($r('app.media.ic_check'))
              .width(14).height(14).fillColor('#FFFFFF')
          }
        }
        .width(20).height(20)
        .onClick(() => this.resetChecked = !this.resetChecked)

        Text($r('app.string.reset_on_interaction'))
          .fontSize(15).fontColor('#E0E0E0')
          .layoutWeight(1).margin({ left: 12 })
          .onClick(() => this.resetChecked = !this.resetChecked)
      }
      .width('100%').height(48)
      .alignItems(VerticalAlign.Center)

      // ── 操作按钮 ──────────────────────────────────────────
      Row({ space: 10 }) {
        Button($r('app.string.cancel'))
          .type(ButtonType.Capsule)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(this.cCancelBg)
          .fontColor('#E0E0E0')
          .height(46)
          .layoutWeight(1)
          .onClick(() => this.onClose())
        Button($r('app.string.ok'))
          .type(ButtonType.Capsule)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(AppColors.orange500)
          .fontColor('#FFFFFF')
          .height(46)
          .layoutWeight(1)
          .enabled(this.canConfirm())
          .opacity(this.canConfirm() ? 1 : 0.35)
          .onClick(() => {
            this.onConfirm(this.totalMillis, this.waitChecked, this.resetChecked);
            this.onClose();
          })
      }
      .width('100%')
      .margin({ top: 18, bottom: 20 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4 })
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 毫秒 → token 序列,用于 aboutToAppear 还原"上次设的值"。
 * 反推规则:总分钟数 % 60 得分钟(只能 0 或 30,其他数用 30 兜底);其余转小时字符串。
 */
function millisToTokens(ms: number): string[] {
  if (ms <= 0) {
    return [];
  }
  const totalMin: number = Math.floor(ms / 60000);
  const hours: number = Math.floor(totalMin / 60);
  const min: number = totalMin % 60;
  const tokens: string[] = [];
  if (hours > 0) {
    const h: string = `${hours}`;
    for (let i: number = 0; i < h.length; i++) {
      tokens.push(h.charAt(i));
    }
  }
  if (min === 30) {
    tokens.push('m30');
  } else if (min !== 0) {
    // 历史值不是 0/30 整倍数(早期版本或外部写入)→ 截到 30,避免显示错乱。
    tokens.push('m30');
  }
  return tokens;
}
