import { Settings } from './Settings';

interface VideoResumeRecord {
  position: number;
  duration: number;
}

/** Each video's progress is persisted independently, as in SweetVideo. */
export class VideoResumeStore {
  static async save(uri: string, position: number, duration: number, completed: boolean = false): Promise<void> {
    // An unprepared/failed player must not erase its previous progress with zero.
    if (!uri || Settings.incognitoMode || !Number.isFinite(position) || (!completed && position <= 0)) {
      return;
    }
    const record: VideoResumeRecord = {
      position: completed ? 0 : Math.floor(position),
      duration: Number.isFinite(duration) ? Math.max(0, duration) : 0,
    };
    await Settings.put(`video_resume:${uri}`, JSON.stringify(record));
  }

  static async load(uri: string): Promise<number> {
    if (!uri || Settings.incognitoMode) {
      return 0;
    }
    const stored = await Settings.getString(`video_resume:${uri}`, '');
    if (stored.length > 0) {
      try {
        const record = JSON.parse(stored) as VideoResumeRecord;
        if (!record || !Number.isFinite(record.position) || !Number.isFinite(record.duration) ||
          record.position <= 0 || record.duration <= 0 || record.position >= record.duration * 0.95) {
          return 0;
        }
        return Math.floor(record.position);
      } catch (_) {
        return 0;
      }
    }
    // Compatibility with positions saved before per-video persistence was introduced.
    if (await Settings.getString(Settings.VIDEO_RESUME_URI, '') === uri) {
      const time = await Settings.getInt(Settings.VIDEO_RESUME_TIME, 0);
      return Number.isFinite(time) ? Math.max(0, time) : 0;
    }
    return 0;
  }
}
