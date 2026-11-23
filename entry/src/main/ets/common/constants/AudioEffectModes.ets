// Must match the persistent native preset IDs and the NAPI support mask.
export const AUDIO_EFFECT_ACCOMPANIMENT: number = 26;
export const AUDIO_EFFECT_VOCALS: number = 27;
export const AUDIO_EFFECT_SEPARATION_BIT: number = 1 << 5;
export const AUDIO_EFFECT_PRESET_MASK: number = AUDIO_EFFECT_SEPARATION_BIT - 1;

export function isAudioSeparation(preset: number): boolean {
  return preset === AUDIO_EFFECT_ACCOMPANIMENT || preset === AUDIO_EFFECT_VOCALS;
}
