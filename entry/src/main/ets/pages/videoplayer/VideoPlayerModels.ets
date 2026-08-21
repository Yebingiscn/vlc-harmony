/** Native XComponent identifiers shared by the active and modular player code. */
export const VLC_VIDEO_XCOMPONENT_ID: string = 'vlc_video_surface';
export const VLC_NAPI_LIBRARY: string = 'libvlcnapi';

/** Minimal queue item passed through navigation. */
export interface VideoPlayItem {
  uri: string;
  title: string;
  artworkUrl?: string;
}

/** Navigation arguments accepted by the video-player page. */
export interface VideoParam {
  uri: string;
  title: string;
  artworkUrl?: string;
  list?: VideoPlayItem[];
  index?: number;
}

/** Player time formatter. Unlike list formatting, zero is rendered as 00:00. */
export function fmtTime(ms: number): string {
  const safe: number = ms > 0 ? ms : 0;
  const totalSec: number = Math.floor(safe / 1000);
  const h: number = Math.floor(totalSec / 3600);
  const m: number = Math.floor((totalSec % 3600) / 60);
  const s: number = totalSec % 60;
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const ss: string = s < 10 ? `0${s}` : `${s}`;
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}
