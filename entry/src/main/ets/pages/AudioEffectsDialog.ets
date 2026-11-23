import { PlaybackService } from '../common/data/PlaybackService';
import { UiFeedback } from '../common/utils/UiFeedback';

class EffectFamily {
  title: Resource;
  first: number;
  presets: Resource[];

  constructor(title: Resource, first: number, presets: Resource[]) {
    this.title = title;
    this.first = first;
    this.presets = presets;
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
  @Local family: number = 0;
  @Local support: number = 0;
  @Local status: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    const playback: PlaybackService = PlaybackService.getInstance();
    this.selected = playback.getAudioEffectPreset();
    this.support = playback.getAudioEffectSupport();
    for (let i = 0; i < FAMILIES.length; ++i) {
      if ((this.support & (1 << i)) !== 0) {
        this.family = i;
        break;
      }
    }
    const activeFamily: number = FAMILIES.findIndex((f: EffectFamily) =>
      this.selected >= f.first && this.selected < f.first + f.presets.length);
    if (activeFamily >= 0 && (this.support & (1 << activeFamily)) !== 0) {
      this.family = activeFamily;
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

  private selectPreset(preset: number): void {
    if (preset === this.selected) {
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

  private subtitle(): Resource {
    if (this.support === 0) {
      return $r('app.string.audio_effects_unavailable');
    }
    if (this.selected !== 0) {
      if (this.status === 3) {
        return $r('app.string.audio_effects_bypassed');
      }
      if (this.status === 2) {
        return $r('app.string.audio_effects_active');
      }
      return $r('app.string.audio_effects_pending');
    }
    return $r('app.string.audio_effects_hint');
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

      Text(this.subtitle())
        .fontSize(13)
        .fontColor($r('app.color.list_subtitle'))
        .width('100%')

      if (this.support !== 0) {
        this.presetRow(0, $r('app.string.audio_effects_off'))
        Scroll() {
          Row({ space: 8 }) {
            Repeat(FAMILIES).each((item: RepeatItem<EffectFamily>) => {
              if ((this.support & (1 << item.index)) !== 0) {
                Button(item.item.title, { type: ButtonType.Capsule })
                  .height(36)
                  .fontSize(13)
                  .fontColor(this.family === item.index ? $r('app.color.orange500') : $r('app.color.list_title'))
                  .backgroundColor(this.family === item.index ? '#20FF8800' : $r('app.color.bottom_sheet_background'))
                  .onClick(() => this.family = item.index)
              }
            }).key((f: EffectFamily) => f.first.toString())
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        Scroll() {
          Column({ space: 4 }) {
            Repeat(FAMILIES[this.family].presets).each((item: RepeatItem<Resource>) => {
              this.presetRow(FAMILIES[this.family].first + item.index, item.item)
            }).key((item: Resource) => item.id.toString())
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 220 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.bottom_sheet_background'))
  }
}
