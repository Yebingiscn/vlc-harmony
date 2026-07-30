import { NavController } from '../common/data/NavController';
import { Playlist } from '../common/models/MediaModels';
import { PlaylistDialog } from './PlaylistDialog';
import { promptAction } from '@kit.ArkUI';

/**
 * PlaylistsPage —— Playlists Tab 根(播放列表聚合)。空态为主(无播放列表时 noplaylist)。
 */
@ObservedV2
class PlaylistsViewModel {
  @Trace playlists: Playlist[] = [];
}

@ComponentV2
export struct PlaylistsPage {
  @Local vm: PlaylistsViewModel = new PlaylistsViewModel();
  @Local showCreate: boolean = false;

  build() {
    Column() {
      if (this.vm.playlists.length === 0) {
        Column() {
          Image($r('app.media.ic_playlist_big')).width(96).height(96).fillColor('#424242')
          Text($r('app.string.noplaylist')).fontSize(14).fontColor('#9E9E9E').margin({ top: 12 })
          Button($r('app.string.create_new_playlist'))
            .type(ButtonType.Normal).borderRadius(4).backgroundColor('#FF8800').fontColor('#FFFFFF').fontSize(14)
            .margin({ top: 16 })
            .onClick(() => {
              this.showCreate = true;
            })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.vm.playlists, (p: Playlist) => {
            ListItem() {
              Row() {
                Image($r('app.media.ic_playlist')).width(40).height(40).fillColor('#FF8800').margin({ right: 12 })
                Text(p.title).fontSize(15).fontColor('#FFFFFF').layoutWeight(1)
              }
              .width('100%').padding(16)
              .onClick(() => promptAction.showToast({ message: $r('app.string.developing') }))
            }
          }, (p: Playlist) => `p${p.id}`)
        }
        .width('100%').layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .bindSheet(this.showCreate, this.createSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => {
        this.showCreate = false;
      },
    })
  }

  @Builder
  createSheet() {
    PlaylistDialog({ onClose: () => {
      this.showCreate = false;
    } }).width('100%')
  }
}
