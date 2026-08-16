import { UiFeedback } from '../common/utils/UiFeedback';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { EmptyLoadingState, formatDuration, Track } from '../common/models/MediaModels';
import { Settings } from '../common/data/Settings';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
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
  @Trace artistAlbums: AlbumCard[][] = []; // 每个歌手下的专辑列表
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
  private onlyFavs: boolean = false;
  private searchQuery: string = '';

  /** 按系统语言进行不区分大小写、支持数字段的名称排序，并统一处理升降序。 */
  private compareNames(left: string, right: string): number {
    const result = left.localeCompare(right, undefined, { numeric: true, sensitivity: 'base' });
    return this.sortDesc ? -result : result;
  }

  async load(): Promise<void> {
    this.loading = true;
    this.tabIndex = await Settings.getInt(Settings.KEY_AUDIO_CURRENT_TAB, 0);
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
    this.showAllArtists = await Settings.getBoolean(Settings.KEY_ARTISTS_SHOW_ALL, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_AUDIO_ONLY_FAVS, false);
    // 尊重「自动重新扫描」开关:autoRescan 关闭时不自动扫描。
    // 手动刷新请走 vm.reload()(下拉刷新),不受此门控影响。
    await MediaLibrary.scan();
    await MediaLibrary.loadMediaFavs();
    this.syncData();
    this.loading = false;
  }

  async reloadSettings(): Promise<void> {
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
    this.showAllArtists = await Settings.getBoolean(Settings.KEY_ARTISTS_SHOW_ALL, false);
    this.onlyFavs = await Settings.getBoolean(Settings.KEY_AUDIO_ONLY_FAVS, false);
    this.syncData();
  }

  async reload(): Promise<void> {
    if (MediaLibrary.isScanning()) {
      return;
    }
    this.loading = true;
    await MediaLibrary.rescan();
    this.syncData();
    this.loading = false;
  }

  syncData(): void {
    const raw = MediaLibrary.getAudios();
    const trimmed = this.searchQuery.trim().toLowerCase();
    // 当前 Tab 内搜索:按标题/艺术家/专辑/流派过滤,四个子 Tab 共用过滤后的结果集
    let all = trimmed.length > 0
      ? raw.filter((t: Track) =>
      t.title.toLowerCase().includes(trimmed) ||
        t.artistName.toLowerCase().includes(trimmed) ||
        t.albumName.toLowerCase().includes(trimmed) ||
        t.genre.toLowerCase().includes(trimmed))
      : raw;
    // 仅显示收藏:按专辑键过滤,四个子 Tab 共用过滤后的结果集
    if (this.onlyFavs) {
      all = all.filter((t: Track) => MediaLibrary.isMediaFav(MediaLibrary.albumFavKey(t.albumName, t.artistName)));
    }
    hilog.info(0x0001, TAG, 'syncData: total tracks=%{public}d', all.length);
    for (let i = 0; i < all.length; i++) {
      const t = all[i];
      hilog.info(0x0001, TAG,
        '  track[%{public}d]: id=%{public}d title="%{public}s" artist="%{public}s" album="%{public}s" art="%{public}s"',
        i, t.id, t.title, t.artistName, t.albumName, t.artworkPath);
    }
    this.tracks = all.slice().sort((a, b) => {
      const titleResult = this.compareNames(a.title, b.title);
      return titleResult !== 0 ? titleResult : this.compareNames(a.artistName, b.artistName);
    });

    // 艺术家分组:每个歌手 → 专辑列表。
    const artistMap = new Map<string, Map<string, Track[]>>();
    for (const t of all) {
      const aKey = t.artistName.length > 0 ? t.artistName : '未知艺术家';
      const alKey = t.albumName.length > 0 ? t.albumName : '未知专辑';
      if (!artistMap.has(aKey)) {
        artistMap.set(aKey, new Map());
      }
      const albumMap2 = artistMap.get(aKey)!;
      if (!albumMap2.has(alKey)) {
        albumMap2.set(alKey, []);
      }
      albumMap2.get(alKey)!.push(t);
    }
    this.artistNames = Array.from(artistMap.keys()).sort((a, b) => this.compareNames(a, b));
    hilog.info(0x0001, TAG, 'artists: %{public}s', this.artistNames.join(', '));
    this.artistAlbums = this.artistNames.map(name => {
      const alMap = artistMap.get(name)!;
      return Array.from(alMap.entries()).sort((a, b) => this.compareNames(a[0], b[0])).map((e) => {
        const tracks = e[1].slice().sort((a, b) => this.compareNames(a.title, b.title));
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
      .sort((a, b) => this.compareNames(a[0], b[0]))
      .map(e => new AlbumCard(e[0].split('|')[0], e[1].artist, e[1].count, e[1].art,
        e[1].tracks.slice().sort((a, b) => this.compareNames(a.title, b.title))));

    // 流派分组
    const genreMap = new Map<string, Track[]>();
    for (const t of all) {
      const raw = t.genre.length > 0 ? t.genre.split(/[,;/]/)[0].trim() : '';
      const key = raw.length > 0 ? raw : '未知流派';
      if (!genreMap.has(key)) {
        genreMap.set(key, []);
      }
      genreMap.get(key)!.push(t);
    }
    const sortedGenres = Array.from(genreMap.entries()).sort((a, b) => this.compareNames(a[0], b[0]));
    this.genres = sortedGenres.map(e => e[1].slice().sort((a, b) => {
      const titleResult = this.compareNames(a.title, b.title);
      return titleResult !== 0 ? titleResult : this.compareNames(a.artistName, b.artistName);
    }));
    this.genreNames = sortedGenres.map(e => e[0]);

    const total = artistMap.size + albumMap.size + all.length + genreMap.size;
    if (total === 0) {
      if (this.searchQuery.trim().length > 0) {
        this.emptyState = EmptyLoadingState.EMPTY_SEARCH;
      } else if (this.onlyFavs) {
        this.emptyState = EmptyLoadingState.EMPTY_FAVORITES;
      } else {
        this.emptyState = EmptyLoadingState.EMPTY;
      }
    } else {
      this.emptyState = EmptyLoadingState.NONE;
    }
  }

  applySearch(q: string): void {
    this.searchQuery = q;
    this.syncData();
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
  @Local sheetAlbumFav: boolean = false;
  @Param settingsVersion: number = 0;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  /** "转到艺人"定位目标(配合 goToArtistVersion 触发 @Monitor)。 */
  @Param goToArtistName: string = '';
  /** "转到艺人"请求版本号:自增保证同名艺人连续定位也触发 @Monitor。 */
  @Param goToArtistVersion: number = 0;
  private controller: TabsController = new TabsController();
  /** 防止播放器首次初始化期间连续点击同一专辑，重复压入 AudioPlayer 页面。 */
  private audioPlayerOpening: boolean = false;
  /** 艺术家列表滚动控制器("转到艺人"时 scrollToIndex 到对应歌手分组)。 */
  private artistScroller: Scroller = new Scroller();
  @Event onSearchGlobal: () => void = () => {
  };

  aboutToAppear(): void {
    // 从播放器返回后允许再次进入；成功 push 后则一直保持锁定到页面重新显示。
    this.audioPlayerOpening = false;
    this.vm.load();
  }

  @Monitor('settingsVersion')
  onSettingsVersionChange(): void {
    this.vm.reloadSettings();
  }

  /** 收到 MainPage "转到艺人"派发:切到"艺术家"子 Tab 并滚动到对应歌手分组。 */
  @Monitor('goToArtistVersion')
  onGoToArtistVersion(): void {
    const artist = this.goToArtistName;
    if (artist.length === 0) {
      return;
    }
    this.vm.saveTab(0);
    this.controller.changeIndex(0);
    // artistNames 下标 = ListItemGroup 下标;等 Tab 切换动画 + 列表渲染后再滚动。
    const idx = this.vm.artistNames.indexOf(artist);
    if (idx >= 0) {
      setTimeout(() => {
        this.artistScroller.scrollToIndex(idx, true);
      }, 60);
    }
  }

  async doRefresh(): Promise<void> {
    this.refreshing = true;
    await this.vm.reload();
    this.refreshing = false;
  }

  @Monitor('searchQuery')
  onSearchQueryChange(): void {
    this.vm.applySearch(this.searchQuery);
  }

  async pickAudioFiles(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 200;
      opts.fileSuffixFilters = ['音频 (.mp3, .flac, .ogg, .wav, .aac, .m4a)|.mp3,.flac,.ogg,.wav,.aac,.m4a'];
      opts.mergeMode = picker.MergeTypeMode.AUDIO;
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.select(opts);
      if (uris.length > 0) {
        await MediaLibrary.importAudioUris(uris);
        this.vm.syncData();
      }
    } catch (e) { /* cancelled */
    }
  }

  playAll(tracks: Track[]): void {
    if (tracks.length === 0) {
      return;
    }
    this.playTrack(tracks[0], tracks);
  }

  playTrack(t: Track, list: Track[]): void {
    if (this.audioPlayerOpening || list.length === 0) {
      return;
    }
    this.audioPlayerOpening = true;
    const queue = list.map(tk => new QueueItem(tk.id, tk.title, tk.uri, tk.artistName, tk.albumName, tk.artworkPath));
    // 播放器首次初始化可能耗时，页面先响应点击；播放队列在后台准备。
    void PlaybackService.playList(queue, list.indexOf(t), true).catch(() => {
      this.audioPlayerOpening = false;
      UiFeedback.showToast({ message: '无法播放该音频' });
    });
    NavController.push('AudioPlayer');
    // MainPage 会常驻并仅切换可见性，返回时本组件不保证再次触发 aboutToAppear。
    // 因此锁只覆盖导航动画窗口，不能一直等生命周期回调释放。
    setTimeout(() => {
      this.audioPlayerOpening = false;
    }, 800);
  }

  /** 打开专辑操作半模态,并按当前收藏状态初始化图标/文案。 */
  openAlbumSheet(card: AlbumCard): void {
    this.sheetAlbum = card;
    this.sheetAlbumFav = MediaLibrary.isMediaFav(MediaLibrary.albumFavKey(card.name, card.artist));
    this.showSheet = true;
  }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: this.vm.tabIndex }) {
          // 艺术家(纵向分组列表:歌手名 → 曲目)
          TabContent() {
            Column() {
              if (this.searchMode) {
                this.searchGlobalButton()
              }
              if (this.vm.artistNames.length === 0) {
                EmptyStateView(
                  { state: this.vm.emptyState, filterQuery: this.searchQuery, onPickFile: () => this.pickAudioFiles() })
                  .layoutWeight(1).width('100%')
              } else {
                this.artistList()
              }
            }.width('100%').height('100%')
          }.tabBar(this.tabBuilder($r('app.string.artists'), 0))

          // 专辑
          TabContent() {
            Column() {
              if (this.searchMode) {
                this.searchGlobalButton()
              }
              if (this.vm.albums.length === 0) {
                EmptyStateView(
                  { state: this.vm.emptyState, filterQuery: this.searchQuery, onPickFile: () => this.pickAudioFiles() })
                  .layoutWeight(1).width('100%')
              } else if (this.vm.displayAsList) {
                this.albumList()
              } else {
                this.albumGrid()
              }
            }.width('100%').height('100%')
          }.tabBar(this.tabBuilder($r('app.string.albums'), 1))

          // 曲目
          TabContent() {
            Column() {
              if (this.searchMode) {
                this.searchGlobalButton()
              }
              if (this.vm.tracks.length === 0) {
                EmptyStateView(
                  { state: this.vm.emptyState, filterQuery: this.searchQuery, onPickFile: () => this.pickAudioFiles() })
                  .layoutWeight(1).width('100%')
              } else if (this.vm.displayAsList) {
                this.trackList()
              } else {
                this.trackGrid()
              }
            }.width('100%').height('100%')
          }.tabBar(this.tabBuilder($r('app.string.tracks'), 2))

          // 流派
          TabContent() {
            Column() {
              if (this.searchMode) {
                this.searchGlobalButton()
              }
              if (this.vm.genres.length === 0) {
                EmptyStateView(
                  { state: this.vm.emptyState, filterQuery: this.searchQuery, onPickFile: () => this.pickAudioFiles() })
                  .layoutWeight(1).width('100%')
              } else if (this.vm.displayAsList) {
                this.genreList()
              } else {
                this.genreGrid()
              }
            }.width('100%').height('100%')
          }.tabBar(this.tabBuilder($r('app.string.genres'), 3))
        }
        .barMode(BarMode.Scrollable)
        .barHeight(40)
        .onChange((index: number) => this.vm.saveTab(index))
        .layoutWeight(1)
        .width('100%')
      }
      .onRefreshing(() => this.doRefresh()).refreshOffset(64)
      .backgroundColor($r('app.color.background_default'))

      // FAB：避让 64vp HdsTabs 底栏以及播放时显示在其上方的 MiniPlayer。
      Button() {
        Image($r('app.media.ic_add')).width(22).height(22).fillColor($r('app.color.colorOnPrimary'))
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#FF8800')
      .shadow({ radius: 8, color: '#44000000', offsetY: 4 })
      .position({ right: 16, bottom: 152 })
      .onClick(() => this.pickAudioFiles())
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    .bindSheet($$this.showSheet, this.albumSheet(), {
      showClose: false,
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.bottom_sheet_background'),
      onDisappear: () => {
        this.showSheet = false;
        this.sheetAlbum = null;
      },
    })
  }

  /** 搜索态:跳转全局搜索页的矩形按钮(橙字灰边居中)。 */
  @Builder
  searchGlobalButton() {
    Row() {
      Button($r('app.string.search_global'))
        .type(ButtonType.Normal)
        .borderRadius(4)
        .backgroundColor($r('app.color.background_default'))
        .fontColor('#FF8800')
        .border({ width: 1, color: $r('app.color.card_border') })
        .fontSize(14)
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
        .onClick(() => this.onSearchGlobal())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  tabBuilder(title: Resource, index: number) {
    Column() {
      Text(title).fontSize(16)
        .fontColor(this.vm.tabIndex === index ? '#FF8800' : $r('app.color.list_subtitle'))
        .fontWeight(this.vm.tabIndex === index ? FontWeight.Medium : FontWeight.Normal)
      Divider()
        .strokeWidth(2)
        .color('#FF8800')
        .width(20)
        .margin({ top: 4 })
        .visibility(this.vm.tabIndex === index ? Visibility.Visible : Visibility.Hidden)
    }
    .padding({ left: 10, right: 10 })
    .height('100%')
    .width('25%')
    .justifyContent(FlexAlign.Center)
  }

  // ---- 艺术家列表(歌手 → 专辑网格) ----

  @Builder
  artistList() {
    List({ space: 0, scroller: this.artistScroller }) {
      Repeat(this.vm.artistAlbums).each((albumsRepeatItem: RepeatItem<AlbumCard[]>) => {
        ListItemGroup({ header: this.artistHeader(albumsRepeatItem.index) }) {
          ListItem() {
            if (this.vm.displayAsList) {
              Column() {
                Repeat(albumsRepeatItem.item).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
                  this.albumRow(cardRepeatItem.item)
                }).key((card: AlbumCard) => `artist_list_${this.vm.artistNames[albumsRepeatItem.index]}_${card.name}`)
              }
              .width('100%')
            } else {
              Grid() {
                Repeat(albumsRepeatItem.item).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
                  GridItem() {
                    this.albumCard(cardRepeatItem.item)
                  }
                }).key((card: AlbumCard) => `artist_grid_${this.vm.artistNames[albumsRepeatItem.index]}_${card.name}`)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .padding({ left: 12, right: 12, bottom: 12 })
              .width('100%')
            }
          }
        }
      }).key((_: AlbumCard[], idx: number) => this.vm.artistNames[idx]).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 16,
      endMargin: 8
    })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  artistHeader(aIdx: number) {
    Row() {
      Text(this.vm.artistNames[aIdx]).fontSize(16).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
      Text(` · ${this.vm.artistAlbums[aIdx].length} 专辑`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 6
    })
    .backgroundColor($r('app.color.audio_header_background'))
  }

  /** 专辑方块卡片:上图(带三点) + 下文(专辑名/曲目数)。 */
  @Builder
  albumCard(card: AlbumCard) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(card.artwork.length > 0 ? card.artwork : $r('app.media.ic_album_big'))
          .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(6)
        Image($r('app.media.ic_more'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.list_title'))
          .margin(4)
          .onClick(() => {
            this.openAlbumSheet(card);
          })
      }
      .width('100%')

      Text(card.name)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
      Text(`${card.trackCount} 首`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .onClick(() => {
      if (card.tracks.length > 0) {
        this.playTrack(card.tracks[0], card.tracks);
      }
    })
  }

  // ---- 专辑网格 ----

  @Builder
  albumList() {
    List() {
      Repeat(this.vm.albums).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
        ListItem() {
          this.albumRow(cardRepeatItem.item)
        }
      }).key((card: AlbumCard) => `album_list_${card.name}|${card.artist}`).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 76,
      endMargin: 8
    })
    .alignListItem(ListItemAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  albumRow(card: AlbumCard) {
    Row() {
      Image(card.artwork.length > 0 ? card.artwork : $r('app.media.ic_album_big'))
        .width(52)
        .height(52)
        .objectFit(ImageFit.Cover)
        .borderRadius(6)
        .margin({ right: 12 })
      Column() {
        Text(card.name)
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${card.trackCount} 首 · ${card.artist}`)
          .fontSize(13)
          .fontColor($r('app.color.list_subtitle'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.ic_more'))
        .width(22)
        .height(22)
        .fillColor($r('app.color.list_title'))
        .margin({ left: 8 })
        .onClick(() => this.openAlbumSheet(card))
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.playAll(card.tracks))
  }

  @Builder
  albumGrid() {
    Grid() {
      Repeat(this.vm.albums).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
        GridItem() {
          Column() {
            // 封面区域
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(cardRepeatItem.item.artwork.length > 0 ? cardRepeatItem.item.artwork : $r('app.media.ic_album_big'))
                .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(8)
              // 三点菜单
              Image($r('app.media.ic_more'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.list_title'))
                .margin(4)
                .onClick(() => {
                  this.openAlbumSheet(cardRepeatItem.item);
                })
            }
            .width('100%')

            Text(cardRepeatItem.item.name)
              .fontSize(14)
              .fontColor($r('app.color.list_title'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
            Text(`${cardRepeatItem.item.trackCount} 首 · ${cardRepeatItem.item.artist}`)
              .fontSize(12)
              .fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%').padding(6)
          .onClick(() => this.playAll(cardRepeatItem.item.tracks))
        }
      }).key((card: AlbumCard) => `${card.name}|${card.artist}`).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(12)
    .padding(8)
    .width('100%')
    .height('100%')
  }

  // ---- 曲目列表 ----

  @Builder
  trackList() {
    List() {
      Repeat(this.vm.tracks).each((tRepeatItem: RepeatItem<Track>) => {
        ListItem() {
          this.trackRow(tRepeatItem.item, this.vm.tracks)
        }
      }).key((t: Track) => `t${t.id}`).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 56,
      endMargin: 8
    })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  trackGrid() {
    Grid() {
      Repeat(this.vm.tracks).each((trackRepeatItem: RepeatItem<Track>) => {
        GridItem() {
          this.trackCard(trackRepeatItem.item, this.vm.tracks)
        }
      }).key((track: Track) => `track_grid_${track.id}`).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(12)
    .padding({ left: 8, right: 8, top: 8, bottom: 152 })
    .width('100%')
    .height('100%')
  }

  @Builder
  trackCard(track: Track, queue: Track[]) {
    Column() {
      Image(track.artworkPath.length > 0 ? track.artworkPath : $r('app.media.ic_song'))
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
      Text(track.title)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
      Text(track.artistName.length > 0 ? track.artistName : '未知艺术家')
        .fontSize(12)
        .fontColor($r('app.color.list_subtitle'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(6)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.playTrack(track, queue))
  }

  // ---- 流派列表 ----

  @Builder
  genreList() {
    List() {
      Repeat(this.vm.genres).each((tracksRepeatItem: RepeatItem<Track[]>) => {
        ListItemGroup({ header: this.genreHeader(this.vm.genreNames[tracksRepeatItem.index], tracksRepeatItem.item.length) }) {
          Repeat(tracksRepeatItem.item).each((tRepeatItem: RepeatItem<Track>) => {
            ListItem() {
              this.trackRow(tRepeatItem.item, tracksRepeatItem.item)
            }
          }).key((t: Track) => `genre_${this.vm.genreNames[tracksRepeatItem.index]}_${t.id}`)
        }
      }).key((_: Track[], idx: number) => this.vm.genreNames[idx]).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 16,
      endMargin: 8
    })
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  genreArtwork(tracks: Track[]): ResourceStr {
    const artworkTrack: Track | undefined = tracks.find((track: Track) => track.artworkPath.length > 0);
    return artworkTrack ? artworkTrack.artworkPath : $r('app.media.ic_album_big');
  }

  @Builder
  genreGrid() {
    Grid() {
      Repeat(this.vm.genres).each((tracksRepeatItem: RepeatItem<Track[]>) => {
        GridItem() {
          this.genreCard(this.vm.genreNames[tracksRepeatItem.index], tracksRepeatItem.item)
        }
      }).key((_: Track[], index: number) => `genre_grid_${this.vm.genreNames[index]}`).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(12)
    .padding({ left: 8, right: 8, top: 8, bottom: 152 })
    .width('100%')
    .height('100%')
  }

  @Builder
  genreCard(name: string, tracks: Track[]) {
    Column() {
      Image(this.genreArtwork(tracks))
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
      Text(name)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
      Text(`${tracks.length} 首`)
        .fontSize(12)
        .fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .padding(6)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.playAll(tracks))
  }

  @Builder
  genreHeader(name: string, count: number) {
    Row() {
      Text(name).fontSize(16).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
      Text(` · ${count}`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 6
    })
    .backgroundColor($r('app.color.audio_header_background'))
  }

  // ---- 曲目行 ----

  @Builder
  trackRow(t: Track, list: Track[]) {
    Row() {
      Image(t.artworkPath.length > 0 ? t.artworkPath : $r('app.media.ic_song'))
        .width(36)
        .height(36)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .margin({ right: 12 })
      Column() {
        Text(t.title)
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (t.artistName.length > 0) {
          Text(t.artistName).fontSize(13).fontColor($r('app.color.list_subtitle')).margin({ top: 2 })
        } else {
          Text(this.fileNameFromUri(t.filePath))
            .fontSize(11)
            .fontColor($r('app.color.font_light'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (t.length > 0) {
        Text(formatDuration(t.length)).fontSize(11).fontColor($r('app.color.font_light')).margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 6,
      bottom: 6
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.playTrack(t, list);
    })
  }

  @Builder
  albumSheet() {
    Column() {
      // 头部:封面 + 专辑名 + 歌手
      Row() {
        Image(this.sheetAlbum!.artwork.length > 0 ? this.sheetAlbum!.artwork : $r('app.media.ic_album_big'))
          .width(56)
          .height(56)
          .alt($r('app.media.ic_album_big'))
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .margin({ right: 12 })
        Column() {
          Text(this.sheetAlbum!.name)
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text(this.sheetAlbum!.artist)
            .fontSize(13)
            .fontColor($r('app.color.list_subtitle'))
            .maxLines(1)
            .margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)

      Divider().strokeWidth(0.5).color($r('app.color.divider'))

      // 播放全部
      Row() {
        Image($r('app.media.ic_play_player'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 12 })
        Text('播放全部').fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 14,
        bottom: 14
      })
      .onClick(() => {
        this.playAll(this.sheetAlbum!.tracks);
        this.showSheet = false;
      })

      // 收藏 / 取消收藏
      Row() {
        Image(this.sheetAlbumFav ? $r('app.media.ic_fav_remove') : $r('app.media.ic_fav_add'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 12 })
        Text(this.sheetAlbumFav ? '取消收藏' : '添加到收藏夹')
          .fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 14,
        bottom: 14
      })
      .onClick(() => {
        const key = MediaLibrary.albumFavKey(this.sheetAlbum!.name, this.sheetAlbum!.artist);
        MediaLibrary.toggleMediaFav(key).then((fav: boolean) => {
          this.sheetAlbumFav = fav;
          UiFeedback.showToast({ message: fav ? '已收藏' : '已取消收藏' });
          this.vm.syncData();
        });
      })

      // 专辑信息
      Row() {
        Image($r('app.media.ic_information'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 12 })
        Text('专辑信息').fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 14,
        bottom: 14
      })
      .onClick(() => {
        UiFeedback.showToast({
          message: `专辑: ${this.sheetAlbum!.name}\n歌手: ${this.sheetAlbum!.artist}\n曲目: ${this.sheetAlbum!.trackCount} 首`
        });
      })

      Divider().strokeWidth(0.5).color($r('app.color.divider'))
      Blank().height(24)
    }
    .width('100%').backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  // ---- 专辑操作半模态 ----

  private fileNameFromUri(uri: string): string {
    const ls = Math.max(uri.lastIndexOf('/'), uri.lastIndexOf('\\'));
    return ls >= 0 ? uri.slice(ls + 1) : uri;
  }
}
