import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 全局 Context 持有者。EntryAbility.onCreate 注入,数据层(Preferences/MediaLibrary)取用。
 */
export class AppContext {
  private static context: common.UIAbilityContext | null = null;
  private static backgroundListeners: Array<() => void> = [];
  private static formatTestMode: boolean = false;
  private static formatTestLimit: number = 0;
  private static formatTestStart: number = 0;
  private static formatVideoTimeoutMs: number = 15000;
  private static formatAudioTimeoutMs: number = 8000;
  private static formatParseTimeoutMs: number = 10000;

  static set(ctx: common.UIAbilityContext): void {
    AppContext.context = ctx;
  }

  static get(): common.UIAbilityContext {
    if (!AppContext.context) {
      throw new Error('AppContext not initialized');
    }
    return AppContext.context;
  }

  static isReady(): boolean {
    return AppContext.context !== null;
  }

  static setFormatTestMode(enabled: boolean): void {
    AppContext.formatTestMode = enabled;
  }

  static isFormatTestMode(): boolean {
    return AppContext.formatTestMode;
  }

  static setFormatTestLimit(limit: number): void {
    AppContext.formatTestLimit = limit;
  }

  static getFormatTestLimit(): number {
    return AppContext.formatTestLimit;
  }

  static setFormatTestStart(start: number): void {
    AppContext.formatTestStart = start;
  }

  static getFormatTestStart(): number {
    return AppContext.formatTestStart;
  }

  static setFormatVideoTimeoutMs(ms: number): void {
    AppContext.formatVideoTimeoutMs = ms;
  }

  static getFormatVideoTimeoutMs(): number {
    return AppContext.formatVideoTimeoutMs;
  }

  static setFormatAudioTimeoutMs(ms: number): void {
    AppContext.formatAudioTimeoutMs = ms;
  }

  static getFormatAudioTimeoutMs(): number {
    return AppContext.formatAudioTimeoutMs;
  }

  static setFormatParseTimeoutMs(ms: number): void {
    AppContext.formatParseTimeoutMs = ms;
  }

  static getFormatParseTimeoutMs(): number {
    return AppContext.formatParseTimeoutMs;
  }

  /** 注册应用退后台回调(EntryAbility.onBackground 触发)。 */
  static onAppBackground(listener: () => void): void {
    if (!AppContext.backgroundListeners.includes(listener)) {
      AppContext.backgroundListeners.push(listener);
    }
  }

  /** 注销应用退后台回调。 */
  static offAppBackground(listener: () => void): void {
    AppContext.backgroundListeners = AppContext.backgroundListeners.filter(
      (l: () => void) => l !== listener);
  }

  /** EntryAbility.onBackground 调用,广播给当前页面。 */
  static notifyAppBackground(): void {
    hilog.info(0x0001, 'VLC', '[VLC] notifyAppBackground listeners=%{public}d',
      AppContext.backgroundListeners.length);
    const copy: Array<() => void> = AppContext.backgroundListeners.slice();
    for (const listener of copy) {
      try {
        listener();
      } catch (e) {
        // 单个监听器异常不影响其它监听器
      }
    }
  }
}
