import { preferences } from '@kit.ArkData';
import { AppContext } from './AppContext';

/**
 * Settings —— Android `org.videolan.tools.Settings` 单例的鸿蒙等价物。
 * 全工程业务偏好统一写入【同一个】preferences(name=`vlc_preferences`,对应安卓默认 prefs 文件)。
 * key 常量逐字转录自 Settings.kt(P0.2),默认值对齐 P0.1/P0.3(见 data/persistence.md)。
 *
 * 能力替换约定:Android SharedPreferences → @kit.ArkData preferences。非 mock,真实持久化。
 */
export class Settings {
  // 版本/迁移
  static readonly KEY_CURRENT_SETTINGS_VERSION: string = 'current_settings_version';
  static readonly KEY_CURRENT_MAJOR_VERSION: string = 'key_current_major_version';
  // Keys
  static readonly KEY_APP_THEME: string = 'app_theme';
  static readonly KEY_BLACK_THEME: string = 'enable_black_theme';
  static readonly KEY_DAYNIGHT: string = 'daynight';
  static readonly SHOW_VIDEO_THUMBNAILS: string = 'show_video_thumbnails';
  static readonly KEY_VIDEO_CONFIRM_RESUME: string = 'video_confirm_resume';
  static readonly KEY_AUDIO_CONFIRM_RESUME: string = 'audio_confirm_resume';
  static readonly KEY_MEDIALIBRARY_AUTO_RESCAN: string = 'auto_rescan';
  static readonly KEY_INCOGNITO: string = 'incognito_mode';
  static readonly KEY_LAST_WHATS_NEW: string = 'last_whats_new';
  static readonly KEY_SHOW_WHATS_NEW: string = 'show_whats_new';
  static readonly KEY_SHOW_UPDATE: string = 'show_update';
  static readonly KEY_LAST_SESSION_CRASHED: string = 'last_session_crashed';
  // Safe mode (PIN)
  static readonly KEY_SAFE_MODE: string = 'safe_mode';
  static readonly KEY_SAFE_MODE_PIN: string = 'safe_mode_pin';
  // Playback
  static readonly KEY_AUDIO_LAST_PLAYLIST: string = 'audio_list';
  static readonly KEY_MEDIA_LAST_PLAYLIST: string = 'media_list';
  static readonly KEY_CURRENT_AUDIO: string = 'current_song';
  static readonly KEY_CURRENT_MEDIA: string = 'current_media';
  // AUDIO
  static readonly KEY_AUDIO_CURRENT_TAB: string = 'key_audio_current_tab';
  static readonly KEY_AUDIO_ALBUM_SONG_CURRENT_TAB: string = 'key_audio_album_song_current_tab';
  // UI
  static readonly LIST_TITLE_ELLIPSIZE: string = 'list_title_ellipsize';
  static readonly KEY_VIDEO_JUMP_DELAY: string = 'video_jump_delay';
  static readonly KEY_VIDEO_LONG_JUMP_DELAY: string = 'video_long_jump_delay';
  static readonly KEY_VIDEO_DOUBLE_TAP_JUMP_DELAY: string = 'video_double_tap_jump_delay';
  static readonly KEY_AUDIO_JUMP_DELAY: string = 'audio_jump_delay';
  static readonly KEY_AUDIO_LONG_JUMP_DELAY: string = 'audio_long_jump_delay';
  static readonly KEY_AUDIO_FORCE_SHUFFLE: string = 'audio_force_shuffle';
  static readonly KEY_AUDIO_SHOW_TRACK_NUMBERS: string = 'audio_show_track_numbers';
  static readonly KEY_BROWSE_NETWORK: string = 'browse_network';
  static readonly KEY_VIDEOS_CARDS: string = 'video_display_in_cards';
  static readonly KEY_GROUP_VIDEOS: string = 'video_min_group_length';
  static readonly KEY_SHOW_HEADERS: string = 'show_headers';
  static readonly KEY_SHOW_TRACK_INFO: string = 'show_track_info';
  static readonly KEY_INCLUDE_MISSING: string = 'include_missing';
  // AudioPlayer
  static readonly AUDIO_SHUFFLING: string = 'audio_shuffling';
  static readonly SHOW_REMAINING_TIME: string = 'show_remaining_time';
  static readonly PREF_PLAYLIST_TIPS_SHOWN: string = 'playlist_tips_shown';
  static readonly PREF_AUDIOPLAYER_TIPS_SHOWN: string = 'audioplayer_tips_shown';
  static readonly KEY_MEDIALIBRARY_SCAN: string = 'ml_scan';
  static readonly KEY_AUDIO_PLAYER_SHOW_COVER: string = 'audio_player_show_cover';
  static readonly AUDIO_PLAY_PROGRESS_MODE: string = 'audio_play_progress_mode';
  // Video
  static readonly VIDEO_RESUME_TIME: string = 'VideoResumeTime';
  static readonly VIDEO_RESUME_URI: string = 'VideoResumeUri';
  static readonly VIDEO_PAUSED: string = 'VideoPaused';
  static readonly VIDEO_SPEED: string = 'VideoSpeed';
  // ── 睡眠倒计时持久化(避免下次开弹框又是空白)──
  static readonly SLEEP_TIMER_MILLIS: string = 'SleepTimerMillis';
  static readonly SLEEP_TIMER_WAIT_MEDIA_END: string = 'SleepTimerWaitMediaEnd';
  static readonly SLEEP_TIMER_RESET_ON_INTERACTION: string = 'SleepTimerResetOnInteraction';
  static readonly VIDEO_RATIO: string = 'video_ratio';
  static readonly SCREEN_ORIENTATION: string = 'screen_orientation';
  static readonly VIDEO_HUD_TIMEOUT: string = 'video_hud_timeout_in_s';
  static readonly VIDEO_TRANSITION_SHOW: string = 'video_transition_show';
  static readonly ENABLE_SEEK_BUTTONS: string = 'enable_seek_buttons';
  static readonly ENABLE_DOUBLE_TAP_SEEK: string = 'enable_double_tap_seek';
  static readonly ENABLE_SWIPE_SEEK: string = 'enable_swipe_seek';
  static readonly ENABLE_DOUBLE_TAP_PLAY: string = 'enable_double_tap_play';
  static readonly ENABLE_VOLUME_GESTURE: string = 'enable_volume_gesture';
  static readonly ENABLE_BRIGHTNESS_GESTURE: string = 'enable_brightness_gesture';
  static readonly ENABLE_SCALE_GESTURE: string = 'enable_scale_gesture';
  static readonly ENABLE_FASTPLAY: string = 'enable_fastplay';
  static readonly FASTPLAY_SPEED: string = 'fastplay_speed';
  static readonly SAVE_BRIGHTNESS: string = 'save_brightness';
  static readonly BRIGHTNESS_VALUE: string = 'brightness_value';
  static readonly LOCK_USE_SENSOR: string = 'lock_use_sensor';
  static readonly LAST_LOCK_ORIENTATION: string = 'last_lock_orientation';
  static readonly KEY_VIDEO_APP_SWITCH: string = 'video_action_switch';
  // Equalizer
  static readonly KEY_CURRENT_EQUALIZER_ID: string = 'current_equalizer_id';
  static readonly KEY_EQUALIZER_ENABLED: string = 'equalizer_enabled';
  // Tips
  static readonly PREF_TIPS_SHOWN: string = 'video_player_tips_shown';
  static readonly KEY_OBSOLETE_RESTORE_FILE_WARNED: string = 'obsolete_restore_file_warned';
  // Permissions / onboarding
  static readonly INITIAL_PERMISSION_ASKED: string = 'initial_permission_asked';
  static readonly PERMISSION_NEVER_ASK: string = 'permission_never_ask';
  static readonly NOTIFICATION_PERMISSION_ASKED: string = 'notification_permission_asked';
  static readonly KEY_FRAGMENT_ID: string = 'fragment_id';
  // Playback speed
  static readonly KEY_PLAYBACK_SPEED_VIDEO_GLOBAL: string = 'playback_speed_video_global';
  static readonly KEY_PLAYBACK_SPEED_AUDIO_GLOBAL: string = 'playback_speed_audio_global';
  static readonly KEY_PLAYBACK_SPEED_VIDEO_GLOBAL_VALUE: string = 'playback_speed_video_global_value';
  static readonly KEY_PLAYBACK_SPEED_AUDIO_GLOBAL_VALUE: string = 'playback_speed_audio_global_value';
  // Misc
  static readonly PLAYBACK_HISTORY: string = 'playback_history';
  static readonly RESUME_PLAYBACK: string = 'resume_playback';
  static readonly AUDIO_DUCKING: string = 'audio_ducking';
  static readonly KEY_MEDIA_SEEN: string = 'media_seen';
  static readonly KEY_AUDIO_BOOST: string = 'audio_boost';
  static readonly BROWSER_SHOW_HIDDEN_FILES: string = 'browser_show_hidden_files';
  static readonly ALBUMS_SHOW_TRACK_NUMBER: string = 'albums_show_track_number';
  static readonly KEY_ARTISTS_SHOW_ALL: string = 'artists_show_all';
  static readonly PLAYLIST_REPLACE: string = 'playlist_replace';
  static readonly HTTP_USER_AGENT: string = 'http_user_agent';

  private static readonly PREFS_NAME: string = 'vlc_preferences';
  private static store: preferences.Preferences | null = null;
  /** 启动时缓存的 key(对齐 P0.1 默认值)。 */
  static showVideoThumbs: boolean = true;
  static incognitoMode: boolean = false;
  static fastplaySpeed: number = 2.0; // FASTPLAY_SPEED default 20 /10f
  static videoHudDelay: number = 4;

  static async init(): Promise<void> {
    if (Settings.store) {
      return;
    }
    const ctx = AppContext.get();
    Settings.store = await preferences.getPreferences(ctx, Settings.PREFS_NAME);
    Settings.showVideoThumbs = await Settings.getBoolean(Settings.SHOW_VIDEO_THUMBNAILS, true);
    Settings.incognitoMode = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
    const fps = await Settings.getInt(Settings.FASTPLAY_SPEED, 20);
    Settings.fastplaySpeed = fps / 10.0;
    let hud = await Settings.getInt(Settings.VIDEO_HUD_TIMEOUT, 4);
    if (hud < 1 || hud > 15) {
      hud = -1;
    }
    Settings.videoHudDelay = hud;
  }

  static async getBoolean(key: string, def: boolean): Promise<boolean> {
    if (!Settings.store) {
      return def;
    }
    const v = await Settings.store.get(key, def);
    return typeof v === 'boolean' ? v : def;
  }

  static async getInt(key: string, def: number): Promise<number> {
    if (!Settings.store) {
      return def;
    }
    const v = await Settings.store.get(key, def);
    return typeof v === 'number' ? v : def;
  }

  static async getFloat(key: string, def: number): Promise<number> {
    if (!Settings.store) {
      return def;
    }
    const v = await Settings.store.get(key, def);
    return typeof v === 'number' ? v : def;
  }

  static async getString(key: string, def: string): Promise<string> {
    if (!Settings.store) {
      return def;
    }
    const v = await Settings.store.get(key, def);
    return typeof v === 'string' ? v : def;
  }

  /** putSingle —— 类型分发写(对齐安卓 putSingle 扩展)。 */
  static async put(key: string, value: boolean | number | string): Promise<void> {
    if (!Settings.store) {
      return;
    }
    await Settings.store.put(key, value);
    await Settings.store.flush();
    if (key === Settings.KEY_INCOGNITO && typeof value === 'boolean') {
      Settings.incognitoMode = value;
    }
    if (key === Settings.SHOW_VIDEO_THUMBNAILS && typeof value === 'boolean') {
      Settings.showVideoThumbs = value;
    }
  }

  static async contains(key: string): Promise<boolean> {
    if (!Settings.store) {
      return false;
    }
    const v = await Settings.store.get(key, undefined);
    return v !== undefined;
  }

  static async remove(key: string): Promise<void> {
    if (!Settings.store) {
      return;
    }
    await Settings.store.delete(key);
    await Settings.store.flush();
  }
}
