import {
  appendSleepDigit,
  appendSleepMinuteShortcut,
  sleepDigitsToParts,
  sleepDigitsToMillis,
  sleepMillisToDigits,
} from '../common/models/SleepTimerInputModels';

/**
 * 睡眠倒计时底部抽屉的内容组件；外层 PreferencesPage 负责 bindSheet 的展示与关闭。
 *
 * 输入规则与 Android VLC 完全一致，关键是数字缓冲从右向左解析，而不是“先输入小时”：
 *
 * - 1 或 2 位数字只代表分钟：`5` 显示为 `5m`，`30` 显示为 `30m`，并不是小时。
 * - 从第 3 位起，最后两位固定代表分钟，前面的数字代表小时：
 *   `123` → `1h 23m`，`1234` → `12h 34m`。
 * - 普通数字最多输入 4 位；达到 4 位后继续点数字不会改变时间。
 * - `:00` / `:30` 是“追加分钟”快捷键：数字不足 4 位时会直接向末尾追加两位，
 *   已满 4 位时无效。Android 对三位数字的原始行为较特殊：`123` 后按 `:30`
 *   会短暂形成 `12330`，解析时只取末四位，因此最终为 `23h 30m`。
 * - 退格每次只删除缓冲末尾的一位；快捷键加入的两位也需要删除两次。
 *
 * initialMillis 与两个 initial 选项来自已保存的默认睡眠计时器。打开抽屉时会还原它们，
 * “确定”将当前缓冲转换成毫秒回传，“移除当前项”交给宿主清空保存值。
 */
@ComponentV2
export struct SleepTimerDialog {
  @Event onClose: () => void = () => {};
  @Event onClear: () => void = () => {};
  @Event onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) => void = () => {};

  @Param initialMillis: number = 0;
  @Param initialWaitMediaEnd: boolean = false;
  @Param initialResetOnInteraction: boolean = false;

  /** 原始数字缓冲；显示值与总毫秒数均由它推导，避免两份状态不同步。 */
  @Local digits: string = '';
  @Local totalMillis: number = 0;
  @Local hasInput: boolean = false;
  @Local waitChecked: boolean = false;
  @Local resetChecked: boolean = false;

  /** 每次打开均从设置页传入的保存值初始化，避免沿用上一次抽屉的临时输入。 */
  aboutToAppear(): void {
    this.waitChecked = this.initialWaitMediaEnd;
    this.resetChecked = this.initialResetOnInteraction;
    this.digits = sleepMillisToDigits(this.initialMillis);
    this.recompute();
  }

  /** 根据数字缓冲同步刷新格式化时间和供父组件持久化的毫秒值。 */
  private recompute(): void {
    this.totalMillis = sleepDigitsToMillis(this.digits);
    this.hasInput = this.digits.length > 0;
  }

  /** 追加一个普通数字；达到四位时 appendSleepDigit 会保留原输入。 */
  private pressDigit(digit: string): void {
    this.digits = appendSleepDigit(this.digits, digit);
    this.recompute();
  }

  /** 追加 `00` 或 `30` 分钟快捷键，不会替换已输入的分钟。 */
  private pressMinutes(minute: string): void {
    this.digits = appendSleepMinuteShortcut(this.digits, minute);
    this.recompute();
  }

  /** 与 Android 的退格键一致：一次只移除最后一个数字。 */
  private deleteLast(): void {
    if (!this.hasInput) {
      return;
    }
    this.digits = this.digits.substring(0, this.digits.length - 1);
    this.recompute();
  }

  /**
   * 使用资源模板输出时间；VLC 的计时器单位固定采用 h/m 缩写，
   * 不随应用语言写成“小时/分钟”或“hour/minute”。
   */
  private displayTime(): ResourceStr {
    const parts = sleepDigitsToParts(this.digits);
    if (parts.hours === 0) {
      return $r('app.string.sleep_timer_minutes', parts.minutes);
    }
    return $r('app.string.sleep_timer_hours_minutes', parts.hours, parts.minutes);
  }

  /**
   * Sheet 内部直接修改 @Local 状态。不要把闭包穿过 @Builder 再作为 onClick 回调，
   * 否则部分 ArkUI 版本不会把这次点击绑定到当前组件实例。
   */
  private toggleOption(option: number): void {
    if (option === 0) {
      this.waitChecked = !this.waitChecked;
      return;
    }
    this.resetChecked = !this.resetChecked;
  }

  /** 数字和分钟快捷键共用的键盘单元；minute 非空时走快捷键逻辑。 */
  @Builder
  digitKey(label: string, minute: string = '') {
    Text(label)
      .width('33.33%')
      .height(60)
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor(minute.length > 0 ? $r('app.color.orange500') : $r('app.color.sleep_timer_key'))
      .textAlign(TextAlign.Center)
      .padding({ top: 16, bottom: 16 })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .onClick(() => {
        if (minute.length > 0) {
          this.pressMinutes(minute);
        } else {
          this.pressDigit(label);
        }
      })
  }

  /** Android 风格的 checkbox 行；使用 ArkUI 原生 Checkbox 处理选中状态与点击事件。 */
  @Builder
  checkOption(label: ResourceStr, checked: boolean, option: number) {
    Row({ space: 18 }) {
      Checkbox()
        .select(checked)
        .selectedColor($r('app.color.orange500'))
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .onChange((selected: boolean) => {
          if (option === 0) {
            this.waitChecked = selected;
          } else {
            this.resetChecked = selected;
          }
        })
      Text(label)
        .fontSize(15)
        .layoutWeight(1)
        .onClick(() => this.toggleOption(option))
    }
    .width('100%')
    .height(68)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      // Android 原版为标题、居中的格式化时间和右侧退格键；没有额外的说明卡片。
      Text($r('app.string.sleep_in'))
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 28 })

      Row() {
        Text(this.displayTime())
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
        Image($r('app.media.ic_backspace'))
          .width(54)
          .height(54)
          .fillColor(this.hasInput ? $r('app.color.sleep_timer_key') : $r('app.color.sleep_timer_backspace_disabled'))
          .opacity(this.hasInput ? 1 : 0.5)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
          .onClick(() => this.deleteLast())
      }
      .width('100%')
      .padding({ left: 120, right: 20 })
      .margin({ bottom: 20 })
      .alignItems(VerticalAlign.Center)

      // 四行三列的 Android 时间键盘；:00/:30 仍占用最后一行两侧的位置。
      Column() {
        Row() { this.digitKey('1'); this.digitKey('2'); this.digitKey('3'); }.width('100%')
        Row() { this.digitKey('4'); this.digitKey('5'); this.digitKey('6'); }.width('100%')
        Row() { this.digitKey('7'); this.digitKey('8'); this.digitKey('9'); }.width('100%')
        Row() { this.digitKey(':00', '00'); this.digitKey('0'); this.digitKey(':30', '30'); }.width('100%')
      }
      .width('100%')
      .margin({ bottom: 22 })

      // 两项均为默认睡眠计时器的持久化选项，不改变上方的数字时间解释规则。
      this.checkOption($r('app.string.wait_before_sleep'), this.waitChecked, 0)
      this.checkOption($r('app.string.reset_on_interaction'), this.resetChecked, 1)

      // “移除当前项”清除已保存的默认计时器；“确定”保存当前数字缓冲计算出的时长。
      Row() {
        Text($r('app.string.remove_current'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.orange500'))
          .padding({ top: 18, bottom: 18 })
          .onClick(() => this.onClear())
        Blank()
        Text($r('app.string.ok'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.orange500'))
          .padding({ left: 32, top: 18, bottom: 18 })
          .onClick(() => this.onConfirm(this.totalMillis, this.waitChecked, this.resetChecked))
      }
      .width('100%')
      .margin({ top: 14, bottom: 12 })
    }
    .width('100%')
    .padding({ left: 40, right: 40 })
    .backgroundColor($r('sys.color.background_primary'))
    .borderRadius({ topLeft: 36, topRight: 36 })
    .alignItems(HorizontalAlign.Center)
  }
}
