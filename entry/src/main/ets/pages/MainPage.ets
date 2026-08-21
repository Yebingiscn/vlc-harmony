import { UiFeedback } from '../common/utils/UiFeedback';
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
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerMode,
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigationMenuItemOptions,
  HdsTabs,
  HdsTabsController,
  HideMode,
  ScrollEffectType
} from '@kit.UIDesignKit';


/**
 * MainPage —— MainActivity(透明 5-Tab 宿主)。
 * HDS 动态标题栏 + 5 个 HdsTabs 内容页 + 扫描进度条 + FAB + 悬浮底栏。
 * 默认 Tab=Video。状态保留用 Stack+visibility(非条件渲染)。
 */
@ComponentV2
export struct MainPage {
  private tabsController: HdsTabsController = new HdsTabsController();
  private videoScroller: Scroller = new Scroller();
  private audioArtistScroller: Scroller = new Scroller();
  private audioAlbumListScroller: Scroller = new Scroller();
  private audioAlbumGridScroller: Scroller = new Scroller();
  private audioTrackListScroller: Scroller = new Scroller();
  private audioTrackGridScroller: Scroller = new Scroller();
  private audioGenreListScroller: Scroller = new Scroller();
  private audioGenreGridScroller: Scroller = new Scroller();
  private browseScroller: Scroller = new Scroller();
  private playlistsScroller: Scroller = new Scroller();
  private moreScroller: Scroller = new Scroller();
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

  private createTitleMenuItem(icon: ResourceStr, label: ResourceStr,
    action: () => void): HdsNavigationMenuItemOptions {
    return {
      content: {
        icon: icon,
        label: label,
        action: action
      }
    };
  }

  private titleMenuItems(): HdsNavigationMenuItemOptions[] {
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.selectionMode) {
      items.push(this.createTitleMenuItem($r('app.media.ic_play_player'), '播放', () => {
        this.selectionActionType = 'play';
        this.selectionActionVersion++;
      }));
      items.push(this.createTitleMenuItem($r('app.media.ic_fav_add'), '收藏', () => {
        this.selectionActionType = 'fav';
        this.selectionActionVersion++;
      }));
      items.push(this.createTitleMenuItem($r('app.media.ic_delete'), '删除', () => {
        this.selectionActionType = 'delete';
        this.selectionActionVersion++;
      }));
      return items;
    }
    if (this.searchMode) {
      return items;
    }
    if (this.currentTab === 'video' || this.currentTab === 'audio' || this.currentTab === 'playlists') {
      items.push(this.createTitleMenuItem($r('app.media.ic_search'), '搜索', () => {
        this.searchMode = true;
        this.searchQuery = '';
      }));
    }
    if (this.currentTab === 'video') {
      items.push(this.createTitleMenuItem($r('app.media.ic_resume_playback'), $r('app.string.resume'), () => {
        void this.resumePlayback();
      }));
      items.push(this.createTitleMenuItem($r('app.media.ic_display_settings'),
        $r('app.string.menu_display_settings'), () => this.openDisplaySettings()));
    } else if (this.currentTab === 'audio') {
      items.push(this.createTitleMenuItem($r('app.media.ic_display_settings'), '音频显示设置',
        () => this.openAudioDisplaySettings()));
    } else if (this.currentTab === 'browse') {
      items.push(this.createTitleMenuItem($r('app.media.ic_view_list'), $r('app.string.menu_display_as_list'), () => {
        void this.toggleDisplayAsList();
      }));
      items.push(this.createTitleMenuItem($r('app.media.ic_network_big'), $r('app.string.menu_browse_network'),
        () => NavController.pushSecondary('NETWORK')));
      items.push(this.createTitleMenuItem($r('app.media.ic_favorite'), $r('app.string.menu_favorite_server'),
        () => this.openFavoriteServer()));
    }
    items.push(this.createTitleMenuItem($r('app.media.ic_incognito'), $r('app.string.incognito_mode'),
      () => this.toggleIncognito()));
    items.push(this.createTitleMenuItem($r('app.media.ic_refresh'), $r('app.string.menu_refresh'), () => {
      void this.refreshMediaLibrary();
    }));
    return items;
  }

  private boundScrollers(): Scroller[] {
    return [
      this.videoScroller,
      this.audioArtistScroller,
      this.audioAlbumListScroller,
      this.audioAlbumGridScroller,
      this.audioTrackListScroller,
      this.audioTrackGridScroller,
      this.audioGenreListScroller,
      this.audioGenreGridScroller,
      this.browseScroller,
      this.playlistsScroller,
      this.moreScroller
    ];
  }

  private closeTransientMode(): void {
    if (this.selectionMode) {
      this.selectionActionType = 'exit';
      this.selectionActionVersion++;
      return;
    }
    this.searchMode = false;
    this.searchQuery = '';
  }

  @Builder
  titleSearchBuilder() {
    Row({ space: 8 }) {
      Search({ value: this.searchQuery, placeholder: $r('app.string.search_in_current_list') })
        .height(40)
        .layoutWeight(1)
        .fontColor($r('app.color.list_title'))
        .placeholderColor($r('app.color.list_subtitle'))
        .backgroundColor($r('app.color.card_background'))
        .defaultFocus(true)
        .onChange((value: string) => {
          this.searchQuery = value;
        })
      if (this.searchQuery.length > 0) {
        Image($r('app.media.ic_close_small'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_subtitle'))
          .onClick(() => {
            this.searchQuery = '';
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
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
    HdsNavDestination() {
      Column() {
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
                contentScroller: this.videoScroller,
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
                artistScroller: this.audioArtistScroller,
                albumListScroller: this.audioAlbumListScroller,
                albumGridScroller: this.audioAlbumGridScroller,
                trackListScroller: this.audioTrackListScroller,
                trackGridScroller: this.audioTrackGridScroller,
                genreListScroller: this.audioGenreListScroller,
                genreGridScroller: this.audioGenreGridScroller,
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
              MainBrowserPage({ contentScroller: this.browseScroller })
            }
            .tabBar(this.tabBarStyle(VLC_TABS[2]))

            TabContent() {
              PlaylistsPage({
                contentScroller: this.playlistsScroller,
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
              MorePage({ contentScroller: this.moreScroller })
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
            lightColor: $r('app.color.orange500')
          })
          .scrollable(false)
          .cachedMaxCount(VLC_TABS.length, TabsCacheMode.CACHE_BOTH_SIDE)
          .onChange((index: number) => this.onTabIndexChange(index))
          .bindSheet(this.showFavoriteServer, this.favoriteServerSheet(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,

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
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      padding: {
        start: LengthMetrics.vp(5),
        end: LengthMetrics.vp(5)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.selectionMode ? `已选择 ${this.selectionCount} 项` : $r('app.string.app_name')
        },
        subIcon: {
          content: {
            icon: this.incognitoMode ? $r('app.media.ic_incognito') : $r('app.media.ic_about_logo'),
            label: $r('app.string.app_name'),
            isEnabled: false
          }
        },
        backIcon: {
          icon: $r('app.media.ic_arrow_back'),
          label: '退出',
          action: () => this.closeTransientMode()
        },
        menu: {
          value: this.titleMenuItems(),
          maxCount: 3
        },
        bottomBuilder: this.searchMode ? {
          builder: (): void => this.titleSearchBuilder(),
          height: 56
        } : undefined,
        divider: {
          showType: DividerShowType.AUTO
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(!this.searchMode && !this.selectionMode)
    .hideToolBar(true)
    .bindToScrollable(this.boundScrollers())
    .dynamicHideTitleBar({
      hideTitleArea: false,
      hideBottomBuilder: true,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP
    })
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
        title: '收藏服务器',
        onClose: () => this.showFavoriteServer = false,
      }).width('100%')
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
