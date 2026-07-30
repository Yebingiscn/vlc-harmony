import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { MediaLibraryItem, MediaWrapper } from '../common/models/MediaModels';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService } from '../common/data/PlaybackService';
import { promptAction } from '@kit.ArkUI';

/** HeaderMediaList 入参(album/playlist MediaLibraryItem)。 */
export class HeaderMediaListParam {
  title: string = '';
  description: string = '';
  isPlaylist: boolean = false;
}

/**
 * HeaderMediaListActivityPage —— 专辑/播放列表详情页(HeaderMediaListActivity)。
 * 角色:pushed(透明宿主,承载底部 AudioPlayer 悬浮容器)。
 * 结构:AppBar 折叠区(模糊封面 + 封面 128vp + 标题/艺术家/时长 + Play/Shuffle/AddPlaylist/Favorite 操作行 + 吸顶 Toolbar)
 *   + 内容区(曲目 List,AudioTrackItem)。
 * 曲目数据来自 MediaLibrary.getAudios()。
 */
@ObservedV2
export class HeaderMediaListVM {
  @Trace title: string = '';
  @Trace description: string = '';
  @Trace isPlaylist: boolean = false;
  @Trace tracks: MediaLibraryItem[] = [];
  @Trace isFavorite: boolean = false;
  @Trace totalDuration: number = 0;

  load(param: HeaderMediaListParam): void {
    this.title = param.title.length > 0 ? param.title : 'Playlist';
    this.description = param.description;
    this.isPlaylist = param.isPlaylist;
    // 曲目数据来自 MediaLibrary.getAudios()(非 mock,设备真实音频;无媒体时空列表)。
    const audios = MediaLibrary.getAudios();
    const list: MediaLibraryItem[] = [];
    let total = 0;
    for (const t of audios) {
      list.push(t as MediaLibraryItem);
      total += t.length;
    }
    this.tracks = list;
    this.totalDuration = total;
  }

  millisToTextLarge(ms: number): string {
    // Tools.millisToTextLarge:简化为大时长串。
    if (ms <= 0) {
      return '';
    }
    const totalSec = Math.floor(ms / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    if (h > 0) {
      return `${h}h ${m}m`;
    }
    return `${m}m`;
  }
}

@ComponentV2
export struct HeaderMediaListActivityPage {
  @Param param: HeaderMediaListParam = new HeaderMediaListParam();
  @Local vm: HeaderMediaListVM = new HeaderMediaListVM();

  aboutToAppear(): void {
    // 入参 playlist 为空 → finish() 退出。
    this.vm.load(this.param);
    if (this.param.title.length === 0 && this.vm.tracks.length === 0 && !MediaLibrary.hasScanned()) {
      // 不强制退出,保留空态展示。
    }
  }

  private playAll(): void {
    // playAll(): MediaUtils.playTracks(this, tracksProvider, 0)
    const items: MediaWrapper[] = [];
    for (const t of this.vm.tracks) {
      const mw = new MediaWrapper(t.id, t.title, '', 1);
      items.push(mw);
    }
    PlaybackService.getInstance().playList(items, 0, true);
  }

  private shuffleAll(): void {
    // shuffleAll(): 随机起始播放
    const items: MediaWrapper[] = [];
    for (const t of this.vm.tracks) {
      items.push(new MediaWrapper(t.id, t.title, '', 1));
    }
    if (items.length === 0) {
      return;
    }
    const start = Math.floor(Math.random() * items.length);
    PlaybackService.getInstance().playList(items, start, true);
    PlaybackService.getInstance().toggleShuffle();
  }

  private addToPlaylist(): void {
    // UiTools.addToPlaylist(tracks) → SavePlaylistDialog
    promptAction.showToast({ message: 'Add to playlist' });
  }

  private toggleFavorite(): void {
    this.vm.isFavorite = !this.vm.isFavorite;
  }

  @Builder
  TrackItem(item: MediaLibraryItem, position: number) {
    Row() {
      // 封面 40×40
      Stack() {
        Image($r('app.media.ic_song'))
          .width(40)
          .height(40)
          .objectFit(ImageFit.Cover)
          .fillColor(AppColors.grey600)
      }
      .width(40)
      .height(40)
      // 标题
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.description.length > 0) {
          Text(item.description)
            .fontSize(AppDimens.audio_item_title_size)
            .fontColor(AppColors.grey700)
        }
      }
      .layoutWeight(1)
      .margin({ left: AppDimens.default_margin, right: AppDimens.kl_normal })
      .alignItems(HorizontalAlign.Start)
      // 右侧收藏图标
      if (item.isFavorite) {
        Image($r('app.media.ic_emoji_favorite'))
          .width(24)
          .height(24)
          .fillColor(AppColors.orange800)
          .padding(3)
      }
      // 更多按钮
      Image($r('app.media.ic_more'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey700)
        .padding(AppDimens.default_margin)
        .onClick(() => {
          // onCtxClick → ContextSheet(收藏增删/复制/重命名/去艺术家/分享)
          promptAction.showToast({ message: 'Context menu' });
        })
    }
    .width('100%')
    .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin, right: AppDimens.kl_normal })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      // onItemClick → playTracks(position)
      const items: MediaWrapper[] = [];
      for (const t of this.vm.tracks) {
        items.push(new MediaWrapper(t.id, t.title, '', 1));
      }
      PlaybackService.getInstance().playList(items, position, true);
    })
  }

  build() {
    NavDestination() {
      Column() {
        // === AppBar 折叠区 ===
        Column() {
          // 折叠头部(模糊封面铺满 header + 封面块 + 标题/艺术家/时长)
          Stack() {
            // 背景图(模糊封面铺满,白透 75 叠加)
            Column()
              .width('100%')
              .height(220)
              .backgroundColor(AppColors.grey200)
            // 封面块 + 文本列
            Row() {
              Image($r('app.media.ic_playlist'))
                .width(128)
                .height(128)
                .objectFit(ImageFit.Contain)
                .fillColor(AppColors.orange800)
                .margin({ top: 86, left: AppDimens.default_margin, right: AppDimens.default_margin })
              // 右侧文本列
              Column() {
                Text(this.vm.title)
                  .fontSize(AppDimens.audio_browser_item_size + 6)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.grey900)
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.vm.description.length > 0) {
                  Text(this.vm.description)
                    .fontSize(AppDimens.audio_item_title_size)
                    .fontColor(AppColors.grey900)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: AppDimens.half_default_margin })
                    .onClick(() => {
                      // header_list_artist → push SecondaryActivity(ALBUMS_SONGS, artist)
                      NavController.pushSecondary('ALBUMS_SONGS', this.vm.description);
                    })
                }
                if (this.vm.totalDuration > 0) {
                  Text(this.vm.millisToTextLarge(this.vm.totalDuration))
                    .fontSize(AppDimens.audio_item_title_size)
                    .fontColor(AppColors.grey900)
                    .margin({ top: AppDimens.half_default_margin })
                }
              }
              .layoutWeight(1)
              .padding({ left: AppDimens.default_margin, right: AppDimens.default_margin })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            // 操作按钮行(Play + Shuffle + AddPlaylist + Favorite)
            Row() {
              Button($r('app.string.play'))
                .height(40)
                .padding(AppDimens.default_margin)
                .backgroundColor(AppColors.orange500)
                .fontColor(AppColors.white)
                .onClick(() => this.playAll())
              Image($r('app.media.ic_shuffle'))
                .width(24)
                .height(24)
                .fillColor(AppColors.grey900)
                .padding(AppDimens.half_default_margin)
                .margin({ left: AppDimens.kl_normal })
                .onClick(() => this.shuffleAll())
              Image($r('app.media.ic_addtoplaylist'))
                .width(24)
                .height(24)
                .fillColor(AppColors.grey900)
                .padding(AppDimens.half_default_margin)
                .margin({ left: AppDimens.default_margin })
                .onClick(() => this.addToPlaylist())
              Image(this.vm.isFavorite ? $r('app.media.ic_header_media_favorite') : $r('app.media.ic_fav_add'))
                .width(24)
                .height(24)
                .fillColor(AppColors.grey900)
                .padding(AppDimens.half_default_margin)
                .margin({ left: AppDimens.default_margin })
                .onClick(() => this.toggleFavorite())
            }
            .width('100%')
            .padding({ left: AppDimens.default_margin, right: AppDimens.default_margin, top: AppDimens.half_default_margin, bottom: AppDimens.default_margin })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignContent(Alignment.TopStart)

          // 吸顶 Toolbar(collapseMode=pin,高 56vp)
          Row() {
            Image($r('app.media.ic_arrow_back'))
              .width(24)
              .height(24)
              .fillColor(AppColors.grey900)
              .padding(AppDimens.default_margin)
              .onClick(() => NavController.pop())
          }
          .width('100%')
          .height(56)
          .backgroundColor(AppColors.white)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .backgroundColor(AppColors.white)

        // === 内容区:曲目 List ===
        Column() {
          List() {
            ForEach(this.vm.tracks, (item: MediaLibraryItem, idx: number) => {
              ListItem() {
                this.TrackItem(item, idx)
              }
            }, (item: MediaLibraryItem) => `${item.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 64 })
          .scrollBar(BarState.Off)
          .backgroundColor(AppColors.white)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppColors.white)

        // === 音频播放器悬浮层 ===
        // TODO(契约): <include audioplayercontainer> 全局音频播放器悬浮条(PlaybackService 当前队列驱动)。
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.transparent)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
