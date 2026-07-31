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
import { DisplaySettingsDialog } from './DisplaySettingsDialog';
import { NetworkServerDialog } from './NetworkServerDialog';
import { promptAction } from '@kit.ArkUI';

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
  @Local showDisplaySettings: boolean = false;
  @Local showFavoriteServer: boolean = false;
  @Local displaySettingsVersion: number = 0;

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
    const map: Record<string, number> = {
      'video': 0,
      'audio': 1,
      'browse': 2,
      'playlists': 3,
      'more': 4
    };
    return map[id] ?? 0;
  }

  openDisplaySettings(): void {
    this.showDisplaySettings = true;
  }

  toggleIncognito(): void {
    const next = !Settings.incognitoMode;
    Settings.put(Settings.KEY_INCOGNITO, next);
    promptAction.showToast({
      message: next ? $r('app.string.menu_incognito_on') : $r('app.string.menu_incognito_off'),
    });
  }

  async refreshMediaLibrary(): Promise<void> {
    this.scanning = true;
    await PermissionCoordinator.askStoragePermission(false, false, true);
    await MediaLibrary.scan();
    this.scanning = false;
  }

  async toggleDisplayAsList(): Promise<void> {
    const next = !(await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false));
    Settings.put(Settings.KEY_DISPLAY_AS_LIST, next);
    promptAction.showToast({
      message: next ? $r('app.string.menu_display_list_on') : $r('app.string.menu_display_list_off'),
    });
  }

  openFavoriteServer(): void {
    this.showFavoriteServer = true;
  }

  /** 显示设置 BottomSheet(自定义组件 builder 必须 .width('100%'))。 */
  @Builder
  displaySettingsSheet() {
    DisplaySettingsDialog({ onClose: () => this.showDisplaySettings = false })
      .width('100%')
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
          showMore: true,
          currentTab: this.currentTab,
          onSearch: () => NavController.push('Search'),
          onMoreSettings: () => this.openDisplaySettings(),
          onMoreIncognito: () => this.toggleIncognito(),
          onMoreDisplayAsList: () => this.toggleDisplayAsList(),
          onMoreBrowseNetwork: () => NavController.pushSecondary('NETWORK'),
          onMoreFavoriteServer: () => this.openFavoriteServer(),
          onMoreRefresh: () => this.refreshMediaLibrary(),
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
        Stack() {
          VideoGridPage({ settingsVersion: this.displaySettingsVersion })
            .visibility(this.currentTab === 'video' ? Visibility.Visible : Visibility.Hidden)
          AudioBrowserPage().visibility(this.currentTab === 'audio' ? Visibility.Visible : Visibility.Hidden)
          MainBrowserPage().visibility(this.currentTab === 'browse' ? Visibility.Visible : Visibility.Hidden)
          PlaylistsPage().visibility(this.currentTab === 'playlists' ? Visibility.Visible : Visibility.Hidden)
          MorePage().visibility(this.currentTab === 'more' ? Visibility.Visible : Visibility.Hidden)
        }
        .layoutWeight(1)
        .width('100%')
        .bindSheet(this.showFavoriteServer, this.favoriteServerSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          backgroundColor: '#FFFFFF',
          showClose: false,
          onDisappear: () => this.showFavoriteServer = false,
        })

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
      .bindSheet(this.showDisplaySettings, this.displaySettingsSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: false,
        backgroundColor: '#FFFFFF',
        showClose: false,
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        onDisappear: () => {
          this.showDisplaySettings = false;
          this.displaySettingsVersion++;
        },
      })
    }
    .hideTitleBar(true)
  }

  /** 收藏服务器 BottomSheet(复用 NetworkServerDialog)。 */
  @Builder
  favoriteServerSheet() {
    Column() {
      NetworkServerDialog({
        onClose: () => this.showFavoriteServer = false,
      }).width('100%')
    }
    .width('100%')
  }
}
