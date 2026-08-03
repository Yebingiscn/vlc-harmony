import { Settings } from '../common/data/Settings';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { VideoSeenState } from '../common/data/VideoSeenState';
import { PermissionCoordinator } from '../common/data/PermissionCoordinator';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { MediaGridCard } from '../common/components/MediaGridCard';
import { MediaListCard } from '../common/components/MediaListCard';
import { EmptyLoadingState, MediaWrapper, VideoGroupingType, formatDuration } from '../common/models/MediaModels';
import { VideoParam, VideoPlayItem } from './VideoPlayerPage';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoGridPage —— VideoGridFragment(Video Tab 根)。
 * 自适应网格/列表双模式(KEY_VIDEOS_CARDS 默认 true=网格) + 下拉刷新 + 空态/加载态。
 */
@ObservedV2
class VideoGridViewModel {
  @Trace items: MediaWrapper[] = [];
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

  async load(): Promise<void> {
    this.loading = true;
    this.emptyState = EmptyLoadingState.LOADING;
    this.cardMode = await Settings.getBoolean(Settings.KEY_VIDEOS_CARDS, true);
    this.showSeenMarker = await Settings.getBoolean(Settings.KEY_MEDIA_SEEN, true);
    this.showThumbnails = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    this.sortField = await Settings.getInt(Settings.KEY_VIDEO_SORT, 1);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_VIDEO_SORT_DESC, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_VIDEO_ONLY_FAVS, false);
    // 先确保媒体读权限(首次弹授权框),再扫描 -- 否则扫描在授权完成前跑会返回空。
    await PermissionCoordinator.askStoragePermission(false, false, true);
    await MediaLibrary.scan();
    await MediaLibrary.loadVideoFavs();
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
    // 仅显示收藏:按视频 uri 过滤
    if (this.onlyFavs) {
      base = base.filter((v: MediaWrapper) => MediaLibrary.isVideoFav(v.uri));
    }
    this.items = this.applySort(base);
    this.updateEmpty();
  }

  applySearch(q: string): void {
    this.searchQuery = q;
    void this.rebuild();
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

  updateEmpty(): void {
    if (this.items.length === 0) {
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
  @Local vm: VideoGridViewModel = new VideoGridViewModel();
  @Local refreshing: boolean = false;
  @Local contextItem: MediaWrapper | null = null;
  @Local showContext: boolean = false;
  @Local contextItemFav: boolean = false;
  @Param settingsVersion: number = 0;
  private removeSettingsListener: (() => void) | null = null;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  @Event onSearchGlobal: () => void = () => {
  };

  aboutToAppear(): void {
    if (this.removeSettingsListener === null) {
      this.removeSettingsListener = Settings.observe((key: string) => {
        if (key === Settings.SHOW_VIDEO_THUMBNAILS) {
          // 开启缩略图时重新扫描以生成缓存；关闭时也立即刷新渲染状态。
          void this.vm.load();
        } else if (key === Settings.KEY_MEDIA_SEEN) {
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

  async playVideo(item: MediaWrapper): Promise<void> {
    const items = this.vm.items;
    const index = items.indexOf(item);
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
    NavController.push('VideoPlayer', param);
  }

  /** 长按/更多 → 打开 ContextSheet。 */
  openContext(item: MediaWrapper): void {
    this.contextItem = item;
    this.contextItemFav = MediaLibrary.isVideoFav(item.uri);
    this.showContext = true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.searchMode) {
          this.searchGlobalButton()
        }
        if (this.vm.emptyState !== EmptyLoadingState.NONE && this.vm.items.length === 0) {
          EmptyStateView({
            state: this.vm.emptyState,
            filterQuery: this.searchQuery,
            onOpenStorage: () => promptAction.showToast({ message: $r('app.string.developing') }),
            onGrantPermission: () => this.vm.refresh(),
            onPickFile: () => promptAction.showToast({ message: $r('app.string.developing') }),
          })
            .layoutWeight(1)
            .width('100%')
        } else {
          Refresh({ refreshing: this.refreshing }) {
            if (this.vm.cardMode) {
              this.gridMode()
            } else {
              this.listMode()
            }
          }
          .onRefreshing(() => this.doRefresh())
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .bindSheet(this.showContext, this.videoContextSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: '#FFFFFF',
      showClose: false,
      onDisappear: () => {
        this.showContext = false;
        this.contextItem = null;
      },
    })
  }

  /** ContextSheet 弹窗内容(自定义组件 → builder 必须 .width('100%'))。 */
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
            .fontColor('#212121')
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').padding(16).alignItems(VerticalAlign.Center)

        Divider().strokeWidth(0.5).color('#E0E0E0')

        // 播放
        Row() {
          Image($r('app.media.ic_play_player')).width(24).height(24).fillColor('#212121').margin({ right: 12 })
          Text('播放').fontSize(15).fontColor('#212121')
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
            .width(24).height(24).fillColor('#212121').margin({ right: 12 })
          Text(this.contextItemFav ? '取消收藏' : '添加到收藏夹').fontSize(15).fontColor('#212121')
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
            promptAction.showToast({ message: fav ? '已收藏' : '已取消收藏' });
            void this.vm.rebuild();
          });
        })

        // 视频信息
        Row() {
          Image($r('app.media.ic_information')).width(24).height(24).fillColor('#212121').margin({ right: 12 })
          Text('视频信息').fontSize(15).fontColor('#212121')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14
        })
        .onClick(() => {
          promptAction.showToast({
            message: `视频: ${this.contextItem!.title}\n时长: ${this.contextItem!.length > 0 ? formatDuration(this.contextItem!.length) : '未知'}`
          });
        })

        Divider().strokeWidth(0.5).color('#E0E0E0')
        Blank().height(24)
      }
    }
    .width('100%').backgroundColor('#FFFFFF')
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
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  gridMode() {
    Grid() {
      ForEach(this.vm.items, (item: MediaWrapper) => {
        GridItem() {
          MediaGridCard({
            item: item,
            showSeenMarker: this.vm.showSeenMarker,
            showThumbnail: this.vm.showThumbnails,
            onItemClick: () => this.playVideo(item),
            onItemLongClick: () => this.openContext(item),
            onItemMoreClick: () => this.openContext(item),
          })
        }
      }, (item: MediaWrapper) => `${item.id}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .padding(4)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  listMode() {
    List({ space: 0 }) {
      ForEach(this.vm.items, (item: MediaWrapper) => {
        ListItem() {
          MediaListCard({
            item: item,
            showSeenMarker: this.vm.showSeenMarker,
            showThumbnail: this.vm.showThumbnails,
            onItemClick: () => this.playVideo(item),
            onItemLongClick: () => this.openContext(item),
            onItemMoreClick: () => this.openContext(item),
          })
        }
      }, (item: MediaWrapper) => `${item.id}`)
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 8,
      endMargin: 8
    })
    .width('100%')
    .layoutWeight(1)
  }
}
