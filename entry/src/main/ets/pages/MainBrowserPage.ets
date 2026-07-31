import { MediaLibrary } from '../common/data/MediaLibrary';
import { BundledMedia } from '../common/data/BundledMedia';
import { NavController } from '../common/data/NavController';
import { TitleListView } from '../common/components/TitleListView';
import { SheetItem, Folder, FileBrowserParam } from '../common/models/MediaModels';
import { NetworkServerDialog } from './NetworkServerDialog';

/**
 * MainBrowserPage —— Browse Tab 根(MainBrowserFragment)。
 * 四段 TitleListView:收藏 / 本地存储 / 应用内视频 / 局域网,各含横向卡片列表 + 加载/空态。
 */
@ObservedV2
class MainBrowserViewModel {
  @Trace favorites: SheetItem[] = [];
  @Trace storages: SheetItem[] = [];
  @Trace appVideos: SheetItem[] = [];
  @Trace network: SheetItem[] = [];
  @Trace loading: boolean = true;

  async load(): Promise<void> {
    this.loading = true;
    await MediaLibrary.scan();
    const folders: Folder[] = MediaLibrary.getVideoFolders();
    this.storages = folders.map((f: Folder, i: number) => new SheetItem(f.title, `${f.mediaCount} videos`,
      $r('app.media.ic_folder')));
    const bundled = BundledMedia.asRootFolder();
    this.appVideos = [
      new SheetItem(bundled.title, `${bundled.mediaCount} video${bundled.mediaCount > 1 ? 's' : ''}`,
        $r('app.media.ic_video')),
    ];
    this.favorites = []; // 无收藏
    this.network = []; // 局域网需手动添加
    this.loading = false;
  }
}

@ComponentV2
export struct MainBrowserPage {
  @Local vm: MainBrowserViewModel = new MainBrowserViewModel();
  /** 添加网络服务器弹窗状态。 */
  @Local showServerSheet: boolean = false;

  aboutToAppear(): void {
    this.vm.load();
  }

  /** 打开添加服务器弹窗。 */
  openServerSheet(): void {
    this.showServerSheet = true;
  }

  build() {
    Scroll() {
      Column() {
        TitleListView({
          title: $r('app.string.favorites'),
          items: this.vm.favorites,
          loading: this.vm.loading,
          emptyText: $r('app.string.no_favorite'),
          onItemClick: () => {
          },
        })
        TitleListView({
          title: $r('app.string.browser_storages'),
          items: this.vm.storages,
          loading: this.vm.loading,
          emptyText: $r('app.string.nomedia'),
          onItemClick: (item: SheetItem) => NavController.pushSecondary('STORAGE'),
        })
        TitleListView({
          title: $r('app.string.browser_app_videos'),
          items: this.vm.appVideos,
          loading: this.vm.loading,
          emptyText: $r('app.string.browser_app_videos_empty'),
          onItemClick: (_item: SheetItem) => {
            const p: FileBrowserParam = { mode: 'bundled' };
            NavController.push('FileBrowser', p);
          },
        })
        // Local Network:标题旁 ic_add 打开 NetworkServerDialog;空态显示「Add server」按钮。
        Column() {
          Row() {
            Text($r('app.string.network_browsing'))
              .fontSize(18)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
              .margin({ left: 12, top: 12, bottom: 8 })
            Image($r('app.media.ic_add'))
              .width(24)
              .height(24)
              .fillColor('#FFFFFF')
              .margin({ right: 12, top: 12, bottom: 8 })
              .onClick(() => this.openServerSheet())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.vm.network.length === 0) {
            Button('Add server')
              .type(ButtonType.Normal)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#33FF8800')
              .borderRadius(4)
              .margin({ left: 12, top: 4, bottom: 8 })
              .onClick(() => this.openServerSheet())
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .scrollBar(BarState.Auto)
    .bindSheet(this.showServerSheet, this.serverSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: '#FFFFFF',
      onDisappear: () => {
        this.showServerSheet = false;
      },
    })
  }

  /** 添加网络服务器 sheet(动作体保留 TODO medialibrary BrowserFavRepository)。 */
  @Builder
  serverSheet() {
    Column() {
      NetworkServerDialog({
        onClose: () => {
          this.showServerSheet = false;
        },
      }).width('100%')
    }
    .width('100%')
  }
}
