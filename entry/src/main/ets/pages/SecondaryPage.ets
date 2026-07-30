import { VlcToolbar } from '../common/components/VlcToolbar';
import { NavController } from '../common/data/NavController';
import { SecondaryParam, FileBrowserParam } from '../common/models/MediaModels';
import { promptAction } from '@kit.ArkUI';

/**
 * SecondaryPage —— SecondaryActivity(pushed 宿主壳)。
 * 读取 KEY_FRAGMENT 派发 8 种子页(ABOUT/STREAMS/HISTORY/PREFERENCES/STORAGE/NETWORK/
 * ARTIST/ALBUM/PLAYLIST),无匹配 finish。统一 Toolbar(标题随 fragment)。
 */
@ComponentV2
export struct SecondaryPage {
  @Param param: SecondaryParam = { fragment: '' };
  @Local title: Resource = $r('app.string.app_name');

  aboutToAppear(): void {
    this.title = this.resolveTitle();
    if (this.param.fragment.length === 0) {
      NavController.pop();
      return;
    }
    // STORAGE/NETWORK 改派发到 FileBrowserPage(BrowserMode)。
    if (this.param.fragment === 'STORAGE') {
      NavController.pop();
      const p: FileBrowserParam = { mode: 'storage' };
      NavController.push('FileBrowser', p);
      return;
    }
    if (this.param.fragment === 'NETWORK') {
      NavController.pop();
      const pn: FileBrowserParam = { mode: 'network' };
      NavController.push('FileBrowser', pn);
      return;
    }
  }

  resolveTitle(): Resource {
    switch (this.param.fragment) {
      case 'ABOUT':
        return $r('app.string.about');
      case 'STREAMS':
        return $r('app.string.streams');
      case 'HISTORY':
        return $r('app.string.history');
      case 'PREFERENCES':
        return $r('app.string.preferences');
      case 'NETWORK':
        return $r('app.string.network_browsing');
      case 'PLAYLIST':
        return $r('app.string.playlists');
      default:
        return $r('app.string.app_name');
    }
  }

  build() {
    NavDestination() {
      Column() {
        VlcToolbar({ title: this.title, showBack: true, onBack: () => NavController.pop() })
        // 内容区:按 fragment 派发(未实现项显示空态 + toast)
        Column() {
          if (this.param.fragment === 'ABOUT') {
            this.aboutContent()
          } else {
            Column() {
              Image($r('app.media.ic_empty')).width(96).height(96).fillColor('#424242')
              Text($r('app.string.developing')).fontSize(14).fontColor('#9E9E9E').margin({ top: 12 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.background_default'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  @Builder
  aboutContent() {
    Scroll() {
      Column() {
        Image($r('app.media.ic_about_logo')).width(96).height(96).objectFit(ImageFit.Contain).margin({ top: 32 })
        Text($r('app.string.app_name')).fontSize(24).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          .margin({ top: 16 })
        Text($r('app.string.welcome_subtitle')).fontSize(13).fontColor('#9E9E9E').margin({ top: 8 })
        Text('© 1996-2026 VideoLAN').fontSize(12).fontColor('#757575').margin({ top: 24 })
        Text('GPLv2').fontSize(12).fontColor('#757575').margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
