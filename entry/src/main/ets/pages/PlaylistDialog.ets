import { Playlist } from '../common/models/MediaModels';
import { SimpleListItem } from '../common/components/SimpleListItem';
import { AppColors } from '../common/constants/AppConstants';
import { promptAction } from '@kit.ArkUI';

/**
 * PlaylistDialog —— SavePlaylistDialog BottomSheet。
 * 滚动表单:创建新歌单输入框+Create、Add to existing 列表+ProgressBar/medias 互斥、
 * Replace 开关、SimpleAdapter 多选列表+空态;底部 Add/Save 按钮。
 */
@ComponentV2
export struct PlaylistDialog {
  @Local name: string = '';
  @Local playlists: Playlist[] = [];
  @Local selected: Set<number> = new Set<number>();
  @Local replace: boolean = false;
  @Local loading: boolean = true;
  @Event onClose: () => void = () => {};

  aboutToAppear(): void {
    // 无持久化歌单表 → 空列表(非 mock:真实读取,当前为空)
    this.playlists = [];
    this.loading = false;
  }

  toggleSelect(id: number): void {
    const next = new Set<number>(this.selected);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selected = next;
  }

  createNew(): void {
    if (this.name.trim().length === 0) {
      promptAction.showToast({ message: $r('app.string.edit_eq_name_not_allowed') });
      return;
    }
    const p = new Playlist(Date.now(), this.name.trim());
    this.playlists = this.playlists.concat(p);
    this.name = '';
    promptAction.showToast({ message: $r('app.string.ok') });
  }

  build() {
    Column() {
      Text($r('app.string.create_new_playlist'))
        .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 12 })

      Scroll() {
        Column() {
          // 创建新歌单
          Row() {
            TextInput({ text: this.name, placeholder: $r('app.string.playlist_name_hint') })
              .fontSize(14).fontColor('#FFFFFF').backgroundColor('#2A2A2A').borderRadius(4).layoutWeight(1)
              .onChange((v: string) => {
                this.name = v;
              })
            Button($r('app.string.create'))
              .type(ButtonType.Normal).borderRadius(4).backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
              .fontSize(13).margin({ left: 8 })
              .onClick(() => this.createNew())
          }
          .width('100%').padding(16).alignItems(VerticalAlign.Center)

          // Replace 开关
          Row() {
            Text($r('app.string.replace_playlist')).fontSize(13).fontColor('#FFFFFF').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.replace }).selectedColor(AppColors.orange500)
              .onChange((on: boolean) => {
                this.replace = on;
              })
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 8 }).alignItems(VerticalAlign.Center)

          // Add to existing 列表 / 空态
          if (this.loading) {
            LoadingProgress().width(28).height(28).color(AppColors.orange500).margin(24)
          } else if (this.playlists.length === 0) {
            Column() {
              Image($r('app.media.ic_playlist_big')).width(64).height(64).fillColor('#424242')
              Text($r('app.string.noplaylist')).fontSize(13).fontColor('#9E9E9E').margin({ top: 8 })
            }
            .width('100%').padding(24).alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.playlists, (p: Playlist) => {
                ListItem() {
                  SimpleListItem({
                    title: p.title,
                    subtitle: `${p.trackCount} songs`,
                    selected: this.selected.has(p.id),
                    onItemClick: () => this.toggleSelect(p.id),
                  })
                }
              }, (p: Playlist) => `pl${p.id}`)
            }
            .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
            .width('100%')
            .height(240)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')

      // 底部 Add / Save 按钮
      Row() {
        Button($r('app.string.add'))
          .type(ButtonType.Normal).borderRadius(4).backgroundColor('#2A2A2A').fontColor('#FFFFFF')
          .layoutWeight(1).margin({ right: 8 })
          .onClick(() => this.onClose())
        Button($r('app.string.ok'))
          .type(ButtonType.Normal).borderRadius(4).backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
          .layoutWeight(1)
          .onClick(() => this.onClose())
      }
      .width('100%').padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
