import { common } from '@kit.AbilityKit';

/**
 * 全局 Context 持有者。EntryAbility.onCreate 注入,数据层(Preferences/MediaLibrary)取用。
 */
export class AppContext {
  private static context: common.UIAbilityContext | null = null;

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
}
