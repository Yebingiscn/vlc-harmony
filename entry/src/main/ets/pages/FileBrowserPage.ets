import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { Folder, MediaLibraryItem, EmptyLoadingState } from '../common/models/MediaModels';

/** 浏览模式:'file' | 'network' | 'storage' | 'picker'。 */
export type BrowserMode = 'file' | 'network' | 'storage' | 'picker';

/**
 * BrowserViewModel —— BaseBrowserFragment 的行为基类(子页注入 categoryTitle + 数据源)。
 * 改数组整体 reassign。network 模式恒空态(file/storage/picker 用 MediaLibrary.getVideoFolders() 样例)。
 */
@ObservedV2
class BrowserViewModel {
  @Trace dataset: Folder[] = [];
  @Trace loading: boolean = false;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.NONE;
  mode: BrowserMode = 'file';

  private isNetworkMode(): boolean {
    return this.mode === 'network';
  }

  /** 首次拉取(子页 browseRoot)。 */
  browseRoot(): void {
    this.loading = true;
    if (this.isNetworkMode()) {
      // network 模式:无连接 → 空态文案。
      this.dataset = [];
      this.emptyState = EmptyLoadingState.EMPTY;
      this.loading = false;
      return;
    }
    // file/storage/picker:用 MediaLibrary.getVideoFolders() 转为文件夹列表样例。
    const folders = MediaLibrary.getVideoFolders();
    this.dataset = folders;
    this.emptyState = folders.length === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
    this.loading = false;
  }

  isEmpty(): boolean {
    return this.dataset.length === 0;
  }
}

/**
 * FileBrowserPage —— 通用目录浏览器(FileBrowserFragment / NetworkBrowserFragment /
 * StorageBrowserFragment / MLStorageBrowserFragment / FilePickerFragment / BaseBrowserFragment)。
 * 面包屑行 + 下拉刷新 + 列表(browser_item:48 图标 + 16 标题 + 12 副标题)。
 * 文案/数值逐字照搬 .harmonyos/spec/pages/BaseBrowserFragment.md 等子页规格。
 */
@ComponentV2
export struct FileBrowserPage {
  @Param mode: BrowserMode = 'file';
  @Local vm: BrowserViewModel = new BrowserViewModel();
  @Local isRefreshing: boolean = false;

  aboutToAppear(): void {
    this.vm.mode = this.mode;
    this.vm.browseRoot();
  }

  private titleForMode(): string {
    if (this.mode === 'network') {
      return 'Network';
    }
    if (this.mode === 'storage') {
      return 'Storage';
    }
    if (this.mode === 'picker') {
      return 'Pick a file';
    }
    return 'Files';
  }

  private onRefresh(): void {
    this.isRefreshing = true;
    this.vm.browseRoot();
    this.isRefreshing = false;
  }

  private onFolderClick(folder: Folder): void {
    // TODO(契约):browse(media, save=true) push 下一级 FileBrowserFragment。本页为样例,无下级目录数据。
    if (this.mode === 'picker') {
      // picker 模式选中文件返回。
      NavController.pop();
      return;
    }
  }

  private breadcrumbSegment(): string {
    return this.mode === 'network' ? 'Network' : 'Local';
  }

  @Builder
  BrowserItem(folder: Folder) {
    Row() {
      // 48×48 图标(folder 占位)
      Stack() {
        Image($r('app.media.ic_folder'))
          .width(AppDimens.audio_cover)
          .height(AppDimens.audio_cover)
          .objectFit(ImageFit.CENTER)
          .fillColor(AppColors.orange800)
      }
      .width(AppDimens.audio_cover)
      .height(AppDimens.audio_cover)
      .margin({ left: 12, top: AppDimens.kl_half, bottom: AppDimens.kl_half })

      // 标题 + 副标题
      Column() {
        Text(folder.title.length > 0 ? folder.title : 'Internal memory')
          .fontSize(16)
          .fontColor(AppColors.grey900)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(folder.mediaCount > 0 ? `${folder.mediaCount} item${folder.mediaCount > 1 ? 's' : ''}` : folder.path)
          .fontSize(12)
          .fontColor(AppColors.grey600)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: AppDimens.kl_small })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        // 返回导航栏(标题随模式变化)
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.white)
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text(this.titleForMode())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
            .margin({ left: AppDimens.kl_half })
          Blank()
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppColors.orange800)

        // §1 面包屑行(仅 scheme 受支持时显示;network/file 均展示)
        if (this.mode !== 'picker') {
          Scroll() {
            Row() {
              Text(this.breadcrumbSegment())
                .fontSize(14)
                .fontColor(AppColors.grey700)
                .padding({ top: 3, bottom: 4 })
                .onClick(() => NavController.pop())
            }
            .padding({ left: AppDimens.kl_normal, right: AppDimens.kl_normal })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .backgroundColor(AppColors.grey50)
        }

        if (this.vm.emptyState !== EmptyLoadingState.NONE) {
          if (this.mode === 'network') {
            // network 模式特有空态文案
            Column() {
              Image($r('app.media.ic_network_big'))
                .width(96)
                .height(96)
                .objectFit(ImageFit.Contain)
                .fillColor(AppColors.grey400)
              Text('No connection to local network.')
                .fontSize(14)
                .fontColor(AppColors.grey600)
                .textAlign(TextAlign.Center)
                .margin({ top: 12, left: 24, right: 24 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            // file/storage/picker 空/加载态
            EmptyStateView({ state: this.vm.emptyState })
              .layoutWeight(1)
          }
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: 0 }) {
              ForEach(this.vm.dataset, (folder: Folder, index: number) => {
                ListItem() {
                  this.BrowserItem(folder)
                }
                .onClick(() => this.onFolderClick(folder))
              }, (folder: Folder, index: number) => `${index}`)
            }
            .width('100%')
            .height('100%')
            .divider({ strokeWidth: 0.5, color: AppColors.grey300, startMargin: 60, endMargin: AppDimens.kl_normal })
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing(() => this.onRefresh())
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
