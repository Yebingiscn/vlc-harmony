import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { NavController } from '../common/data/NavController';
import { SheetItem, VideoNavParam, Folder, FileBrowserParam } from '../common/models/MediaModels';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { TitleListView } from '../common/components/TitleListView';
import { NetworkServerDialog } from './NetworkServerDialog';

/**
 * MainBrowserPage —— Browse Tab (对齐 Android MainBrowserFragment 3.6.0)。
 *
 * 状态管理对齐 AudioBrowserVM 模式: @ObservedV2 + @Trace + syncData()。
 * 关键点: @Builder 不传响应式数组参数(参数是快照),直接通过 this.vm.xxx 读取状态。
 * 收藏: Settings JSON 持久化
 * 存储: DocumentViewPicker 选择音视频 → 导入 MediaLibrary → 可收藏
 */
@ObservedV2
class BrowseVM {
  @Trace favorites: SheetItem[] = [];
  @Trace storages: SheetItem[] = [];

  async load(): Promise<void> {
    await MediaLibrary.loadStorageFiles();
    const favs = await MediaLibrary.getFavorites();
    this.syncData(favs);
  }

  /**
   * 同步数据到 @Trace 属性 —— 对齐 AudioBrowserVM.syncData()。
   * 每次创建新数组引用,触发 ArkUI V2 @ObservedV2 → @Trace 观察链。
   */
  syncData(favs: SheetItem[]): void {
    const stors = MediaLibrary.getStorageFiles();
    console.info(`[Browse] syncData: favs=${favs.length} storages=${stors.length}`);
    for (let i = 0; i < stors.length; i++) {
      const s = stors[i];
      console.info(`[Browse]   stor[${i}]: title="${s.title}" artworkPath="${s.artworkPath}"`);
    }
    // 展开为新数组引用(对齐 Audio tab: this.tracks = all.slice().sort(...))
    this.favorites = [...favs];
    this.storages = [...stors];
  }
}

@ComponentV2
export struct MainBrowserPage {
  @Local vm: BrowseVM = new BrowseVM();
  @Local ctxItem: SheetItem | null = null;
  @Local ctxIsFavorite: boolean = false;
  @Local showCtxSheet: boolean = false;

  async aboutToAppear(): Promise<void> {
    await this.vm.load();
    const favs = await MediaLibrary.getFavorites();
    this.vm.syncData(favs);
  }

  /** 打开文件选择器,导入音视频文件到存储列表。对齐 Audio tab pickAudioFiles() 模式。 */
  async pickStorageFiles(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 200;
      opts.fileSuffixFilters = [
        '音频|.mp3,.flac,.ogg,.wav,.aac,.m4a,.wma,.opus',
        '视频|.mp4,.mkv,.avi,.mov,.webm,.ts',
        '光盘映像|.iso',
        'VLC 模块|.so'
      ];
      const docPicker = new picker.DocumentViewPicker(ctx);
      const uris = await docPicker.select(opts);
      if (uris && uris.length > 0) {
        await MediaLibrary.importStorageFiles(uris);
        const favs = await MediaLibrary.getFavorites();
        this.vm.syncData(favs);
      }
    } catch (e) {
      // user cancelled
    }
  }

  /** 播放存储中的文件,音频→AudioPlayer,视频→VideoPlayer。 */
  playStorageItem(item: SheetItem): void {
    if (item.uri.length === 0) { return; }
    const lower = item.uri.toLowerCase();
    const audioExts = ['.mp3', '.flac', '.ogg', '.wav', '.aac', '.m4a', '.wma', '.opus'];
    const isAudio = audioExts.some(e => lower.endsWith(e));
    if (isAudio) {
      const artist = item.subtitle.length > 0 && item.subtitle !== '音频' ? item.subtitle : '';
      const qi = new QueueItem(0, item.title, item.uri, artist, '', '');
      PlaybackService.playList([qi], 0, true);
      NavController.push('AudioPlayer');
    } else {
      const vp: VideoNavParam = { uri: item.uri, title: item.title };
      NavController.push('VideoPlayer', vp);
    }
  }

  onFavCardClick(item: SheetItem): void {
    this.playStorageItem(item);
  }

  onStorageCardClick(item: SheetItem): void {
    this.playStorageItem(item);
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // === 收藏 ===
          if (this.vm.favorites.length > 0) {
            this.sectionTitle($r('app.string.favorites'))
            // ForEach+List 内联在 build() 中直接读 this.vm.favorites,避免 @Builder 参数快照问题
            List({ space: 8 }) {
              ForEach(this.vm.favorites, (item: SheetItem) => {
                ListItem() {
                  this.cardItem(item, true)
                }
              }, (item: SheetItem) => item.title)
            }
            .listDirection(Axis.Horizontal)
            .width('100%').height(160)
            .scrollBar(BarState.Off)
            .padding({ left: 12, right: 12 })
            .margin({ top: 12 })
          }

          // === 存储设备 ===
          this.sectionTitle($r('app.string.browser_storages'))
          Row() {
            Blank()
            Image($r('app.media.ic_add')).width(24).height(24).fillColor($r('app.color.list_title'))
              .margin({ right: 6 })
              .onClick(() => { this.pickStorageFiles(); })
            Text('导入').fontSize(13).fontColor($r('app.color.list_subtitle'))
              .margin({ right: 16 })
              .onClick(() => { this.pickStorageFiles(); })
          }
          .width('100%').margin({ top: -8, bottom: 4 })

          if (this.vm.storages.length > 0) {
            // 纵向列表(对齐 Android browser_item.xml 行式布局)
            List({ space: 0 }) {
              ForEach(this.vm.storages, (item: SheetItem) => {
                ListItem() {
                  this.storageRowItem(item)
                }
              }, (item: SheetItem) => item.title)
            }
            .width('100%')
            .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 60, endMargin: 16 })
            .padding({ left: 0, right: 0 })
            .margin({ top: 8 })
          }

        }
        .width('100%').height('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.background_default')).scrollBar(BarState.Auto)
    }
    .width('100%').height('100%')
    .bindSheet(this.showCtxSheet, this.ctxSheet(), {
      height: SheetSize.FIT_CONTENT, dragBar: true,
      onDisappear: () => { this.showCtxSheet = false; this.ctxItem = null; },
    })
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title)
      .fontSize(18).fontColor($r('app.color.colorAccent')).fontWeight(FontWeight.Medium)
      .margin({ left: 16, top: 16 })
      .width('100%')
  }

  /** 存储列表行式布局(对齐 Android browser_item.xml): 48vp 缩略图 + 标题/副标题。 */
  @Builder
  storageRowItem(item: SheetItem) {
    Row() {
      Image(item.artworkPath.length > 0 ? item.artworkPath : item.icon)
        .width(48).height(48).objectFit(ImageFit.Cover).borderRadius(4)
        .margin({ left: 12, top: 4, bottom: 4 })
      Column() {
        Text(item.title).fontSize(16).fontColor($r('app.color.list_title')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.subtitle.length > 0) {
          Text(item.subtitle).fontSize(12).fontColor($r('app.color.list_subtitle')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12, right: 8 })
      Image($r('app.media.ic_more')).width(24).height(24).fillColor($r('app.color.list_subtitle'))
        .padding(4).margin({ right: 4 })
        .onClick(() => {
          this.ctxItem = item;
          this.ctxIsFavorite = false;
          this.showCtxSheet = true;
        })
    }
    .width('100%').constraintSize({ minHeight: 56 }).alignItems(VerticalAlign.Center)
    .onClick(() => { this.onStorageCardClick(item); })
  }

  /** 卡片内容(对齐 Android card_browser_item.xml)。由 ForEach 迭代调用,item 来自 ForEach 的响应式迭代。 */
  @Builder
  cardItem(item: SheetItem, isFavorite: boolean) {
    Column() {
      // 优先显示音频提取的封面图,回退到通用图标
      Image(item.artworkPath.length > 0 ? item.artworkPath : item.icon)
        .width(64).height(64).objectFit(ImageFit.Cover)
        .borderRadius(4)
        .margin({ top: 8 })

      Text(item.title)
        .fontSize(14).fontColor($r('app.color.list_title')).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, left: 8, right: 8 })

      Row() {
        Text(item.subtitle)
          .fontSize(12).fontColor($r('app.color.list_subtitle')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Image($r('app.media.ic_more')).width(24).height(24).fillColor($r('app.color.list_subtitle'))
          .padding(4).margin({ left: 4 })
          .onClick(() => {
            this.ctxItem = item;
            this.ctxIsFavorite = isFavorite;
            this.showCtxSheet = true;
          })
      }
      .width('100%')
      .margin({ left: 8, right: 8, bottom: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width(140).borderRadius(4).backgroundColor($r('app.color.card_background'))
    .padding(2)
    .onClick(() => {
      if (isFavorite) {
        this.onFavCardClick(item);
      } else {
        this.onStorageCardClick(item);
      }
    })
  }

  /** 上下文操作半模态(对齐 Android ContextOption: CTX_PLAY / CTX_FAV_ADD / CTX_FAV_REMOVE / CTX_INFORMATION)。 */
  @Builder
  ctxSheet() {
    Column() {
      // 头部: 项目名称
      Row() {
        Image(this.ctxItem?.icon ?? $r('app.media.ic_folder'))
          .width(40).height(40).objectFit(ImageFit.Contain)
          .margin({ right: 12 })
        Text(this.ctxItem?.title ?? '')
          .fontSize(16).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium).maxLines(1)
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)

      Divider().strokeWidth(0.5).color($r('app.color.divider'))

      // CTX_PLAY — 播放
      Row() {
        Image($r('app.media.ic_play_player')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text('播放').fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        if (this.ctxItem) {
          this.playStorageItem(this.ctxItem);
        }
        this.showCtxSheet = false;
      })

      // CTX_FAV_ADD / CTX_FAV_REMOVE
      if (this.ctxIsFavorite) {
        Row() {
          Image($r('app.media.ic_fav_remove')).width(24).height(24).fillColor('#FF8800').margin({ right: 12 })
          Text('取消收藏').fontSize(15).fontColor('#FF8800')
        }
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(async () => {
          if (this.ctxItem) {
            await MediaLibrary.removeFavorite(this.ctxItem.title);
            const favs = await MediaLibrary.getFavorites();
            this.vm.syncData(favs);
          }
          this.showCtxSheet = false;
        })
      } else {
        Row() {
          Image($r('app.media.ic_fav_add')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
          Text('收藏').fontSize(15).fontColor($r('app.color.list_title'))
        }
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(async () => {
          if (this.ctxItem) {
            await MediaLibrary.addFavorite(this.ctxItem);
            const favs = await MediaLibrary.getFavorites();
            this.vm.syncData(favs);
          }
          promptAction.showToast({ message: '已收藏' });
          this.showCtxSheet = false;
        })
      }

      // CTX_INFORMATION — 信息
      Row() {
        Image($r('app.media.ic_information')).width(24).height(24).fillColor('#FFFFFF').margin({ right: 12 })
        Text($r('app.string.video_information')).fontSize(15).fontColor($r('app.color.list_title'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .onClick(() => {
        promptAction.showToast({ message: `名称: ${this.ctxItem?.title}` });
        this.showCtxSheet = false;
      })

      Blank().height(24)
    }
    .width('100%').backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

}
