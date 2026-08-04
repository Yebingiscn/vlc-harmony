import { common } from '@kit.AbilityKit';

/**
 * 全局 Context 持有者。EntryAbility.onCreate 注入,数据层(Preferences/MediaLibrary)取用。
 */
export class AppContext {
  private static context: common.UIAbilityContext | null = null;
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
}
