import {
  equalizerCreate,
  equalizerCreateFromPreset,
  equalizerGetAmp,
  equalizerGetBandCount,
  equalizerGetBandFrequency,
  equalizerGetPreAmp,
  equalizerGetPresetCount,
  equalizerGetPresetName,
  equalizerRelease,
  equalizerSetAmp,
  equalizerSetPreAmp,
} from 'libvlcnapi.so';
import { VLCObject } from './VLCObject';

/**
 * Equalizer —— 对齐 MediaPlayer.Equalizer。
 */
export class Equalizer extends VLCObject {
  private constructor(handle: number) {
    super(handle);
  }

  static create(): Equalizer | null {
    const h = equalizerCreate();
    return h === 0 ? null : new Equalizer(h);
  }

  static fromPreset(index: number): Equalizer | null {
    const h = equalizerCreateFromPreset(index);
    return h === 0 ? null : new Equalizer(h);
  }

  static getPresetCount(): number {
    return equalizerGetPresetCount();
  }

  static getPresetName(index: number): string {
    return equalizerGetPresetName(index);
  }

  static getBandCount(): number {
    return equalizerGetBandCount();
  }

  static getBandFrequency(index: number): number {
    return equalizerGetBandFrequency(index);
  }

  setPreAmp(preamp: number): boolean {
    return this.isReleased() ? false : equalizerSetPreAmp(this.handle, preamp);
  }

  getPreAmp(): number {
    return this.isReleased() ? 0 : equalizerGetPreAmp(this.handle);
  }

  setAmp(band: number, amp: number): boolean {
    return this.isReleased() ? false : equalizerSetAmp(this.handle, band, amp);
  }

  getAmp(band: number): number {
    return this.isReleased() ? 0 : equalizerGetAmp(this.handle, band);
  }

  protected onNativeRelease(): void {
    if (this.handle !== 0) {
      equalizerRelease(this.handle);
    }
  }
}
