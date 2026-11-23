import { PlaybackService } from '../common/data/PlaybackService';
import { UiFeedback } from '../common/utils/UiFeedback';
import {
  AUDIO_EFFECT_ACCOMPANIMENT, AUDIO_EFFECT_PRESET_MASK, AUDIO_EFFECT_SEPARATION_BIT,
  AUDIO_EFFECT_VOCALS, isAudioSeparation
} from '../common/constants/AudioEffectModes';
import { EqualizerDialog } from './EqualizerDialog';

enum EffectSection {
  PRESETS,
  EQUALIZER,
  SEPARATION,
}

class EffectPreset {
  id: number;
  label: Resource;

  constructor(id: number, label: Resource) {
    this.id = id;
    this.label = label;
  }
}

class EffectFamily {
  title: Resource;
  first: number;
  presets: EffectPreset[];

  constructor(title: Resource, first: number, presets: Resource[]) {
    this.title = title;
    this.first = first;
    this.presets = presets.map((label: Resource, index: number) => new EffectPreset(first + index, label));
  }
}

// Family order matches the native support bits. Preset IDs are persistent.
const FAMILIES: EffectFamily[] = [
  new EffectFamily($r('app.string.audio_effects_soundfield'), 1, [
    $r('app.string.audio_fx_front'), $r('app.string.audio_fx_grand'),
    $r('app.string.audio_fx_near'), $r('app.string.audio_fx_wide')
  ]),
  new EffectFamily($r('app.string.audio_effects_space'), 5, [
    $r('app.string.audio_fx_position'), $r('app.string.audio_fx_rotation'), $r('app.string.audio_fx_extension')
  ]),
  new EffectFamily($r('app.string.audio_effects_beauty'), 8, [
    $r('app.string.audio_fx_clear'), $r('app.string.audio_fx_theatre'),
    $r('app.string.audio_fx_cd'), $r('app.string.audio_fx_studio')
  ]),
  new EffectFamily($r('app.string.audio_effects_environment'), 12, [
    $r('app.string.audio_fx_broadcast'), $r('app.string.audio_fx_earpiece'),
    $r('app.string.audio_fx_underwater'), $r('app.string.audio_fx_gramophone')
  ]),
  new EffectFamily($r('app.string.audio_effects_voice'), 16, [
    $r('app.string.audio_fx_cute'), $r('app.string.audio_fx_cyberpunk'), $r('app.string.audio_fx_female'),
    $r('app.string.audio_fx_male'), $r('app.string.audio_fx_reverb'), $r('app.string.audio_fx_monster'),
    $r('app.string.audio_fx_seasoned'), $r('app.string.audio_fx_synth'), $r('app.string.audio_fx_trill'),
    $r('app.string.audio_fx_war')
  ])
];

@ComponentV2
export struct AudioEffectsDialog {
  @Param reserveSystemCloseSpace: boolean = false;
  @Event onClose: () => void = () => {};
  @Local selected: number = 0;
  @Local family: number = -1;
  @Local visiblePresets: EffectPreset[] = [];
  @Local support: number = 0;
  @Local status: number = 0;
  @Local section: EffectSection = EffectSection.PRESETS;
  @Local equalizerOpened: boolean = false;
  private presetScroller: Scroller = new Scroller();
  private timer: number = -1;

  aboutToAppear(): void {
    const playback: PlaybackService = PlaybackService.getInstance();
    this.selected = playback.getAudioEffectPreset();
    this.support = playback.getAudioEffectSupport();
    const matching: number = FAMILIES.findIndex((family: EffectFamily, index: number) =>
      this.supportsFamily(index) && family.presets.some((preset: EffectPreset) => preset.id === this.selected));
    const firstAvailable: number = FAMILIES.findIndex((_family: EffectFamily, index: number) =>
      this.supportsFamily(index));
    this.showFamily(matching >= 0 ? matching : firstAvailable);
    if (this.supportsSeparation() &&
      (isAudioSeparation(this.selected) || (this.support & AUDIO_EFFECT_PRESET_MASK) === 0)) {
      this.section = EffectSection.SEPARATION;
    } else if ((this.support & AUDIO_EFFECT_PRESET_MASK) === 0 && !this.supportsSeparation()) {
      this.switchSection(EffectSection.EQUALIZER);
    }
    this.status = playback.getAudioEffectStatus();
    if (this.support !== 0) {
      this.timer = setInterval(() => this.status = playback.getAudioEffectStatus(), 500);
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private supportsFamily(index: number): boolean {
    return index >= 0 && index < FAMILIES.length && (this.support & (1 << index)) !== 0;
  }

  private showFamily(index: number): void {
    this.family = index;
    this.visiblePresets = index < 0 ? [] : FAMILIES[index].presets.slice();
  }

  private switchFamily(index: number): void {
    if (index === this.family || !this.supportsFamily(index)) {
      return;
    }
    // A long family can be scrolled; don't carry its offset into a short one.
    this.presetScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.showFamily(index);
  }

  private selectPreset(preset: number): void {
    if (preset === this.selected || (isAudioSeparation(preset) && !this.supportsSeparation())) {
      return;
    }
    const playback: PlaybackService = PlaybackService.getInstance();
    if (!playback.setAudioEffectPreset(preset)) {
      UiFeedback.showToast({ message: $r('app.string.audio_effects_apply_failed') });
      return;
    }
    this.selected = preset;
    this.status = playback.getAudioEffectStatus();
  }

  private supportsSeparation(): boolean {
    return (this.support & AUDIO_EFFECT_SEPARATION_BIT) !== 0;
  }

  private switchSection(section: EffectSection): void {
    this.section = section;
    if (section === EffectSection.EQUALIZER) {
      this.equalizerOpened = true;
    }
  }

  private subtitle(): Resource {
    const separation = this.section === EffectSection.SEPARATION;
    if (separation ? !this.supportsSeparation() : (this.support & AUDIO_EFFECT_PRESET_MASK) === 0) {
      return separation ? $r('app.string.audio_separation_unavailable') : $r('app.string.audio_effects_unavailable');
    }
    if (this.selected !== 0 && separation === isAudioSeparation(this.selected)) {
      if (this.status === 3) {
        return $r('app.string.audio_effects_bypassed');
      }
      if (this.status === 2) {
        return $r('app.string.audio_effects_active');
      }
      return $r('app.string.audio_effects_pending');
    }
    return separation ? $r('app.string.audio_separation_hint') : $r('app.string.audio_effects_hint');
  }

  @Builder
  presetRow(preset: number, label: Resource) {
    Button(label, { type: ButtonType.Normal })
      .width('100%')
      .height(42)
      .borderRadius(10)
      .fontSize(15)
      .fontColor(this.selected === preset ? $r('app.color.orange500') : $r('app.color.list_title'))
      .backgroundColor(this.selected === preset ? '#20FF8800' : Color.Transparent)
      .onClick(() => this.selectPreset(preset))
  }

  @Builder
  sectionTab(section: EffectSection, label: Resource) {
    Button(label, { type: ButtonType.Capsule })
      .height(36)
      .layoutWeight(1)
      .fontSize(13)
      .fontColor(this.section === section ? $r('app.color.orange500') : $r('app.color.list_title'))
      .backgroundColor(this.section === section ? '#20FF8800' : Color.Transparent)
      .onClick(() => this.switchSection(section))
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.audio_effects_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
        if (!this.reserveSystemCloseSpace) {
          Button($r('app.string.close'), { type: ButtonType.Normal })
            .height(36)
            .fontColor($r('app.color.list_subtitle'))
            .backgroundColor(Color.Transparent)
            .onClick(() => this.onClose())
        }
      }
      .width('100%')
      .padding({ right: this.reserveSystemCloseSpace ? 48 : 0 })

      Row({ space: 6 }) {
        this.sectionTab(EffectSection.PRESETS, $r('app.string.audio_effects_presets'))
        this.sectionTab(EffectSection.EQUALIZER, $r('app.string.equalizer'))
        this.sectionTab(EffectSection.SEPARATION, $r('app.string.audio_separation_title'))
      }
      .width('100%')

      if (this.section !== EffectSection.EQUALIZER) {
        Text(this.subtitle())
          .fontSize(13)
          .fontColor($r('app.color.list_subtitle'))
          .width('100%')
          .constraintSize({ minHeight: 36 })
      }

      if (this.equalizerOpened) {
        Scroll() {
          EqualizerDialog()
        }
        .width('100%')
        .constraintSize({ maxHeight: 290 })
        .scrollBar(BarState.Auto)
        .visibility(this.section === EffectSection.EQUALIZER ? Visibility.Visible : Visibility.None)
      }

      if (this.section === EffectSection.SEPARATION && this.supportsSeparation()) {
        this.presetRow(0, $r('app.string.audio_effects_off'))
        this.presetRow(AUDIO_EFFECT_ACCOMPANIMENT, $r('app.string.audio_separation_accompaniment'))
        this.presetRow(AUDIO_EFFECT_VOCALS, $r('app.string.audio_separation_vocals'))
      }

      if (this.section === EffectSection.PRESETS && (this.support & AUDIO_EFFECT_PRESET_MASK) !== 0) {
        this.presetRow(0, $r('app.string.audio_effects_off'))
        Scroll() {
          Row({ space: 8 }) {
            Repeat(FAMILIES).each((item: RepeatItem<EffectFamily>) => {
              if (this.supportsFamily(item.index)) {
                Button(item.item.title, { type: ButtonType.Capsule })
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.family === item.index ? $r('app.color.orange500') : $r('app.color.list_title'))
                  .backgroundColor(this.family === item.index ? '#20FF8800' : $r('app.color.bottom_sheet_background'))
                  .onClick(() => this.switchFamily(item.index))
              }
            }).key((f: EffectFamily) => f.first.toString())
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        Scroll(this.presetScroller) {
          Column({ space: 4 }) {
            // The native preset ID and its label come from the same item,
            // independent of the currently selected category and row index.
            Repeat(this.visiblePresets).each((item: RepeatItem<EffectPreset>) => {
              Button(item.item.label, { type: ButtonType.Normal })
                .width('100%')
                .height(42)
                .borderRadius(10)
                .fontSize(15)
                .fontColor(this.selected === item.item.id ? $r('app.color.orange500') : $r('app.color.list_title'))
                .backgroundColor(this.selected === item.item.id ? '#20FF8800' : Color.Transparent)
                .onClick(() => this.selectPreset(item.item.id))
            }).key((preset: EffectPreset) => preset.id.toString())
          }
          .width('100%')
        }
        .width('100%')
        .height(180)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.bottom_sheet_background'))
  }
}
