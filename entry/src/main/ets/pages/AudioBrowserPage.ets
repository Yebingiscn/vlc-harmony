import { NATIVE_BOTTOM_SHEET_RADIUS } from '../common/constants/BottomSheetStyle';
import { UiFeedback } from '../common/utils/UiFeedback';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { audioAlbumArtist, audioAlbumKey, audioTag, audioTagKey } from '../common/data/AudioLibraryIdentity';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { AudioPlayerRoute, NavController } from '../common/data/NavController';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { FloatingAddButton } from '../common/components/FloatingAddButton';
import { EmptyLoadingState, formatDuration, Track } from '../common/models/MediaModels';
import { Settings } from '../common/data/Settings';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { pinyin4js } from '@ohos/pinyin4js';
import { AppColors, AppDimens } from '../common/constants/AppConstants';

const TAG = 'VLC-Audio';
const TRACKS_TAB: number = 2;
const AUDIO_MORE_BUTTON_SIZE: number = 40;
const AUDIO_COVER_MORE_INSET: number = 4;

// ---- 网格卡片数据 ----

class AlbumCard {
  key: string;
  name: string;
  artist: string;
  trackCount: number;
  artwork: string;
  tracks: Track[];

  constructor(key: string, name: string, artist: string, artwork: string, tracks: Track[]) {
    this.key = key;
    this.name = name;
    this.artist = artist;
    this.trackCount = tracks.length;
    this.artwork = artwork;
    this.tracks = tracks;
  }
}

class AlbumMapEntry {
  name: string = '';
  artist: string = '';
  art: string = '';
  tracks: Track[] = [];
}

class AlbumPlaybackRequest {
  track: Track;
  tracks: Track[];
  artistSourceId: string;

  constructor(track: Track, tracks: Track[], artistSourceId: string) {
    this.track = track;
    this.tracks = tracks;
    this.artistSourceId = artistSourceId;
  }
}

class ArtistGroup {
  key: string;
  name: string;
  albums: AlbumCard[] = [];

  constructor(key: string, name: string) {
    this.key = key;
    this.name = name;
  }
}

// ---- ViewModel ----

@ObservedV2
export class AudioBrowserVM {
  @Trace artistGroups: ArtistGroup[] = [];
  @Trace albums: AlbumCard[] = [];
  @Trace tracks: Track[] = [];
  @Trace genres: Track[][] = [];
  @Trace genreNames: string[] = [];
  @Trace loading: boolean = true;
  @Trace tabIndex: number = 0;
  @Trace emptyState: EmptyLoadingState = EmptyLoadingState.LOADING;
  @Trace displayAsList: boolean = false;
  /** 分组视图的重建版本；曲目列表和网格按 URI 保持节点身份。 */
  @Trace renderVersion: number = 0;
  private sortDesc: boolean = false;
  private onlyFavs: boolean = false;
  private searchQuery: string = '';
  private pinyinCache: Map<string, string> = new Map();
  private static splitRegex = /(\d+)/g;
  private static readonly COLLATOR = new Intl.Collator('zh-CN', {
    sensitivity: 'variant',
    numeric: true,
    ignorePunctuation: false,
    caseFirst: 'upper'
  });

  /** 与 SweetVideo 一致：先转简拼，再按中文区域规则进行自然排序。 */
  private compareNames(left: string, right: string): number {
    const leftPinyin = this.getPinyin(left);
    const rightPinyin = this.getPinyin(right);
    let result = AudioBrowserVM.naturalCompare(leftPinyin, rightPinyin);
    // 同音或简拼相同时再比较原名，避免不同名称的次序依赖媒体扫描顺序。
    if (result === 0) {
      result = AudioBrowserVM.COLLATOR.compare(left, right);
    }
    return this.sortDesc ? -result : result;
  }

  private getPinyin(name: string): string {
    const cached = this.pinyinCache.get(name);
    if (cached !== undefined) {
      return cached;
    }
    const pinyin = pinyin4js.getShortPinyin(name) as string;
    this.pinyinCache.set(name, pinyin);
    return pinyin;
  }

  private static naturalCompare(left: string, right: string): number {
    const leftParts = left.split(AudioBrowserVM.splitRegex).filter(Boolean);
    const rightParts = right.split(AudioBrowserVM.splitRegex).filter(Boolean);
    const count = Math.min(leftParts.length, rightParts.length);
    for (let i = 0; i < count; i++) {
      const leftPart = leftParts[i];
      const rightPart = rightParts[i];
      const leftIsNumber = /^\d+$/.test(leftPart);
      const rightIsNumber = /^\d+$/.test(rightPart);
      if (leftIsNumber && rightIsNumber) {
        const leftNumber = parseInt(leftPart, 10);
        const rightNumber = parseInt(rightPart, 10);
        if (leftNumber !== rightNumber) {
          return leftNumber - rightNumber;
        }
      } else {
        const result = AudioBrowserVM.COLLATOR.compare(leftPart, rightPart);
        if (result !== 0) {
          return result;
        }
      }
    }
    return leftParts.length - rightParts.length;
  }

  async load(): Promise<void> {
    this.loading = true;
    this.tabIndex = await Settings.getInt(Settings.KEY_AUDIO_CURRENT_TAB, 0);
    this.displayAsList = await Settings.getBoolean(Settings.KEY_DISPLAY_AS_LIST, false);
    this.sortDesc = await Settings.getBoolean(Settings.KEY_AUDIO_SORT_DESC, false);
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

  private addAlbum(index: Map<string, AlbumMapEntry>, key: string, track: Track): void {
    let album = index.get(key);
    if (album === undefined) {
      album = new AlbumMapEntry();
      album.name = audioTag(track.albumName) || '未知专辑';
      album.artist = audioAlbumArtist(track) || '未知艺术家';
      index.set(key, album);
    }
    album.tracks.push(track);
    if (album.art.length === 0 && track.artworkPath.length > 0) {
      album.art = track.artworkPath;
    }
  }

  private albumCards(index: Map<string, AlbumMapEntry>): AlbumCard[] {
    return Array.from(index.entries())
      .sort((a, b) => this.compareNames(a[1].name, b[1].name) || this.compareNames(a[1].artist, b[1].artist))
      .map(e => new AlbumCard(e[0], e[1].name, e[1].artist, e[1].art, this.sortAlbumTracks(e[1].tracks)));
  }

  private sortAlbumTracks(tracks: Track[]): Track[] {
    return tracks.slice().sort((a, b) => this.compareNames(a.title, b.title) ||
      (a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0));
  }

  albumDetails(card: AlbumCard): AlbumCard {
    const tracks = MediaLibrary.getAudios().filter((track: Track) => audioAlbumKey(track) === card.key);
    return new AlbumCard(card.key, card.name, card.artist, card.artwork,
      this.sortAlbumTracks(tracks.length > 0 ? tracks : card.tracks));
  }

  syncData(forceRebuild: boolean = false): void {
    const raw = MediaLibrary.getAudios();
    const trimmed = audioTagKey(this.searchQuery);
    // 当前 Tab 内搜索:按标题/艺术家/专辑/流派过滤,四个子 Tab 共用过滤后的结果集
    let all = trimmed.length > 0
      ? raw.filter((t: Track) =>
      audioTagKey(t.title).includes(trimmed) ||
        audioTagKey(t.artistName).includes(trimmed) ||
        audioTagKey(t.albumName).includes(trimmed) ||
        audioTagKey(audioAlbumArtist(t)).includes(trimmed) ||
        t.genre.toLowerCase().includes(trimmed))
      : raw;
    // 仅显示收藏:按专辑键过滤,四个子 Tab 共用过滤后的结果集
    if (this.onlyFavs) {
      const favorites = MediaLibrary.getFavoriteAudioAlbumKeys();
      all = all.filter((t: Track) => favorites.has(audioAlbumKey(t)));
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

    // Store each heading with its albums so virtual reuse never reads an old index.
    const artistMap = new Map<string, ArtistGroup>();
    const artistAlbums = new Map<string, Map<string, AlbumMapEntry>>();
    const albumMap = new Map<string, AlbumMapEntry>();
    for (const t of all) {
      const aKey = audioTagKey(t.artistName);
      const alKey = audioAlbumKey(t);
      if (!artistMap.has(aKey)) {
        artistMap.set(aKey, new ArtistGroup(aKey, audioTag(t.artistName) || '未知艺术家'));
        artistAlbums.set(aKey, new Map<string, AlbumMapEntry>());
      }
      this.addAlbum(artistAlbums.get(aKey)!, alKey, t);
      this.addAlbum(albumMap, alKey, t);
    }
    const groups = Array.from(artistMap.values()).sort((a, b) => this.compareNames(a.name, b.name));
    for (const group of groups) {
      group.albums = this.albumCards(artistAlbums.get(group.key)!);
    }
    this.artistGroups = groups;
    this.albums = this.albumCards(albumMap);

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
    if (forceRebuild) {
      this.renderVersion++;
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
  @Param @Require vm: AudioBrowserVM = new AudioBrowserVM();
  @Param @Require controller: TabsController = new TabsController();
  @Local refreshing: boolean = false;
  @Local sheetAlbum: AlbumCard | null = null;
  @Local showSheet: boolean = false;
  @Local sheetAlbumFav: boolean = false;
  @Local showAlbumTracks: boolean = false;
  @Local duplicateAlbumTitles: Set<string> = new Set<string>();
  @Local importActive: boolean = false;
  @Local importCurrent: number = 0;
  @Local importTotal: number = 0;
  @Local fabBottom: number = AppDimens.floating_content_bottom_inset;
  @Local selectedTrackUris: string[] = [];
  @Param settingsVersion: number = 0;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  /** 各视图独立 Scroller，供主页 HdsNavDestination 同时绑定滚动联动。 */
  @Param artistScroller: Scroller = new Scroller();
  @Param albumListScroller: Scroller = new Scroller();
  @Param albumGridScroller: Scroller = new Scroller();
  @Param trackListScroller: Scroller = new Scroller();
  @Param trackGridScroller: Scroller = new Scroller();
  @Param genreListScroller: Scroller = new Scroller();
  @Param genreGridScroller: Scroller = new Scroller();
  /** "转到艺人"定位目标(配合 goToArtistVersion 触发 @Monitor)。 */
  @Param goToArtistName: string = '';
  /** "转到艺人"请求版本号:自增保证同名艺人连续定位也触发 @Monitor。 */
  @Param goToArtistVersion: number = 0;
  @Param selectionActionVersion: number = 0;
  @Param selectionActionType: string = '';
  /** 防止播放器首次初始化期间连续点击同一专辑，重复压入 AudioPlayer 页面。 */
  private audioPlayerOpening: boolean = false;
  private removingTrack: boolean = false;
  private albumSheetArtistId: string = '';
  private pendingAlbumPlayback: AlbumPlaybackRequest | null = null;
  @Event onSearchGlobal: () => void = () => {
  };
  @Event onSelectionChange: (active: boolean, count: number, allSelected: boolean) => void =
    (_active: boolean, _count: number, _allSelected: boolean): void => {};

  aboutToAppear(): void {
    // 从播放器返回后允许再次进入；成功 push 后则一直保持锁定到页面重新显示。
    this.audioPlayerOpening = false;
    this.vm.load();
  }

  @Monitor('settingsVersion')
  async onSettingsVersionChange(): Promise<void> {
    await this.vm.reloadSettings();
    this.pruneTrackSelection();
  }

  /** 收到 MainPage "转到艺人"派发:切到"艺术家"子 Tab 并滚动到对应歌手分组。 */
  @Monitor('goToArtistVersion')
  onGoToArtistVersion(): void {
    const artist = this.goToArtistName;
    if (artist.length === 0) {
      return;
    }
    this.exitTrackSelection();
    this.vm.saveTab(0);
    this.controller.changeIndex(0);
    const artistKey = audioTagKey(artist);
    const idx = this.vm.artistGroups.findIndex((group: ArtistGroup) => group.key === artistKey);
    if (idx >= 0) {
      setTimeout(() => {
        this.artistScroller.scrollToIndex(idx, true);
      }, 60);
    }
  }

  async doRefresh(): Promise<void> {
    if (this.hasTrackSelection()) {
      this.refreshing = false;
      return;
    }
    this.refreshing = true;
    await this.vm.reload();
    this.pruneTrackSelection();
    this.refreshing = false;
  }

  @Monitor('searchQuery')
  onSearchQueryChange(): void {
    this.vm.applySearch(this.searchQuery);
    this.pruneTrackSelection();
  }

  async pickAudioFiles(): Promise<void> {
    if (this.importActive) {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 200;
      opts.fileSuffixFilters = ['音频 (.mp3, .flac, .ogg, .wav, .aac, .m4a)|.mp3,.flac,.ogg,.wav,.aac,.m4a'];
      opts.mergeMode = picker.MergeTypeMode.AUDIO;
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await docPicker.select(opts);
      if (uris.length > 0) {
        this.importActive = true;
        this.importCurrent = 0;
        this.importTotal = uris.length;
        const result = await MediaLibrary.importAudioUris(uris, (current: number, total: number): void => {
          this.importCurrent = current;
          this.importTotal = total;
        });
        this.importActive = false;
        UiFeedback.showToast({
          message: $r('app.string.media_import_result', result.succeeded, result.failed, result.duplicates),
        });
        this.vm.syncData(true);
        this.pruneTrackSelection();
      }
    } catch (e) {
      if (this.importActive) {
        UiFeedback.showToast({ message: $r('app.string.media_import_error') });
      }
      hilog.warn(0x0001, 'VLC', '[VLC] pickAudioFiles: %{public}s', (e as Error).message ?? String(e));
    } finally {
      this.importActive = false;
    }
  }

  private hasTrackSelection(): boolean {
    return this.selectedTrackUris.length > 0;
  }

  private setTrackSelection(uris: string[]): void {
    this.selectedTrackUris = uris;
    this.onSelectionChange(uris.length > 0, uris.length, uris.length > 0 && uris.length === this.vm.tracks.length);
  }

  private exitTrackSelection(): void {
    if (this.hasTrackSelection()) {
      this.setTrackSelection([]);
    }
  }

  private pruneTrackSelection(): void {
    if (!this.hasTrackSelection()) {
      return;
    }
    const visible = new Set<string>(this.vm.tracks.map((track: Track) => track.uri));
    this.setTrackSelection(this.selectedTrackUris.filter((uri: string) => visible.has(uri)));
  }

  private toggleTrackSelection(uri: string): void {
    if (this.removingTrack || this.vm.tabIndex !== TRACKS_TAB) {
      return;
    }
    this.setTrackSelection(this.selectedTrackUris.includes(uri)
      ? this.selectedTrackUris.filter((item: string) => item !== uri)
      : this.selectedTrackUris.concat([uri]));
  }

  private changeAudioTab(index: number): void {
    if (index !== TRACKS_TAB) {
      this.exitTrackSelection();
    }
    this.vm.saveTab(index);
  }

  private activateTrack(track: Track, queue: Track[], scope: string): void {
    if (this.removingTrack) {
      return;
    }
    if (this.vm.tabIndex === TRACKS_TAB && this.hasTrackSelection()) {
      this.toggleTrackSelection(track.uri);
    } else {
      this.playTrack(track, queue, AudioPlayerRoute.trackPrefix(scope, track.uri));
    }
  }

  @Monitor('selectionActionVersion')
  onSelectionAction(): void {
    const action = this.selectionActionType;
    if (action === 'exit') {
      this.exitTrackSelection();
      return;
    }
    if (this.removingTrack || this.vm.tabIndex !== TRACKS_TAB || !this.hasTrackSelection()) {
      return;
    }
    this.pruneTrackSelection();
    if (!this.hasTrackSelection()) {
      return;
    }
    if (action === 'all') {
      this.setTrackSelection(this.selectedTrackUris.length === this.vm.tracks.length
        ? [] : this.vm.tracks.map((track: Track) => track.uri));
    } else if (action === 'play') {
      const selected = new Set<string>(this.selectedTrackUris);
      const tracks = this.vm.tracks.filter((track: Track) => selected.has(track.uri));
      this.exitTrackSelection();
      this.playAll(tracks);
    } else if (action === 'delete') {
      const uris = this.selectedTrackUris.slice();
      void this.confirmRemoveTracks(uris, $r('app.string.audio_remove_batch_confirm', uris.length), true);
    }
  }

  private confirmRemoveTrack(track: Track): Promise<void> {
    return this.confirmRemoveTracks([track.uri], $r('app.string.audio_remove_confirm', track.title), false);
  }

  private async confirmRemoveTracks(uris: string[], message: Resource, fromSelection: boolean): Promise<void> {
    if (this.removingTrack || uris.length === 0) {
      return;
    }
    this.removingTrack = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.audio_remove_from_library'),
        message: message,
        buttons: [
          { text: $r('app.string.cancel'), color: $r('app.color.list_title') },
          { text: $r('app.string.audio_remove_action'), color: $r('app.color.colorAccent') }
        ]
      }).catch(() => undefined);
      if (result?.index !== 1) {
        return;
      }
      const removed = await MediaLibrary.removeAudiosFromLibrary(uris);
      if (removed > 0) {
        this.vm.syncData(true);
        this.exitTrackSelection();
        UiFeedback.showToast({
          message: fromSelection ? $r('app.string.audio_remove_batch_success', removed) : $r('app.string.audio_remove_success')
        });
      } else {
        UiFeedback.showToast({ message: $r('app.string.audio_remove_failed') });
      }
    } catch (_error) {
      UiFeedback.showToast({ message: $r('app.string.audio_remove_failed') });
    } finally {
      this.removingTrack = false;
    }
  }

  private artistHeaderId(artistKey: string): string {
    return `audio-artist-header:${encodeURIComponent(artistKey)}`;
  }

  private albumArtistId(card: AlbumCard, mode: string): string {
    return `audio-album-artist:${mode}:${encodeURIComponent(card.key)}`;
  }

  private artistAlbumSourceId(card: AlbumCard): string {
    return this.artistHeaderId(audioTagKey(card.tracks[0]?.artistName ?? ''));
  }

  playAll(tracks: Track[]): void {
    if (tracks.length === 0) {
      return;
    }
    this.playTrack(tracks[0], tracks);
  }

  playTrack(t: Track, list: Track[], sourcePrefix: string = '', artistSourceId: string = ''): void {
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
    if (sourcePrefix.length > 0 || artistSourceId.length > 0) {
      const route: AudioPlayerRoute = new AudioPlayerRoute();
      route.fromMiniPlayer = false;
      route.sourcePrefix = sourcePrefix;
      route.artistSourceId = artistSourceId;
      route.uri = t.uri;
      route.title = t.title;
      route.artist = t.artistName;
      route.artworkPath = t.artworkPath;
      NavController.openAudioPlayer(this.getUIContext(), route);
    } else {
      NavController.push('AudioPlayer');
    }
    // MainPage 会常驻并仅切换可见性，返回时本组件不保证再次触发 aboutToAppear。
    // 因此锁只覆盖导航动画窗口，不能一直等生命周期回调释放。
    setTimeout(() => {
      this.audioPlayerOpening = false;
    }, 800);
  }

  /** 专辑卡片打开曲目明细；三点仍打开专辑操作。 */
  openAlbumSheet(card: AlbumCard, showTracks: boolean = false, artistSourceId: string = ''): void {
    if (this.showSheet || this.pendingAlbumPlayback !== null) {
      return;
    }
    const album = this.vm.albumDetails(card);
    this.sheetAlbum = album;
    const seen = new Set<string>();
    const duplicates = new Set<string>();
    for (const track of album.tracks) {
      const title = audioTagKey(track.title);
      if (seen.has(title)) {
        duplicates.add(title);
      }
      seen.add(title);
    }
    this.duplicateAlbumTitles = duplicates;
    this.sheetAlbumFav = MediaLibrary.getFavoriteAudioAlbumKeys().has(card.key);
    this.showAlbumTracks = showTracks;
    this.albumSheetArtistId = artistSourceId;
    this.showSheet = true;
  }

  private queueAlbumTrack(uri: string): void {
    const album = this.sheetAlbum;
    if (album === null || this.pendingAlbumPlayback !== null || this.audioPlayerOpening) {
      return;
    }
    const track = album.tracks.find((item: Track) => item.uri === uri);
    if (track === undefined) {
      return;
    }
    this.pendingAlbumPlayback = new AlbumPlaybackRequest(track, album.tracks, this.albumSheetArtistId);
    this.showSheet = false;
  }

  private onAlbumSheetDisappear(): void {
    const playback = this.pendingAlbumPlayback;
    this.pendingAlbumPlayback = null;
    this.showSheet = false;
    this.sheetAlbum = null;
    this.showAlbumTracks = false;
    this.duplicateAlbumTitles = new Set<string>();
    this.albumSheetArtistId = '';
    if (playback !== null) {
      // Wait until the sheet is gone so it cannot cover the player.
      this.playTrack(playback.track, playback.tracks, '', playback.artistSourceId);
    }
  }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        Column() {
          if (this.importActive) {
            Row() {
              Progress({ value: this.importCurrent, total: this.importTotal, type: ProgressType.Linear })
                .layoutWeight(1)
                .height(4)
                .color(AppColors.orange500)
            }
            .width('100%').padding(8)
          }
          Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: this.vm.tabIndex }) {
          // 艺术家(纵向分组列表:歌手名 → 曲目)
          TabContent() {
            Column() {
              if (this.searchMode) {
                this.searchGlobalButton()
              }
              if (this.vm.artistGroups.length === 0) {
                EmptyStateView(
                  { state: this.vm.emptyState, filterQuery: this.searchQuery, onPickFile: () => this.pickAudioFiles() })
                  .layoutWeight(1).width('100%')
              } else {
                this.artistList()
              }
            }.width('100%').height('100%')
          }

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
          }

          // 曲目
          TabContent() {
            Column() {
              if (this.searchMode && !this.hasTrackSelection()) {
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
          }

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
          }
          }
          .barHeight(0)
          .onChange((index: number) => this.changeAudioTab(index))
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('100%')
      }
      .pullToRefresh(!this.hasTrackSelection())
      .onRefreshing(() => this.doRefresh()).refreshOffset(64)
      .backgroundColor($r('app.color.background_default'))

      if (!this.hasTrackSelection()) {
        FloatingAddButton({ onPress: () => this.pickAudioFiles() })
          .position({ right: 16, bottom: this.fabBottom })
      }
    }
    .width('100%').height('100%')
    .clip(false)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const h: number = Number(newArea.height);
      this.fabBottom = Math.max(16, Math.min(AppDimens.floating_content_bottom_inset, h - 64));
    })
    .backgroundColor($r('app.color.background_default'))
    .bindSheet($$this.showSheet, this.albumSheet(), {
      radius: NATIVE_BOTTOM_SHEET_RADIUS,
      showClose: false,
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.bottom_sheet_background'),
      onDisappear: () => this.onAlbumSheetDisappear(),
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

  // ---- 艺术家列表(歌手 → 专辑网格) ----

  @Builder
  artistList() {
    List({ space: 0, scroller: this.artistScroller }) {
      Repeat(this.vm.artistGroups).each((group: RepeatItem<ArtistGroup>) => {
        ListItemGroup({ header: this.artistHeader(group) }) {
          ListItem() {
            if (this.vm.displayAsList) {
              Column() {
                Repeat(group.item.albums).each((card: RepeatItem<AlbumCard>) => {
                  this.albumRow(card, true)
                }).key((card: AlbumCard) => card.key)
              }
              .width('100%')
            } else {
              Grid() {
                Repeat(group.item.albums).each((card: RepeatItem<AlbumCard>) => {
                  GridItem() {
                    this.albumCard(card)
                  }
                }).key((card: AlbumCard) => card.key)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .width('100%')
            }
          }
        }
      }).key((group: ArtistGroup) => 'artist:' + group.key).virtualScroll()
    }
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  artistHeader(group: RepeatItem<ArtistGroup>) {
    Row() {
      Text(group.item.name).fontSize(16).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
        .geometryTransition(this.artistHeaderId(group.item.key), { follow: true })
        .transition(TransitionEffect.OPACITY)
      Text(` · ${group.item.albums.length} 专辑`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 6
    })
    .backgroundColor($r('app.color.card_background'))
  }

  /** 专辑方块卡片:上图(带三点) + 下文(专辑名/曲目数)。 */
  @Builder
  albumCard(row: RepeatItem<AlbumCard>) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(row.item.artwork.length > 0 ? row.item.artwork : $r('app.media.ic_album_big'))
          .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(6)
        this.albumCoverActions(row)
      }
      .width('100%')

      Text(row.item.name)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
      Text(`${row.item.trackCount} 首`).fontSize(12).fontColor($r('app.color.list_subtitle'))
    }
    .width('100%')
    .onClick(() => {
      this.openAlbumSheet(row.item, true, this.artistAlbumSourceId(row.item));
    })
  }

  @Builder
  albumCoverActions(row: RepeatItem<AlbumCard>) {
    Button({ type: ButtonType.Circle }) {
      this.audioMoreIcon(true)
    }
    .width(AUDIO_MORE_BUTTON_SIZE)
    .height(AUDIO_MORE_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .margin({ top: AUDIO_COVER_MORE_INSET, right: AUDIO_COVER_MORE_INSET })
    .accessibilityText($r('app.string.audio_item_actions', row.item.name))
    .onClick(() => this.openAlbumSheet(row.item))
  }

  // ---- 专辑网格 ----

  @Builder
  albumList() {
    List({ scroller: this.albumListScroller }) {
      Repeat(this.vm.albums).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
        ListItem() {
          this.albumRow(cardRepeatItem, false)
        }
      }).key((card: AlbumCard) => card.key).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 76,
      endMargin: 8
    })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .alignListItem(ListItemAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder
  albumRow(row: RepeatItem<AlbumCard>, fromArtist: boolean) {
    Row() {
      Image(row.item.artwork.length > 0 ? row.item.artwork : $r('app.media.ic_album_big'))
        .width(52)
        .height(52)
        .objectFit(ImageFit.Cover)
        .borderRadius(6)
        .margin({ right: 12 })
      Column() {
        Text(row.item.name)
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(`${row.item.trackCount} 首 · `)
            .fontSize(13)
            .fontColor($r('app.color.list_subtitle'))
            .flexShrink(0)
          Text(row.item.artist)
            .fontSize(13)
            .fontColor($r('app.color.list_subtitle'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            // 艺术家页复用分组标题作为唯一源，不在每张专辑重复注册同一歌手 ID。
            .geometryTransition(fromArtist ? '' : this.albumArtistId(row.item, 'list'), { follow: true })
            .transition(TransitionEffect.OPACITY)
        }
        .width('100%')
        .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.ic_more'))
        .width(22)
        .height(22)
        .fillColor($r('app.color.list_title'))
        .margin({ left: 8 })
        .onClick(() => this.openAlbumSheet(row.item))
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openAlbumSheet(row.item, true,
      fromArtist ? this.artistAlbumSourceId(row.item) : this.albumArtistId(row.item, 'list')))
  }

  @Builder
  albumGrid() {
    Grid(this.albumGridScroller) {
      Repeat(this.vm.albums).each((cardRepeatItem: RepeatItem<AlbumCard>) => {
        GridItem() {
          Column() {
            // 封面区域
            Stack({ alignContent: Alignment.TopEnd }) {
              Image(cardRepeatItem.item.artwork.length > 0 ? cardRepeatItem.item.artwork : $r('app.media.ic_album_big'))
                .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius(8)
              this.albumCoverActions(cardRepeatItem)
            }
            .width('100%')

            Text(cardRepeatItem.item.name)
              .fontSize(14)
              .fontColor($r('app.color.list_title'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
            Row() {
              Text(`${cardRepeatItem.item.trackCount} 首 · `)
                .fontSize(12)
                .fontColor($r('app.color.list_subtitle'))
                .flexShrink(0)
              Text(cardRepeatItem.item.artist)
                .fontSize(12)
                .fontColor($r('app.color.list_subtitle'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
                .geometryTransition(this.albumArtistId(cardRepeatItem.item, 'grid'), { follow: true })
                .transition(TransitionEffect.OPACITY)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%').padding(6)
          .onClick(() => this.openAlbumSheet(cardRepeatItem.item, true, this.albumArtistId(cardRepeatItem.item, 'grid')))
        }
      }).key((card: AlbumCard) => card.key).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(12)
    .padding({ left: 8, right: 8, top: 8 })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .height('100%')
  }

  // ---- 曲目列表 ----

  @Builder
  trackList() {
    List({ scroller: this.trackListScroller }) {
      Repeat(this.vm.tracks).each((tRepeatItem: RepeatItem<Track>) => {
        ListItem() {
          this.trackRow(tRepeatItem, () => this.vm.tracks, () => 'tracks')
        }
      }).key((t: Track) => t.uri).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 56,
      endMargin: 8
    })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  @Builder
  trackGrid() {
    // Use ordered lanes: a sorted import inserts items without leaving old
    // GridItem positions behind. The full RepeatItem keeps recycled cards live.
    List({ scroller: this.trackGridScroller, space: 12 }) {
      Repeat(this.vm.tracks).each((trackRepeatItem: RepeatItem<Track>) => {
        ListItem() {
          this.trackCard(trackRepeatItem)
        }
      }).key((track: Track) => track.uri).virtualScroll()
    }
    .lanes(2, 8)
    .padding({ left: 8, right: 8, top: 8 })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .width('100%')
    .height('100%')
  }

  @Builder
  trackCard(row: RepeatItem<Track>) {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.trackCardContent(row)
      Row() {
        if (this.hasTrackSelection()) {
          this.trackSelectionMark(row, true)
        } else {
          this.trackActions(row, true)
        }
      }
      .margin({ top: AUDIO_COVER_MORE_INSET, right: AUDIO_COVER_MORE_INSET })
    }
    .width('100%')
    .padding(6)
  }

  @Builder
  trackCardContent(row: RepeatItem<Track>) {
    Column() {
      Image(row.item.artworkPath.length > 0 ? row.item.artworkPath : $r('app.media.ic_song'))
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .geometryTransition(`${AudioPlayerRoute.trackPrefix('grid', row.item.uri)}-cover`, { follow: true })
        .transition(TransitionEffect.OPACITY)
      Text(row.item.title)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
        .geometryTransition(`${AudioPlayerRoute.trackPrefix('grid', row.item.uri)}-title`, { follow: true })
        .transition(TransitionEffect.OPACITY)
      Text(row.item.artistName.length > 0 ? row.item.artistName : '未知艺术家')
        .fontSize(12)
        .fontColor($r('app.color.list_subtitle'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .geometryTransition(`${AudioPlayerRoute.trackPrefix('grid', row.item.uri)}-artist`, { follow: true })
        .transition(TransitionEffect.OPACITY)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.activateTrack(row.item, this.vm.tracks, 'grid'))
    .gesture(LongPressGesture().onAction(() => this.toggleTrackSelection(row.item.uri)))
  }

  @Builder
  trackSelectionMark(row: RepeatItem<Track>, onCover: boolean) {
    Button({ type: ButtonType.Normal }) {
      if (this.selectedTrackUris.includes(row.item.uri)) {
        Image($r('app.media.ic_video_grid_check'))
          .width(onCover ? 16 : 24)
          .height(onCover ? 16 : 24)
          .fillColor($r('app.color.orange500'))
      }
    }
    .width(AUDIO_MORE_BUTTON_SIZE)
    .height(AUDIO_MORE_BUTTON_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.selectedTrackUris.includes(row.item.uri)
      ? $r('app.string.audio_unselect_track', row.item.title) : $r('app.string.audio_select_track', row.item.title))
    .onClick(() => this.toggleTrackSelection(row.item.uri))
  }

  @Builder
  audioMoreIcon(onCover: boolean) {
    Image($r('app.media.ic_more'))
      .width(20)
      .height(20)
      .fillColor(onCover ? Color.White : $r('app.color.list_subtitle'))
  }

  @Builder
  trackActions(row: RepeatItem<Track>, onCover: boolean) {
    Button({ type: ButtonType.Circle }) {
      this.audioMoreIcon(onCover)
    }
    .width(AUDIO_MORE_BUTTON_SIZE)
    .height(AUDIO_MORE_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText($r('app.string.audio_item_actions', row.item.title))
    .bindMenu(this.trackMenu(row), { placement: Placement.BottomRight })
  }

  private trackMenu(row: RepeatItem<Track>): MenuElement[] {
    const items: MenuElement[] = [];
    if (this.vm.tabIndex === TRACKS_TAB) {
      const selectIcon = new SymbolGlyphModifier($r('sys.symbol.checkmark_square_fill'));
      selectIcon.fontColor([$r('sys.color.icon_primary')]);
      items.push({
        value: $r('app.string.audio_multi_select'),
        symbolIcon: selectIcon,
        action: () => { this.toggleTrackSelection(row.item.uri); }
      });
    }
    const removeIcon = new SymbolGlyphModifier($r('sys.symbol.trash'));
    removeIcon.fontColor([$r('sys.color.icon_primary')]);
    items.push({
      value: $r('app.string.audio_remove_from_library'),
      symbolIcon: removeIcon,
      action: () => { this.confirmRemoveTrack(row.item); }
    });
    return items;
  }

  // ---- 流派列表 ----

  @Builder
  genreList() {
    List({ scroller: this.genreListScroller }) {
      Repeat(this.vm.genres).each((tracksRepeatItem: RepeatItem<Track[]>) => {
        ListItemGroup({ header: this.genreHeader(this.vm.genreNames[tracksRepeatItem.index], tracksRepeatItem.item.length) }) {
          Repeat(tracksRepeatItem.item).each((tRepeatItem: RepeatItem<Track>) => {
            ListItem() {
              this.trackRow(tRepeatItem, () => tracksRepeatItem.item,
                () => `genre-${this.vm.genreNames[tracksRepeatItem.index]}`)
            }
          }).key((t: Track) =>
          `genre_${this.vm.renderVersion}_${this.vm.genreNames[tracksRepeatItem.index]}_${t.uri}`)
        }
      }).key((_: Track[], idx: number) =>
      `genre_list_${this.vm.renderVersion}_${this.vm.genreNames[idx]}`).virtualScroll()
    }
    .divider({
      strokeWidth: 0.5,
      color: $r('app.color.divider'),
      startMargin: 16,
      endMargin: 8
    })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
    .alignListItem(ListItemAlign.Start).width('100%').height('100%')
  }

  genreArtwork(tracks: Track[]): ResourceStr {
    const artworkTrack: Track | undefined = tracks.find((track: Track) => track.artworkPath.length > 0);
    return artworkTrack ? artworkTrack.artworkPath : $r('app.media.ic_album_big');
  }

  @Builder
  genreGrid() {
    Grid(this.genreGridScroller) {
      Repeat(this.vm.genres).each((tracksRepeatItem: RepeatItem<Track[]>) => {
        GridItem() {
          this.genreCard(this.vm.genreNames[tracksRepeatItem.index], tracksRepeatItem.item)
        }
      }).key((_: Track[], index: number) =>
      `genre_grid_${this.vm.renderVersion}_${this.vm.genreNames[index]}`).virtualScroll()
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(12)
    .padding({ left: 8, right: 8, top: 8 })
    .contentEndOffset(AppDimens.floating_content_bottom_inset)
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
  trackRow(row: RepeatItem<Track>, queue: () => Track[], scope: () => string) {
    Row() {
      this.trackRowContent(row, queue, scope)
      if (this.vm.tabIndex === TRACKS_TAB && this.hasTrackSelection()) {
        this.trackSelectionMark(row, false)
      } else {
        this.trackActions(row, false)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 8, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.vm.tabIndex === TRACKS_TAB && this.selectedTrackUris.includes(row.item.uri)
      ? '#20FF8800' : Color.Transparent)
  }

  @Builder
  trackRowContent(row: RepeatItem<Track>, queue: () => Track[], scope: () => string) {
    Row() {
      Image(row.item.artworkPath.length > 0 ? row.item.artworkPath : $r('app.media.ic_song'))
        .width(36)
        .height(36)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .margin({ right: 12 })
        .geometryTransition(`${AudioPlayerRoute.trackPrefix(scope(), row.item.uri)}-cover`, { follow: true })
        .transition(TransitionEffect.OPACITY)
      Column() {
        Text(row.item.title)
          .fontSize(16)
          .fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .geometryTransition(`${AudioPlayerRoute.trackPrefix(scope(), row.item.uri)}-title`, { follow: true })
          .transition(TransitionEffect.OPACITY)
        if (row.item.artistName.length > 0) {
          Text(row.item.artistName).fontSize(13).fontColor($r('app.color.list_subtitle')).margin({ top: 2 })
            .geometryTransition(`${AudioPlayerRoute.trackPrefix(scope(), row.item.uri)}-artist`, { follow: true })
            .transition(TransitionEffect.OPACITY)
        } else {
          Text(this.fileNameFromUri(row.item.filePath))
            .fontSize(11)
            .fontColor($r('app.color.font_light'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (row.item.length > 0) {
        Text(formatDuration(row.item.length)).fontSize(11).fontColor($r('app.color.font_light')).margin({ left: 8 })
      }
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.activateTrack(row.item, queue(), scope()))
    .gesture(LongPressGesture().onAction(() => this.toggleTrackSelection(row.item.uri)))
  }

  @Builder
  albumSheet() {
    Column() {
      if (this.sheetAlbum !== null) {
        this.albumSheetContent()
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.bottom_sheet_background'))
  }

  @Builder
  albumSheetContent() {
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
        const first = this.sheetAlbum?.tracks[0];
        if (first !== undefined) {
          this.queueAlbumTrack(first.uri);
        }
      })

      if (this.showAlbumTracks) {
        this.albumTrackList()
      } else {
        this.albumActions()
      }

      Blank().height(24)
    }
    .width('100%')
  }

  @Builder
  albumActions() {
    Column() {
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
        const key = this.sheetAlbum!.key;
        MediaLibrary.toggleAudioAlbumFavorite(key).then((fav: boolean) => {
          if (this.sheetAlbum?.key === key) {
            this.sheetAlbumFav = fav;
          }
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

    }
    .width('100%')
  }

  @Builder
  albumTrackList() {
    Column() {
      Text($r('app.string.audio_album_tracks_count', this.sheetAlbum!.trackCount))
        .fontSize(13)
        .fontColor($r('app.color.list_subtitle'))
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 4 })
      List() {
        Repeat(this.sheetAlbum!.tracks).each((row: RepeatItem<Track>) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(String(row.index + 1))
                .width(28)
                .fontSize(13)
                .fontColor($r('app.color.list_subtitle'))
              Column({ space: 3 }) {
                Text(row.item.title)
                  .fontSize(15)
                  .fontColor($r('app.color.list_title'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.albumTrackSubtitle(row.item))
                  .fontSize(12)
                  .fontColor($r('app.color.list_subtitle'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (row.item.length > 0) {
                Text(formatDuration(row.item.length))
                  .fontSize(12)
                  .fontColor($r('app.color.list_subtitle'))
              }
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.queueAlbumTrack(row.item.uri))
          }
        }).key((track: Track) => track.uri).virtualScroll()
      }
      .width('100%')
      .height(Math.min(280, this.sheetAlbum!.tracks.length * 56))
    }
    .width('100%')
  }

  private albumTrackSubtitle(track: Track): string {
    const artist = audioTag(track.artistName);
    if (artist.length > 0 && !this.duplicateAlbumTitles.has(audioTagKey(track.title))) {
      return artist;
    }
    const rawName = this.fileNameFromUri(track.filePath || track.uri).split(/[?#]/)[0];
    try {
      return decodeURIComponent(rawName);
    } catch (_error) {
      return rawName;
    }
  }

  // ---- 专辑操作半模态 ----

  private fileNameFromUri(uri: string): string {
    const ls = Math.max(uri.lastIndexOf('/'), uri.lastIndexOf('\\'));
    return ls >= 0 ? uri.slice(ls + 1) : uri;
  }
}
