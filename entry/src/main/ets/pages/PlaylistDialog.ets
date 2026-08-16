import { UiFeedback } from '../common/utils/UiFeedback';
import { AppColors } from '../common/constants/AppConstants';

/**
 * PlaylistDialog —— 新建播放列表 BottomSheet。
 * 这里只负责创建空播放列表；向现有播放列表添加媒体由 AddToPlaylistDialog 负责。
 */
@ComponentV2
export struct PlaylistDialog {
  @Local name: string = '';
  @Local submitting: boolean = false;
  /** 创建新播放列表回调:父组件负责持久化,返回 Promise 确保 await 生效。 */
  @Event onCreate: (name: string) => Promise<void> = async () => {
  };

  @Event onClose: () => void = () => {
  };

  /** 名称有效且持久化成功后才关闭，避免留下只有遮罩的空 Sheet。 */
  async createNew(): Promise<void> {
    const trimmedName: string = this.name.trim();
    if (trimmedName.length === 0) {
      UiFeedback.showToast({ message: $r('app.string.edit_eq_name_not_allowed') });
      return;
    }
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    try {
      await this.onCreate(trimmedName);
      this.name = '';
      this.onClose();
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column() {
      Text($r('app.string.create_new_playlist'))
        .fontSize(18).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
        .margin({ top: 32, bottom: 12 })
        .width('100%')
        .textAlign(TextAlign.Center)

      TextInput({ text: this.name, placeholder: $r('app.string.playlist_name_hint') })
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .placeholderColor($r('app.color.font_light'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(4)
        .border({ width: 0.5, color: $r('app.color.card_border') })
        .margin({ left: 16, right: 16, bottom: 16 })
        .onChange((value: string) => {
          this.name = value;
        })
        .onSubmit(() => this.createNew())

      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => this.onClose())
        Button($r('app.string.ok'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor(AppColors.orange500)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .enabled(this.name.trim().length > 0 && !this.submitting)
          .opacity(this.name.trim().length > 0 && !this.submitting ? 1 : 0.4)
          .onClick(() => this.createNew())
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 })

      Blank().height(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.bottom_sheet_background'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
