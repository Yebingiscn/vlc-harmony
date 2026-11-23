import { EqualizerPreset } from '../common/models/MediaModels';
import { EqualizerBar } from '../common/components/EqualizerBar';
import { Settings } from '../common/data/Settings';
import { AppColors } from '../common/constants/AppConstants';
import { PlaybackService } from '../common/data/PlaybackService';
import { Equalizer } from '../libvlc';
import { AppContext } from '../common/data/AppContext';

const FREQ_LABELS: string[] = ['60', '170', '310', '600', '1K', '3K', '6K', '12K'];
const FLAT_BANDS: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
let equalizerPanelSave: Promise<void> = Promise.resolve();

class PanelPreset extends EqualizerPreset {
  preamp: number;

  constructor(id: number, name: string, bands: number[], preamp: number) {
    super(id, name, bands);
    this.preamp = preamp;
  }
}

class EqualizerPanelState {
  id: number = 0;
  preamp: number = 0;
  bands: number[] = [];
  snap: boolean = false;
  custom: PanelPreset[] = [];
}

/** Equalizer controls embedded in the shared Audio Effects panel. */
@ComponentV2
export struct EqualizerDialog {
  @Local ready: boolean = false;
  @Local eqEnabled: boolean = false;
  @Local preamp: number = 0;
  @Local bands: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @Local snap: boolean = false;
  @Local presetIndex: number = 0;
  @Local presets: PanelPreset[] = [];
  @Local savedBands: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @Local savedPreamp: number = 0;
  private builtInCount: number = 0;
  private alive: boolean = false;
  private dirty: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.alive = true;
    await equalizerPanelSave;
    const savedId = await Settings.getInt(Settings.KEY_CURRENT_EQUALIZER_ID, 0);
    const enabled = await Settings.getBoolean(Settings.KEY_EQUALIZER_ENABLED, false);
    const json = await Settings.getString(Settings.KEY_EQUALIZER_PANEL, '');
    if (!this.alive) {
      return;
    }
    const count = Equalizer.getPresetCount();
    const bandCount = Math.min(Equalizer.getBandCount(), FLAT_BANDS.length);
    const next: PanelPreset[] = [];
    for (let i = 0; i < count; i++) {
      const name = Equalizer.getPresetName(i);
      const eq = Equalizer.fromPreset(i);
      const bands = FLAT_BANDS.slice();
      for (let b = 0; b < bandCount; b++) {
        bands[b] = eq?.getAmp(b) ?? 0;
      }
      next.push(new PanelPreset(i, name.length > 0 ? name : `Preset ${i}`, bands, eq?.getPreAmp() ?? 0));
      eq?.release();
    }
    if (next.length === 0) {
      next.push(new PanelPreset(0, 'Flat', FLAT_BANDS.slice(), 0));
    }
    this.builtInCount = next.length;
    let state: EqualizerPanelState = new EqualizerPanelState();
    try {
      if (json.length > 0) {
        state = JSON.parse(json) as EqualizerPanelState;
        for (const preset of state.custom) {
          if (Number.isInteger(preset.id) && preset.id >= this.builtInCount &&
            this.validCurve(preset.bands, preset.preamp) &&
            typeof preset.name === 'string' && !next.some((p: PanelPreset) => p.id === preset.id)) {
            next.push(new PanelPreset(preset.id, preset.name, preset.bands.slice(), preset.preamp));
          }
        }
      }
    } catch (_error) {
      state = new EqualizerPanelState();
    }
    const preset = next.find((p: PanelPreset) => p.id === savedId) ?? next[0];
    this.presets = next;
    this.eqEnabled = enabled;
    this.snap = state.snap === true;
    this.loadPreset(preset);
    if (state.id === preset.id && this.validCurve(state.bands, state.preamp)) {
      this.bands = state.bands.slice();
      this.preamp = state.preamp;
    }
    this.ready = true;
    this.pushToPlayer(false);
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (!this.dirty) {
      return;
    }
    const state = new EqualizerPanelState();
    state.id = this.presetIndex;
    state.bands = this.bands.slice();
    state.preamp = this.preamp;
    state.snap = this.snap;
    state.custom = this.presets.filter((p: PanelPreset) => p.id >= this.builtInCount);
    const enabled = this.eqEnabled;
    const json = JSON.stringify(state);
    equalizerPanelSave = equalizerPanelSave.then(async () => {
      await Settings.put(Settings.KEY_EQUALIZER_PANEL, json);
      await Settings.put(Settings.KEY_CURRENT_EQUALIZER_ID, state.id);
      await Settings.put(Settings.KEY_EQUALIZER_ENABLED, enabled);
    });
  }

  private validCurve(bands: number[], preamp: number): boolean {
    return Number.isFinite(preamp) && preamp >= -20 && preamp <= 20 &&
      Array.isArray(bands) && bands.length === FLAT_BANDS.length &&
      bands.every((gain: number) => Number.isFinite(gain) && gain >= -20 && gain <= 20);
  }

  private loadPreset(p: PanelPreset): void {
    this.presetIndex = p.id;
    this.bands = p.bands.slice();
    this.savedBands = p.bands.slice();
    this.preamp = p.preamp;
    this.savedPreamp = p.preamp;
  }

  private applyPreset(p: PanelPreset): void {
    this.loadPreset(p);
    this.pushToPlayer();
  }

  setBand(index: number, v: number): void {
    const next = this.bands.slice();
    next[index] = v;
    this.bands = next;
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
            this.pushToPlayer();
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 4,
        bottom: 8,
      })
      .alignItems(VerticalAlign.Center)

      // 预设 Chip 横滑条
      Scroll() {
        Row() {
          Repeat(this.presets).each((pRepeatItem: RepeatItem<PanelPreset>) => {
            Text(pRepeatItem.item.name)
              .fontSize(16)
              .fontColor(this.presetIndex === pRepeatItem.item.id ? $r('app.color.list_title') : $r('app.color.font_light'))
              .backgroundColor(this.presetIndex === pRepeatItem.item.id ? AppColors.orange800 : '#1AFF610A')
              .borderRadius(16)
              .padding({
                left: 16,
                right: 16,
                top: 8,
                bottom: 8
              })
              .margin({ left: 4, right: 4 })
              .onClick(() => this.applyPreset(pRepeatItem.item))
          }).key((p: PanelPreset) => `${p.id}`)
        }
        .padding({ left: 12, right: 12 })
      }
      .clip(false)
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
            reverse: true,
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
          Repeat(FREQ_LABELS).each((labelRepeatItem: RepeatItem<string>) => {
            EqualizerBar({
              label: labelRepeatItem.item,
              value: this.bands[labelRepeatItem.index],
              onChange: (v: number) => {
                this.setBand(labelRepeatItem.index, v);
                this.pushToPlayer();
              },
            })
          }).key((label: string) => label)
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
              this.dirty = true;
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
            const id = this.presets.reduce((max: number, p: PanelPreset) => Math.max(max, p.id), -1) + 1;
            const labelIndex = id - this.builtInCount + 1;
            const ctx = AppContext.get();
            const name = ctx?.resourceManager.getStringSync($r('app.string.custom_preset_name').id, labelIndex) ??
              `Custom ${labelIndex}`;
            const newPreset = new PanelPreset(id, name, this.bands.slice(), this.preamp);
            this.presets = this.presets.concat([newPreset]);
            this.applyPreset(newPreset);
          })
        Image($r('app.media.ic_undo'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => {
            this.bands = this.savedBands.slice();
            this.preamp = this.savedPreamp;
            this.pushToPlayer();
          })
        Image($r('app.media.ic_delete'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.list_title'))
          .margin({ right: 16 })
          .onClick(() => {
            if (this.presetIndex >= this.builtInCount) {
              this.presets = this.presets.filter((p: PanelPreset) => p.id !== this.presetIndex);
              this.applyPreset(this.presets[0]);
            }
          })
      }
      .width('100%').padding(16).alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .enabled(this.ready)
    .alignItems(HorizontalAlign.Center)
  }

  private pushToPlayer(save: boolean = true): void {
    if (!this.ready) {
      return;
    }
    this.dirty = this.dirty || save;
    PlaybackService.getInstance().applyEqualizer(this.eqEnabled, this.presetIndex, this.preamp, this.bands);
  }
}
