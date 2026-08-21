import { MediaLibrary } from '../common/data/MediaLibrary';
import { NavController } from '../common/data/NavController';
import { SearchItem } from '../common/components/SearchItem';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { EmptyLoadingState, MediaLibraryItem, MediaWrapper, Track, } from '../common/models/MediaModels';
import { PlaybackService } from '../common/data/PlaybackService';
import { VideoParam } from './VideoPlayerPage';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
/**
 * SearchPage —— SearchActivity(全屏搜索页,push,无 Tab 栏)。
 * 顶部固定搜索栏(返回 + TextInput + 清空)+ 内容区互斥渲染结果滚动区(6 分组)或空态。
 */
@ObservedV2
class SearchViewModel {
  @Trace query: string = '';
  @Trace results: MediaLibraryItem[] = [];
  @Trace searched: boolean = false;

  async search(q: string): Promise<void> {
    this.query = q;
    this.searched = true;
    if (q.trim().length === 0) {
      this.results = [];
      return;
    }
    await MediaLibrary.scan();
    const lower = q.toLowerCase();
    const videos: MediaWrapper[] = MediaLibrary.getVideos()
      .filter((v: MediaWrapper) => v.title.toLowerCase().includes(lower));
    const tracks: Track[] = MediaLibrary.getAudios()
      .filter((t: Track) => t.title.toLowerCase().includes(lower));
    const combined: MediaLibraryItem[] = [];
    for (const v of videos) {
      v.description = v.resolution;
      combined.push(v);
    }
    for (const t of tracks) {
      t.description = t.artistName.length > 0 ? t.artistName : '';
      t.artworkUrl = t.artworkPath;
      combined.push(t);
    }
    this.results = combined;
  }
}

@ComponentV2
export struct SearchPage {
  @Local vm: SearchViewModel = new SearchViewModel();
  @Local input: string = '';

  build() {
    HdsNavDestination() {
      Column() {
        // 搜索栏
        Row() {
          Image($r('app.media.ic_search'))
            .width(20).height(20).fillColor($r('app.color.list_subtitle'))
            .margin({ left: 12 })
          TextInput({ text: this.input, placeholder: $r('app.string.search_hint') })
            .fontSize(15)
            .fontColor($r('app.color.list_title'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .height(40)
            .margin({ left: 8 })
            .onChange((v: string) => {
              this.input = v;
              this.vm.search(v);
            })
          if (this.input.length > 0) {
            Image($r('app.media.ic_close_small'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.list_subtitle'))
              .margin({ right: 12 })
              .onClick(() => {
                this.input = '';
                this.vm.search('');
              })
          }
        }
        .layoutWeight(0)
        .height(48)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(24)
        .border({ width: 1, color: $r('app.color.card_border') })
        .margin({ left: 12, right: 12, top: 8 })
        .alignItems(VerticalAlign.Center)

        // 结果 / 空态
        if (this.vm.query.trim().length === 0) {
          Column() {
            Image($r('app.media.ic_search')).width(96).height(96).fillColor($r('app.color.grey800'))
            Text($r('app.string.search_global'))
              .fontSize(14)
              .fontColor($r('app.color.list_subtitle'))
              .margin({ top: 12 })
          }
          .borderRadius(4)
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.vm.results.length === 0) {
          EmptyStateView({ state: EmptyLoadingState.EMPTY_SEARCH, filterQuery: this.vm.query })
        } else {
          List() {
            Repeat(this.vm.results).each((itemRepeatItem: RepeatItem<MediaLibraryItem>) => {
              ListItem() {
                SearchItem({
                  item: itemRepeatItem.item,
                  onItemClick: () => {
                    if (itemRepeatItem.item instanceof MediaWrapper && (itemRepeatItem.item as MediaWrapper).isVideo()) {
                      const video = itemRepeatItem.item as MediaWrapper;
                      void PlaybackService.getInstance().prepareList([video], 0, true).then(() => {
                        const vparam: VideoParam = { uri: video.uri, title: video.title };
                        NavController.push('VideoPlayer', vparam);
                      });
                    } else {
                      const track = itemRepeatItem.item as Track;
                      const mw = new MediaWrapper(track.id, track.title, track.uri, 1);
                      mw.artistName = track.artistName;
                      mw.albumName = track.albumName;
                      mw.artworkPath = track.artworkPath;
                      void PlaybackService.getInstance().playList([mw], 0, true);
                      NavController.push('AudioPlayer');
                    }
                  },
                })
              }
            }).key((item: MediaLibraryItem) => `${item.id}-${item.title}`).virtualScroll()
          }
          .divider({
            strokeWidth: 0.5,
            color: $r('app.color.divider'),
            startMargin: 76,
            endMargin: 16
          })
          .height('100%')
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
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
          mainTitle: $r('app.string.search_global')
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
    .hideTitleBar(false)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
