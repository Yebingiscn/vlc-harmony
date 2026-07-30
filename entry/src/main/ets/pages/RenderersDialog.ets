import { AppColors } from '../common/constants/AppConstants';

/** 渲染器行:36vp 图标(chromecast→ic_dialog_renderer/其它→ic_dialog_unknown)+ 16fp 渲染器名,当前项橙色高亮。 */
@ComponentV2
struct RendererItemRow {
  @Param displayName: string = '';
  @Param type: string = '';
  @Param isCurrent: boolean = false;
  @Event onItemClick: () => void = () => {};

  build() {
    Row() {
      Image(this.type === 'chromecast' ? $r('app.media.ic_dialog_renderer') : $r('app.media.ic_dialog_unknown'))
        .width(36).height(36)
        .objectFit(ImageFit.Contain)
        .fillColor(this.isCurrent ? AppColors.orange500 : '#FFFFFF')
        .margin({ left: 24 })
      Text(this.displayName)
        .fontSize(16)
        .fontColor(this.isCurrent ? AppColors.orange500 : '#FFFFFF')
        .margin({ left: 16, top: 16, bottom: 16, right: 16 })
        .layoutWeight(1)
        .onClick(() => this.onItemClick())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * RenderersDialog —— 投屏渲染器列表 BottomSheet。
 * 20fp Bold 标题(renderer_list_title,padding 16)+ 渲染器列表(当前项橙色高亮)
 * + 底部 Disconnect 文字按钮(仅 hasRenderer 时,橙色)。minWidth 384vp。
 * TODO(契约): connect(item|null) → PlaybackService.renderer.value=item(null=断开)+dismiss+snackbar(casting_connected_renderer)。
 *   renderers 来源 RendererDelegate.renderers;hasRenderer=PlaybackService.hasRenderer()。
 */
@ComponentV2
export struct RenderersDialog {
  @Event onClose: () => void = () => {};
  @Event onConnect: (id: number) => void = () => {};
  @Event onDisconnect: () => void = () => {};

  @Local renderers: RendererEntry[] = [];
  @Local currentId: number = -1;
  @Local hasRenderer: boolean = false;

  aboutToAppear(): void {
    // TODO(契约): renderers=RendererDelegate.renderers 快照;currentId=PlaybackService.renderer.value;
    //   hasRenderer=PlaybackService.hasRenderer();showPinIfNeeded() PIN 校验。
  }

  build() {
    Column() {
      Text($r('app.string.renderer_list_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding(16)
        .width('100%')

      List({ space: 0 }) {
        ForEach(this.renderers, (item: RendererEntry) => {
          ListItem() {
            RendererItemRow({
              displayName: item.displayName,
              type: item.type,
              isCurrent: item.id === this.currentId,
              onItemClick: () => {
                this.onConnect(item.id);
                this.onClose();
              },
            })
          }
        }, (item: RendererEntry) => `${item.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ bottom: 16 })
      .scrollBar(BarState.Auto)

      if (this.hasRenderer) {
        Button($r('app.string.renderers_disconnect'))
          .type(ButtonType.Normal)
          .fontColor(AppColors.orange500)
          .backgroundColor(AppColors.transparent)
          .margin({ left: 8, right: 8, bottom: 8 })
          .onClick(() => {
            this.onDisconnect();
            this.onClose();
          })
      }
    }
    .constraintSize({ minWidth: 384 })
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}

/** 渲染器条目数据载体。 */
export class RendererEntry {
  id: number;
  displayName: string;
  type: string;
  constructor(id: number, displayName: string, type: string) {
    this.id = id;
    this.displayName = displayName;
    this.type = type;
  }
}
