/**
 * VLC 睡眠计时器的数字缓冲：最多四位，最后两位始终表示分钟。
 * 例如：7 -> 7m，123 -> 1h 23m，1234 -> 12h 34m。
 */
export function appendSleepDigit(digits: string, digit: string): string {
  if (digits.length >= 4 || digit.length !== 1 || digit < '0' || digit > '9') {
    return digits;
  }
  return digits + digit;
}

/** `:00` / `:30` 在还有两个输入位时补到数字缓冲的末尾。 */
export function appendSleepMinuteShortcut(digits: string, minute: string): string {
  // Android 先判断当前输入是否已满四位，随后整体追加分钟快捷键。
  // 因此三位数字再按 :00/:30 时会形成五位缓冲，解析时仅保留末四位。
  if ((minute !== '00' && minute !== '30') || digits.length >= 4) {
    return digits;
  }
  return digits + minute;
}

/**
 * 从输入缓冲得到与语言无关的时间数字。界面层用资源文件决定“小时/分钟”的实际文案，
 * 因此本模型不拼接 h、m 或任何中文文字。
 */
export interface SleepTimeParts {
  hours: number;
  minutes: number;
}

export function sleepDigitsToParts(digits: string): SleepTimeParts {
  if (digits.length === 0) {
    return { hours: 0, minutes: 0 };
  }
  if (digits.length <= 2) {
    return { hours: 0, minutes: parseInt(digits, 10) };
  }
  const normalized: string = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
  const minuteDigits: string = normalized.substring(normalized.length - 2);
  const hourDigits: string = normalized.substring(0, normalized.length - 2);
  return { hours: parseInt(hourDigits, 10), minutes: parseInt(minuteDigits, 10) };
}

/** 数字缓冲转为毫秒，供播放器和设置页持久化。 */
export function sleepDigitsToMillis(digits: string): number {
  const parts: SleepTimeParts = sleepDigitsToParts(digits);
  return parts.hours * 3600000 + parts.minutes * 60000;
}

/** 已保存的倒计时反推为不超过四位的数字缓冲。 */
export function sleepMillisToDigits(millis: number): string {
  if (millis <= 0) {
    return '';
  }
  const totalMinutes: number = Math.floor(millis / 60000);
  const hours: number = Math.floor(totalMinutes / 60);
  const minutes: number = totalMinutes % 60;
  if (hours === 0) {
    return `${minutes}`;
  }
  const minuteText: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
  const value: string = `${hours}${minuteText}`;
  return value.length > 4 ? value.substring(value.length - 4) : value;
}
