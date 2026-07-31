import { hilog } from '@kit.PerformanceAnalysisKit';
import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { BundledMedia } from '../common/data/BundledMedia';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { Folder, SheetItem, EmptyLoadingState } from '../common/models/MediaModels';
import { VideoParam } from './VideoPlayerPage';

/** 浏览模式。 */
export type BrowserMode = 'file' | 'network' | 'storage' | 'picker' | 'bundled';

@ObservedV2
class BrowserViewModel {
  @Trace dataset: SheetItem[] = [];
  @Trace loading: boolean = false;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.NONE;
  mode: BrowserMode = 'file';

  // Folder → SheetItem 转换辅助函数。
  private static folderToSheetItem(f: Folder): SheetItem {
    return new SheetItem(f.title, `${f.mediaCount} 个视频`, $r('app.media.ic_folder'));
  }

  isBundledMode(): boolean {
    return this.mode === 'bundled';
  }

  browseRoot(): void {
    this.loading = true;
    if (this.mode === 'network') {
      this.dataset = [];
      this.emptyState = EmptyLoadingState.EMPTY;
      this.loading = false;
      return;
    }
    if (this.isBundledMode()) {
      const folders = BundledMedia.asFolders();
      this.dataset = folders.map(BrowserViewModel.folderToSheetItem);
      this.emptyState = folders.length === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
      this.loading = false;
      return;
    }
    // storage/file → 视频目录列表
    const items: SheetItem[] = MediaLibrary.getVideoDirectories();
    this.dataset = items;
    this.emptyState = items.length === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
    this.loading = false;
  }

  isEmpty(): boolean { return this.dataset.length === 0; }
}

/**
 * FileBrowserPage — 目录浏览器(对齐 Android FileBrowserFragment browser_item.xml)。
 * 列表: 48vp 图标 + 16fp 标题 + 12fp 副标题 + 更多按钮。
 * 替代方案: photoAccessHelper 目录分组(因鸿蒙沙箱限制,无法递归文件系统)。
 */
@ComponentV2
export struct FileBrowserPage {
  @Param mode: BrowserMode = 'file';
  @Local vm: BrowserViewModel = new BrowserViewModel();
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    this.vm.mode = this.mode;
    this.vm.browseRoot();
  }

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        Row() {
          Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor($r('app.color.list_title'))
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          if (this.mode === 'bundled') {
            Text($r('app.string.browser_app_videos'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.white)
              .margin({ left: AppDimens.kl_half })
          } else {
            Text(this.mode === 'network' ? '网络' : '存储设备')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.list_title'))
              .margin({ left: 8 })
          }
          Blank()
        }
        .width('100%').height(56).alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.background_actionbar'))

        if (this.vm.emptyState !== EmptyLoadingState.NONE) {
          EmptyStateView({ state: this.vm.emptyState }).layoutWeight(1)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List() {
              ForEach(this.vm.dataset, (item: SheetItem) => {
                ListItem() {
                  this.browserItem(item)
                }
              }, (item: SheetItem) => item.title)
            }
            .width('100%').height('100%')
            .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 72, endMargin: 16 })
            .alignListItem(ListItemAlign.Start)
          }
          .layoutWeight(1).width('100%')
          .onRefreshing(() => {
            this.vm.browseRoot();
          })
          .backgroundColor($r('app.color.background_default'))
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
    .onBackPressed(() => { NavController.pop(); return true; })
  }

  /** 对齐 Android browser_item.xml: 48vp 左图标 + 16fp 标题 + 12fp 副标题 + 更多右。 */
  @Builder
  browserItem(item: SheetItem) {
    Row() {
      Image(item.icon).width(48).height(48).objectFit(ImageFit.Contain)
        .margin({ left: 12, top: 4, bottom: 4 })
      Column() {
        Text(item.title).fontSize(16).fontColor($r('app.color.list_title')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.subtitle.length > 0) {
          Text(item.subtitle).fontSize(12).fontColor($r('app.color.list_subtitle')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12, right: 8 })
    }
    .width('100%').constraintSize({ minHeight: 56 }).alignItems(VerticalAlign.Center)
    .onClick(() => {
      // TODO: 点击进入下层目录或播放目录内媒体
    })
  }
}
