import { Settings } from '../common/data/Settings';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { PermissionCoordinator } from '../common/data/PermissionCoordinator';
import { PlaybackService } from '../common/data/PlaybackService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { MediaGridCard } from '../common/components/MediaGridCard';
import { MediaListCard } from '../common/components/MediaListCard';
import { ContextSheet } from './ContextSheet';
import {
  MediaWrapper,
  VideoGroupingType,
  EmptyLoadingState,
  SheetItem,
} from '../common/models/MediaModels';
import { VideoParam } from './VideoPlayerPage';
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

  async load(): Promise<void> {
    this.loading = true;
    this.emptyState = EmptyLoadingState.LOADING;
    const cards = await Settings.getBoolean(Settings.KEY_VIDEOS_CARDS, true);
    this.cardMode = cards;
    // 先确保媒体读权限(首次弹授权框),再扫描 —— 否则扫描在授权完成前跑会返回空。
    await PermissionCoordinator.askStoragePermission(false, false, true);
    await MediaLibrary.scan();
    this.items = MediaLibrary.getVideos().slice();
    this.updateEmpty();
    this.loading = false;
  }

  async refresh(): Promise<void> {
    await MediaLibrary.scan();
    this.items = MediaLibrary.getVideos().slice();
    this.updateEmpty();
  }

  updateEmpty(): void {
    if (this.items.length === 0) {
      this.emptyState = EmptyLoadingState.EMPTY;
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

  aboutToAppear(): void {
    this.vm.load();
  }

  async doRefresh(): Promise<void> {
    this.refreshing = true;
    await this.vm.refresh();
    this.refreshing = false;
  }

  playVideo(item: MediaWrapper): void {
    hilog.info(0x0001, 'VLC', '[VLC] playVideo clicked: uri=%{public}s title=%{public}s', item.uri, item.title);
    const items = this.vm.items;
    PlaybackService.playList(MediaLibrary.toQueueItems(items), items.indexOf(item), true);
    const param: VideoParam = { uri: item.uri, title: item.title };
    NavController.push('VideoPlayer', param);
    hilog.info(0x0001, 'VLC', '[VLC] pushed VideoPlayer route');
  }

  /** 长按/更多 → 打开 ContextSheet。 */
  openContext(item: MediaWrapper): void {
    this.contextItem = item;
    this.showContext = true;
  }

  /** ContextSheet 动作菜单(Play/Append/Delete/Share…)。 */
  contextMenuItems(): SheetItem[] {
    return [
      new SheetItem('Play', '', $r('app.media.ic_play')),
      new SheetItem('Append to playlist', '', $r('app.media.ic_play_append')),
      new SheetItem('Delete', '', $r('app.media.ic_delete')),
      new SheetItem('Share', '', $r('app.media.ic_share')),
    ];
  }

  /** ContextSheet 动作回传。
   * TODO(medialibrary 契约): Play/Append/Delete/Share 等真实动作由 medialibrary rename/removeFolder/
   *   pagedList 与 ACTION_SEND 移植实现,此处仅占位(弹窗能弹即可)。
   */
  onContextAction(index: number): void {
    void index;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.vm.emptyState !== EmptyLoadingState.NONE && this.vm.items.length === 0) {
          EmptyStateView({
            state: this.vm.emptyState,
            onOpenStorage: () => promptAction.showToast({ message: $r('app.string.developing') }),
            onGrantPermission: () => this.vm.refresh(),
            onPickFile: () => promptAction.showToast({ message: $r('app.string.developing') }),
          })
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
    .bindSheet(this.showContext, () => {
      this.contextSheetBuilder()
    }, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => {
        this.showContext = false;
        this.contextItem = null;
      },
    })
  }

  /** ContextSheet 弹窗内容(自定义组件 → builder 必须 .width('100%'))。 */
  @Builder
  contextSheetBuilder() {
    Column() {
      if (this.contextItem !== null) {
        ContextSheet({
          showCover: true,
          coverTitle: this.contextItem.title,
          title: this.contextItem.title,
          cover: $r('app.media.ic_empty'),
          menuItems: this.contextMenuItems(),
          onClose: () => {
            this.showContext = false;
            this.contextItem = null;
          },
          onItemClick: (index: number) => this.onContextAction(index),
        })
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  gridMode() {
    Grid() {
      ForEach(this.vm.items, (item: MediaWrapper) => {
        GridItem() {
          MediaGridCard({
            item: item,
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
            onItemClick: () => this.playVideo(item),
            onItemLongClick: () => this.openContext(item),
            onItemMoreClick: () => this.openContext(item),
          })
        }
      }, (item: MediaWrapper) => `${item.id}`)
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 8, endMargin: 8 })
    .width('100%')
    .layoutWeight(1)
  }
}
