import { AppColors } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';

/** 功能卡:图标 + 16fp Medium 标题 + 14fp 次级灰说明 + 右对齐 "Show in settings" 橙色文字按钮。 */
@ComponentV2
struct FeatureCard {
  @Param icon: Resource = $r('app.media.ic_empty');
  @Param title: Resource = $r('app.string.equalizer');
  @Param body: string = '';
  @Param btnText: Resource = $r('app.string.show_in_settings');
  @Event onClickBtn: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        Image(this.icon).width(24).height(24).fillColor('#FFFFFF')
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%').alignItems(VerticalAlign.Center)

      Text(this.body)
        .fontSize(14).fontColor(AppColors.grey500)
        .width('100%').margin({ top: 8 })

      Row() {
        Text(this.btnText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.orange500)
          .padding({ top: 8, bottom: 8 })
          .onClick(() => this.onClickBtn())
      }
      .width('100%').justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(16)
    .border({ width: 1, color: AppColors.grey800, radius: 4 })
    .backgroundColor($r('app.color.background_default_darker'))
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * WhatsNewDialog —— "新功能" BottomSheet。
 * 顶部标题行(ic_whats_new + 18fp Medium "What's new in VLC for Android X.Y",minHeight 56vp)
 * + 3 张功能卡(Equalizer / Export settings / Android Auto,各含图标+标题+说明+橙色"Show in settings"按钮)
 * + 底部 "Never show again" 复选框(写 KEY_SHOW_WHATS_NEW = !checked)。
 * TODO(契约): 三张卡按钮分别 → EqualizerSettingsActivity / PreferencesActivity.launchWithPref("export_settings") / ("playback_speed_audio_global")。
 */
@ComponentV2
export struct WhatsNewDialog {
  @Local neverAgainChecked: boolean = false;

  @Event onClose: () => void = () => {
  };

  build() {
    Scroll() {
      Column() {
        // 顶部标题行
        Row() {
          Image($r('app.media.ic_whats_new')).width(28).height(28).margin({ left: 16 })
          Text("What's new in VLC for Android")
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .margin({ left: 16, right: 16 })
            .maxLines(1)
        }
        .width('100%').height(56).alignItems(VerticalAlign.Center)

        // 3 张功能卡
        FeatureCard({
          icon: $r('app.media.ic_equalizer'),
          title: $r('app.string.equalizer'),
          body: 'A new equalizer is now available with presets and custom bands.',
          btnText: $r('app.string.show_in_settings'),
          onClickBtn: () => {
            this.onClose();
          },
        }).margin({ top: 24, left: 16, right: 16 })

        FeatureCard({
          icon: $r('app.media.ic_whats_new_import_export'),
          title: $r('app.string.export_settings'),
          body: 'You can now export and import your settings between devices.',
          btnText: $r('app.string.show_in_settings'),
          onClickBtn: () => {
            this.onClose();
          },
        }).margin({ top: 24, left: 16, right: 16 })

        FeatureCard({
          icon: $r('app.media.ic_pref_android_auto'),
          title: $r('app.string.android_auto'),
          body: 'Improved Android Auto support with a redesigned interface.',
          btnText: $r('app.string.show_in_settings'),
          onClickBtn: () => {
            this.onClose();
          },
        }).margin({ top: 24, left: 16, right: 16 })

        // 底部复选框
        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.neverAgainChecked }).selectedColor(AppColors.orange500)
            .onChange((on: boolean) => {
              this.neverAgainChecked = on;
              Settings.put(Settings.KEY_SHOW_WHATS_NEW, !on);
            })
          Text($r('app.string.never_show_again'))
            .fontSize(14).fontColor('#FFFFFF').margin({ left: 8 }).layoutWeight(1)
        }
        .width('100%')
        .margin({
          top: 24,
          left: 16,
          right: 16,
          bottom: 16
        })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
