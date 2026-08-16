import { UiFeedback } from '../common/utils/UiFeedback';
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
import { AudioBrowserRequest } from '../common/data/AudioBrowserRequest';
import { AppColors, TabItem, VLC_TABS } from '../common/constants/AppConstants';
import { DisplaySettingsDialog } from './DisplaySettingsDialog';
import { AudioDisplaySettingsDialog } from './AudioDisplaySettingsDialog';
import { NetworkServerDialog } from './NetworkServerDialog';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { VideoParam, VideoPlayItem } from './VideoPlayerPage';
import { DividerMode, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';


/**
 * MainPage —— MainActivity(透明 5-Tab 宿主)。
 * 顶部 VlcToolbar + 内容区(visibility 切换保留各 Tab 状态)+ 扫描进度条 + FAB + BottomTabBar。
 * 默认 Tab=Video。状态保留用 Stack+visibility(非条件渲染)。
 */
@ComponentV2
export struct MainPage {
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local currentTab: string = 'video';
  @Local currentTabIndex: number = 0;
  @Local scanning: boolean = false;
  @Local showFab: boolean = false;
  @Local showDisplaySettings: boolean = false;
  @Local showFavoriteServer: boolean = false;
  @Local displaySettingsVersion: number = 0;
  @Local incognitoMode: boolean = false;
  @Local showAudioDisplaySettings: boolean = false;
  @Local audioSettingsVersion: number = 0;
  @Local searchMode: boolean = false;
  @Local searchQuery: string = '';
  /** 自增用于通知 PlaylistsPage 重新拉取数据(NavDestination 重新可见时 +1)。 */
  @Local playlistsVersion: number = 0;
  /** "转到艺人"定位目标(传给 AudioBrowserPage,配合 goToArtistVersion 触发 @Monitor)。 */
  @Local goToArtistName: string = '';
  /** "转到艺人"定位请求版本号:自增保证同名艺人连续定位也会触发 @Monitor。 */
  @Local goToArtistVersion: number = 0;
  @Local selectionMode: boolean = false;
  @Local selectionCount: number = 0;
  @Local selectionActionVersion: number = 0;
  @Local selectionActionType: string = '';

  async aboutToAppear(): Promise<void> {
    this.incognitoMode = Settings.incognitoMode;
    this.scanning = MediaLibrary.isScanning() || !MediaLibrary.hasScanned();
    await MediaLibrary.scan();
    this.scanning = false;
    this.displaySettingsVersion++;
    this.audioSettingsVersion++;
  }

  onTabChange(id: string): void {
    this.currentTab = id;
    this.currentTabIndex = this.indexOfTab(id);
    // 切换 Tab 时退出搜索和选择模式
    this.searchMode = false;
    this.searchQuery = '';
    if (this.selectionMode) {
      this.selectionActionType = 'exit';
      this.selectionActionVersion++;
    }
    Settings.put(Settings.KEY_FRAGMENT_ID, this.indexOfTab(id));
    this.showFab = id === 'video';
  }

  onTabIndexChange(index: number): void {
    const tab: TabItem | undefined = VLC_TABS[index];
    if (tab) {
      this.onTabChange(tab.id);
    }
  }

  tabBarStyle(tab: TabItem): BottomTabBarStyle {
    return BottomTabBarStyle.of(tab.icon, tab.label)
      .labelStyle({
        font: { size: 12 },
        selectedColor: AppColors.orange500,
        unselectedColor: $r('app.color.list_subtitle'),
      })
      .iconStyle({
        selectedColor: AppColors.orange500,
        unselectedColor: $r('app.color.list_subtitle'),
      });
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

  openAudioDisplaySettings(): void {
    this.showAudioDisplaySettings = true;
  }

  async resumePlayback(): Promise<void> {
    const entries = await PlaybackHistory.load();
    if (entries.length === 0) {
      UiFeedback.showToast({ message: '暂无播放历史' });
      return;
    }
    const latest = entries[0];
    const param: VideoParam = {
      uri: latest.uri,
      title: latest.title,
      list: [{ uri: latest.uri, title: latest.title, artworkUrl: latest.artworkUrl } as VideoPlayItem],
      index: 0,
    };
    NavController.push('VideoPlayer', param);
  }

  toggleIncognito(): void {
    const next = !Settings.incognitoMode;
    Settings.put(Settings.KEY_INCOGNITO, next);
    this.incognitoMode = next;
    UiFeedback.showToast({
      message: next ? $r('app.string.menu_incognito_on') : $r('app.string.menu_incognito_off'),
    });
  }

  async refreshMediaLibrary(): Promise<void> {
    this.scanning = true;
    await MediaLibrary.rescan();
    this.scanning = false;
    // 通知 VideoGridPage 重建列表(scan 完成后数据已更新,但页面不会自动 rebuild)。
    this.displaySettingsVersion++;
    this.audioSettingsVersion++;
  }

  async toggleDisplayAsList(): Promise<void> {
    const next = !(await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false));
    Settings.put(Settings.KEY_DISPLAY_AS_LIST, next);
    UiFeedback.showToast({
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

  /** 音频显示设置 BottomSheet。 */
  @Builder
  audioDisplaySettingsSheet() {
    AudioDisplaySettingsDialog({ onClose: () => this.showAudioDisplaySettings = false })
      .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        VlcToolbar({
          title: $r('app.string.app_name'),
          showBack: false,
          showSearch: !this.searchMode && !this.selectionMode &&
            (this.currentTab === 'video' || this.currentTab === 'audio' || this.currentTab === 'playlists'),
          showMore: !this.selectionMode,
          currentTab: this.currentTab,
          incognitoMode: this.incognitoMode,
          searchMode: this.searchMode,
          searchQuery: this.searchQuery,
          selectionMode: this.selectionMode,
          selectionCount: this.selectionCount,
          onSearch: () => {
            this.searchMode = true;
            this.searchQuery = '';
          },
          onSearchBack: () => {
            this.searchMode = false;
            this.searchQuery = '';
          },
          onSearchQueryChange: (q: string) => {
            this.searchQuery = q;
          },
          onSelectionBack: () => {
            this.selectionActionType = 'exit';
            this.selectionActionVersion++;
          },
          onSelectionPlay: () => {
            this.selectionActionType = 'play';
            this.selectionActionVersion++;
          },
          onSelectionFav: () => {
            this.selectionActionType = 'fav';
            this.selectionActionVersion++;
          },
          onSelectionDelete: () => {
            this.selectionActionType = 'delete';
            this.selectionActionVersion++;
          },
          onMoreSettings: () => this.openDisplaySettings(),
          onMoreIncognito: () => this.toggleIncognito(),
          onMoreDisplayAsList: () => this.toggleDisplayAsList(),
          onMoreBrowseNetwork: () => NavController.pushSecondary('NETWORK'),
          onMoreFavoriteServer: () => this.openFavoriteServer(),
          onMoreRefresh: () => this.refreshMediaLibrary(),
          onResumePlayback: () => this.resumePlayback(),
          onAudioDisplaySettings: () => this.openAudioDisplaySettings(),
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

        Stack({ alignContent: Alignment.Bottom }) {
          HdsTabs({
            controller: this.tabsController,
            barPosition: BarPosition.End,
            index: this.currentTabIndex,
          }) {
          TabContent() {
            VideoGridPage({
              settingsVersion: this.displaySettingsVersion,
              searchMode: this.searchMode,
              searchQuery: this.searchQuery,
              selectionActionVersion: this.selectionActionVersion,
              selectionActionType: this.selectionActionType,
              onSearchGlobal: () => {
                this.searchMode = false;
                this.searchQuery = '';
                NavController.push('Search');
              },
              onSelectionChange: (active: boolean, count: number) => {
                this.selectionMode = active;
                this.selectionCount = count;
              },
            })
          }
          .tabBar(this.tabBarStyle(VLC_TABS[0]))

          TabContent() {
            AudioBrowserPage({
              settingsVersion: this.audioSettingsVersion,
              searchMode: this.searchMode,
              searchQuery: this.searchQuery,
              goToArtistName: this.goToArtistName,
              goToArtistVersion: this.goToArtistVersion,
              onSearchGlobal: () => {
                this.searchMode = false;
                this.searchQuery = '';
                NavController.push('Search');
              },
            })
          }
          .tabBar(this.tabBarStyle(VLC_TABS[1]))

          TabContent() {
            MainBrowserPage()
          }
          .tabBar(this.tabBarStyle(VLC_TABS[2]))

          TabContent() {
            PlaylistsPage({
              searchMode: this.searchMode,
              searchQuery: this.searchQuery,
              currentTab: this.currentTab,
              playlistsVersion: this.playlistsVersion,
              onSearchGlobal: () => {
                this.searchMode = false;
                this.searchQuery = '';
                NavController.push('Search');
              },
            })
          }
          .tabBar(this.tabBarStyle(VLC_TABS[3]))

          TabContent() {
            MorePage()
          }
          .tabBar(this.tabBarStyle(VLC_TABS[4]))
          }
          .width('100%')
          .height('100%')
          .barWidth(328)
          .barHeight(64)
          .divider({ mode: DividerMode.NONE })
          .vertical(false)
          .barPosition(BarPosition.End)
          .barOverlap(true)
          .barFloatingStyle({
            barBottomMargin: 28,
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.ADAPTIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
            },
          })
          .scrollable(false)
          .cachedMaxCount(VLC_TABS.length, TabsCacheMode.CACHE_BOTH_SIDE)
          .onChange((index: number) => this.onTabIndexChange(index))
          .bindSheet(this.showFavoriteServer, this.favoriteServerSheet(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            backgroundColor: '#FFFFFF',
            showClose: false,
            onDisappear: () => this.showFavoriteServer = false,
          })

          MiniPlayer()
            .width(328)
            .margin({ bottom: 100 })
        }.borderRadius(16)
        .layoutWeight(1)
        .width('100%')

      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
      .bindSheet(this.showDisplaySettings, this.displaySettingsSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: false,
        backgroundColor: $r('app.color.bottom_sheet_background'),
        showClose: false,
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        onDisappear: () => {
          this.showDisplaySettings = false;
          this.displaySettingsVersion++;
        },
      })
    }
    .hideTitleBar(true)
    .onShown(() => {
      // 从 VideoPlayer/AudioPlayer 等子页面返回时触发,
      // 自增版本号让 PlaylistsPage 通过 @Monitor('playlistsVersion') 重新拉数据。
      this.playlistsVersion++;
      // 消费 AudioPlayer "转到艺人"请求:切到音频 tab,派发给 AudioBrowserPage 定位到该艺人。
      const artist = AudioBrowserRequest.consumeArtist();
      if (artist.length > 0) {
        this.onTabChange('audio');
        this.goToArtistName = artist;
        this.goToArtistVersion++;
      }
    })
    .onBackPressed(() => {
      // 选择模式优先退出选择,搜索模式其次退出搜索,最后交给系统
      if (this.selectionMode) {
        this.selectionActionType = 'exit';
        this.selectionActionVersion++;
        return true;
      }
      if (this.searchMode) {
        this.searchMode = false;
        this.searchQuery = '';
        return true;
      }
      return false;
    })
    .bindSheet(this.showAudioDisplaySettings, this.audioDisplaySettingsSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: false,
      backgroundColor: $r('app.color.bottom_sheet_background'),
      showClose: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onDisappear: () => {
        this.showAudioDisplaySettings = false;
        this.audioSettingsVersion++;
      },
    })
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
