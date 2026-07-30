import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { MediaWrapper, formatDuration, VideoNavParam } from '../common/models/MediaModels';

/**
 * HistoryViewModel —— HistoryFragment 的 VM。
 * @Trace 字段;改数组整体 reassign。
 */
@ObservedV2
class HistoryViewModel {
  @Trace dataset: MediaWrapper[] = [];
  @Trace loading: boolean = false;
  @Trace isEmpty: boolean = true;

  /** 刷新:历史样例 = MediaLibrary.getVideos().slice(0,5)。 */
  refresh(): void {
    this.loading = true;
    // TODO(契约):medialibrary.history(HISTORY_TYPE_LOCAL) 未迁移,样例取设备视频前 5 条。
    const all = MediaLibrary.getVideos();
    const sample = all.slice(0, 5);
    this.dataset = sample;
    this.isEmpty = sample.length === 0;
    this.loading = false;
  }
}

/**
 * HistoryFragmentPage —— HistoryFragment(历史列表页)。
 * Refresh + List/empty 两态;item 行(缩略图 + 标题 14sp + 副标题 12sp)。
 * 文案/数值逐字照搬 .harmonyos/spec/pages/HistoryFragment.md。
 */
@ComponentV2
export struct HistoryFragmentPage {
  @Local vm: HistoryViewModel = new HistoryViewModel();
  @Local isRefreshing: boolean = false;

  aboutToAppear(): void {
    this.vm.refresh();
  }

  private onRefresh(): void {
    this.isRefreshing = true;
    this.vm.refresh();
    this.isRefreshing = false;
  }

  private onItemClick(item: MediaWrapper): void {
    // TODO(契约):MediaUtils 播放入口 —— 播放该 MediaWrapper(进入播放器)。
    const p: VideoNavParam = { uri: item.uri, title: item.title };
    NavController.push('VideoPlayer', p);
  }

  build() {
    NavDestination() {
      Column() {
        // 返回导航栏(标题 = "History")
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.white)
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text($r('app.string.history'))
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

        if (this.vm.isEmpty) {
          // 空态文案:居中、20fp、paddingTop=30dp
          Column() {
            Text($r('app.string.nohistory'))
              .fontSize(20)
              .fontColor(AppColors.grey600)
              .textAlign(TextAlign.Center)
              .margin({ top: 30, left: AppDimens.kl_normal, right: AppDimens.kl_normal })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ space: 0 }) {
              ForEach(this.vm.dataset, (item: MediaWrapper, index: number) => {
                ListItem() {
                  Row() {
                    // 缩略图区(16:10 比例占位,40vp 高)
                    Stack() {
                      Image($r('app.media.ic_song'))
                        .width('100%')
                        .height('100%')
                        .objectFit(ImageFit.Cover)
                        .fillColor(AppColors.grey400)
                    }
                    .width(64)
                    .height(40)
                    .backgroundColor(AppColors.grey200)
                    .margin({ left: AppDimens.kl_normal, top: AppDimens.kl_half, bottom: AppDimens.kl_half })

                    // 中间文字区
                    Column() {
                      Text(item.title)
                        .fontSize(14)
                        .fontColor(AppColors.grey900)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      if (item.description.length > 0) {
                        Text(item.description)
                          .fontSize(12)
                          .fontColor(AppColors.grey600)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .margin({ top: 2 })
                          .width('100%')
                      } else if (item.length > 0) {
                        Text(formatDuration(item.length))
                          .fontSize(12)
                          .fontColor(AppColors.grey600)
                          .maxLines(1)
                          .margin({ top: 2 })
                          .width('100%')
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_small })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => this.onItemClick(item))
                }
              }, (item: MediaWrapper, index: number) => `${index}`)
            }
            .width('100%')
            .height('100%')
            .padding({ top: 10, bottom: AppDimens.default_margin })
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing(() => this.onRefresh())
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.grey50)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
