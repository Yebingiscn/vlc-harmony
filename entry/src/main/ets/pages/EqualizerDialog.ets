import { EqualizerPreset } from '../common/models/MediaModels';
import { EqualizerBar } from '../common/components/EqualizerBar';
import { Settings } from '../common/data/Settings';
import { AppColors } from '../common/constants/AppConstants';
import { PlaybackService } from '../common/data/PlaybackService';
import { Equalizer } from '../libvlc';

const FREQ_LABELS: string[] = ['60', '170', '310', '600', '1K', '3K', '6K', '12K'];

/**
 * EqualizerDialog —— 底部 BottomSheet 均衡器。
 * 标题(18sp Medium)+ 启用开关 + 预设 Chip 横滑条 + 前置放大滑块 + 频段竖直条(EqualizerBar,150dp)
 * + snap 开关 + 增删改撤销图标。启用态持久化(KEY_EQUALIZER_ENABLED),预设 id 持久化(KEY_CURRENT_EQUALIZER_ID)。
 */
@ComponentV2
export struct EqualizerDialog {
  @Local eqEnabled: boolean = false;
  @Local preamp: number = 0;
  @Local bands: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @Local snap: boolean = false;
  @Local presetIndex: number = 0;
  @Local presets: EqualizerPreset[] = [];
  @Event onClose: () => void = () => {
  };

  async aboutToAppear(): Promise<void> {
    const count = Equalizer.getPresetCount();
    const bandCount = Equalizer.getBandCount();
    const next: EqualizerPreset[] = [];
    if (count > 0) {
      for (let i = 0; i < count; i++) {
        const name = Equalizer.getPresetName(i);
        const bands: number[] = [];
        for (let b = 0; b < Math.min(bandCount, 8); b++) {
          bands.push(0);
        }
        while (bands.length < 8) {
          bands.push(0);
        }
        next.push(new EqualizerPreset(i, name.length > 0 ? name : `Preset ${i}`, bands));
      }
    } else {
      next.push(new EqualizerPreset(0, 'Flat', [0, 0, 0, 0, 0, 0, 0, 0]));
    }
    this.presets = next;
    const savedId = await Settings.getInt(Settings.KEY_CURRENT_EQUALIZER_ID, 0);
    const idx = savedId >= 0 && savedId < this.presets.length ? savedId : 0;
    this.eqEnabled = await Settings.getBoolean(Settings.KEY_EQUALIZER_ENABLED, false);
    this.applyPreset(this.presets[idx]);
  }

  applyPreset(p: EqualizerPreset): void {
    this.presetIndex = p.id;
    this.bands = p.bands.slice();
    Settings.put(Settings.KEY_CURRENT_EQUALIZER_ID, p.id);
    this.pushToPlayer();
  }

  setBand(index: number, v: number): void {
    const next = this.bands.slice();
    next[index] = v;
    this.bands = next;
  }

  toggleEnabled(): void {
    this.eqEnabled = !this.eqEnabled;
    Settings.put(Settings.KEY_EQUALIZER_ENABLED, this.eqEnabled);
  }

  build() {
    Column() {
      // 标题 + 启用开关
      Row() {
        Text($r('app.string.equalizer'))
          .fontSize(18)
          .fontColor($r('app.color.list_title'))
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.eqEnabled })
          .selectedColor(AppColors.orange500)
          .onChange((on: boolean) => {
            this.eqEnabled = on;
            Settings.put(Settings.KEY_EQUALIZER_ENABLED, on);
            this.pushToPlayer();
          })
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)

      // 预设 Chip 横滑条
      Scroll() {
        Row() {
          ForEach(this.presets, (p: EqualizerPreset) => {
            Text(p.name)
              .fontSize(16)
              .fontColor(this.presetIndex === p.id ? $r('app.color.list_title') : $r('app.color.font_light'))
              .backgroundColor(this.presetIndex === p.id ? AppColors.orange800 : '#1AFF610A')
              .borderRadius(16)
              .padding({
                left: 16,
                right: 16,
                top: 8,
                bottom: 8
              })
              .margin({ left: 4, right: 4 })
              .onClick(() => this.applyPreset(p))
          }, (p: EqualizerPreset) => `${p.id}`)
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(48)
      .margin({ bottom: 8 })

      // 前置放大 + 频段竖直条
      Row() {
        // 前置放大
        Column() {
          Text($r('app.string.preamp')).fontSize(12).fontColor($r('app.color.font_light')).margin({ bottom: 8 })
          Slider({
            value: this.preamp,
            min: -20,
            max: 20,
            step: 1,
            direction: Axis.Vertical,
            style: SliderStyle.OutSet
          })
            .width(40)
            .height(150)
            .blockColor(AppColors.orange500)
            .selectedColor(AppColors.orange500)
            .trackColor($r('app.color.background_default_darker'))
            .onChange((v: number) => {
              this.preamp = Math.round(v);
              this.pushToPlayer();
            })
          Text(`${this.preamp}`).fontSize(10).fontColor($r('app.color.font_light')).margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 8, right: 8 })

        // 频段竖直条
        Row() {
          ForEach(FREQ_LABELS, (label: string, idx: number) => {
            EqualizerBar({
              label: label,
              value: this.bands[idx],
              onChange: (v: number) => {
                this.setBand(idx, v);
                this.pushToPlayer();
              },
            })
          }, (label: string) => label)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 16 })

      // snap 开关 + 增删改撤销图标
      Row() {
        Row() {
          Toggle({ type: ToggleType.Switch, isOn: this.snap }).selectedColor(AppColors.orange500)
            .onChange((on: boolean) => {
              this.snap = on;
            })
          Text($r('app.string.eq_snap_bands')).fontSize(12).fontColor($r('app.color.font_light')).margin({ left: 8 })
        }
        .layoutWeight(1)

        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => {
          })
        Image($r('app.media.ic_undo'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => {
          })
        Image($r('app.media.ic_delete'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => {
          })
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)

      Button($r('app.string.ok'))
        .type(ButtonType.Normal)
        .borderRadius(4)
        .backgroundColor(AppColors.orange500)
        .fontColor('#FFFFFF')
        .width('80%')
        .onClick(() => {
          this.pushToPlayer();
          this.onClose();
        })
        .margin({ bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  private pushToPlayer(): void {
    PlaybackService.getInstance().applyEqualizer(this.eqEnabled, this.presetIndex, this.preamp, this.bands);
  }
}
