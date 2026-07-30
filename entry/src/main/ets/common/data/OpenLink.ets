import { common, Want } from '@kit.AbilityKit';
import { AppContext } from './AppContext';

/**
 * OpenLink —— 安卓 `openLinkIfPossible(url)` 的鸿蒙等价物。
 * 用系统默认处理器(Want action=ohos.want.action.viewData + uri)拉起浏览器/外链。
 * 失败(无可用处理器/Context 未就绪)静默返回 false,不崩。
 */
export class OpenLink {
  static open(url: string): boolean {
    if (url.length === 0 || !AppContext.isReady()) {
      return false;
    }
    try {
      const ctx: common.UIAbilityContext = AppContext.get();
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      ctx.startAbility(want);
      return true;
    } catch (e) {
      return false;
    }
  }
}
