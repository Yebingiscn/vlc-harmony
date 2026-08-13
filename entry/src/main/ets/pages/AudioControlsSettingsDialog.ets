import { AppColors } from '../common/constants/AppConstants';

/** 嵌入偏好行:标题 + 右侧 Toggle(Switch)。 */
@ComponentV2
struct ControlToggleRow {
  @Param title: Resource = $r('app.string.audio');
  @Param summary: string = '';
  @Param checked: boolean = false;
  @Event onToggle: (on: boolean) => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow(TextOverflow.Ellipsis)
        if (this.summary.length > 0) {
          Text(this.summary)
            .fontSize(12)
            .fontColor(AppColors.grey500)
            .maxLines(2)
            .textOverflow(TextOverflow.Ellipsis)
        }
      }
      .layoutWeight(1)
      .margin({ left: 16, right: 16 })

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor(AppColors.orange500)
        .onChange((on: boolean) => this.onToggle(on))
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * AudioControlsSettingsDialog —— 音频手势/控制偏好 BottomSheet。
 * 18fp Medium 标题(headphones/earphones 控制设置)+ 一组 Toggle 行(强制播放全部/强制随机/快进延时等),
 * 橙色 AppColors.orange500 强调。设置项持久化走 Settings(由调用方绑定具体 key)。
 * TODO(契约): 具体偏好 key 与默认值由 PreferencesAudioControls 提供;此处用 Toggle 行复用渲染。
 */
@ComponentV2
export struct AudioControlsSettingsDialog {
  @Local forcePlayAllAudio: boolean = false;
  @Local forceShuffle: boolean = false;
  @Local resumeOnHeadset: boolean = false;
  @Local headsetControls: boolean = true;

  @Event onClose: () => void = () => {
  };

  aboutToAppear(): void {
    // TODO(契约): 从 Settings 读默认值(force_play_all_audio / force_shuffle / resume_on_headset / headset_controls 等 key)。
  }

  build() {
    Column() {
      Text($r('app.string.controls_setting'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .height(56)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .maxLines(1)
        .textAlign(TextAlign.Start)

      ControlToggleRow({
        title: $r('app.string.force_play_all_audio_title'),
        summary: 'Play all media items when plugging headphones',
        checked: this.forcePlayAllAudio,
        onToggle: (on: boolean) => {
          this.forcePlayAllAudio = on;
          // TODO(契约): 写入对应偏好 key(PreferencesAudioControls),由调用方绑定具体 Settings 键。
        },
      })

      ControlToggleRow({
        title: $r('app.string.force_shuffle_title'),
        summary: 'Shuffle when plugging headphones',
        checked: this.forceShuffle,
        onToggle: (on: boolean) => {
          this.forceShuffle = on;
          // TODO(契约): 写入对应偏好 key(PreferencesAudioControls),由调用方绑定具体 Settings 键。
        },
      })

      ControlToggleRow({
        title: 'Resume on headset reconnect',
        summary: 'Resume playback when headphones are reconnected',
        checked: this.resumeOnHeadset,
        onToggle: (on: boolean) => {
          this.resumeOnHeadset = on;
        },
      })

      ControlToggleRow({
        title: 'Headset controls',
        summary: 'Control playback with headset buttons',
        checked: this.headsetControls,
        onToggle: (on: boolean) => {
          this.headsetControls = on;
        },
      })

      Button($r('app.string.ok'))
        .type(ButtonType.Normal)
        .borderRadius(4)
        .backgroundColor(AppColors.orange500)
        .fontColor('#FFFFFF')
        .width('80%')
        .onClick(() => this.onClose())
        .margin({ top: 16, bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
