import { MediaLibrary } from '../common/data/MediaLibrary';
import { NavController } from '../common/data/NavController';
import { BackTitleBar } from '../common/components/BackTitleBar';
import { SearchItem } from '../common/components/SearchItem';
import { EmptyStateView } from '../common/components/EmptyStateView';
import {
  MediaWrapper,
  Track,
  EmptyLoadingState,
  MediaLibraryItem,
} from '../common/models/MediaModels';
import { PlaybackService } from '../common/data/PlaybackService';
import { VideoParam } from './VideoPlayerPage';

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
    NavDestination() {
      Column() {
        // 搜索栏
        Row() {
          Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor($r('app.color.list_title'))
            .onClick(() => NavController.pop())
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
              Image($r('app.media.ic_close_small')).width(20).height(20).fillColor($r('app.color.list_subtitle'))
                .margin({ right: 12 })
                .onClick(() => {
                  this.input = '';
                  this.vm.search('');
                })
            }
          }
          .layoutWeight(1).height(40)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(20)
          .border({ width: 1, color: $r('app.color.card_border') })
          .margin({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(94)
        .padding({ left: 12, right: 12, top: 38 })
        .backgroundColor($r('app.color.background_actionbar'))
        .alignItems(VerticalAlign.Center)

        // 结果 / 空态
        if (this.vm.query.trim().length === 0) {
          Column() {
            Image($r('app.media.ic_search')).width(96).height(96).fillColor($r('app.color.grey800'))
            Text($r('app.string.search_global')).fontSize(14).fontColor($r('app.color.list_subtitle')).margin({ top: 12 })
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.vm.results.length === 0) {
          EmptyStateView({ state: EmptyLoadingState.EMPTY_SEARCH, filterQuery: this.vm.query })
        } else {
          List() {
            ForEach(this.vm.results, (item: MediaLibraryItem) => {
              ListItem() {
                SearchItem({
                  item: item,
                  onItemClick: () => {
                    if (item instanceof MediaWrapper && (item as MediaWrapper).isVideo()) {
                      const video = item as MediaWrapper;
                      void PlaybackService.getInstance().prepareList([video], 0, true).then(() => {
                        const vparam: VideoParam = { uri: video.uri, title: video.title };
                        NavController.push('VideoPlayer', vparam);
                      });
                    } else {
                      const track = item as Track;
                      const mw = new MediaWrapper(track.id, track.title, track.uri, 1);
                      void PlaybackService.getInstance().playList([mw], 0, true);
                      NavController.push('AudioPlayer');
                    }
                  },
                })
              }
            }, (item: MediaLibraryItem) => `${item.id}-${item.title}`)
          }
          .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 76, endMargin: 16 })
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
