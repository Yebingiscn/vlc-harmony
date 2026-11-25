import { Track } from '../models/MediaModels';
import { pinyin4js } from '@ohos/pinyin4js';

const HAN_CHAR = /[\u3400-\u9fff]/;

/** Keep the displayed spelling while dropping invisible tag padding. */
export function audioTag(value: string): string {
  return value.replace(/[\u0000\u200B\uFEFF]/g, '').replace(/\s+/g, ' ').trim().normalize('NFC');
}

export function audioTagKey(value: string, foldChinese: boolean = true): string {
  const key = audioTag(value).normalize('NFKC').toLowerCase();
  // Use the character mapping, not pinyin: homophones are different names.
  return foldChinese && HAN_CHAR.test(key) ? pinyin4js.convertToSimplifiedChinese(key) as string : key;
}

export function audioAlbumArtist(track: Track): string {
  return audioTag(track.albumArtistName ?? '') || audioTag(track.artistName);
}

export function audioAlbumKey(track: Track, foldChinese: boolean = true): string {
  return 'audio-album:' +
    JSON.stringify([audioTagKey(track.albumName, foldChinese), audioTagKey(audioAlbumArtist(track), foldChinese)]);
}
