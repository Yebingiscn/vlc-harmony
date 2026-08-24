import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { NavController } from '../common/data/NavController';
import { FileBrowserParam, formatDuration, SecondaryParam, Track } from '../common/models/MediaModels';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { EmptyStateView } from '../common/components/EmptyStateView';

/**
 * SecondaryPage —— SecondaryActivity(pushed 宿主壳)。
 * 读取 KEY_FRAGMENT 派发子页:ABOUT/STREAMS/HISTORY/PREFERENCES/STORAGE/NETWORK/
 * ARTIST/ALBUM/GENRE/PLAYLIST,无匹配 finish。统一 Toolbar(标题随 fragment)。
 */
@ComponentV2
export struct SecondaryPage {
  @Param param: SecondaryParam = { fragment: '' };
  @Local title: string = '';
  @Local tracks: Track[] = [];

  aboutToAppear(): void {
    this.title = this.param.title ?? '';
    if (this.param.fragment.length === 0) {
      NavController.pop();
      return;
    }
    // STORAGE/NETWORK 改派发到 FileBrowserPage(BrowserMode)。
    if (this.param.fragment === 'STORAGE') {
      NavController.pop();
      const p: FileBrowserParam = { mode: 'storage' };
      NavController.push('FileBrowser', p);
      return;
    }
    if (this.param.fragment === 'NETWORK') {
      NavController.pop();
      const pn: FileBrowserParam = { mode: 'network' };
      NavController.push('FileBrowser', pn);
      return;
    }
    // ARTIST / ALBUM / GENRE → 按分类筛选曲目。
    if (this.param.fragment === 'ARTIST' || this.param.fragment === 'ALBUM' || this.param.fragment === 'GENRE') {
      this.filterTracks();
    }
  }

  /** 按当前 fragment + title 筛选曲目并排序。 */
  filterTracks(): void {
    const all = MediaLibrary.getAudios();
    const key = this.title;
    let filtered: Track[];
    switch (this.param.fragment) {
      case 'ARTIST':
        filtered = all.filter((t: Track) => (t.artistName.length > 0 ? t.artistName : 'Unknown Artist') === key);
        filtered.sort((a: Track, b: Track) => a.albumName.localeCompare(b.albumName) || a.title.localeCompare(b.title));
        break;
      case 'ALBUM':
        filtered = all.filter((t: Track) => (t.albumName.length > 0 ? t.albumName : 'Unknown Album') === key);
        filtered.sort((a: Track, b: Track) => a.trackNumber - b.trackNumber || a.title.localeCompare(b.title));
        break;
      case 'GENRE':
        filtered = all.filter((t: Track) => {
          const g = t.genre.length > 0 ? t.genre.split(/[,;/]/)[0].trim() : '';
          return (g.length > 0 ? g : 'Unknown Genre') === key;
        });
        filtered.sort(
          (a: Track, b: Track) => a.artistName.localeCompare(b.artistName) || a.title.localeCompare(b.title));
        break;
      default:
        filtered = all.slice();
        break;
    }
    this.tracks = filtered;
  }

  resolveTitle(): Resource {
    switch (this.param.fragment) {

      case 'STREAMS':
        return $r('app.string.streams');
      case 'HISTORY':
        return $r('app.string.history');
      case 'PREFERENCES':
        return $r('app.string.preferences');
      case 'NETWORK':
        return $r('app.string.network_browsing');
      case 'PLAYLIST':
        return $r('app.string.playlists');
      default:
        return $r('app.string.app_name');
    }
  }

  async playTrack(track: Track): Promise<void> {
    const all = this.tracks.length > 0 ? this.tracks : MediaLibrary.getAudios();
    const queue: QueueItem[] = all.map((t: Track) =>
    new QueueItem(t.id, t.title, t.uri, t.artistName, t.albumName, t.artworkPath)
    );
    await PlaybackService.playList(queue, all.indexOf(track), true);
    NavController.push('AudioPlayer');
  }

  build() {
    HdsNavDestination() {
        Column() {
          if (this.param.fragment === 'ARTIST' || this.param.fragment === 'ALBUM' ||
            this.param.fragment === 'GENRE') {
            if (this.tracks.length === 0) {
              EmptyStateView({ state: 1 /* EMPTY */ })
            } else {
              this.trackList()
            }
          } else {
            Column() {
              Image($r('app.media.ic_empty')).width(96).height(96).fillColor('#424242')
              Text($r('app.string.developing'))
                .fontSize(14)
                .fontColor($r('app.color.list_subtitle'))
                .margin({ top: 12 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .layoutWeight(1)
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
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
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
          mainTitle: this.title.length > 0 ? this.title : this.resolveTitle()
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

  @Builder
  trackList() {
    List() {
      Repeat(this.tracks).each((tRepeatItem: RepeatItem<Track>) => {
        ListItem() {
          Row() {
            Image($r('app.media.ic_song')).width(40).height(40).fillColor('#FF8800').margin({ right: 12 })
            Column() {
              Text(tRepeatItem.item.title).fontSize(15).fontColor($r('app.color.list_title')).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(tRepeatItem.item.length > 0 ? formatDuration(tRepeatItem.item.length) : tRepeatItem.item.artistName)
                .fontSize(12)
                .fontColor($r('app.color.list_subtitle'))
                .margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 8,
            bottom: 8
          })
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.playTrack(tRepeatItem.item))
        }
      }).key((t: Track) => `s${t.id}`).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 68,
      endMargin: 8
    })
    .height('100%')
    .width('100%')
    .layoutWeight(1)
  }

}
