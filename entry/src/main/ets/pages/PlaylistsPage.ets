import { NavController } from '../common/data/NavController';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { Track } from '../common/models/MediaModels';
import { PlaylistDialog } from './PlaylistDialog';
import { RenameDialog } from './RenameDialog';
import { Settings } from '../common/data/Settings';
import { promptAction } from '@kit.ArkUI';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';

// ---- 数据模型 ----

class PlaylistCard {
  id: number;
  name: string;
  trackCount: number;
  artwork: string;

  constructor(id: number, name: string, trackCount: number, artwork: string) {
    this.id = id;
    this.name = name;
    this.trackCount = trackCount;
    this.artwork = artwork;
  }
}

interface StoredPlaylist {
  id: number;
  name: string;
  uriList: string[];
}

const KEY_PLAYLISTS = 'vlc_playlists';

/** 半模态类型:一个组件只能绑定一个 bindSheet,内部按模式切换内容。 */
type SheetMode = 'none' | 'create' | 'ctxmenu' | 'rename';

// ---- ViewModel ----

@ObservedV2
class PlaylistsVM {
  @Trace playlists: PlaylistCard[] = [];
  @Trace loading: boolean = true;

  async load(): Promise<void> {
    this.loading = true;
    await MediaLibrary.scan();
    this.rebuildCards();
    this.loading = false;
  }

  rebuildCards(): void {
    const stored = PlaylistsVM.loadStored();
    const audios = MediaLibrary.getAudios();
    const uriSet = new Set(audios.map((t: Track) => t.uri));
    this.playlists = stored.map((s: StoredPlaylist) => {
      const availableUris = s.uriList.filter((u: string) => uriSet.has(u));
      const count = availableUris.length;
      const art = audios.find((t: Track) => s.uriList.includes(t.uri) && t.artworkPath.length > 0);
      return new PlaylistCard(s.id, s.name, count, art ? art.artworkPath : '');
    });
  }

  async rename(id: number, newName: string): Promise<void> {
    const stored = PlaylistsVM.loadStored();
    const pl = stored.find((s: StoredPlaylist) => s.id === id);
    if (pl) {
      pl.name = newName;
      await PlaylistsVM.saveStored(stored);
      this.rebuildCards();
    }
  }

  async deletePlaylist(id: number): Promise<void> {
    const stored = PlaylistsVM.loadStored().filter((s: StoredPlaylist) => s.id !== id);
    await PlaylistsVM.saveStored(stored);
    this.rebuildCards();
  }

  static async create(name: string): Promise<void> {
    const stored = PlaylistsVM.loadStored();
    const id = Date.now();
    stored.push({ id: id, name: name, uriList: [] });
    await PlaylistsVM.saveStored(stored);
  }

  static async addTrack(playlistId: number, uri: string): Promise<void> {
    const stored = PlaylistsVM.loadStored();
    const pl = stored.find((s: StoredPlaylist) => s.id === playlistId);
    if (pl && !pl.uriList.includes(uri)) {
      pl.uriList.push(uri);
      await PlaylistsVM.saveStored(stored);
    }
  }

  static getTrackUris(playlistId: number): string[] {
    const stored = PlaylistsVM.loadStored();
    const pl = stored.find((s: StoredPlaylist) => s.id === playlistId);
    return pl ? pl.uriList : [];
  }

  private static loadStored(): StoredPlaylist[] {
    return PlaylistsVM.cachedStored;
  }

  private static async saveStored(stored: StoredPlaylist[]): Promise<void> {
    PlaylistsVM.cachedStored = stored;
    await Settings.put(KEY_PLAYLISTS, JSON.stringify(stored));
  }

  private static cachedStored: StoredPlaylist[] = [];

  static async initCache(): Promise<void> {
    const raw = await Settings.getString(KEY_PLAYLISTS, '[]');
    try { PlaylistsVM.cachedStored = JSON.parse(raw) as StoredPlaylist[]; } catch (e) { PlaylistsVM.cachedStored = []; }
  }
}

// ---- 页面 ----

@ComponentV2
export struct PlaylistsPage {
  @Local vm: PlaylistsVM = new PlaylistsVM();
  @Local refreshing: boolean = false;
  /** 统一半模态状态:一个组件只能有一个 bindSheet。 */
  @Local sheetMode: SheetMode = 'none';
  @Local showSheet: boolean = false;
  @Local ctxCard: PlaylistCard | null = null;

  async aboutToAppear(): Promise<void> {
    await PlaylistsVM.initCache();
    await this.vm.load();
  }

  async doRefresh(): Promise<void> {
    this.refreshing = true;
    await this.vm.load();
    this.refreshing = false;
  }

  playAll(card: PlaylistCard): void {
    const uriList = PlaylistsVM.getTrackUris(card.id);
    const audios = MediaLibrary.getAudios();
    const tracks = audios.filter((t: Track) => uriList.includes(t.uri));
    if (tracks.length > 0) {
      const queue = tracks.map((t: Track) =>
        new QueueItem(t.id, t.title, t.uri, t.artistName, t.albumName, t.artworkPath));
      PlaybackService.playList(queue, 0, true);
      NavController.push('AudioPlayer');
    } else {
      promptAction.showToast({ message: '播放列表为空' });
    }
  }

  openCreate(): void { this.sheetMode = 'create'; this.showSheet = true; }
  openCtxMenu(card: PlaylistCard): void { this.ctxCard = card; this.sheetMode = 'ctxmenu'; this.showSheet = true; }
  openRename(): void { this.sheetMode = 'rename'; this.showSheet = true; }
  closeSheet(): void { this.showSheet = false; this.sheetMode = 'none'; this.ctxCard = null; }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing }) {
        if (this.vm.playlists.length === 0) {
          Column() {
            Image($r('app.media.ic_playlist_big')).width(96).height(96).fillColor($r('app.color.grey800'))
            Text($r('app.string.noplaylist')).fontSize(15).fontColor($r('app.color.list_subtitle')).margin({ top: 12 })
            Button($r('app.string.create_new_playlist'))
              .type(ButtonType.Normal).borderRadius(4).backgroundColor('#FF8800').fontColor('#FFFFFF').fontSize(14)
              .margin({ top: 16 })
              .onClick(() => { this.openCreate(); })
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          Grid() {
            ForEach(this.vm.playlists, (card: PlaylistCard) => {
              GridItem() {
                Column() {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(card.artwork.length > 0 ? card.artwork : $r('app.media.ic_playlist_big'))
                      .width('100%').aspectRatio(1).objectFit(ImageFit.Cover).borderRadius({ topLeft: 6, topRight: 6 })
                    Image($r('app.media.ic_more')).width(20).height(20).fillColor($r('app.color.list_title')).margin(4)
                      .onClick(() => { this.openCtxMenu(card); })
                  }
                  .width('100%')
                  Text(card.name).fontSize(14).fontColor($r('app.color.list_title')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 6, left: 8, right: 8 })
                  Text(`${card.trackCount} 首`).fontSize(12).fontColor($r('app.color.list_subtitle'))
                    .margin({ bottom: 6 })
                }
                .width('100%')
                .borderRadius(6)
                .backgroundColor($r('app.color.card_background'))
                .border({ width: 0.5, color: $r('app.color.card_border') })
                .shadow({ radius: 4, color: '#1A000000', offsetY: 2 })
                .onClick(() => { this.playAll(card); })
              }
            }, (card: PlaylistCard) => `pl${card.id}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10).rowsGap(12)
          .padding({ left: 12, right: 12, top: 8, bottom: 80 })
          .width('100%').height('100%')
        }
      }
      .onRefreshing(() => this.doRefresh()).refreshOffset(64)
      .backgroundColor($r('app.color.background_default'))
      .width('100%').height('100%')

      // FAB
      Button() {
        Image($r('app.media.ic_add')).width(22).height(22).fillColor($r('app.color.colorOnPrimary'))
      }
      .width(48).height(48).borderRadius(24).backgroundColor('#FF8800')
      .shadow({ radius: 8, color: '#44000000', offsetY: 4 })
      .position({ right: 16, bottom: 16 })
      .onClick(() => { this.openCreate(); })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    // 唯一的 bindSheet,内部按 sheetMode 切换内容
    .bindSheet(this.showSheet, this.unifiedSheet(), {
      height: SheetSize.FIT_CONTENT, dragBar: true,
      onDisappear: () => { this.closeSheet(); },
    })
  }

  /** 统一半模态:根据 sheetMode 渲染不同内容。 */
  @Builder
  unifiedSheet() {
    if (this.sheetMode === 'create') {
      PlaylistDialog({
        onClose: () => { this.closeSheet(); this.vm.load(); },
        onCreate: async (name: string) => {
          await PlaylistsVM.create(name);
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
        onCancel: () => { this.closeSheet(); },
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
        Image($r('app.media.ic_play_player')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text('播放全部').fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        if (this.ctxCard) { this.playAll(this.ctxCard); }
        this.closeSheet();
      })

      // 重命名
      Row() {
        Image($r('app.media.ic_edit')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text($r('app.string.rename')).fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => { this.openRename(); })

      // 删除
      Row() {
        Image($r('app.media.ic_playlist_delete')).width(24).height(24).fillColor('#FF8800').margin({ right: 12 })
        Text($r('app.string.delete')).fontSize(15).fontColor('#FF8800')
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(async () => {
        if (this.ctxCard) {
          await this.vm.deletePlaylist(this.ctxCard.id);
          promptAction.showToast({ message: $r('app.string.stream_deleted') });
        }
        this.closeSheet();
      })

      Blank().height(24)
    }
    .width('100%').backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
