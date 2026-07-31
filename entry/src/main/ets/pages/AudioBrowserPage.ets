import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { Track, EmptyLoadingState, formatDuration } from '../common/models/MediaModels';
import { Settings } from '../common/data/Settings';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'VLC-Audio';

// ---- 网格卡片数据 ----

class AlbumCard {
  name: string;
  artist: string;
  trackCount: number;
  artwork: string;
  tracks: Track[];

  constructor(name: string, artist: string, trackCount: number, artwork: string, tracks: Track[]) {
    this.name = name;
    this.artist = artist;
    this.trackCount = trackCount;
    this.artwork = artwork;
    this.tracks = tracks;
  }
}

class AlbumMapEntry {
  artist: string = '';
  count: number = 0;
  art: string = '';
  tracks: Track[] = [];
}

// ---- ViewModel ----

@ObservedV2
class AudioBrowserVM {
  @Trace artistNames: string[] = [];
  @Trace artistAlbums: AlbumCard[][] = [];  // 每个歌手下的专辑列表
  @Trace albums: AlbumCard[] = [];
  @Trace tracks: Track[] = [];
  @Trace genres: Track[][] = [];
  @Trace genreNames: string[] = [];
  @Trace loading: boolean = true;
  @Trace tabIndex: number = 0;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.LOADING;
  @Trace displayAsList: boolean = false;
  private sortDesc: boolean = false;
  private showAllArtists: boolean = false;

  async load(): Promise<void> {
    this.loading = true;
    this.tabIndex = await Settings.getInt(Settings.KEY_AUDIO_CURRENT_TAB, 0);
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
    this.showAllArtists = await Settings.getBoolean(Settings.KEY_ARTISTS_SHOW_ALL, false);
    await MediaLibrary.scan();
    this.syncData();
    this.loading = false;
  }

  async reloadSettings(): Promise<void> {
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
    this.showAllArtists = await Settings.getBoolean(Settings.KEY_ARTISTS_SHOW_ALL, false);
    this.syncData();
  }

  async reload(): Promise<void> {
    if (MediaLibrary.isScanning()) { return; }
    this.loading = true;
    await MediaLibrary.rescan();
    this.syncData();
    this.loading = false;
  }

  syncData(): void {
    const all = MediaLibrary.getAudios();
    hilog.info(0x0001, TAG, 'syncData: total tracks=%{public}d', all.length);
    for (let i = 0; i < all.length; i++) {
      const t = all[i];
      hilog.info(0x0001, TAG, '  track[%{public}d]: id=%{public}d title="%{public}s" artist="%{public}s" album="%{public}s" art="%{public}s"',
        i, t.id, t.title, t.artistName, t.albumName, t.artworkPath);
    }
    this.tracks = all.slice().sort((a, b) => {
      const cmp = a.title.localeCompare(b.title);
      return this.sortDesc ? -cmp : cmp;
    });

    // 艺术家分组:每个歌手 → 专辑列表。
    const artistMap = new Map<string, Map<string, Track[]>>();
    for (const t of all) {
      const aKey = t.artistName.length > 0 ? t.artistName : '未知艺术家';
      const alKey = t.albumName.length > 0 ? t.albumName : '未知专辑';
      if (!artistMap.has(aKey)) { artistMap.set(aKey, new Map()); }
      const albumMap2 = artistMap.get(aKey)!;
      if (!albumMap2.has(alKey)) { albumMap2.set(alKey, []); }
      albumMap2.get(alKey)!.push(t);
    }
    this.artistNames = Array.from(artistMap.keys()).sort((a, b) => a.localeCompare(b));
    hilog.info(0x0001, TAG, 'artists: %{public}s', this.artistNames.join(', '));
    this.artistAlbums = this.artistNames.map(name => {
      const alMap = artistMap.get(name)!;
      return Array.from(alMap.entries()).sort((a, b) => a[0].localeCompare(b[0])).map((e, idx) => {
        const tracks = e[1].sort((a, b) => a.trackNumber - b.trackNumber || a.title.localeCompare(b.title));
        const art = tracks.find(x => x.artworkPath.length > 0);
        return new AlbumCard(e[0], name, tracks.length, art ? art.artworkPath : '', tracks);
      });
    });

    // 专辑卡片
    const albumMap = new Map<string, AlbumMapEntry>();
    for (const t of all) {
      const key = t.albumName.length > 0 ? t.albumName : '未知专辑';
      const compositeKey = `${key}|${t.artistName}`;
      if (!albumMap.has(compositeKey)) {
        const ae = new AlbumMapEntry();
        ae.artist = t.artistName.length > 0 ? t.artistName : '未知艺术家';
        ae.art = t.artworkPath;
        albumMap.set(compositeKey, ae);
      }
      const alEntry = albumMap.get(compositeKey)!;
      alEntry.count++;
      alEntry.tracks.push(t);
      if (alEntry.art.length === 0 && t.artworkPath.length > 0) {
        alEntry.art = t.artworkPath;
      }
    }
    this.albums = Array.from(albumMap.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(e => new AlbumCard(e[0].split('|')[0], e[1].artist, e[1].count, e[1].art, e[1].tracks));

    // 流派分组
    const genreMap = new Map<string, Track[]>();
    for (const t of all) {
      const raw = t.genre.length > 0 ? t.genre.split(/[,;/]/)[0].trim() : '';
      const key = raw.length > 0 ? raw : '未知流派';
      if (!genreMap.has(key)) { genreMap.set(key, []); }
      genreMap.get(key)!.push(t);
    }
    const sortedGenres = Array.from(genreMap.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    this.genres = sortedGenres.map(e => e[1].sort((a, b) => a.artistName.localeCompare(b.artistName) || a.title.localeCompare(b.title)));
    this.genreNames = sortedGenres.map(e => e[0]);

    const total = artistMap.size + albumMap.size + all.length + genreMap.size;
    this.emptyState = total === 0 ? EmptyLoadingState.EMPTY : EmptyLoadingState.NONE;
  }

  saveTab(index: number): void {
    this.tabIndex = index;
    Settings.put(Settings.KEY_AUDIO_CURRENT_TAB, index);
  }
}

// ---- 页面 ----

@ComponentV2
export struct AudioBrowserPage {
  @Local vm: AudioBrowserVM = new AudioBrowserVM();
  @Local refreshing: boolean = false;
  @Local sheetAlbum: AlbumCard | null = null;
  @Local showSheet: boolean = false;
  @Param settingsVersion: number = 0;
  private controller: TabsController = new TabsController();

  aboutToAppear(): void { this.vm.load(); }

  @Monitor('settingsVersion')
  onSettingsVersionChange(): void { this.vm.reloadSettings(); }

  async doRefresh(): Promise<void> { this.refreshing = true; await this.vm.reload(); this.refreshing = false; }

  async pickAudioFiles(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 200;
      opts.fileSuffixFilters = ['音频 (.mp3, .flac, .ogg, .wav, .aac, .m4a)|.mp3,.flac,.ogg,.wav,.aac,.m4a'];
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.select(opts);
      if (uris.length > 0) { await MediaLibrary.importAudioUris(uris); this.vm.syncData(); }
    } catch (e) { /* cancelled */ }
  }

  playAll(tracks: Track[]): void {
    if (tracks.length === 0) { return; }
    this.playTrack(tracks[0], tracks);
  }

  async playTrack(t: Track, list: Track[]): Promise<void> {
    const queue = list.map(tk => new QueueItem(tk.id, tk.title, tk.uri, tk.artistName, tk.albumName, tk.artworkPath));
    await PlaybackService.playList(queue, list.indexOf(t), true);
    NavController.push('AudioPlayer');
  }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: this.vm.tabIndex }) {
          // 艺术家(纵向分组列表:歌手名 → 曲目)
          TabContent() {
            if (this.vm.artistNames.length === 0) {
              EmptyStateView({ state: this.vm.emptyState, onPickFile: () => this.pickAudioFiles() })
            } else {
              this.artistList()
            }
          }.tabBar(this.tabBuilder($r('app.string.artists'), 0))

          // 专辑
          TabContent() {
            if (this.vm.albums.length === 0) {
              EmptyStateView({ state: this.vm.emptyState, onPickFile: () => this.pickAudioFiles() })
            } else {
              this.albumGrid()
            }
          }.tabBar(this.tabBuilder($r('app.string.albums'), 1))

          // 曲目
          TabContent() {
            if (this.vm.tracks.length === 0) {
              EmptyStateView({ state: this.vm.emptyState, onPickFile: () => this.pickAudioFiles() })
            } else {
              this.trackList()
            }
          }.tabBar(this.tabBuilder($r('app.string.tracks'), 2))

          // 流派
          TabContent() {
            if (this.vm.genres.length === 0) {
              EmptyStateView({ state: this.vm.emptyState, onPickFile: () => this.pickAudioFiles() })
            } else {
              this.genreList()
            }
          }.tabBar(this.tabBuilder($r('app.string.genres'), 3))
        }
        .barMode(BarMode.Scrollable).barHeight(40)
        .onChange((index: number) => this.vm.saveTab(index))
        .layoutWeight(1)
      }
      .onRefreshing(() => this.doRefresh()).refreshOffset(64)
      .backgroundColor($r('app.color.background_default'))

      // FAB
      Button() {
        Image($r('app.media.ic_add')).width(22).height(22).fillColor($r('app.color.colorOnPrimary'))
      }
      .width(48).height(48).borderRadius(24).backgroundColor('#FF8800')
      .shadow({ radius: 8, color: '#44000000', offsetY: 4 })
      .position({ right: 16, bottom: 16 })
      .onClick(() => this.pickAudioFiles())
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    .bindSheet($$this.showSheet, this.albumSheet(), {
      height: SheetSize.FIT_CONTENT, dragBar: true,
      onDisappear: () => { this.showSheet = false; this.sheetAlbum = null; },
    })
  }

  @Builder
  tabBuilder(title: Resource, index: number) {
    Column() {
      Text(title).fontSize(13)
        .fontColor(this.vm.tabIndex === index ? '#FF8800' : $r('app.color.list_subtitle'))
        .fontWeight(this.vm.tabIndex === index ? FontWeight.Medium : FontWeight.Normal)
      Divider().strokeWidth(2).color('#FF8800').width(20).margin({ top: 4 })
        .visibility(this.vm.tabIndex === index ? Visibility.Visible : Visibility.Hidden)
    }
    .padding({ left: 10, right: 10 }).height('100%').justifyContent(FlexAlign.Center)
  }

  // ---- 艺术家列表(歌手 → 专辑网格) ----

  @Builder
  artistList() {
    List() {
      ForEach(this.vm.artistAlbums, (albums: AlbumCard[], aIdx: number) => {
        ListItemGroup({ header: this.artistHeader(aIdx) }) {
          ListItem() {
            Grid() {
              ForEach(albums, (card: AlbumCard) => {
                GridItem() { this.albumCard(card) }
              }, (card: AlbumCard) => `artist_${this.vm.artistNames[aIdx]}_${card.name}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10).rowsGap(10)
            .padding({ left: 12, right: 12, bottom: 12 })
            .width('100%')
          }
        }
      }, (_: AlbumCard[], idx: number) => this.vm.artistNames[idx])
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 16, endMargin: 8 })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  artistHeader(aIdx: number) {
    Row() {
      Text(this.vm.artistNames[aIdx]).fontSize(15).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
      Text(` · ${this.vm.artistAlbums[aIdx].length} 专辑`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 6 }).backgroundColor($r('app.color.audio_header_background'))
  }

  /** 专辑方块卡片:上图(带三点) + 下文(专辑名/曲目数)。 */
  @Builder
  albumCard(card: AlbumCard) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(card.artwork.length > 0 ? card.artwork : $r('app.media.ic_album_big'))
          .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(6)
        Image($r('app.media.ic_more')).width(20).height(20).fillColor($r('app.color.list_title')).margin(4)
          .onClick(() => { this.sheetAlbum = card; this.showSheet = true; })
      }
      .width('100%')
      Text(card.name).fontSize(13).fontColor($r('app.color.list_title')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
      Text(`${card.trackCount} 首`).fontSize(11).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .onClick(() => { if (card.tracks.length > 0) { this.playTrack(card.tracks[0], card.tracks); } })
  }

  // ---- 专辑网格 ----

  @Builder
  albumGrid() {
    Grid() {
      ForEach(this.vm.albums, (card: AlbumCard) => {
        GridItem() {
          Column() {
            // 封面区域
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(card.artwork.length > 0 ? card.artwork : $r('app.media.ic_album_big'))
                .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(8)
              // 三点菜单
              Image($r('app.media.ic_more')).width(20).height(20)
                .fillColor($r('app.color.list_title')).margin(4)
                .onClick(() => {
                  this.sheetAlbum = card;
                  this.showSheet = true;
                })
            }
            .width('100%')
            Text(card.name).fontSize(13).fontColor($r('app.color.list_title')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6 })
            Text(`${card.trackCount} 首 · ${card.artist}`).fontSize(11).fontColor($r('app.color.list_subtitle')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%').padding(6)
          .onClick(() => this.playAll(card.tracks))
        }
      }, (card: AlbumCard) => `${card.name}|${card.artist}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8).rowsGap(12)
    .padding(8).width('100%').height('100%')
  }

  // ---- 曲目列表 ----

  @Builder
  trackList() {
    List() {
      ForEach(this.vm.tracks, (t: Track) => {
        ListItem() { this.trackRow(t, this.vm.tracks) }
      }, (t: Track) => `t${t.id}`)
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 56, endMargin: 8 })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  // ---- 流派列表 ----

  @Builder
  genreList() {
    List() {
      ForEach(this.vm.genres, (tracks: Track[], idx: number) => {
        ListItemGroup({ header: this.genreHeader(this.vm.genreNames[idx], tracks.length) }) {
          ForEach(tracks, (t: Track) => {
            ListItem() { this.trackRow(t, tracks) }
          }, (t: Track) => `genre_${this.vm.genreNames[idx]}_${t.id}`)
        }
      }, (_: Track[], idx: number) => this.vm.genreNames[idx])
    }
    .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 16, endMargin: 8 })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  genreHeader(name: string, count: number) {
    Row() {
      Text(name).fontSize(14).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
      Text(` · ${count}`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 }).backgroundColor($r('app.color.audio_header_background'))
  }

  // ---- 曲目行 ----

  @Builder
  trackRow(t: Track, list: Track[]) {
    Row() {
      Image(t.artworkPath.length > 0 ? t.artworkPath : $r('app.media.ic_song'))
        .width(36).height(36).objectFit(ImageFit.Cover).borderRadius(4).margin({ right: 12 })
      Column() {
        Text(t.title).fontSize(14).fontColor($r('app.color.list_title')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (t.artistName.length > 0) {
          Text(t.artistName).fontSize(12).fontColor($r('app.color.list_subtitle')).margin({ top: 2 })
        } else {
          Text(this.fileNameFromUri(t.filePath)).fontSize(11).fontColor($r('app.color.font_light')).margin({ top: 2 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (t.length > 0) { Text(formatDuration(t.length)).fontSize(11).fontColor($r('app.color.font_light')).margin({ left: 8 }) }
    }
    .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 }).alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.playTrack(t, list);
    })
  }

  private fileNameFromUri(uri: string): string {
    const ls = Math.max(uri.lastIndexOf('/'), uri.lastIndexOf('\\'));
    return ls >= 0 ? uri.slice(ls + 1) : uri;
  }

  // ---- 专辑操作半模态 ----

  @Builder
  albumSheet() {
    Column() {
      // 头部:封面 + 专辑名 + 歌手
      Row() {
        Image(this.sheetAlbum!.artwork.length > 0 ? this.sheetAlbum!.artwork : $r('app.media.ic_album_big'))
          .width(56).height(56).objectFit(ImageFit.Cover).borderRadius(6).margin({ right: 12 })
        Column() {
          Text(this.sheetAlbum!.name).fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Medium).maxLines(1)
          Text(this.sheetAlbum!.artist).fontSize(13).fontColor('#9E9E9E').maxLines(1).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)

      Divider().strokeWidth(0.5).color('#333333')

      // 播放全部
      Row() {
        Image($r('app.media.ic_play_player')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text('播放全部').fontSize(15).fontColor('#FFFFFF')
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        this.playAll(this.sheetAlbum!.tracks);
        this.showSheet = false;
        this.sheetAlbum = null;
      })

      // 收藏
      Row() {
        Image($r('app.media.ic_fav_add')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text($r('app.string.favorites')).fontSize(15).fontColor('#FFFFFF')
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        promptAction.showToast({ message: '已收藏' });
        this.sheetAlbum = null;
      })

      // 专辑信息
      Row() {
        Image($r('app.media.ic_information')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text('专辑信息').fontSize(15).fontColor('#FFFFFF')
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        promptAction.showToast({ message: `专辑: ${this.sheetAlbum!.name}\n歌手: ${this.sheetAlbum!.artist}\n曲目: ${this.sheetAlbum!.trackCount} 首` });
        this.sheetAlbum = null;
      })

      Divider().strokeWidth(0.5).color('#333333')
      Blank().height(24)
    }
    .width('100%').backgroundColor('#1A1A1A')
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
