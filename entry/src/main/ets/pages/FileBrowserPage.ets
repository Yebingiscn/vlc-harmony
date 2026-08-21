import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { EmptyLoadingState, Folder, SheetItem } from '../common/models/MediaModels';
import { NetworkServerDialog } from './NetworkServerDialog';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

/** 浏览模式。 */
export type BrowserMode = 'file' | 'network' | 'storage' | 'picker';

@ObservedV2
class BrowserViewModel {
  @Trace dataset: SheetItem[] = [];
  @Trace loading: boolean = false;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.NONE;
  mode: BrowserMode = 'file';

  // Folder → SheetItem 转换辅助函数。
  private static folderToSheetItem(f: Folder): SheetItem {
    return new SheetItem(f.title, `${f.mediaCount} 个视频`, $r('app.media.ic_folder'), f.path);
  }

  browseRoot(): void {
    this.loading = true;
    if (this.mode === 'network') {
      this.dataset = [];
      this.emptyState = EmptyLoadingState.EMPTY;
      this.loading = false;
      return;
    }
    // storage/file → 视频目录列表
    const items: SheetItem[] = MediaLibrary.getVideoDirectories();
    this.dataset = items;
    this.emptyState = items.length === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
    this.loading = false;
  }

  isEmpty(): boolean {
    return this.dataset.length === 0;
  }
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

  @Local showServerDialog: boolean = false;

  onAddClick(): void {
    if (this.mode === 'network') {
      this.showServerDialog = true;
    }
  }

  @Builder
  serverSheet() {
    Column() {
      NetworkServerDialog({
        onClose: () => this.showServerDialog = false,
      }).width('100%')
    }
    .width('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.vm.emptyState !== EmptyLoadingState.NONE) {
          EmptyStateView({
            state: this.vm.emptyState,
            onPickFile: () => this.onAddClick()
          }).layoutWeight(1)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List() {
              Repeat(this.vm.dataset).each((itemRepeatItem: RepeatItem<SheetItem>) => {
                ListItem() {
                  this.browserItem(itemRepeatItem.item)
                }
              }).key((item: SheetItem) => item.title).virtualScroll()
            }
            .width('100%').height('100%')
            .divider({
              strokeWidth: 0.5,
              color: $r('app.color.divider'),
              startMargin: 72,
              endMargin: 16
            })
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
      .bindSheet(this.showServerDialog, this.serverSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => this.showServerDialog = false,
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
          mainTitle: this.mode === 'network' ? '网络' : '存储设备'
        },
        backIcon: {
          icon: $r('app.media.ic_arrow_back'),
          label: '返回',
          action: () => NavController.pop()
        },
        divider: {
          showType: DividerShowType.AUTO
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
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
          Text(item.subtitle)
            .fontSize(12)
            .fontColor($r('app.color.list_subtitle'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12, right: 8 })
    }
    .width('100%').constraintSize({ minHeight: 56 }).alignItems(VerticalAlign.Center)
  }
}
