import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService } from '../common/data/PlaybackService';
import { NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { Artist, Album, Track, EmptyLoadingState, formatDuration, MediaWrapper } from '../common/models/MediaModels';
import { Settings } from '../common/data/Settings';

/**
 * AudioBrowserPage —— Audio Tab 根(AudioBrowserFragment,4 子 Tab:艺术家/专辑/曲目/流派)。
 * 顶部 Tabs(对应 ViewPager2 + TabLayout)+ 各 Tab 列表。子 Tab 选中态持久化(KEY_AUDIO_CURRENT_TAB)。
 */
@ObservedV2
class AudioBrowserViewModel {
  @Trace artists: Artist[] = [];
  @Trace albums: Album[] = [];
  @Trace tracks: Track[] = [];
  @Trace loading: boolean = true;
  @Trace tabIndex: number = 0;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.LOADING;

  async load(): Promise<void> {
    this.loading = true;
    this.tabIndex = await Settings.getInt(Settings.KEY_AUDIO_CURRENT_TAB, 0);
    await MediaLibrary.scan();
    this.artists = MediaLibrary.getArtists().slice();
    this.albums = MediaLibrary.getAlbums().slice();
    this.tracks = MediaLibrary.getAudios().slice();
    this.updateEmpty();
    this.loading = false;
  }

  updateEmpty(): void {
    const total = this.artists.length + this.albums.length + this.tracks.length;
    this.emptyState = total === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
  }

  saveTab(index: number): void {
    this.tabIndex = index;
    Settings.put(Settings.KEY_AUDIO_CURRENT_TAB, index);
  }
}

@ComponentV2
export struct AudioBrowserPage {
  @Local vm: AudioBrowserViewModel = new AudioBrowserViewModel();
  private controller: TabsController = new TabsController();

  aboutToAppear(): void {
    this.vm.load();
  }

  playTrack(track: Track): void {
    const queue: MediaWrapper[] = this.vm.tracks.map((t: Track): MediaWrapper => {
      const mw = new MediaWrapper(t.id, t.title, t.uri, 1);
      return mw;
    });
    PlaybackService.getInstance().playList(queue, this.vm.tracks.indexOf(track), true);
    NavController.push('AudioPlayer');
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: this.vm.tabIndex }) {
        TabContent() {
          if (this.vm.artists.length === 0) {
            EmptyStateView({ state: this.vm.emptyState })
          } else {
            this.artistList()
          }
        }.tabBar(this.tabBuilder($r('app.string.artists'), 0))

        TabContent() {
          if (this.vm.albums.length === 0) {
            EmptyStateView({ state: this.vm.emptyState })
          } else {
            this.albumList()
          }
        }.tabBar(this.tabBuilder($r('app.string.albums'), 1))

        TabContent() {
          if (this.vm.tracks.length === 0) {
            EmptyStateView({ state: this.vm.emptyState })
          } else {
            this.trackList()
          }
        }.tabBar(this.tabBuilder($r('app.string.tracks'), 2))

        TabContent() {
          EmptyStateView({ state: this.vm.emptyState })
        }.tabBar(this.tabBuilder($r('app.string.genres'), 3))
      }
      .barMode(BarMode.Scrollable)
      .barHeight(40)
      .onChange((index: number) => this.vm.saveTab(index))
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
  }

  @Builder
  tabBuilder(title: Resource, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontColor(this.vm.tabIndex === index ? '#FF8800' : '#9E9E9E')
        .fontWeight(this.vm.tabIndex === index ? FontWeight.Medium : FontWeight.Normal)
      Divider().strokeWidth(2).color('#FF8800').width('100%').margin({ top: 6 })
        .visibility(this.vm.tabIndex === index ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  artistList() {
    List() {
      ForEach(this.vm.artists, (a: Artist) => {
        ListItem() {
          Row() {
            Image($r('app.media.ic_artist_big')).width(40).height(40).fillColor('#FF8800').margin({ right: 12 })
            Column() {
              Text(a.title).fontSize(15).fontColor('#FFFFFF').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${a.trackCount} songs`).fontSize(12).fontColor('#9E9E9E').margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 }).alignItems(VerticalAlign.Center)
          .onClick(() => NavController.pushSecondary('ARTIST', a.title))
        }
      }, (a: Artist) => `a${a.id}`)
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 68, endMargin: 8 })
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  albumList() {
    List() {
      ForEach(this.vm.albums, (al: Album) => {
        ListItem() {
          Row() {
            Image($r('app.media.ic_album_big')).width(40).height(40).fillColor('#FF8800').margin({ right: 12 })
            Column() {
              Text(al.title).fontSize(15).fontColor('#FFFFFF').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(al.artistName).fontSize(12).fontColor('#9E9E9E').margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 }).alignItems(VerticalAlign.Center)
          .onClick(() => NavController.pushSecondary('ALBUM', al.title))
        }
      }, (al: Album) => `al${al.id}`)
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 68, endMargin: 8 })
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  trackList() {
    List() {
      ForEach(this.vm.tracks, (t: Track) => {
        ListItem() {
          Row() {
            Image($r('app.media.ic_song')).width(40).height(40).fillColor('#FF8800').margin({ right: 12 })
            Column() {
              Text(t.title).fontSize(15).fontColor('#FFFFFF').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(t.length > 0 ? formatDuration(t.length) : t.albumName).fontSize(12).fontColor('#9E9E9E')
                .margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }
          .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 }).alignItems(VerticalAlign.Center)
          .onClick(() => this.playTrack(t))
        }
      }, (t: Track) => `t${t.id}`)
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 68, endMargin: 8 })
    .width('100%')
    .layoutWeight(1)
  }
}
