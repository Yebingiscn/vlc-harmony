import { UiFeedback } from '../common/utils/UiFeedback';
import { Settings } from '../common/data/Settings';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { VideoSeenState } from '../common/data/VideoSeenState';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens, RouteName } from '../common/constants/AppConstants';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { MediaGridCard } from '../common/components/MediaGridCard';
import { MediaListCard } from '../common/components/MediaListCard';
import {
  EmptyLoadingState,
  Folder,
  formatDuration,
  MediaWrapper,
  VideoGroupingType
} from '../common/models/MediaModels';
import { HeaderMediaListParam } from './HeaderMediaListActivityPage';
import { VideoParam, VideoPlayItem } from './VideoPlayerPage';

/**
 * VideoGridPage —— VideoGridFragment(Video Tab 根)。
 * 自适应网格/列表双模式(KEY_VIDEOS_CARDS 默认 true=网格) + 下拉刷新 + 空态/加载态。
 */
@ObservedV2
class VideoGridViewModel {
  @Trace items: MediaWrapper[] = [];
  @Trace folders: Folder[] = [];
  @Trace loading: boolean = true;
  @Trace refreshing: boolean = false;
  @Trace cardMode: boolean = true; // KEY_VIDEOS_CARDS 默认 true(网格)
  @Trace grouping: VideoGroupingType = VideoGroupingType.NAME;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.LOADING;
  @Trace showSeenMarker: boolean = true;
  @Trace showThumbnails: boolean = true;
  private sortField: number = 1;
  private sortDesc: boolean = false;
  private onlyFavs: boolean = false;
  private searchQuery: string = '';

  /** 设置项索引(0=按名称,1=按文件夹,2=不分组) -> VideoGroupingType。 */
  private static toGroupingType(idx: number): VideoGroupingType {
    switch (idx) {
      case 1:
        return VideoGroupingType.FOLDER;
      case 2:
        return VideoGroupingType.NONE;
      default:
        return VideoGroupingType.NAME;
    }
  }

  async load(): Promise<void> {
    this.loading = true;
    this.emptyState = EmptyLoadingState.LOADING;
    this.cardMode = await Settings.getBoolean(Settings.KEY_VIDEOS_CARDS, true);
    this.showSeenMarker = await Settings.getBoolean(Settings.KEY_MEDIA_SEEN, true);
    this.showThumbnails = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    this.sortField = await Settings.getInt(Settings.KEY_VIDEO_SORT, 1);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_VIDEO_SORT_DESC, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_VIDEO_ONLY_FAVS, false);
    this.grouping = VideoGridViewModel.toGroupingType(await Settings.getInt(Settings.KEY_GROUP_VIDEOS, 0));
    // 尊重「自动重新扫描」开关:autoRescan 关闭时不自动扫描。
    // 手动刷新请走 vm.refresh()(下拉 / FAB / 权限弹窗授权后),不受此门控影响。
    await MediaLibrary.scan();
    await MediaLibrary.loadVideoFavs();
    await MediaLibrary.loadFolderFavs();
    await this.rebuild();
    this.loading = false;
  }

  async refresh(): Promise<void> {
    await MediaLibrary.scan();
    await this.rebuild();
  }

  /** 仅重读设置(不重新扫描),用于半模态关闭后刷新显示模式和排序。 */
  async reloadSettings(): Promise<void> {
    this.cardMode = await Settings.getBoolean(Settings.KEY_VIDEOS_CARDS, true);
    this.showSeenMarker = await Settings.getBoolean(Settings.KEY_MEDIA_SEEN, true);
    this.showThumbnails = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    this.sortField = await Settings.getInt(Settings.KEY_VIDEO_SORT, 1);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_VIDEO_SORT_DESC, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_VIDEO_ONLY_FAVS, false);
    this.grouping = VideoGridViewModel.toGroupingType(await Settings.getInt(Settings.KEY_GROUP_VIDEOS, 0));
    await this.rebuild();
  }

  /** 依据当前排序与搜索关键词重建显示列表。 */
  async rebuild(): Promise<void> {
    let base = MediaLibrary.getVideos().slice();
    await VideoSeenState.hydrate(base);
    const trimmed = this.searchQuery.trim().toLowerCase();
    if (trimmed.length > 0) {
      base = base.filter((v: MediaWrapper) => v.title.toLowerCase().includes(trimmed));
    }

    if (this.grouping === VideoGroupingType.FOLDER && trimmed.length === 0) {
      // 按文件夹分组:从全量视频列表派生文件夹卡片。
      let folders = MediaLibrary.getFoldersFromVideos(base);
      // 仅显示收藏:按文件夹收藏过滤(而非视频收藏)。
      if (this.onlyFavs) {
        folders = folders.filter((f: Folder) => MediaLibrary.isFolderFav(f.path));
      }
      this.folders = this.applyFolderSort(folders);
      this.items = [];
    } else {
      // 扁平列表模式:按视频收藏过滤。
      if (this.onlyFavs) {
        base = base.filter((v: MediaWrapper) => MediaLibrary.isVideoFav(v.uri));
      }
      this.folders = [];
      this.items = this.applySort(base);
    }
    this.updateEmpty();
  }

  applySearch(q: string): void {
    this.searchQuery = q;
    this.rebuild();
  }

  applySort(items: MediaWrapper[]): MediaWrapper[] {
    const sorted = items.slice();
    sorted.sort((a: MediaWrapper, b: MediaWrapper) => {
      let cmp = 0;
      switch (this.sortField) {
        case 1:
          cmp = a.title.localeCompare(b.title);
          break;
        case 2:
          cmp = a.length - b.length;
          break;
        case 3:
          cmp = a.dateModified - b.dateModified;
          break;
        case 4:
          cmp = a.id - b.id;
          break;
        case 5:
          cmp = a.dateAdded - b.dateAdded;
          break;
        default:
          cmp = a.title.localeCompare(b.title);
      }
      return this.sortDesc ? -cmp : cmp;
    });
    return sorted;
  }

  /** 文件夹排序:sortField=4(轨道编号)按视频数排序,其余按文件夹名。 */
  applyFolderSort(folders: Folder[]): Folder[] {
    const sorted = folders.slice();
    sorted.sort((a: Folder, b: Folder) => {
      let cmp = 0;
      if (this.sortField === 4) {
        cmp = a.mediaCount - b.mediaCount;
      } else {
        cmp = a.title.localeCompare(b.title);
      }
      return this.sortDesc ? -cmp : cmp;
    });
    return sorted;
  }

  updateEmpty(): void {
    const hasContent = (this.grouping === VideoGroupingType.FOLDER && this.folders.length > 0) ||
      (this.grouping !== VideoGroupingType.FOLDER && this.items.length > 0);
    if (!hasContent) {
      if (this.searchQuery.trim().length > 0) {
        this.emptyState = EmptyLoadingState.EMPTY_SEARCH;
      } else if (this.onlyFavs) {
        this.emptyState = EmptyLoadingState.EMPTY_FAVORITES;
      } else {
        this.emptyState = EmptyLoadingState.EMPTY;
      }
    } else {
      this.emptyState = EmptyLoadingState.NONE;
    }
  }

  toggleCardMode(): void {
    this.cardMode = !this.cardMode;
    Settings.put(Settings.KEY_VIDEOS_CARDS, this.cardMode);
  }
}

@ComponentV2
export struct VideoGridPage {
  /** 由主页 HdsNavDestination 注入，用于标题栏滚动联动。 */
  @Param contentScroller: Scroller = new Scroller();
  @Local vm: VideoGridViewModel = new VideoGridViewModel();
  @Local refreshing: boolean = false;
  @Local contextItem: MediaWrapper | null = null;
  @Local showContext: boolean = false;
  @Local contextItemFav: boolean = false;
  @Local contextFolder: Folder | null = null;
  @Local contextFolderFav: boolean = false;
  @Local inSelection: boolean = false;
  @Local selectedUris: string[] = [];
  @Local importActive: boolean = false;
  @Local importCurrent: number = 0;
  @Local importTotal: number = 0;
  @Param settingsVersion: number = 0;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  @Param selectionActionVersion: number = 0;
  @Param selectionActionType: string = '';
  private removeSettingsListener: (() => void) | null = null;
  /** 防止播放器导航动画期间连续点击，重复压入 VideoPlayer 页面。 */
  private videoPlayerOpening: boolean = false;
  @Event onSearchGlobal: () => void = () => {
  };
  @Event onSelectionChange: (active: boolean, count: number) => void = () => {
  };

  aboutToAppear(): void {
    this.videoPlayerOpening = false;
    if (this.removeSettingsListener === null) {
      this.removeSettingsListener = Settings.observe((key: string) => {
        if (key === Settings.SHOW_VIDEO_THUMBNAILS) {
          // 开启缩略图时重新扫描以生成缓存；关闭时也立即刷新渲染状态。
          void this.vm.load();
        } else if (key === Settings.KEY_MEDIA_SEEN || key === Settings.KEY_GROUP_VIDEOS) {
          void this.vm.reloadSettings();
        }
      });
    }
    void this.vm.load();
  }

  aboutToDisappear(): void {
    if (this.removeSettingsListener !== null) {
      this.removeSettingsListener();
      this.removeSettingsListener = null;
    }
  }

  @Monitor('settingsVersion')
  onSettingsVersionChange(): void {
    void this.vm.reloadSettings();
  }

  @Monitor('searchQuery')
  onSearchQueryChange(): void {
    this.vm.applySearch(this.searchQuery);
  }

  async doRefresh(): Promise<void> {
    this.refreshing = true;
    await this.vm.refresh();
    this.refreshing = false;
  }

  /** 点击文件夹卡片 -> 进入文件夹内视频列表详情页。 */
  openFolder(folder: Folder): void {
    const param = new HeaderMediaListParam();
    param.title = folder.title;
    param.description = `${folder.mediaCount} 个视频`;
    param.folderPath = folder.path;
    param.isVideoFolder = true;
    NavController.push(RouteName.HeaderMediaList, param);
  }

  /** 长按/更多 -> 打开文件夹 ContextSheet。 */
  openFolderContext(folder: Folder): void {
    this.contextFolder = folder;
    this.contextItem = null;
    this.contextFolderFav = MediaLibrary.isFolderFav(folder.path);
    this.showContext = true;
  }

  /** 播放全部:以文件夹内全部视频为队列,从第一个开始播放。 */
  playAllInFolder(folder: Folder): void {
    const videos = MediaLibrary.getVideosByFolder(folder.path);
    if (videos.length === 0) {
      return;
    }
    const list: VideoPlayItem[] = videos.map((v: MediaWrapper) => {
      const e: VideoPlayItem = { uri: v.uri, title: v.title, artworkUrl: v.artworkUrl };
      return e;
    });
    const param: VideoParam = {
      uri: videos[0].uri,
      title: videos[0].title,
      list: list,
      index: 0,
    };
    NavController.push('VideoPlayer', param);
  }

  /** 全部标记为已播放/未播放。 */
  markFolderSeen(folder: Folder, seen: boolean): void {
    const videos = MediaLibrary.getVideosByFolder(folder.path);
    const tasks: Promise<void>[] = videos.map((v: MediaWrapper) =>
    seen ? VideoSeenState.markSeen(v.uri) : VideoSeenState.markUnseen(v.uri)
    );
    Promise.all(tasks).then(() => {
      UiFeedback.showToast({ message: seen ? '已标记为已播放' : '已标记为未播放' });
      void this.vm.rebuild();
    });
  }

  playVideo(item: MediaWrapper): void {
    if (this.videoPlayerOpening) {
      return;
    }
    const items = this.vm.items;
    // 设置页返回时可能触发列表重建，卡片事件里保留的 item 与当前
    // vm.items 中的对象不一定还是同一个引用。用 URI 定位才能保证点击
    // 的视频对应当前播放队列中的正确位置，而不是在 indexOf 失败后回退到 0。
    const index = items.findIndex((candidate: MediaWrapper) => candidate.uri === item.uri);
    hilog.info(0x0001, 'VLC', '[VLC] playVideo: idx=%{public}d uri=%{public}s', index, item.uri);
    // 队列由 VideoPlayer setup 内 prepareList+bindAndPlay;此处只传列表给详情页 UI(上一曲/下一曲)
    const list: VideoPlayItem[] = items.map((m: MediaWrapper) => {
      const e: VideoPlayItem = { uri: m.uri, title: m.title, artworkUrl: m.artworkUrl };
      return e;
    });
    const param: VideoParam = {
      uri: item.uri,
      title: item.title,
      list: list,
      index: index >= 0 ? index : 0,
    };
    this.videoPlayerOpening = true;
    NavController.push('VideoPlayer', param);
    // MainPage 常驻时不保证子组件每次返回都重新触发 aboutToAppear，
    // 因此锁只覆盖一次导航动画窗口。
    setTimeout(() => {
      this.videoPlayerOpening = false;
    }, 800);
  }

  /** 长按/更多 → 打开 ContextSheet。 */
  openContext(item: MediaWrapper): void {
    this.contextItem = item;
    this.contextFolder = null;
    this.contextItemFav = MediaLibrary.isVideoFav(item.uri);
    this.showContext = true;
  }

  isSelected(uri: string): boolean {
    return this.selectedUris.includes(uri);
  }

  // ---- 选择模式 ----

  enterSelection(item: MediaWrapper): void {
    this.inSelection = true;
    this.selectedUris = [item.uri];
    this.onSelectionChange(true, 1);
  }

  toggleSelection(uri: string): void {
    if (this.selectedUris.includes(uri)) {
      this.selectedUris = this.selectedUris.filter((u: string) => u !== uri);
    } else {
      this.selectedUris = [...this.selectedUris, uri];
    }
    if (this.selectedUris.length === 0) {
      this.exitSelection();
    } else {
      this.onSelectionChange(true, this.selectedUris.length);
    }
  }

  exitSelection(): void {
    this.inSelection = false;
    this.selectedUris = [];
    this.onSelectionChange(false, 0);
  }

  /** MainPage 工具栏操作触发:play / fav / delete / exit。 */
  @Monitor('selectionActionVersion')
  onSelectionAction(): void {
    if (this.selectionActionType === 'play') {
      this.playSelected();
    } else if (this.selectionActionType === 'fav') {
      this.favSelected();
    } else if (this.selectionActionType === 'delete') {
      this.deleteSelected();
    } else if (this.selectionActionType === 'exit') {
      this.exitSelection();
    }
  }

  /** 播放选中的第一个视频(以全部选中视频为队列)。 */
  playSelected(): void {
    const items = this.vm.items.filter((v: MediaWrapper) => this.selectedUris.includes(v.uri));
    if (items.length === 0) {
      return;
    }
    const list: VideoPlayItem[] = items.map((m: MediaWrapper) => {
      const e: VideoPlayItem = { uri: m.uri, title: m.title, artworkUrl: m.artworkUrl };
      return e;
    });
    const param: VideoParam = {
      uri: items[0].uri,
      title: items[0].title,
      list: list,
      index: 0,
    };
    this.exitSelection();
    NavController.push('VideoPlayer', param);
  }

  /** 切换选中视频的收藏状态:全部已收藏则取消收藏,否则收藏未收藏项。 */
  favSelected(): void {
    if (this.selectedUris.length === 0) {
      this.exitSelection();
      return;
    }
    const allFav: boolean = this.selectedUris.every((uri: string) => MediaLibrary.isVideoFav(uri));
    const targets: string[] = allFav
      ? this.selectedUris.slice()
      : this.selectedUris.filter((uri: string) => !MediaLibrary.isVideoFav(uri));
    if (targets.length === 0) {
      this.exitSelection();
      return;
    }
    const tasks: Promise<boolean>[] = targets.map((uri: string) => MediaLibrary.toggleVideoFav(uri));
    Promise.all(tasks).then(() => {
      UiFeedback.showToast({ message: allFav ? '已取消收藏' : '已收藏' });
      void this.vm.rebuild();
      this.exitSelection();
    });
  }

  /** 删除选中的视频。 */
  deleteSelected(): void {
    const items = this.vm.items.filter((v: MediaWrapper) => this.selectedUris.includes(v.uri));
    if (items.length === 0) {
      return;
    }
    const tasks: Promise<boolean>[] = items.map((v: MediaWrapper) => MediaLibrary.deleteVideo(v));
    Promise.all(tasks).then(() => {
      UiFeedback.showToast({ message: '已从媒体库移除' });
      void this.vm.rebuild();
      this.exitSelection();
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.importActive) {
          Row() {
            Progress({ value: this.importCurrent, total: this.importTotal, type: ProgressType.Linear })
              .layoutWeight(1)
              .height(4)
              .color(AppColors.orange500)
          }
          .width('100%').padding(8)
        }
        if (this.searchMode) {
          this.searchGlobalButton()
        }
        if (this.vm.emptyState !== EmptyLoadingState.NONE && this.vm.items.length === 0 &&
          this.vm.folders.length === 0) {
          EmptyStateView({
            state: this.vm.emptyState,
            filterQuery: this.searchQuery,
            onOpenStorage: () => UiFeedback.showToast({ message: $r('app.string.developing') }),
            onGrantPermission: () => this.vm.refresh(),
            onPickFile: () => this.onAddVideo(),
          })
            .layoutWeight(1)
            .width('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            if (this.vm.grouping === VideoGroupingType.FOLDER && this.vm.folders.length > 0) {
              if (this.vm.cardMode) {
                this.folderGridMode()
              } else {
                this.folderListMode()
              }
            } else {
              if (this.vm.cardMode) {
                this.gridMode()
              } else {
                this.listMode()
              }
            }
          }
          .onRefreshing(() => this.doRefresh())
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')

      // 与音频页保持一致：已有视频后也能继续通过系统文件选择器添加。
      if (!this.searchMode && !this.inSelection) {
        Button() {
          Image($r('app.media.ic_add'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.colorOnPrimary'))
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(AppColors.orange500)
        .shadow({ radius: 8, color: '#44000000', offsetY: 4 })
        .position({ right: 16, bottom: 152 })
        .onClick(() => this.onAddVideo())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .bindSheet(this.showContext, this.contextSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: $r('app.color.bottom_sheet_background'),
      showClose: false,
      onDisappear: () => {
        this.showContext = false;
        this.contextItem = null;
        this.contextFolder = null;
      },
    })
  }

  /** 统一 ContextSheet:根据 contextItem / contextFolder 判断渲染视频或文件夹内容。 */
  @Builder
  contextSheet() {
    if (this.contextFolder !== null) {
      this.folderContextContent()
    } else {
      this.videoContextSheet()
    }
  }

  /** 视频操作半模态:顶部封面+名称,后续 播放 / 添加到收藏夹。 */
  @Builder
  videoContextSheet() {
    Column() {
      if (this.contextItem !== null) {
        // 头部:封面 + 视频名称
        Row() {
          Image(
            this.contextItem.artworkUrl.length > 0 ? this.contextItem.artworkUrl : $r('app.media.ic_no_thumbnail_1610'))
            .width(80)
            .height(50)
            .objectFit(ImageFit.Cover)
            .borderRadius(4)
            .margin({ right: 12 })
            .alt($r('app.media.ic_no_thumbnail_1610'))
          Text(this.contextItem.title)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(16)
        .alignItems(VerticalAlign.Center)

        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))

        // 播放
        Row() {
          Image($r('app.media.ic_play_player'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('播放')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const item = this.contextItem!;
          this.showContext = false;
          this.playVideo(item);
        })

        // 添加到收藏夹 / 取消收藏
        Row() {
          Image(this.contextItemFav ? $r('app.media.ic_fav_remove') : $r('app.media.ic_fav_add'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text(this.contextItemFav ? '取消收藏' : '添加到收藏夹')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const uri = this.contextItem!.uri;
          MediaLibrary.toggleVideoFav(uri).then((fav: boolean) => {
            this.contextItemFav = fav;
            UiFeedback.showToast({ message: fav ? '已收藏' : '已取消收藏' });
            void this.vm.rebuild();
          });
        })

        // 视频信息
        Row() {
          Image($r('app.media.ic_information'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('视频信息')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          UiFeedback.showToast({
            message: `视频: ${this.contextItem!.title}\n时长: ${this.contextItem!.length > 0 ?
              formatDuration(this.contextItem!.length) : '未知'}`
          });
        })

        // 分享
        Row() {
          Image($r('app.media.ic_share'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('分享')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const item = this.contextItem!;
          this.showContext = false;
          void MediaLibrary.shareVideo(item.uri, item.title);
        })

        // 删除(MediaAssetChangeRequest.deleteAssets 会弹系统确认框)
        Row() {
          Image($r('app.media.ic_delete'))
            .width(24)
            .height(24)
            .fillColor('#F44336')
            .margin({ right: 12 })
          Text('删除')
            .fontSize(15)
            .fontColor('#F44336')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const item = this.contextItem!;
          this.showContext = false;
          MediaLibrary.deleteVideo(item).then((ok: boolean) => {
            if (ok) {
              UiFeedback.showToast({ message: '已从媒体库移除' });
              void this.vm.rebuild();
            } else {
              UiFeedback.showToast({ message: '删除失败,可能缺少权限' });
            }
          });
        })

        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))
        Blank()
          .height(24)
      }
    }
    .width('100%').backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  /** ContextSheet 弹窗内容(自定义组件 → builder 必须 .width('100%'))。 */

  /** 文件夹操作半模态内容:文件夹名 + 播放 / 打开文件夹 / 收藏 / 全部标记已播放 / 全部标记未播放。 */
  @Builder
  folderContextContent() {
    Column() {
      if (this.contextFolder !== null) {
        // 头部:文件夹名称
        Text(this.contextFolder.title)
          .fontSize(18)
          .fontColor($r('app.color.list_title'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 20,
            bottom: 8
          })

        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))

        // 播放(播放第一个视频)
        Row() {
          Image($r('app.media.ic_play_player'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('播放')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const folder = this.contextFolder!;
          this.showContext = false;
          this.playAllInFolder(folder);
        })

        // 打开文件夹
        Row() {
          Image($r('app.media.ic_folder'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('打开文件夹')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const folder = this.contextFolder!;
          this.showContext = false;
          this.openFolder(folder);
        })

        // 添加到收藏夹 / 取消收藏
        Row() {
          Image(this.contextFolderFav ? $r('app.media.ic_fav_remove') : $r('app.media.ic_fav_add'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text(this.contextFolderFav ? '取消收藏' : '添加到收藏夹')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const path = this.contextFolder!.path;
          MediaLibrary.toggleFolderFav(path).then((fav: boolean) => {
            this.contextFolderFav = fav;
            UiFeedback.showToast({ message: fav ? '已收藏' : '已取消收藏' });
            this.vm.rebuild();
          });
        })

        // 全部标记为已播放
        Row() {
          Image($r('app.media.ic_check'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('全部标记为已播放')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const folder = this.contextFolder!;
          this.showContext = false;
          this.markFolderSeen(folder, true);
        })

        // 全部标记为未播放
        Row() {
          Image($r('app.media.ic_close_small'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.list_title'))
            .margin({ right: 12 })
          Text('全部标记为未播放')
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          const folder = this.contextFolder!;
          this.showContext = false;
          this.markFolderSeen(folder, false);
        })

        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))
        Blank()
          .height(24)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  /** 搜索态:跳转全局搜索页的矩形按钮(橙字灰边居中)。 */
  @Builder
  searchGlobalButton() {
    Row() {
      Button($r('app.string.search_global'))
        .type(ButtonType.Normal)
        .borderRadius(4)
        .backgroundColor($r('app.color.background_default'))
        .fontColor('#FF8800')
        .border({ width: 1, color: $r('app.color.card_border') })
        .fontSize(14)
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
        .onClick(() => this.onSearchGlobal())
    }.borderRadius(4)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  gridMode() {
    Grid(this.contentScroller) {
      Repeat(this.vm.items).each((itemRepeatItem: RepeatItem<MediaWrapper>) => {
        GridItem() {
          MediaGridCard({
            item: itemRepeatItem.item,
            isFavorite: MediaLibrary.isVideoFav(itemRepeatItem.item.uri),
            selected: this.isSelected(itemRepeatItem.item.uri),
            inSelection: this.inSelection,
            showSeenMarker: this.vm.showSeenMarker,
            showThumbnail: this.vm.showThumbnails,
            onItemClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.playVideo(itemRepeatItem.item);
              }
            },
            onItemLongClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.enterSelection(itemRepeatItem.item);
              }
            },
            onItemMoreClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.openContext(itemRepeatItem.item);
              }
            },
          })
        }
      }).key((item: MediaWrapper) => item.uri + (MediaLibrary.isVideoFav(item.uri) ? '|1' : '|0')).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .padding({ left: 4, right: 4, top: 4 })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  listMode() {
    List({ space: 0, scroller: this.contentScroller }) {
      Repeat(this.vm.items).each((itemRepeatItem: RepeatItem<MediaWrapper>) => {
        ListItem() {
          MediaListCard({
            item: itemRepeatItem.item,
            isFavorite: MediaLibrary.isVideoFav(itemRepeatItem.item.uri),
            selected: this.isSelected(itemRepeatItem.item.uri),
            inSelection: this.inSelection,
            showSeenMarker: this.vm.showSeenMarker,
            showThumbnail: this.vm.showThumbnails,
            onItemClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.playVideo(itemRepeatItem.item);
              }
            },
            onItemLongClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.enterSelection(itemRepeatItem.item);
              }
            },
            onItemMoreClick: () => {
              if (this.inSelection) {
                this.toggleSelection(itemRepeatItem.item.uri);
              } else {
                this.openContext(itemRepeatItem.item);
              }
            },
          })
        }
      }).key((item: MediaWrapper) => item.uri + (MediaLibrary.isVideoFav(item.uri) ? '|1' : '|0')).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 8,
      endMargin: 8
    })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  folderGridMode() {
    Grid(this.contentScroller) {
      Repeat(this.vm.folders).each((folderRepeatItem: RepeatItem<Folder>) => {
        GridItem() {
          Column() {
            Stack({ alignContent: Alignment.Top }) {
              // 文件夹封面:4+缩略图时用 2x2 拼图,否则单图/图标。
              if (this.vm.showThumbnails && folderRepeatItem.item.thumbnailUrls.length >= 4) {
                Column() {
                  Row() {
                    Image(folderRepeatItem.item.thumbnailUrls[0])
                      .width('50%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                      .draggable(false)
                    Image(folderRepeatItem.item.thumbnailUrls[1])
                      .width('50%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                      .draggable(false)
                  }
                  .width('100%')
                  .height('50%')

                  Row() {
                    Image(folderRepeatItem.item.thumbnailUrls[2])
                      .width('50%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                      .draggable(false)
                    Image(folderRepeatItem.item.thumbnailUrls[3])
                      .width('50%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                      .draggable(false)
                  }
                  .width('100%')
                  .height('50%')
                }
                .width('100%')
                .height('100%')
              } else {
                Image(this.vm.showThumbnails && folderRepeatItem.item.artworkUrl.length > 0 ? folderRepeatItem.item.artworkUrl :
                  $r('app.media.ic_folder'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .alt($r('app.media.ic_folder'))
                  .draggable(false)
                  .backgroundColor($r('app.color.card_background'))
              }
              // 右上角:更多按钮(与视频网格卡片完全一致的样式)。
              Row() {
                Blank()
                Image($r('app.media.ic_more'))
                  .width(16)
                  .height(16)
                  .fillColor('#FFFFFF')
                  .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
                  .borderRadius(4)
                  .onClick(() => this.openFolderContext(folderRepeatItem.item))
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .padding({ left: 4, right: 4, top: 4 })

              // 左下角:收藏角标(已收藏时显示)。
              if (MediaLibrary.isFolderFav(folderRepeatItem.item.path)) {
                Row() {
                  Image($r('app.media.ic_emoji_favorite_white'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFFFFF')
                    .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
                    .borderRadius(3)
                    .padding(3)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Start)
                .alignItems(VerticalAlign.Bottom)
                .padding({ left: 4, bottom: 4 })
                .hitTestBehavior(HitTestMode.None)
              }
            }
            .aspectRatio(1.6)
            .borderRadius(4)
            .clip(true)
            .width('100%')

            Text(folderRepeatItem.item.title)
              .fontSize(16)
              .fontColor($r('app.color.list_title'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
              .width('100%')

            Text(`${folderRepeatItem.item.mediaCount} 个视频`)
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
              .width('100%')
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.video_card_background'))
          .borderRadius(8)
          .clip(true)
          .onClick(() => this.openFolder(folderRepeatItem.item))
          .gesture(LongPressGesture().onAction(() => this.openFolderContext(folderRepeatItem.item)))
        }
      }).key((folder: Folder) => folder.path.length > 0 ? folder.path : folder.title).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .padding({ left: 4, right: 4, top: 4 })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  folderListMode() {
    List({ space: 0, scroller: this.contentScroller }) {
      Repeat(this.vm.folders).each((folderRepeatItem: RepeatItem<Folder>) => {
        ListItem() {
          Row() {
            // 左侧:文件夹缩略图/图标(80x50,与视频列表卡片一致)。
            Stack() {
              Image(this.vm.showThumbnails && folderRepeatItem.item.artworkUrl.length > 0
                ? folderRepeatItem.item.artworkUrl : $r('app.media.ic_folder'))
                .width(80)
                .height(50)
                .objectFit(ImageFit.Cover)
                .alt($r('app.media.ic_folder'))
                .draggable(false)
                .borderRadius(4)
                .backgroundColor($r('app.color.card_background'))
            }
            .borderRadius(4)
            .clip(true)
            .margin({ right: 16 })

            // 中间:文件夹名 + 视频数。
            Column() {
              Text(folderRepeatItem.item.title)
                .fontSize(16)
                .fontColor($r('app.color.list_title'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${folderRepeatItem.item.mediaCount} 个视频`)
                .fontSize(12)
                .fontColor($r('app.color.list_subtitle'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ right: 4 })

            // 收藏指示(已收藏时显示星标)。
            if (MediaLibrary.isFolderFav(folderRepeatItem.item.path)) {
              Image($r('app.media.ic_emoji_favorite'))
                .width(24).height(24).objectFit(ImageFit.Contain).margin({ right: 4 })
            }

            // 右侧:更多按钮(与视频列表卡片一致的 44x44 触控区)。
            Row() {
              Image($r('app.media.ic_more'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.list_subtitle'))
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ right: 4 })
            .onClick(() => this.openFolderContext(folderRepeatItem.item))
          }
          .width('100%')
          .padding({ left: 8, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.video_list_background'))
          .onClick(() => this.openFolder(folderRepeatItem.item))
          .gesture(LongPressGesture().onAction(() => this.openFolderContext(folderRepeatItem.item)))
        }
      }).key((folder: Folder) => folder.path.length > 0 ? folder.path : folder.title).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 8,
      endMargin: 8
    })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .layoutWeight(1)
  }

  /** 通过系统文件选择器导入视频，仅保存持久 URI 引用。 */
  private async onAddVideo(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 200;
      options.fileSuffixFilters = [
        '视频 (.mp4, .mkv, .avi, .mov, .webm, .ts, .m4v)|.mp4,.mkv,.avi,.mov,.webm,.ts,.m4v',
      ];
      options.mergeMode = picker.MergeTypeMode.VIDEO;
      const uris = await new picker.DocumentViewPicker(ctx).select(options);
      if (uris.length > 0) {
        this.importActive = true;
        this.importCurrent = 0;
        this.importTotal = uris.length;
        await MediaLibrary.importVideoUris(uris, (current: number, total: number): void => {
          this.importCurrent = current;
          this.importTotal = total;
        });
        this.importActive = false;
        await this.vm.rebuild();
      }
    } catch (e) {
      this.importActive = false;
      hilog.warn(0x0001, 'VLC', '[VLC] onAddVideo: %{public}s', (e as Error).message ?? String(e));
    }
  }
}
