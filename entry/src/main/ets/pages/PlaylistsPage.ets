import { UiFeedback } from '../common/utils/UiFeedback';
import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { Settings } from '../common/data/Settings';
import { EmptyLoadingState, MediaWrapper, Track } from '../common/models/MediaModels';
import { EmptyStateView } from '../common/components/EmptyStateView';
import { PlaylistDialog } from './PlaylistDialog';
import { RenameDialog } from './RenameDialog';
import { emitter } from '@kit.BasicServicesKit';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { VideoParam, VideoPlayItem } from './VideoPlayerPage';
import { HeaderMediaListParam } from './HeaderMediaListActivityPage';
import { RouteName } from '../common/constants/AppConstants';

// ---- 数据模型 ----

@ObservedV2
class PlaylistCard {
  @Trace id: number;
  @Trace name: string;
  @Trace trackCount: number;
  @Trace artwork: string;

  constructor(id: number, name: string, trackCount: number, artwork: string) {
    this.id = id;
    this.name = name;
    this.trackCount = trackCount;
    this.artwork = artwork;
  }
}

/** 半模态类型:一个组件只能绑定一个 bindSheet,内部按模式切换内容。 */
type SheetMode = 'none' | 'create' | 'ctxmenu' | 'rename';

// ---- ViewModel ----

@ObservedV2
class PlaylistsVM {
  @Trace playlists: PlaylistCard[] = [];
  @Trace loading: boolean = true;

  async load(forceScan: boolean = false): Promise<void> {
    this.loading = true;
    // 每次加载都强制从 Settings 刷新播放列表数据
    await MediaLibrary.reloadPlaylistCache();
    // 尊重「自动重新扫描」开关:autoRescan 关闭时不自动扫描。
    // forceScan=true 用于下拉刷新等用户主动路径,绕过此门控(对齐 vm.refresh/vm.reload)。
    const autoRescan = forceScan || await Settings.getBoolean(Settings.KEY_MEDIALIBRARY_AUTO_RESCAN, true);
    if (autoRescan) {
      await MediaLibrary.scan();
    }
    this.rebuildCards();
    this.loading = false;
  }

  rebuildCards(): void {
    const stored = MediaLibrary.getStoredPlaylists();
    const audios = MediaLibrary.getAudios();
    const videos = MediaLibrary.getVideos();
    const next: PlaylistCard[] = stored.map((s: StoredPlaylist) => {
      // 直接用存储的 URI 数量,不依赖媒体库扫描结果。
      const count = s.uriList.length;
      // 封面优先用音频专辑图,其次视频缩略图。
      const audioArt = audios.find((t: Track) => s.uriList.includes(t.uri) && t.artworkPath.length > 0);
      const videoArt = videos.find((v: MediaWrapper) => s.uriList.includes(v.uri) && v.artworkUrl.length > 0);
      const art = audioArt ? audioArt.artworkPath : (videoArt ? videoArt.artworkUrl : '');
      return new PlaylistCard(s.id, s.name, count, art);
    });
    // 用现有 card 实例 + 字段级 @Trace 更新(而不是整体替换数组),
    // 确保 ForEach 即使 key(id) 相同也能感知 trackCount/name/artwork 字段变化。
    const oldById = new Map<number, PlaylistCard>(this.playlists.map((c) => [c.id, c]));
    const merged: PlaylistCard[] = next.map((c) => {
      const existing = oldById.get(c.id);
      if (existing) {
        existing.name = c.name;
        existing.trackCount = c.trackCount;
        existing.artwork = c.artwork;
        return existing;
      }
      return c;
    });
    // 任何 id 缺失(被删除)时整体替换一次以清掉,新增的也通过 next 带入。
    const sameIds = merged.length === this.playlists.length
      && merged.every((c, i) => c.id === this.playlists[i].id);
    if (!sameIds) {
      this.playlists = merged;
    }
  }

  applySearch(_q: string): void {
    this.rebuildCards();
  }

  async rename(id: number, newName: string): Promise<void> {
    await MediaLibrary.renamePlaylist(id, newName);
    this.rebuildCards();
  }

  async deletePlaylist(id: number): Promise<void> {
    await MediaLibrary.deletePlaylist(id);
    this.rebuildCards();
  }
}

/** 持久化用的播放列表结构（与 MediaLibrary 保持一致）。 */
interface StoredPlaylist {
  id: number;
  name: string;
  uriList: string[];
}

// ---- 页面 ----

@ComponentV2
export struct PlaylistsPage {
  @Param contentScroller: Scroller = new Scroller();
  @Local vm: PlaylistsVM = new PlaylistsVM();
  @Local refreshing: boolean = false;
  /** 统一半模态状态:一个组件只能有一个 bindSheet。 */
  @Local sheetMode: SheetMode = 'none';
  @Local showSheet: boolean = false;
  @Local ctxCard: PlaylistCard | null = null;
  @Param searchMode: boolean = false;
  @Param searchQuery: string = '';
  @Param currentTab: string = '';
  @Param playlistsVersion: number = 0;
  @Event onSearchGlobal: () => void = () => {
  };

  async aboutToAppear(): Promise<void> {
    await MediaLibrary.initPlaylistCache();
    await this.vm.load();
    this.playlistsChangedHandler = (): void => {
      void this.vm.load();
    };
    emitter.on(MediaLibrary.EVENT_PLAYLISTS_CHANGED, this.playlistsChangedHandler);
  }

  aboutToDisappear(): void {
    emitter.off(MediaLibrary.EVENT_PLAYLISTS_CHANGED, this.playlistsChangedHandler);
  }

  @Monitor('currentTab')
  onTabChange(): void {
    if (this.currentTab === 'playlists') {
      void this.vm.load();
    }
  }

  @Monitor('playlistsVersion')
  onPlaylistsVersionChange(): void {
    void this.vm.load();
  }

  @Monitor('searchQuery')
  onSearchQueryChange(): void {
    this.vm.applySearch(this.searchQuery);
  }

  async doRefresh(): Promise<void> {
    this.refreshing = true;
    // 下拉刷新:用户主动路径,绕过 autoRescan 门控,强制重新扫描。
    await this.vm.load(true);
    this.refreshing = false;
  }

  /** 点击播放列表卡片 → 进入曲目详情页(HeaderMediaListActivityPage)。 */
  openPlaylist(card: PlaylistCard): void {
    const plParam = new HeaderMediaListParam();
    plParam.title = card.name;
    plParam.description = `${card.trackCount} 首`;
    plParam.isPlaylist = true;
    plParam.playlistId = card.id;
    NavController.push(RouteName.HeaderMediaList, plParam);
  }

  playAll(card: PlaylistCard): void {
    const uriList = MediaLibrary.getPlaylistUris(card.id);
    const audios = MediaLibrary.getAudios();
    const videos = MediaLibrary.getVideos();

    // 优先匹配音频
    const audioTracks: Track[] = audios.filter((t: Track) => uriList.includes(t.uri));
    if (audioTracks.length > 0) {
      const queue = audioTracks.map((t: Track) =>
      new QueueItem(t.id, t.title, t.uri, t.artistName, t.albumName, t.artworkPath));
      PlaybackService.playList(queue, 0, true);
      NavController.push('AudioPlayer');
      return;
    }

    // 无音频则尝试匹配视频
    const videoTracks: MediaWrapper[] = videos.filter((v: MediaWrapper) => uriList.includes(v.uri));
    if (videoTracks.length > 0) {
      const list: VideoPlayItem[] = [];
      for (const v of videoTracks) {
        const item: VideoPlayItem = { uri: v.uri, title: v.title };
        list.push(item);
      }
      const param: VideoParam = {
        uri: videoTracks[0].uri,
        title: videoTracks[0].title,
        list: list,
        index: 0
      };
      NavController.push('VideoPlayer', param);
      return;
    }

    UiFeedback.showToast({ message: '播放列表为空' });
  }

  openCreate(): void {
    this.sheetMode = 'create';
    this.showSheet = true;
  }

  openCtxMenu(card: PlaylistCard): void {
    this.ctxCard = card;
    this.sheetMode = 'ctxmenu';
    this.showSheet = true;
  }

  openRename(): void {
    this.sheetMode = 'rename';
    this.showSheet = true;
  }

  closeSheet(): void {
    this.showSheet = false;
  }

  /** Sheet 退出动画结束后再清理内容，避免只剩遮罩层。 */
  finishCloseSheet(): void {
    this.showSheet = false;
    this.sheetMode = 'none';
    this.ctxCard = null;
  }

  build() {
    Stack() {
      Column() {
        if (this.searchMode) {
          this.searchGlobalButton()
        }
        Refresh({ refreshing: $$this.refreshing }) {
          if (this.vm.playlists.length === 0) {
            if (this.searchQuery.trim().length > 0) {
              EmptyStateView({ state: EmptyLoadingState.EMPTY_SEARCH, filterQuery: this.searchQuery })
            } else {
              Column() {
                Image($r('app.media.ic_playlist_big')).width(96).height(96).fillColor($r('app.color.grey800'))
                Text($r('app.string.noplaylist'))
                  .fontSize(15)
                  .fontColor($r('app.color.list_subtitle'))
                  .margin({ top: 12 })
                Button($r('app.string.create_new_playlist'))
                  .type(ButtonType.Normal)
                  .borderRadius(4)
                  .backgroundColor('#FF8800')
                  .fontColor($r('app.color.colorOnPrimary'))
                  .fontSize(14)
                  .margin({ top: 16 })
                  .onClick(() => {
                    this.openCreate();
                  })
              }
              .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            }
          } else {
            Grid(this.contentScroller) {
              Repeat(this.vm.playlists).each((cardRepeatItem: RepeatItem<PlaylistCard>) => {
                GridItem() {
                  Column() {
                    Stack({ alignContent: Alignment.TopEnd }) {
                      Image(cardRepeatItem.item.artwork.length > 0 ? cardRepeatItem.item.artwork : $r('app.media.ic_playlist_big'))
                        .width('100%')
                        .aspectRatio(1)
                        .objectFit(ImageFit.Cover)
                        .borderRadius({ topLeft: 6, topRight: 6 })
                      Image($r('app.media.ic_more'))
                        .width(20)
                        .height(20)
                        .fillColor($r('app.color.list_title'))
                        .margin(4)
                        .onClick(() => {
                          this.openCtxMenu(cardRepeatItem.item);
                        })
                    }
                    .width('100%')

                    Text(cardRepeatItem.item.name)
                      .fontSize(14)
                      .fontColor($r('app.color.list_title'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 6, left: 8, right: 8 })
                    Text(`${cardRepeatItem.item.trackCount} 首`).fontSize(12).fontColor($r('app.color.list_subtitle'))
                      .margin({ bottom: 6 })
                  }
                  .width('100%')
                  .borderRadius(6)
                  .backgroundColor($r('app.color.card_background'))
                  .border({ width: 0.5, color: $r('app.color.card_border') })
                  .shadow({ radius: 4, color: '#1A000000', offsetY: 2 })
                  .onClick(() => {
                    this.openPlaylist(cardRepeatItem.item);
                  })
                }
              }).key((card: PlaylistCard) => `pl${card.id}`).virtualScroll()
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(12)
            .padding({
              left: 12,
              right: 12,
              top: 8,
              bottom: 80
            })
            .width('100%')
            .height('100%')
          }
        }
        .onRefreshing(() => this.doRefresh())
        .refreshOffset(64)
        .backgroundColor($r('app.color.background_default'))
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%').height('100%')

      // FAB
      Button() {
        Image($r('app.media.ic_add')).width(22).height(22).fillColor($r('app.color.colorOnPrimary'))
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#FF8800')
      .shadow({ radius: 8, color: '#44000000', offsetY: 4 })
      .position({ right: 16, bottom: 152 })
      .onClick(() => {
        this.openCreate();
      })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    // 唯一的 bindSheet,内部按 sheetMode 切换内容
    .bindSheet(this.showSheet, this.unifiedSheet(), {
      height: SheetSize.FIT_CONTENT, dragBar: true,
      backgroundColor: $r('app.color.bottom_sheet_background'),
      onDisappear: () => {
        this.finishCloseSheet();
      },
    })
  }

  /** 搜索态:跳转全局搜索页的矩形按钮(橙字灰边居中)。 */
  @Builder
  searchGlobalButton() {
    Row() {
      Button($r('app.string.search_global'))
        .type(ButtonType.Normal)
        .backgroundColor($r('app.color.background_default'))
        .fontColor('#FF8800')
        .borderRadius(4)
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
    .borderRadius(4)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  /** 统一半模态:根据 sheetMode 渲染不同内容。 */
  @Builder
  unifiedSheet() {
    if (this.sheetMode === 'create') {
      PlaylistDialog({
        onClose: () => {
          this.closeSheet();
        },
        onCreate: async (name: string) => {
          await MediaLibrary.createPlaylist(name);
          await this.vm.load();
        },
      }).width('100%')
    } else if (this.sheetMode === 'ctxmenu') {
      this.ctxMenuContent()
    } else if (this.sheetMode === 'rename') {
      RenameDialog({
        currentName: this.ctxCard?.name ?? '',
        onConfirm: async (newName: string) => {
          if (this.ctxCard && newName.trim().length > 0) {
            await this.vm.rename(this.ctxCard.id, newName.trim());
          }
          this.closeSheet();
        },
        onCancel: () => {
          this.closeSheet();
        },
      }).width('100%')
    }
  }

  /** 上下文菜单内容(对齐 Android CTX_RENAME / CTX_DELETE / CTX_PLAY_ALL)。 */
  @Builder
  ctxMenuContent() {
    Column() {
      Row() {
        Image($r('app.media.ic_playlist_big'))
          .width(40).height(40).objectFit(ImageFit.Contain).margin({ right: 12 })
        Text(this.ctxCard?.name ?? '')
          .fontSize(16).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium).maxLines(1)
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
        if (this.ctxCard) {
          this.playAll(this.ctxCard);
        }
        this.closeSheet();
      })

      // 重命名
      Row() {
        Image($r('app.media.ic_edit')).width(24).height(24).fillColor($r('app.color.list_title')).margin({ right: 12 })
        Text($r('app.string.rename')).fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 14,
        bottom: 14
      })
      .onClick(() => {
        this.openRename();
      })

      // 删除
      Row() {
        Image($r('app.media.ic_playlist_delete')).width(24).height(24).fillColor('#FF8800').margin({ right: 12 })
        Text($r('app.string.delete')).fontSize(15).fontColor('#FF8800')
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 14,
        bottom: 14
      })
      .onClick(async () => {
        if (this.ctxCard) {
          await this.vm.deletePlaylist(this.ctxCard.id);
          UiFeedback.showToast({ message: $r('app.string.stream_deleted') });
        }
        this.closeSheet();
      })

      Blank().height(24)
    }
    .width('100%').backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  /** 持有 emitter 回调引用,aboutToDisappear 时按引用解绑。 */
  private playlistsChangedHandler: (data: emitter.EventData) => void = () => {
  };
}
