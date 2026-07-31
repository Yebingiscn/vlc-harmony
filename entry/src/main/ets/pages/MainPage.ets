import { BottomTabBar } from '../common/components/BottomTabBar';
import { VlcToolbar } from '../common/components/VlcToolbar';
import { MiniPlayer } from '../common/components/MiniPlayer';
import { VideoGridPage } from './VideoGridPage';
import { AudioBrowserPage } from './AudioBrowserPage';
import { MainBrowserPage } from './MainBrowserPage';
import { PlaylistsPage } from './PlaylistsPage';
import { MorePage } from './MorePage';
import { Settings } from '../common/data/Settings';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { NavController } from '../common/data/NavController';
import { PermissionCoordinator } from '../common/data/PermissionCoordinator';
import { AppColors } from '../common/constants/AppConstants';

/**
 * MainPage —— MainActivity(透明 5-Tab 宿主)。
 * 顶部 VlcToolbar + 内容区(visibility 切换保留各 Tab 状态)+ 扫描进度条 + FAB + BottomTabBar。
 * 默认 Tab=Video。状态保留用 Stack+visibility(非条件渲染)。
 */
@ComponentV2
export struct MainPage {
  @Local currentTab: string = 'video';
  @Local scanning: boolean = false;
  @Local showFab: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.scanning = MediaLibrary.isScanning() || !MediaLibrary.hasScanned();
    const autoRescan = await Settings.getBoolean(Settings.KEY_MEDIALIBRARY_AUTO_RESCAN, true);
    if (autoRescan) {
      // 先确保媒体读权限(首次弹系统授权框),再扫描 —— 无权限时 photoAccessHelper 返回空。
      await PermissionCoordinator.askStoragePermission(false, false, true);
      await MediaLibrary.scan();
      this.scanning = false;
    } else {
      this.scanning = false;
    }
  }

  onTabChange(id: string): void {
    this.currentTab = id;
    Settings.put(Settings.KEY_FRAGMENT_ID, this.indexOfTab(id));
    // FAB 仅 Video Tab 显示(刷新媒体库)
    this.showFab = id === 'video';
  }

  indexOfTab(id: string): number {
    const map: Record<string, number> = { 'video': 0, 'audio': 1, 'browse': 2, 'playlists': 3, 'more': 4 };
    return map[id] ?? 0;
  }

  build() {
    NavDestination() {
      Column() {
        // 状态栏同色小条
        Column().width('100%').height(0)
        VlcToolbar({
          title: $r('app.string.app_name'),
          showBack: false,
          showSearch: true,
          onSearch: () => NavController.push('Search'),
        })

        if (this.scanning) {
          Row() {
            Progress({ value: 50, total: 100, type: ProgressType.Linear })
              .layoutWeight(1)
              .height(4)
              .color(AppColors.orange500)
          }
          .width('100%').padding(8)
        }

        // 内容区:Stack + visibility 保留各 Tab 状态
        Stack({ alignContent: Alignment.TopStart }) {
          VideoGridPage().visibility(this.currentTab === 'video' ? Visibility.Visible : Visibility.None)
          AudioBrowserPage().visibility(this.currentTab === 'audio' ? Visibility.Visible : Visibility.None)
          MainBrowserPage().visibility(this.currentTab === 'browse' ? Visibility.Visible : Visibility.None)
          PlaylistsPage().visibility(this.currentTab === 'playlists' ? Visibility.Visible : Visibility.None)
          MorePage().visibility(this.currentTab === 'more' ? Visibility.Visible : Visibility.None)
        }
        .layoutWeight(1)
        .width('100%')

        // 迷你播放条:无媒体时由 MiniPlayer 自身按 getCurrent()!=null 不渲染。
        MiniPlayer()

        BottomTabBar({
          currentTab: this.currentTab,
          onTabChange: (id: string) => this.onTabChange(id),
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
  }
}
