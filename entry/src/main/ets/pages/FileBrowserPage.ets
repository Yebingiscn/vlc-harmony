import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { BundledMedia } from '../common/data/BundledMedia';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { Folder, EmptyLoadingState } from '../common/models/MediaModels';
import { VideoParam } from './VideoPlayerPage';

/** 浏览模式:'file' | 'network' | 'storage' | 'picker' | 'bundled'。 */
export type BrowserMode = 'file' | 'network' | 'storage' | 'picker' | 'bundled';

/**
 * BrowserViewModel —— BaseBrowserFragment 的行为基类(子页注入 categoryTitle + 数据源)。
 * 改数组整体 reassign。network 模式恒空态;bundled 列 rawfile 打包媒体;
 * file/storage/picker 用 MediaLibrary.getVideoFolders()。
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

  private isBundledMode(): boolean {
    return this.mode === 'bundled';
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
    if (this.isBundledMode()) {
      const folders = BundledMedia.asFolders();
      this.dataset = folders;
      this.emptyState = folders.length === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
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
    if (this.mode === 'bundled') {
      return 'In-app videos';
    }
    return 'Files';
  }

  private onRefresh(): void {
    this.isRefreshing = true;
    this.vm.browseRoot();
    this.isRefreshing = false;
  }

  private async onFolderClick(folder: Folder): Promise<void> {
    // TODO(契约):browse(media, save=true) push 下一级 FileBrowserFragment。本页为样例,无下级目录数据。
    if (this.mode === 'picker') {
      // picker 模式选中文件返回。
      NavController.pop();
      return;
    }
    if (this.mode === 'bundled') {
      await this.playBundled(folder);
    }
  }

  /** 解压 rawfile → 沙箱后进入 VideoPlayer。 */
  private async playBundled(folder: Folder): Promise<void> {
    const rawName = BundledMedia.rawNameFromUri(folder.path);
    if (rawName.length === 0) {
      return;
    }
    hilog.info(0x0001, 'VLC', '[VLC] playBundled raw=%{public}s', rawName);
    const media = await BundledMedia.resolveMedia(rawName, folder.title);
    if (!media) {
      hilog.error(0x0001, 'VLC', '[VLC] playBundled resolve failed raw=%{public}s', rawName);
      return;
    }
    const param: VideoParam = { uri: media.uri, title: media.title };
    NavController.push('VideoPlayer', param);
  }

  private breadcrumbSegment(): string {
    if (this.mode === 'network') {
      return 'Network';
    }
    if (this.mode === 'bundled') {
      return 'In-app';
    }
    return 'Local';
  }

  private subtitleFor(folder: Folder): string {
    if (this.mode === 'bundled') {
      return folder.description.length > 0 ? folder.description : folder.title;
    }
    if (folder.mediaCount > 0) {
      return `${folder.mediaCount} item${folder.mediaCount > 1 ? 's' : ''}`;
    }
    return folder.path;
  }

  @Builder
  BrowserItem(folder: Folder) {
    Row() {
      // 48×48 图标(folder 占位;bundled 用视频图标)
      Stack() {
        Image(this.mode === 'bundled' ? $r('app.media.ic_video') : $r('app.media.ic_folder'))
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
        Text(this.subtitleFor(folder))
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
          if (this.mode === 'bundled') {
            Text($r('app.string.browser_app_videos'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.white)
              .margin({ left: AppDimens.kl_half })
          } else {
            Text(this.titleForMode())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.white)
              .margin({ left: AppDimens.kl_half })
          }
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
