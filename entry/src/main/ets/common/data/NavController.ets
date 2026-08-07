import { SecondaryParam } from '../models/MediaModels';

/**
 * 全局 NavPathStack 持有(供非页面层,如 PlaybackService 触发跳转,或 cross-tab 通信)。
 * Index 页面 aboutToAppear 注入。
 */
export class NavController {
  private static stack: NavPathStack | null = null;

  static set(stack: NavPathStack): void {
    NavController.stack = stack;
  }

  static get(): NavPathStack | null {
    return NavController.stack;
  }

  static push(name: string, param?: Object): void {
    if (NavController.stack) {
      if (param) {
        NavController.stack.pushPathByName(name, param);
      } else {
        NavController.stack.pushPathByName(name, '');
      }
    }
  }

  /** 跳转 Secondary 宿主页(KEY_FRAGMENT 派发)。集中构造 SecondaryParam 以满足 ArkTS 字面量类型要求。 */
  static pushSecondary(fragment: string, title?: string): void {
    const param: SecondaryParam = { fragment: fragment, title: title };
    NavController.push('Secondary', param);
  }

  static pop(): void {
    if (NavController.stack) {
      NavController.stack.pop();
    }
  }

  /** 弹出 Main 之上的所有页面,直接落回 Main(用于"回到音频浏览器"类跨页跳转)。 */
  static popToMain(): void {
    if (NavController.stack) {
      NavController.stack.popToName('Main', '');
    }
  }
}
