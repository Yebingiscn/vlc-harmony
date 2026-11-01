import { SecondaryParam } from '../models/MediaModels';
import { curves, UIContext } from '@kit.ArkUI';
import { LyricsDocument } from './EmbeddedLyrics';

export class AudioPlayerRoute {
  fromMiniPlayer: boolean = true;
  sourcePrefix: string = '';
  /** 艺术家/专辑入口只共享歌手名，不把专辑名误配成正在播放的曲目名。 */
  artistSourceId: string = '';
  uri: string = '';
  title: string = '';
  artist: string = '';
  artworkPath: string = '';
  lyrics: LyricsDocument | null = null;

  static trackPrefix(scope: string, uri: string): string {
    return `audio-track:${encodeURIComponent(scope)}:${encodeURIComponent(uri)}`;
  }
}

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

  /** 悬浮栏和曲目入口使用共享元素转场，避免叠加系统页面动画。 */
  static openAudioPlayer(context: UIContext, route: AudioPlayerRoute = new AudioPlayerRoute(),
    onFinish?: () => void): boolean {
    const stack: NavPathStack | null = NavController.stack;
    if (stack === null || stack.getAllPathName().includes('AudioPlayer')) {
      return false;
    }
    context.animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38), onFinish: onFinish }, () => {
      stack.pushPathByName('AudioPlayer', route, false);
    });
    return true;
  }

  static closeAudioPlayer(context: UIContext, shared: boolean): void {
    const names: string[] = NavController.stack?.getAllPathName() ?? [];
    if (names[names.length - 1] !== 'AudioPlayer') { return; }
    if (shared) {
      context.animateTo({ curve: curves.interpolatingSpring(0, 1, 342, 38) }, () => NavController.stack?.pop(false));
    } else {
      NavController.pop();
    }
  }

  /** 弹出 Main 之上的所有页面,直接落回 Main(用于"回到音频浏览器"类跨页跳转)。 */
  static popToMain(): void {
    if (NavController.stack) {
      NavController.stack.popToName('Main', '');
    }
  }
}
