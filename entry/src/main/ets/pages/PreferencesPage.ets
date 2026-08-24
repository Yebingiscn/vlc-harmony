import { UiFeedback } from '../common/utils/UiFeedback';

import { PreferenceRow } from '../common/components/PreferenceRow';
import { PreferenceChoiceDialog } from '../common/components/PreferenceChoiceDialog';
import { PreferenceNumberPickerDialog } from './PreferenceNumberPickerDialog';
import { PreferenceMultiSelectDialog } from './PreferenceMultiSelectDialog';
import { PreferenceConfirmDialog } from './PreferenceConfirmDialog';
import { SleepTimerDialog } from './SleepTimerDialog';
import { NavController } from '../common/data/NavController';
import { Settings } from '../common/data/Settings';
import { AppTheme } from '../common/data/AppTheme';
import { PreferenceGroup, PreferenceItem, PreferenceScreen } from '../common/models/PreferenceModels';
import { PreferencesScreenParam } from '../common/models/MediaModels';
import { i18n } from '@kit.LocalizationKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigationMenuItemOptions,
  ScrollEffectType
} from '@kit.UIDesignKit';

/** 字幕/控件颜色调色板(对应 VLC ColorPreferenceCompat 预设)。 */
const COLOR_PALETTE: number[] = [
  0xFFFFFFFF, 0xFF000000, 0xFFFFFF00, 0xFFFF8800, 0xFFFF0000,
  0xFF00FF00, 0xFF00FFFF, 0xFF0000FF, 0xFFFF00FF, 0xFF808080,
];

/**
 * PreferencesPage —— VLC 偏好设置通用引擎(@ComponentV2 NavDestination)。
 * 接收 @Param screenKey;从 buildScreens() 注册表(Map<key,PreferenceScreen>)取 screen;
 * VlcToolbar(标题=screen.title,showBack)+ Scroll{Column{ 分组标题 + ForEach items{ PreferenceRow } }}。
 *
 * 各子 Preferences* 的 screen 数据定义在 buildScreens()(文案/分组/项 key 用 Settings 真实 key,
 * 文案优先 $r('app.string.*');string.json 未覆盖的 key 用字面量字符串,逐字照搬 spec)。
 *
 * 外部运行时契约(startRemoteAccess / VLCInstance.restart / PinCodeActivity / FilePickerActivity 等)
 * 仅标 TODO 注释,不编造实现。
 */
@ComponentV2
export struct PreferencesPage {
  @Param screenKey: string = '';
  @Local title: Resource = $r('app.string.preferences');
  @Local groups: PreferenceGroup[] = [];
  /** key→当前 toggle 值镜像(供 dependency 置灰)。 */
  @Local toggleStates: Record<string, boolean> = {};
  /** 无痕模式是“持续开启”唯一的父开关，单独用响应式状态驱动其可用性。 */
  @Local incognitoEnabled: boolean = false;
  /** “无痕模式持续开启”的持久化值。 */
  @Local persistentIncognitoEnabled: boolean = true;
  /** 弹窗状态:number/multi/text/color 选择器(由 onListSelect/onNumberPicker/...触发)。 */
  @Local sheetOpen: boolean = false;
  @Local sheetKind: string = ''; // '' | 'number' | 'multi' | 'text' | 'color'
  @Local sheetItem: PreferenceItem = new PreferenceItem({});
  @Local textDraft: string = '';
  @Local colorDraft: number = 0;
  /** 当前 list 弹窗的真实选中值，不能再用静态 defaultValue 代替。 */
  @Local listValue: string = '';
  /** 选项确认后重建条目，使摘要立即读取持久化后的值。 */
  @Local rowVersion: number = 0;
  @Local sleepMillis: number = 0;
  @Local sleepWaitMediaEnd: boolean = false;
  @Local sleepResetOnInteraction: boolean = false;
  @Local sleepSheetOpen: boolean = false;
  @Local dialogKind: string = '';
  @Local preferenceDialogId: number = -1;
  /** 禁用确认弹窗:置 false 历史/续播类开关前先确认。独立于 sheetOpen(选择器 sheet)。 */
  @Local confirmSheetOpen: boolean = false;
  @Local confirmItem: PreferenceItem = new PreferenceItem({});

  // ============== 偏好 screen 注册表(逐页照 spec 构建)==============
  static buildScreens(): Map<string, PreferenceScreen> {
    const m: Map<string, PreferenceScreen> = new Map<string, PreferenceScreen>();
    m.set('root', PreferencesPage.rootScreen());
    m.set('ui_category', PreferencesPage.uiScreen());
    m.set('video_category', PreferencesPage.videoScreen());
    m.set('subtitles_category', PreferencesPage.subtitlesScreen());
    m.set('audio_category', PreferencesPage.audioScreen());
    m.set('casting_category', PreferencesPage.castingScreen());
    m.set('parental_control', PreferencesPage.parentalScreen());
    m.set('remote_access_category', PreferencesPage.remoteAccessScreen());
    m.set('android_auto_category', PreferencesPage.androidAutoScreen());
    m.set('adv_category', PreferencesPage.advancedScreen());
    m.set('audio_controls', PreferencesPage.audioControlsScreen());
    m.set('video_controls', PreferencesPage.videoControlsScreen());
    m.set('optional_features', PreferencesPage.optionalScreen());
    m.set('widgets', PreferencesPage.widgetsScreen());
    return m;
  }

  // ---- root: PreferencesFragment(R.xml.preferences) ----
  static rootScreen(): PreferenceScreen {
    const groups: PreferenceGroup[] = [
      // Media library
      new PreferenceGroup('Media library', [
        new PreferenceItem({
          key: 'directories',
          title: 'Media library folders',
          type: 'nav',
          summary: 'Select directories to include in the media library',
        }),
        new PreferenceItem({
          key: Settings.KEY_MEDIALIBRARY_AUTO_RESCAN,
          title: 'Auto rescan',
          type: 'toggle',
          summary: 'Automatically scan device for new or deleted media at application startup',
          defaultValue: true,
        }),
      ]),
      // Video
      new PreferenceGroup('Video', [
        new PreferenceItem({
          key: Settings.KEY_VIDEO_APP_SWITCH,
          title: 'Background/PiP mode',
          type: 'list',
          summary: 'Select VLC behavior when you switch to other application from video playback',
          defaultValue: '0',
          optionValues: ['0', '1', '2'],
          options: ['Stop', 'Play videos in background', 'Play videos in Picture-in-picture mode'],
        }),
        new PreferenceItem({
          key: 'hardware_acceleration',
          title: 'Hardware Acceleration',
          type: 'list',
          summary: 'Disabled: better stability\nDecoding: may improve performance\nFull: may improve performance further',
          defaultValue: '-1',
          optionValues: ['-1', '0', '1', '2'],
          options: ['Automatic', 'Disabled', 'Decoding acceleration', 'Full acceleration'],
        }),
        new PreferenceItem({
          key: Settings.SCREEN_ORIENTATION,
          title: 'Video screen orientation',
          type: 'list',
          defaultValue: '99',
          optionValues: ['99', '102', '101', '103', '98'],
          options: ['Automatic (sensor)', 'Portrait', 'Landscape', 'Landscape reverse', 'Last locked orientation'],
        }),
      ]),
      // Network
      new PreferenceGroup('Network', [
        new PreferenceItem({
          key: 'metered_connection',
          title: 'Action for streams when the connection is metered',
          type: 'list',
          defaultValue: '0',
          optionValues: ['0', '1', '2'],
          options: ['Do nothing', 'Stop playback', 'Warn me (the warning may be missed for audio playback)'],
        }),
      ]),
      // Permissions
      new PreferenceGroup('Permissions', [
        new PreferenceItem({
          key: 'permissions',
          title: 'Permissions',
          type: 'nav',
          summary: 'List of all the permissions',
        }),
      ]),
      // History
      new PreferenceGroup('History', [
        new PreferenceItem({
          key: Settings.ENABLE_PLAYBACK_HISTORY,
          title: 'Playback history',
          type: 'toggle',
          summary: 'Save all media played in History section',
          defaultValue: true,
        }),
        new PreferenceItem({
          key: Settings.VIDEO_PLAY_QUEUE_HISTORY,
          title: 'Video play queue history',
          type: 'toggle',
          summary: 'Allow saving the video play queue to resume later',
          defaultValue: true,
          dependency: Settings.ENABLE_PLAYBACK_HISTORY,
        }),
        new PreferenceItem({
          key: Settings.AUDIO_PLAY_QUEUE_HISTORY,
          title: 'Audio play queue history',
          type: 'toggle',
          summary: 'Allow saving the audio play queue to resume later',
          defaultValue: true,
          dependency: Settings.ENABLE_PLAYBACK_HISTORY,
        }),
      ]),
      // Extra settings(带图标跳转)
      new PreferenceGroup('Extra settings', [
        new PreferenceItem({
          key: 'ui_category',
          title: 'Interface',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'ui_category'
        }),
        new PreferenceItem({
          key: 'video_category',
          title: 'Video',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'video_category'
        }),
        new PreferenceItem({
          key: 'subtitles_category',
          title: 'Subtitles',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'subtitles_category'
        }),
        new PreferenceItem({
          key: 'audio_category',
          title: 'Audio',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'audio_category'
        }),
        new PreferenceItem({
          key: 'equalizer',
          title: $r('app.string.equalizer'),
          type: 'nav',
          icon: $r('app.media.ic_settings')
        }),
        new PreferenceItem({
          key: 'casting_category',
          title: 'Casting',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'casting_category'
        }),
        new PreferenceItem({
          key: 'parental_control',
          title: $r('app.string.parental_control'),
          type: 'nav',
          icon: $r('app.media.ic_settings')
        }),
        new PreferenceItem({
          key: 'remote_access_category',
          title: 'Remote access',
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'remote_access_category'
        }),
        new PreferenceItem({
          key: 'android_auto_category',
          title: $r('app.string.android_auto'),
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'android_auto_category'
        }),
        new PreferenceItem({
          key: 'adv_category',
          title: $r('app.string.advanced_prefs_category'),
          type: 'nav',
          icon: $r('app.media.ic_settings'),
          targetScreen: 'adv_category'
        }),
      ]),
    ];
    return new PreferenceScreen('root', $r('app.string.preferences'), groups);
  }

  // ---- PreferencesUi ----
  static uiScreen(): PreferenceScreen {
    const root: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.KEY_APP_THEME,
        title: $r('app.string.daynight_title'),
        type: 'list',
        defaultValue: '-1',
        optionValues: ['-1', '1', '2'],
        options: [$r('app.string.follow_system_mode'), $r('app.string.light_theme'),
          $r('app.string.enable_black_theme')],
      }),
      new PreferenceItem({
        key: 'set_locale',
        title: $r('app.string.setting_language'),
        type: 'list',
        defaultValue: 'default',
        optionValues: ['default', 'zh-CN', 'en-US'],
        options: [$r('app.string.locale_follow_system'), $r('app.string.locale_simplified_chinese'),
          $r('app.string.locale_english')],
      }),
      new PreferenceItem({
        key: Settings.LIST_TITLE_ELLIPSIZE,
        title: $r('app.string.list_title_ellipsize'),
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2', '3', '4'],
        options: [
          $r('app.string.ellipsize_default'),
          $r('app.string.ellipsize_left'),
          $r('app.string.ellipsize_right'),
          $r('app.string.ellipsize_middle'),
          $r('app.string.ellipsize_marquee'),
        ],
      }),
      new PreferenceItem({
        key: Settings.KEY_SHOW_HEADERS,
        title: $r('app.string.show_headers'),
        type: 'checkbox',
        summary: $r('app.string.show_headers_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.KEY_INCLUDE_MISSING,
        title: $r('app.string.browser_show_missing_media'),
        type: 'checkbox',
        summary: $r('app.string.browser_show_missing_media_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'default_sleep_timer',
        title: $r('app.string.sleep_title'),
        type: 'click',
        summary: $r('app.string.sleep_timer_disabled')
      }),
      new PreferenceItem({
        key: Settings.KEY_INCOGNITO,
        title: $r('app.string.incognito_mode'),
        type: 'checkbox',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'persistent_incognito',
        title: $r('app.string.persistent_incognito_mode'),
        type: 'checkbox',
        summary: $r('app.string.persistent_incognito_mode_summary'),
        defaultValue: true,
        dependency: Settings.KEY_INCOGNITO
      }),
    ];
    const video: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.KEY_MEDIA_SEEN,
        title: $r('app.string.media_seen'),
        type: 'checkbox',
        summary: $r('app.string.media_seen_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.SHOW_VIDEO_THUMBNAILS,
        title: $r('app.string.show_video_thumbnails'),
        type: 'checkbox',
        summary: $r('app.string.show_video_thumbnails_summary'),
        defaultValue: true
      }),
    ];
    const audio: PreferenceItem[] = [
      new PreferenceItem({
        key: 'audio_resume_card',
        title: $r('app.string.audio_resume_card_title'),
        type: 'checkbox',
        summary: $r('app.string.audio_resume_card_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'lockscreen_cover',
        title: $r('app.string.lockscreen_cover_title'),
        type: 'checkbox',
        summary: $r('app.string.lockscreen_cover_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'show_seek_in_compact_notification',
        title: $r('app.string.show_seek_in_compact_notif_title'),
        type: 'checkbox',
        summary: $r('app.string.show_seek_in_compact_notif_summary'),
        defaultValue: false
      }),
    ];
    return new PreferenceScreen('ui_category', $r('app.string.interface_prefs_screen'), [
      new PreferenceGroup('', root),
      new PreferenceGroup($r('app.string.video'), video),
      new PreferenceGroup($r('app.string.audio'), audio),
    ]);
  }

  // ---- PreferencesVideo ----
  static videoScreen(): PreferenceScreen {
    const top: PreferenceItem[] = [
      new PreferenceItem({
        key: 'always_fast_seek',
        title: '总是使用快速定位',
        type: 'checkbox',
        summary: '定位速度更快，但可能不够精确',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'popup_force_legacy',
        title: '使用自定义画中画弹窗',
        type: 'checkbox',
        summary: '使用大小可调整的自定义画中画弹出窗口',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'restore_background_video',
        title: '恢复后台播放的视频',
        type: 'checkbox',
        summary: '重新打开 VLC for Android 时恢复后台播放的视频',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'video_match_frame_rate',
        title: '匹配显示器帧率',
        type: 'checkbox',
        summary: '使显示刷新率与媒体帧率相匹配。例如，24p (每秒24帧、逐行扫描) 的影片会以 24p 刷新率播放',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'preferred_resolution',
        title: '首选视频分辨率',
        type: 'list',
        summary: '流媒体有多种格式可选时，自动选择的视频质量上限为:',
        defaultValue: '-1',
        optionValues: ['-1', '1080', '720', '480', '360', '240'],
        options: ['可用的最高画质', '全高清 (1080p)', '高清 (720p)', '标清 (480p)', '低清 (360p)', '极低画质 (240p)'],
      }),
    ];
    const secondary: PreferenceItem[] = [
      new PreferenceItem({
        key: 'secondary_display_category_summary',
        title: '',
        type: 'info',
        summary: '连接外部显示器时的设置 (HDMI/Chromecast)'
      }),
      new PreferenceItem({
        key: 'enable_clone_mode',
        title: '克隆优先',
        type: 'checkbox',
        summary: '克隆设备屏幕，不使用遥控功能',
        defaultValue: false
      }),
    ];
    return new PreferenceScreen('video_category', '视频', [
      new PreferenceGroup('', top),
      new PreferenceGroup('外置显示器', secondary),
    ]);
  }

  // ---- PreferencesSubtitles ----
  static subtitlesScreen(): PreferenceScreen {
    const rootItems: PreferenceItem[] = [
      new PreferenceItem({
        key: 'subtitles_presets',
        title: 'Subtitles presets',
        type: 'list',
        defaultValue: '-1',
        optionValues: ['0', '1', '2', '3', '4', '5'],
        options: ['Default', 'Large text', 'Largest text and contrast', 'With background', 'Yellow',
          'Yellow with background']
      }),
      new PreferenceItem({
        key: 'subtitles_autoload',
        title: 'Auto load subtitles',
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'subtitle_text_encoding',
        title: 'Subtitle text encoding',
        type: 'list',
        defaultValue: '',
        optionValues: ['', 'UTF-8', 'UTF-16', 'GB18030', 'Windows-1252', 'KOI8-R', 'Big5'],
        options: ['Default (Windows-1252)', 'Universal (UTF-8)', 'Universal (UTF-16)', 'Universal, Chinese (GB18030)',
          'Western European (Windows-1252)', 'Russian (KOI8-R)', 'Traditional Chinese (Big5)']
      }),
      new PreferenceItem({
        key: 'subtitle_preferred_language',
        title: 'Preferred subtitle language',
        type: 'list',
        summary: 'No language preference',
        defaultValue: ''
      }),
    ];
    const fontStyle: PreferenceItem[] = [
      new PreferenceItem({
        key: 'subtitles_size',
        title: 'Subtitles Size',
        type: 'list',
        defaultValue: '16',
        optionValues: ['40', '32', '25', '19', '16', '13', '10'],
        options: ['Nano', 'Micro', 'Smallest', 'Small', 'Normal', 'Big', 'Huge']
      }),
      new PreferenceItem({
        key: 'subtitles_bold',
        title: 'Bold subtitles',
        type: 'toggle',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'subtitles_color',
        title: 'Color',
        type: 'color',
        defaultValue: 0xFFFFFFFF
      }),
      new PreferenceItem({
        key: 'subtitles_color_opacity',
        title: $r('app.string.opacity'),
        type: 'seekbar',
        min: 50,
        max: 255,
        defaultValue: 255,
        step: 1
      }),
    ];
    const bg: PreferenceItem[] = [
      new PreferenceItem({
        key: 'subtitles_background',
        title: 'Subtitles Background',
        type: 'toggle',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'subtitles_background_color',
        title: 'Color',
        type: 'color',
        defaultValue: 0xFF000000,
        dependency: 'subtitles_background'
      }),
      new PreferenceItem({
        key: 'subtitles_background_color_opacity',
        title: $r('app.string.opacity'),
        type: 'seekbar',
        min: 0,
        max: 255,
        defaultValue: 255,
        step: 1,
        dependency: 'subtitles_background'
      }),
    ];
    const shadow: PreferenceItem[] = [
      new PreferenceItem({
        key: 'subtitles_shadow',
        title: 'Subtitles shadow',
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'subtitles_shadow_color',
        title: 'Color',
        type: 'color',
        defaultValue: 0xFF000000,
        dependency: 'subtitles_shadow'
      }),
      new PreferenceItem({
        key: 'subtitles_shadow_color_opacity',
        title: $r('app.string.opacity'),
        type: 'seekbar',
        min: 0,
        max: 255,
        defaultValue: 128,
        step: 1,
        dependency: 'subtitles_shadow'
      }),
    ];
    const outline: PreferenceItem[] = [
      new PreferenceItem({
        key: 'subtitles_outline',
        title: 'Subtitles outline',
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'subtitles_outline_color',
        title: 'Color',
        type: 'color',
        defaultValue: 0xFF000000,
        dependency: 'subtitles_outline'
      }),
      new PreferenceItem({
        key: 'subtitles_outline_color_opacity',
        title: $r('app.string.opacity'),
        type: 'seekbar',
        min: 0,
        max: 255,
        defaultValue: 255,
        step: 1,
        dependency: 'subtitles_outline'
      }),
    ];
    return new PreferenceScreen('subtitles_category', 'Subtitles', [
      new PreferenceGroup('', rootItems),
      new PreferenceGroup('Subtitles font style', fontStyle),
      new PreferenceGroup('Subtitles Background', bg),
      new PreferenceGroup('Subtitles shadow', shadow),
      new PreferenceGroup('Subtitles outline', outline),
    ]);
  }

  // ---- PreferencesAudio ----
  static audioScreen(): PreferenceScreen {
    const top: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.RESUME_PLAYBACK,
        title: '通话结束后继续播放',
        type: 'toggle',
        summary: '否则保持暂停',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'audio_task_removed',
        title: '滑开应用时停止',
        type: 'toggle',
        summary: '应用程序被滑开时停止播放',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'audio_digital_output',
        title: '数字音频输出 (直通)',
        type: 'toggle',
        summary: '音频数字输出已禁用',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'audio_preferred_language',
        title: '偏好的音频语言',
        type: 'list',
        defaultValue: '',
        optionValues: ['', 'zh-CN', 'en-US'],
        options: ['无语言偏好', '简体中文', 'English']
      }),
      new PreferenceItem({
        key: Settings.KEY_AUDIO_CONFIRM_RESUME,
        title: '继续播放音频',
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2'],
        options: ['总是', '不要', '要求确认']
      }),
    ];
    const headset: PreferenceItem[] = [
      new PreferenceItem({
        key: 'enable_headset_detection',
        title: '启用耳机侦测',
        type: 'toggle',
        summary: '检测耳机的插入和拔出',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'enable_play_on_headset_insertion',
        title: '在插入耳机后继续播放',
        type: 'toggle',
        summary: '否则暂停',
        defaultValue: false,
        dependency: 'enable_headset_detection'
      }),
      new PreferenceItem({
        key: 'ignore_headset_media_button_presses',
        title: '忽略耳机媒体按钮的动作',
        type: 'toggle',
        summary: '例如正在使用的耳机物理按键损坏，这种情况下会用到该选项',
        defaultValue: false
      }),
    ];
    const replay: PreferenceItem[] = [
      new PreferenceItem({
        key: 'audio-replay-gain-enable',
        title: '启用回放增益',
        type: 'toggle',
        summary: '由于默认增益的作用，对于没有回放增益信息的音频流，其音量可能会略低于其他音频流',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'audio-replay-gain-mode',
        title: '回放增益模式',
        type: 'list',
        summary: '｢音轨模式｣ 会以相同的响度播放所有带有回放增益信息的音频流。而 ｢专辑模式｣ 将保留同一张专辑内各音轨的相对响度。',
        defaultValue: 'track',
        optionValues: ['track', 'album'],
        options: ['音轨模式', '专辑模式'],
        dependency: 'audio-replay-gain-enable'
      }),
      new PreferenceItem({
        key: 'audio-replay-gain-preamp',
        title: '回放前置放大',
        type: 'text',
        summary: '为带有回放增益信息的音频流更改默认的目标电平 (89 dB)',
        defaultValue: '0.0',
        dependency: 'audio-replay-gain-enable'
      }),
      new PreferenceItem({
        key: 'audio-replay-gain-default',
        title: '默认回放增益',
        type: 'text',
        summary: '适用于没有回放增益信息的音频流\n设为 0 可禁用',
        defaultValue: '-7.0',
        dependency: 'audio-replay-gain-enable'
      }),
      new PreferenceItem({
        key: 'audio-replay-gain-peak-protection',
        title: '峰值保护',
        type: 'toggle',
        summary: '防止爆音',
        defaultValue: true,
        dependency: 'audio-replay-gain-enable'
      }),
    ];
    const advanced: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.AUDIO_DUCKING,
        title: '收到通知时降低 VLC 音量',
        type: 'toggle',
        summary: '有助于听清通知声音、导航语音或辅助功能讲解',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'aout',
        title: '音频输出',
        type: 'list',
        summary: '更改 VLC 输出音频的方式',
        defaultValue: '0',
        optionValues: ['0', '2'],
        options: ['AudioTrack', 'OpenSL ES']
      }),
      new PreferenceItem({
        key: 'soundfont',
        title: 'MIDI 音色库',
        type: 'nav',
        summary: '选择用于播放 MIDI 音轨的 SoundFont 文件'
      }),
    ];
    return new PreferenceScreen('audio_category', '音频', [
      new PreferenceGroup('', top),
      new PreferenceGroup('耳机', headset),
      new PreferenceGroup('回放增益', replay),
      new PreferenceGroup($r('app.string.advanced_prefs_category'), advanced),
    ]);
  }

  // ---- PreferencesCasting ----
  static castingScreen(): PreferenceScreen {
    const items: PreferenceItem[] = [
      new PreferenceItem({
        key: 'enable_casting',
        title: '启用无线投屏',
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'casting_audio_only',
        title: '仅音频',
        type: 'toggle',
        summary: '仅投音频，不投视频',
        defaultValue: false,
        dependency: 'enable_casting'
      }),
      new PreferenceItem({
        key: 'casting_passthrough',
        title: '音频透传',
        type: 'toggle',
        summary: '让电视处理音频渲染',
        defaultValue: false,
        dependency: 'enable_casting'
      }),
      new PreferenceItem({
        key: 'casting_quality',
        title: '转换质量',
        type: 'list',
        summary: '投屏到远程屏幕时的转换质量',
        defaultValue: '2',
        optionValues: ['0', '1', '2', '3'],
        options: ['高', '中', '低', '最低'],
        dependency: 'enable_casting'
      }),
    ];
    return new PreferenceScreen('casting_category', '投屏', [new PreferenceGroup('', items)]);
  }

  // ---- PreferencesParentalControl ----
  static parentalScreen(): PreferenceScreen {
    return new PreferenceScreen('parental_control', $r('app.string.parental_control'), [
      new PreferenceGroup('', [
        new PreferenceItem({
          key: 'change_pin',
          title: $r('app.string.change_password'),
          type: 'nav',
          routeName: 'ParentalControl'
        }),
        new PreferenceItem({
          key: 'restrict_settings',
          title: $r('app.string.restrict_settings_access'),
          type: 'checkbox',
          defaultValue: false
        }),
        new PreferenceItem({
          key: 'safe_mode',
          title: $r('app.string.safe_mode'),
          type: 'checkbox',
          summary: $r('app.string.safe_mode_summary'),
          defaultValue: false
        }),
      ]),
    ]);
  }

  // ---- PreferencesRemoteAccess ----
  static remoteAccessScreen(): PreferenceScreen {
    const top: PreferenceItem[] = [
      new PreferenceItem({
        key: 'enable_remote_access',
        title: $r('app.string.enable_remote_access'),
        type: 'checkbox',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'remote_access_status',
        title: $r('app.string.remote_access_status'),
        type: 'nav',
        summary: $r('app.string.remote_access_status_summary'),
        dependency: 'enable_remote_access'
      }),
    ];
    const content: PreferenceItem[] = [
      new PreferenceItem({
        key: 'remote_access_medialibrary_content',
        title: $r('app.string.remote_access_medialibrary_content'),
        type: 'multiselect',
        defaultValue: '',
        defaultSelected: ['0', '1', '2', '3'],
        optionValues: ['0', '1', '2', '3'],
        options: [$r('app.string.video'), $r('app.string.audio'), $r('app.string.playlists'), $r('app.string.search')],
        dependency: 'enable_remote_access',
      }),
      new PreferenceItem({
        key: 'remote_access_file_browser_content',
        title: $r('app.string.remote_access_file_browser_content'),
        type: 'checkbox',
        defaultValue: false,
        dependency: 'enable_remote_access'
      }),
      new PreferenceItem({
        key: 'remote_access_network_browser_content',
        title: $r('app.string.remote_access_network_browser_content'),
        type: 'checkbox',
        defaultValue: false,
        dependency: 'enable_remote_access'
      }),
      new PreferenceItem({
        key: 'remote_access_history_content',
        title: $r('app.string.history'),
        type: 'checkbox',
        defaultValue: false,
        dependency: 'enable_remote_access'
      }),
      new PreferenceItem({
        key: 'remote_access_playback_control',
        title: $r('app.string.remote_access_playback_control'),
        type: 'checkbox',
        defaultValue: true,
        dependency: 'enable_remote_access'
      }),
      new PreferenceItem({
        key: 'remote_access_logs',
        title: $r('app.string.remote_access_logs'),
        type: 'checkbox',
        defaultValue: false,
        dependency: 'enable_remote_access'
      }),
    ];
    return new PreferenceScreen('remote_access_category', $r('app.string.remote_access'), [
      new PreferenceGroup('', top),
      new PreferenceGroup($r('app.string.remote_access_content'), content),
    ]);
  }

  // ---- PreferencesAndroidAuto ----
  static androidAutoScreen(): PreferenceScreen {
    const iface: PreferenceItem[] = [
      new PreferenceItem({
        key: 'android_auto_title_scale_val',
        title: 'Title text size',
        type: 'seekbar',
        min: 50,
        max: 100,
        defaultValue: 100,
        step: 1
      }),
      new PreferenceItem({
        key: 'android_auto_subtitle_scale_val',
        title: 'Subtitle text size',
        type: 'seekbar',
        min: 50,
        max: 100,
        defaultValue: 100,
        step: 1
      }),
      new PreferenceItem({
        key: 'android_auto_queue_info_pos',
        title: 'Queue information',
        type: 'list',
        defaultValue: '3',
        optionValues: ['0', '1', '2', '3'],
        options: ['Do not show queue position', 'Before title', 'After title', 'Before subtitle']
      }),
      new PreferenceItem({
        key: 'android_auto_queue_format',
        title: 'Queue format',
        type: 'list',
        defaultValue: '1',
        optionValues: ['0', '1'],
        options: ['Queue position', 'Queue position / Queue size']
      }),
    ];
    const controls: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL,
        title: 'Use the global playback speed',
        type: 'toggle',
        summary: 'Use the playback speed set globally for all the tracks.\nIndividual tracks\' playback speed will be ignored.',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'enable_android_auto_speed_buttons',
        title: 'Android Auto playback speed',
        type: 'toggle',
        summary: 'Show speed control in the overflow menu',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'enable_android_auto_seek_buttons',
        title: 'Android Auto seek buttons',
        type: 'toggle',
        summary: 'Show rewind and fast forward in the overflow menu. Try holding steering wheel previous and next buttons before enabling.',
        defaultValue: false
      }),
    ];
    return new PreferenceScreen('android_auto_category', $r('app.string.android_auto'), [
      new PreferenceGroup($r('app.string.interface_prefs_screen'), iface),
      new PreferenceGroup($r('app.string.controls_prefs_category'), controls),
    ]);
  }

  // ---- PreferencesAdvanced ----
  static advancedScreen(): PreferenceScreen {
    const rootItems: PreferenceItem[] = [
      new PreferenceItem({
        key: 'network_caching',
        title: $r('app.string.network_caching'),
        type: 'text',
        summary: $r('app.string.network_caching_summary'),
        defaultValue: '0',
        maxLength: 5
      }),
      new PreferenceItem({
        key: 'prefer_smbv1',
        title: 'Prefer SMB 1',
        type: 'toggle',
        summary: 'Uncheck this setting if you have some difficulties browsing your SMB server',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.HTTP_USER_AGENT,
        title: 'HTTP user agent',
        type: 'text',
        defaultValue: ''
      }),
      new PreferenceItem({ key: 'quit_app', title: $r('app.string.quit'), type: 'click' }),
    ];
    const appData: PreferenceItem[] = [
      new PreferenceItem({
        key: 'dump_media_db',
        title: 'Dump media database',
        type: 'click',
        summary: $r('app.string.dump_media_db_summary')
      }),
      new PreferenceItem({
        key: 'dump_app_db',
        title: 'Dump app database',
        type: 'click',
        summary: $r('app.string.dump_media_db_summary')
      }),
      new PreferenceItem({
        key: 'clear_media_db',
        title: $r('app.string.clear_media_db'),
        type: 'click',
        summary: $r('app.string.clear_media_database_summary')
      }),
      new PreferenceItem({
        key: 'clear_app_data',
        title: $r('app.string.clear_app_data'),
        type: 'click',
        summary: $r('app.string.clear_app_data_summary')
      }),
      new PreferenceItem({ key: 'clear_history', title: $r('app.string.clear_playback_history'), type: 'click' }),
      new PreferenceItem({
        key: 'export_settings',
        title: $r('app.string.export_settings'),
        type: 'click',
        summary: $r('app.string.export_settings_summary')
      }),
      new PreferenceItem({
        key: 'restore_settings',
        title: $r('app.string.restore_settings'),
        type: 'click',
        summary: $r('app.string.restore_settings_summary')
      }),
    ];
    const performance: PreferenceItem[] = [
      new PreferenceItem({
        key: 'enable_time_stretching_audio',
        title: $r('app.string.enable_time_stretching_audio'),
        type: 'toggle',
        summary: $r('app.string.enable_time_stretching_audio_summary'),
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'opengl',
        title: $r('app.string.opengl_title'),
        type: 'list',
        summary: $r('app.string.opengl_summary'),
        defaultValue: '-1',
        optionValues: ['-1', '1', '0'],
        options: ['Automatic', 'Force On', 'Force Off']
      }),
      new PreferenceItem({
        key: 'aout',
        title: 'Audio output',
        type: 'list',
        summary: '',
        defaultValue: '0',
        optionValues: ['0', '2'],
        options: ['AudioTrack', 'OpenSL ES']
      }),
      new PreferenceItem({
        key: 'deblocking',
        title: $r('app.string.deblocking'),
        type: 'list',
        summary: $r('app.string.deblocking_summary'),
        defaultValue: '-1',
        optionValues: ['-1', '0', '1', '3', '4'],
        options: ['Automatic', 'Full deblocking (slowest)', 'Medium deblocking', 'Low deblocking',
          'No deblocking (fastest)']
      }),
      new PreferenceItem({
        key: 'enable_frame_skip',
        title: $r('app.string.enable_frame_skip'),
        type: 'toggle',
        summary: $r('app.string.enable_frame_skip_summary'),
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'dav1d_thread_number',
        title: 'Dav1d thread number',
        type: 'text',
        defaultValue: ''
      }),
      new PreferenceItem({
        key: 'quick_play',
        title: 'Browser quick play menu',
        type: 'toggle',
        summary: '',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'quick_play_default',
        title: 'Quick play as default action',
        type: 'toggle',
        summary: '',
        defaultValue: false,
        dependency: 'quick_play'
      }),
    ];
    const developer: PreferenceItem[] = [
      new PreferenceItem({
        key: 'enable_verbose_mode',
        title: $r('app.string.enable_verbose_mode'),
        type: 'toggle',
        summary: $r('app.string.enable_verbose_mode_summary'),
        defaultValue: true
      }),
      new PreferenceItem({ key: 'debug_logs', title: $r('app.string.debug_logs'), type: 'click' }),
      new PreferenceItem({ key: 'nightly_install', title: $r('app.string.install_nightly'), type: 'click' }),
      new PreferenceItem({
        key: Settings.KEY_SHOW_UPDATE,
        title: $r('app.string.update_nightly'),
        type: 'toggle',
        summary: $r('app.string.update_nightly_summary'),
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'custom_libvlc_options',
        title: $r('app.string.custom_libvlc_options'),
        type: 'text',
        defaultValue: ''
      }),
    ];
    return new PreferenceScreen('adv_category', $r('app.string.advanced_prefs_category'), [
      new PreferenceGroup('', rootItems),
      new PreferenceGroup($r('app.string.prefs_app_data'), appData),
      new PreferenceGroup($r('app.string.performance_prefs_category'), performance),
      new PreferenceGroup($r('app.string.developer_prefs_category'), developer),
    ]);
  }

  // ---- PreferencesAudioControls ----
  static audioControlsScreen(): PreferenceScreen {
    const controls: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.KEY_AUDIO_JUMP_DELAY,
        title: 'Forward/backward time delay',
        type: 'numberpicker',
        summary: '10 seconds',
        defaultValue: 10,
        numberMin: 1,
        numberMax: 100
      }),
      new PreferenceItem({
        key: Settings.KEY_AUDIO_LONG_JUMP_DELAY,
        title: 'Long tap forward/backward time delay',
        type: 'numberpicker',
        summary: '20 seconds',
        defaultValue: 20,
        numberMin: 1,
        numberMax: 100
      }),
      new PreferenceItem({
        key: Settings.KEY_AUDIO_FORCE_SHUFFLE,
        title: 'Force shuffle',
        type: 'toggle',
        summary: 'Force shuffling when launching a playback',
        defaultValue: false
      }),
    ];
    const iface: PreferenceItem[] = [
      new PreferenceItem({
        key: 'blurred_cover_background',
        title: 'Blurred cover background',
        type: 'toggle',
        summary: 'Blurred cover in audio player background',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.ALBUMS_SHOW_TRACK_NUMBER,
        title: 'Show track numbers',
        type: 'toggle',
        defaultValue: false
      }),
      new PreferenceItem({
        key: 'audio_show_chapter_buttons',
        title: 'Show chapter buttons',
        type: 'toggle',
        summary: 'Show buttons to navigate between chapters',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'audio_show_bookmark_buttons',
        title: $r('app.string.show_bookmark_buttons'),
        type: 'toggle',
        summary: $r('app.string.show_bookmark_buttons_summary'),
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'audio_show_bookmark_markers',
        title: $r('app.string.show_bookmark_markers'),
        type: 'toggle',
        summary: $r('app.string.show_bookmark_markers_summary'),
        defaultValue: true,
        dependency: 'audio_show_bookmark_buttons'
      }),
    ];
    return new PreferenceScreen('audio_controls', $r('app.string.controls_prefs_category'), [
      new PreferenceGroup($r('app.string.controls_prefs_category'), controls),
      new PreferenceGroup($r('app.string.interface_prefs_screen'), iface),
    ]);
  }

  // ---- PreferencesVideoControls ----
  static videoControlsScreen(): PreferenceScreen {
    const top: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.KEY_AUDIO_BOOST,
        title: 'Audio-boost',
        type: 'toggle',
        summary: 'Allow volume up to 200%',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'save_individual_audio_delay',
        title: 'Save audio delay',
        type: 'toggle',
        summary: 'Save individual audio delay for each video',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.KEY_VIDEO_CONFIRM_RESUME,
        title: 'Resume played videos',
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2'],
        options: ['Always', 'Never', 'Ask confirmation']
      }),
    ];
    const gestures: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.ENABLE_VOLUME_GESTURE,
        title: 'Volume gesture',
        type: 'toggle',
        summary: 'Control volume by gesture during video playback',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.ENABLE_BRIGHTNESS_GESTURE,
        title: 'Brightness gesture',
        type: 'toggle',
        summary: 'Control brightness by gesture during video playback',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.SAVE_BRIGHTNESS,
        title: 'Save brightness level',
        type: 'toggle',
        summary: 'Keep brightness level between media',
        defaultValue: false
      }),
      new PreferenceItem({
        key: Settings.ENABLE_SWIPE_SEEK,
        title: 'Swipe to seek',
        type: 'toggle',
        summary: 'Swipe your finger across the screen to seek',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.ENABLE_SCALE_GESTURE,
        title: 'Two finger zoom',
        type: 'toggle',
        summary: 'Zoom in and out with two fingers',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.ENABLE_DOUBLE_TAP_SEEK,
        title: 'Double tap to seek',
        type: 'toggle',
        summary: 'Double tap on screen edges to seek by 10 seconds',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.KEY_VIDEO_DOUBLE_TAP_JUMP_DELAY,
        title: 'Double tap time delay',
        type: 'numberpicker',
        summary: '10 seconds',
        defaultValue: 10,
        numberMin: 1,
        numberMax: 100,
        dependency: Settings.ENABLE_DOUBLE_TAP_SEEK
      }),
      new PreferenceItem({
        key: Settings.ENABLE_DOUBLE_TAP_PLAY,
        title: 'Double tap to play/pause',
        type: 'toggle',
        summary: 'Double tap on screen center to play or pause',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'screenshot_mode',
        title: 'Take a screenshot',
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2', '3'],
        options: ['Disabled', 'Show the screenshot button', 'Tap with 3 fingers', 'Button and gesture']
      }),
      new PreferenceItem({
        key: Settings.ENABLE_FASTPLAY,
        title: 'Enable Fastplay',
        type: 'toggle',
        summary: 'Tap and hold to increase the playback speed',
        defaultValue: false
      }),
      new PreferenceItem({
        key: Settings.FASTPLAY_SPEED,
        title: 'Fastplay speed',
        type: 'seekbar',
        min: 11,
        max: 80,
        defaultValue: 20,
        step: 1,
        dependency: Settings.ENABLE_FASTPLAY
      }),
    ];
    const player: PreferenceItem[] = [
      new PreferenceItem({
        key: Settings.ENABLE_SEEK_BUTTONS,
        title: 'Seek buttons',
        type: 'toggle',
        summary: 'Show rewind and fast forward buttons on the video interface',
        defaultValue: false
      }),
      new PreferenceItem({
        key: Settings.KEY_VIDEO_JUMP_DELAY,
        title: 'Forward/backward time delay',
        type: 'numberpicker',
        summary: '10 seconds',
        defaultValue: 10,
        numberMin: 1,
        numberMax: 100,
        dependency: Settings.ENABLE_SEEK_BUTTONS
      }),
      new PreferenceItem({
        key: Settings.KEY_VIDEO_LONG_JUMP_DELAY,
        title: 'Long tap forward/backward time delay',
        type: 'numberpicker',
        summary: '20 seconds',
        defaultValue: 20,
        numberMin: 1,
        numberMax: 100,
        dependency: Settings.ENABLE_SEEK_BUTTONS
      }),
      new PreferenceItem({
        key: 'popup_keepscreen',
        title: 'Keep screen ON in Pop-Up mode',
        type: 'toggle',
        summary: 'Always keep screen ON while Pop-Up is displayed, even if video is paused.',
        defaultValue: false
      }),
      new PreferenceItem({
        key: Settings.VIDEO_HUD_TIMEOUT,
        title: 'Video player controls hiding delay',
        type: 'seekbar',
        min: 1,
        max: 16,
        defaultValue: 4,
        step: 1
      }),
      new PreferenceItem({
        key: Settings.VIDEO_TRANSITION_SHOW,
        title: 'Videos transition',
        type: 'toggle',
        summary: 'Show new video title on transition',
        defaultValue: true
      }),
      new PreferenceItem({
        key: Settings.LOCK_USE_SENSOR,
        title: 'Lock with sensor',
        type: 'toggle',
        summary: 'When the orientation is locked, use the sensor to allow the reverse orientation',
        defaultValue: true
      }),
    ];
    return new PreferenceScreen('video_controls', $r('app.string.controls_prefs_category'), [
      new PreferenceGroup('', top),
      new PreferenceGroup('Gestures', gestures),
      new PreferenceGroup('Player controls', player),
    ]);
  }

  // ---- PreferencesOptional ----
  static optionalScreen(): PreferenceScreen {
    // FeatureFlag 枚举当前无条目 → 列表为空(数据驱动结构,下游补枚举即自动出现)。TODO(契约)
    return new PreferenceScreen('optional_features', $r('app.string.optional_features_warning'), [
      new PreferenceGroup('', []),
    ]);
  }

  // ---- PreferencesWidgets ----
  static widgetsScreen(): PreferenceScreen {
    const items: PreferenceItem[] = [
      new PreferenceItem({
        key: 'widget_theme',
        title: $r('app.string.widget_theme'),
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2'],
        options: ['Material You (pulls colors from wallpaper)', 'Palette (pulls colors from the media cover)', 'Custom']
      }),
      new PreferenceItem({
        key: 'widget_type',
        title: 'Widget type',
        type: 'list',
        defaultValue: '0',
        optionValues: ['0', '1', '2', '3', '4'],
        options: ['Automatic', 'Pill', 'Normal', 'Circle', 'Large']
      }),
      new PreferenceItem({
        key: 'widget_light_theme',
        title: 'Light theme',
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'opacity',
        title: $r('app.string.opacity'),
        type: 'seekbar',
        min: 0,
        max: 100,
        defaultValue: 100,
        step: 1
      }),
      new PreferenceItem({
        key: 'background_color',
        title: $r('app.string.widget_background'),
        type: 'color',
        defaultValue: 0xFF000000
      }),
      new PreferenceItem({
        key: 'foreground_color',
        title: $r('app.string.widget_foreground'),
        type: 'color',
        defaultValue: 0xFF000000
      }),
      new PreferenceItem({
        key: 'widget_show_cover',
        title: $r('app.string.widget_show_cover'),
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'widget_show_seek',
        title: $r('app.string.widget_show_seek'),
        type: 'toggle',
        defaultValue: true
      }),
      new PreferenceItem({
        key: 'widget_forward_delay',
        title: $r('app.string.widget_forward_delay'),
        type: 'numberpicker',
        defaultValue: 10,
        numberMin: 1,
        numberMax: 100
      }),
      new PreferenceItem({
        key: 'widget_rewind_delay',
        title: $r('app.string.widget_rewind_delay'),
        type: 'numberpicker',
        defaultValue: 10,
        numberMin: 1,
        numberMax: 100
      }),
      new PreferenceItem({
        key: 'widget_show_configure',
        title: $r('app.string.widget_show_configure'),
        type: 'toggle',
        summary: $r('app.string.widget_show_configure_summary'),
        defaultValue: false
      }),
    ];
    return new PreferenceScreen('widgets', $r('app.string.widget_preferences'), [
      new PreferenceGroup($r('app.string.widget_theme'), items),
    ]);
  }

  aboutToAppear(): void {
    const registry: Map<string, PreferenceScreen> = PreferencesPage.buildScreens();
    const screen: PreferenceScreen | undefined = registry.get(this.screenKey);
    if (screen) {
      this.title = screen.title as Resource;
      this.groups = screen.groups;
    } else {
      // 默认根设置页
      const root: PreferenceScreen | undefined = registry.get('root');
      if (root) {
        this.title = root.title as Resource;
        this.groups = root.groups;
      }
    }
    this.loadToggleStates();
    this.loadSleepTimerSummary();
  }

  loadSleepTimerSummary(): void {
    if (!this.isInterfaceScreen()) {
      return;
    }
    Settings.getInt(Settings.SLEEP_TIMER_MILLIS, 0).then((millis: number) => {
      Settings.getBoolean(Settings.SLEEP_TIMER_WAIT_MEDIA_END, false).then((waitForMediaEnd: boolean) => {
        Settings.getBoolean(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, false).then((resetOnInteraction: boolean) => {
          for (const group of this.groups) {
            for (const item of group.items) {
              if (item.key === 'default_sleep_timer') {
                item.summary = this.sleepSummary(millis, waitForMediaEnd, resetOnInteraction);
                this.rowVersion++;
                return;
              }
            }
          }
        });
      });
    });
  }

  async loadToggleStates(): Promise<void> {
    // 预读所有 toggle 项,供 dependency 行 enabled 判定。
    const map: Record<string, boolean> = {};
    for (const g of this.groups) {
      for (const it of g.items) {
        if (it.type === 'toggle' || it.type === 'checkbox') {
          map[it.key] =
            await Settings.getBoolean(it.key, typeof it.defaultValue === 'boolean' ? it.defaultValue : false);
        }
      }
    }
    this.toggleStates = map;
    this.incognitoEnabled = map[Settings.KEY_INCOGNITO] === true;
    this.persistentIncognitoEnabled = map['persistent_incognito'] === true;
  }

  dependencyEnabledFor(item: PreferenceItem): boolean {
    if (!item.dependency) {
      return true;
    }
    if (item.dependency === Settings.KEY_INCOGNITO) {
      return this.incognitoEnabled;
    }
    if (item.dependency === Settings.ENABLE_PLAYBACK_HISTORY) {
      return this.toggleStates[Settings.ENABLE_PLAYBACK_HISTORY] !== true;
    }
    return this.toggleStates[item.dependency] === true;
  }

  isInterfaceScreen(): boolean {
    return this.screenKey === 'ui_category';
  }

  /** 按 screen + item.key 决定该行下方是否显示分割线。 */
  shouldShowDivider(item: PreferenceItem): boolean {
    if (this.isInterfaceScreen()) {
      return false;
    }
    if (this.screenKey === 'video_category') {
      return item.key === 'preferred_resolution';
    }
    if (this.screenKey === 'casting_category') {
      return false;
    }
    if (this.screenKey === 'remote_access_category') {
      return item.key === 'remote_access_status';
    }
    return true;
  }

  groupIndex(group: PreferenceGroup): number {
    return this.groups.indexOf(group);
  }

  private createTitleMenuItem(icon: ResourceStr, label: ResourceStr,
    action: () => void): HdsNavigationMenuItemOptions {
    return {
      content: {
        icon: icon,
        label: label,
        action: action
      }
    };
  }

  private titleMenuItems(): HdsNavigationMenuItemOptions[] {
    return [
      this.createTitleMenuItem($r('app.media.ic_search'), '搜索',
        () => UiFeedback.showToast({ message: '搜索功能暂未实现' }))
    ];
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll() {
          Column() {
            Repeat(this.groups).each((groupRepeatItem: RepeatItem<PreferenceGroup>) => {
              // 分组标题(靠左)
              if (groupRepeatItem.item.title &&
                (!this.isInterfaceScreen() || this.groupIndex(groupRepeatItem.item) > 0)) {
                Text(groupRepeatItem.item.title)
                  .fontSize(this.isInterfaceScreen() ? 18 : 14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.orange500'))
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .padding({
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: 8,
                  })
              }
              Column() {
                Repeat(groupRepeatItem.item.items).each((itemRepeatItem: RepeatItem<PreferenceItem>) => {
                  if (itemRepeatItem.item.key === 'persistent_incognito') {
                    this.persistentIncognitoRow(itemRepeatItem.item)
                  } else {
                    PreferenceRow({
                      item: itemRepeatItem.item,
                      dependencyEnabled: this.dependencyEnabledFor(itemRepeatItem.item),
                      showTrailingIndicator: !this.isInterfaceScreen(),
                      verticalPadding: this.isInterfaceScreen() ? 16 : 14,
                      showDivider: itemRepeatItem.index < groupRepeatItem.item.items.length - 1,
                      onNav: (it: PreferenceItem) => this.onNav(it),
                      onListSelect: (it: PreferenceItem) => this.onListSelect(it),
                      onNumberPicker: (it: PreferenceItem) => this.onNumberPicker(it),
                      onMultiselect: (it: PreferenceItem) => this.onMultiselect(it),
                      onTextEdit: (it: PreferenceItem) => this.onTextEdit(it),
                      onColorPick: (it: PreferenceItem) => this.onColorPick(it),
                      onToggleChange: (it: PreferenceItem, newVal: boolean) => this.onToggleChange(it, newVal),
                    })
                  }
                }).key((item: PreferenceItem) => `${item.key}-${this.rowVersion}-${this.dependencyEnabledFor(item)}`)
              }
              .borderRadius(20)
              .backgroundColor($r('app.color.card_background'))
              .clip(true)
              .margin({ left: 12, right: 12, bottom: 16 })
            }).key((_group: PreferenceGroup, idx: number) => `${idx}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 24 })
        }
        .clip(false)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .bindSheet(this.sheetOpen, this.preferenceSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          onDisappear: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_primary'))
      .bindSheet(this.confirmSheetOpen, this.confirmSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        onDisappear: () => {
          this.confirmSheetOpen = false;
        },
      })
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      padding: {
        start: LengthMetrics.vp(5),
        end: LengthMetrics.vp(5)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.title
        },
        backIcon: {
          icon: $r('app.media.ic_arrow_back'),
          label: '返回',
          action: () => NavController.pop()
        },
        menu: {
          value: this.titleMenuItems(),
          maxCount: 3
        },
        divider: {
          showType: DividerShowType.AUTO
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindSheet(this.sleepSheetOpen, this.sleepTimerSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: $r('app.color.background_default'),
      onDisappear: () => this.sleepSheetOpen = false,
    })
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  /** nav/click 跳转:有 targetScreen → push PreferencesPage(targetScreen);否则 toast。 */
  onNav(item: PreferenceItem): void {
    if (item.key === 'default_sleep_timer') {
      this.openSleepTimer(item);
      return;
    }
    if (item.routeName && item.routeName.length > 0) {
      NavController.push(item.routeName);
      return;
    }
    if (item.targetScreen && item.targetScreen.length > 0) {
      const p: PreferencesScreenParam = { screenKey: item.targetScreen };
      NavController.push('Preferences', p);
    } else {
      // 外部契约跳转(directories / equalizer 等)。TODO(契约)
      UiFeedback.showToast({ message: item.key });
    }
  }

  /**
   * toggle/checkbox 切换拦截:当 key 属于「禁用需确认」集合(历史/续播)且即将置 false 时,
   * 先弹 PreferenceConfirmDialog 确认;确认后再 Settings.put(key,false);取消则不改。
   * 其它情况返回 false 交由 PreferenceRow 直接 put,但需同步 toggleStates 镜像使 dependency 即时生效。
   */
  onToggleChange(item: PreferenceItem, newValue: boolean): boolean {
    const confirmKeys: string[] = [Settings.ENABLE_PLAYBACK_HISTORY];
    if (!newValue && confirmKeys.indexOf(item.key) >= 0) {
      this.confirmItem = item;
      this.confirmSheetOpen = true;
      return true; // 已接管,本行不自动 put。
    }
    // PreferenceRow 会自行持久化普通开关；这里同步页面的依赖镜像，
    // 让依赖 KEY_INCOGNITO 的“无痕模式持续开启”在本次点击后立即启用或置灰。
    const states: Record<string, boolean> = this.toggleStates;
    states[item.key] = newValue;
    this.toggleStates = states;
    if (item.key === Settings.KEY_INCOGNITO) {
      this.incognitoEnabled = newValue;
    }
    // 新建对象触发 @Local 重渲染(同引用赋值不会触发),dependency 置灰即时生效。
    this.toggleStates = this.updateToggleState(item.key, newValue);
    return false; // 未接管,PreferenceRow 直接 put。
  }

  @Builder
  persistentIncognitoRow(item: PreferenceItem) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontColor(this.incognitoEnabled ? $r('app.color.list_title') : $r('app.color.grey700'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.summary) {
          Text(item.summary)
            .fontSize(12)
            .fontColor($r('app.color.list_subtitle'))
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.setPersistentIncognito(!this.persistentIncognitoEnabled))

      Toggle({ type: ToggleType.Checkbox, isOn: this.persistentIncognitoEnabled })
        .selectedColor($r('app.color.orange500'))
        .enabled(this.incognitoEnabled)
        .onChange((enabled: boolean) => this.setPersistentIncognito(enabled))
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 18,
      bottom: 18
    })
    .alignItems(VerticalAlign.Center)
    .opacity(this.incognitoEnabled ? 1.0 : 0.4)
  }

  /** 确认禁用 → Settings.put(key, false) + 关闭确认弹窗。 */
  confirmDisable(): void {
    Settings.put(this.confirmItem.key, false);
    // 新建对象触发 @Local 重渲染,dependency 置灰即时生效。
    this.toggleStates = this.updateToggleState(this.confirmItem.key, false);
    this.confirmSheetOpen = false;
  }

  /** 取消禁用 → 不改 Settings,仅关闭弹窗。 */
  cancelDisable(): void {
    this.confirmSheetOpen = false;
  }

  /** list 弹单选:用 BottomSheet 单选列表(回写 Settings)。 */
  onListSelect(item: PreferenceItem): void {
    if (!item.options || !item.optionValues || item.options.length === 0) {
      return;
    }
    this.listValue = typeof item.defaultValue === 'string' ? item.defaultValue : '';
    this.sheetItem = item;
    this.openPreferenceDialog('list');
    Settings.getString(item.key, typeof item.defaultValue === 'string' ? item.defaultValue : '')
      .then((value: string) => {
        this.listValue = value;
      });
  }

  /** list 单选确认 → Settings.put(key, 选中 optionValue)。 */
  onListConfirm(value: string): void {
    if (this.sheetItem.key === 'set_locale') {
      // HarmonyOS 会向当前进程分发语言配置更新，无需主动重启应用。
      try {
        i18n.System.setAppPreferredLanguage(this.appPreferredLanguage(value));
      } catch (err) {
        return;
      }
      this.listValue = value;
      Settings.put(this.sheetItem.key, value);
      this.rowVersion++;
      this.closePreferenceDialog();
      return;
    }
    if (this.sheetItem.key === Settings.KEY_APP_THEME) {
      AppTheme.apply(value);
    }
    Settings.put(this.sheetItem.key, value);
    this.listValue = value;
    this.rowVersion++;
    this.closePreferenceDialog();
  }

  openSleepTimer(item: PreferenceItem): void {
    Settings.getInt(Settings.SLEEP_TIMER_MILLIS, 0).then((millis: number) => {
      Settings.getBoolean(Settings.SLEEP_TIMER_WAIT_MEDIA_END, false).then((waitForMediaEnd: boolean) => {
        Settings.getBoolean(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, false).then((resetOnInteraction: boolean) => {
          this.sleepMillis = millis;
          this.sleepWaitMediaEnd = waitForMediaEnd;
          this.sleepResetOnInteraction = resetOnInteraction;
          this.sheetItem = item;
          this.sleepSheetOpen = true;
        });
      });
    });
  }

  onSleepConfirm(millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean): void {
    this.sleepMillis = millis;
    this.sleepWaitMediaEnd = waitForMediaEnd;
    this.sleepResetOnInteraction = resetOnInteraction;
    Settings.put(Settings.SLEEP_TIMER_MILLIS, millis);
    Settings.put(Settings.SLEEP_TIMER_WAIT_MEDIA_END, waitForMediaEnd);
    Settings.put(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, resetOnInteraction);
    this.sheetItem.summary = this.sleepSummary(millis, waitForMediaEnd, resetOnInteraction);
    this.rowVersion++;
    this.sleepSheetOpen = false;
  }

  /** 对齐 Android 的“移除当前项”：清除默认倒计时和关联选项。 */
  onSleepClear(): void {
    this.sleepMillis = 0;
    this.sleepWaitMediaEnd = false;
    this.sleepResetOnInteraction = false;
    Settings.put(Settings.SLEEP_TIMER_MILLIS, 0);
    Settings.put(Settings.SLEEP_TIMER_WAIT_MEDIA_END, false);
    Settings.put(Settings.SLEEP_TIMER_RESET_ON_INTERACTION, false);
    this.sheetItem.summary = this.sleepSummary(0, false, false);
    this.rowVersion++;
    this.sleepSheetOpen = false;
  }

  openPreferenceDialog(kind: string): void {
    this.dialogKind = kind;
    try {
      this.getUIContext()
        .getPromptAction()
        .openCustomDialog({
          builder: () => {
            this.preferenceCustomDialog();
          },
          alignment: kind === 'sleep' ? DialogAlignment.Bottom : DialogAlignment.Center,
          autoCancel: true,
          maskColor: $r('app.color.dialog_mask'),
          backgroundColor: Color.Transparent,
        })
        .then((dialogId: number) => {
          this.preferenceDialogId = dialogId;
        })
        .catch(() => {
          this.preferenceDialogId = -1;
        });
    } catch (error) {
      this.preferenceDialogId = -1;
    }
  }

  closePreferenceDialog(): void {
    if (this.preferenceDialogId >= 0) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(this.preferenceDialogId);
      } catch (error) {
        // The dialog may already have been dismissed by the system.
      }
    }
    this.preferenceDialogId = -1;
    this.dialogKind = '';
  }

  clearSleepTimer(): void {
    this.onSleepConfirm(0, false, false);
  }

  sleepSummary(millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean): ResourceStr {
    if (millis <= 0) {
      return $r('app.string.sleep_timer_disabled');
    }
    const totalMinutes: number = Math.floor(millis / 60000);
    const hours: number = Math.floor(totalMinutes / 60);
    const minutes: number = totalMinutes % 60;
    const minuteText: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
    if (waitForMediaEnd && resetOnInteraction) {
      return $r('app.string.sleep_timer_summary_wait_reset', hours, minuteText);
    }
    if (waitForMediaEnd) {
      return $r('app.string.sleep_timer_summary_wait', hours, minuteText);
    }
    if (resetOnInteraction) {
      return $r('app.string.sleep_timer_summary_reset', hours, minuteText);
    }
    return $r('app.string.sleep_timer_summary', hours, minuteText);
  }

  onNumberPicker(item: PreferenceItem): void {
    this.sheetItem = item;
    this.sheetKind = 'number';
    this.sheetOpen = true;
  }

  onMultiselect(item: PreferenceItem): void {
    this.sheetItem = item;
    this.openPreferenceDialog('multi');
  }

  onTextEdit(item: PreferenceItem): void {
    this.sheetItem = item;
    this.sheetKind = 'text';
    Settings.getString(item.key, typeof item.defaultValue === 'string' ? item.defaultValue : '').then((v: string) => {
      this.textDraft = v;
    });
    this.sheetOpen = true;
  }

  onColorPick(item: PreferenceItem): void {
    this.sheetItem = item;
    this.sheetKind = 'color';
    Settings.getInt(item.key, typeof item.defaultValue === 'number' ? item.defaultValue : 0).then((v: number) => {
      this.colorDraft = v;
    });
    this.sheetOpen = true;
  }

  /** 数字选择器确认 → Settings.put(key, int) + 关闭。 */
  onNumberConfirm(value: number): void {
    Settings.put(this.sheetItem.key, value);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 多选确认 → 把 stringSet 存成「逗号拼接」串(无原生 stringSet,落 Settings string)。 */
  onMultiConfirm(values: string[]): void {
    Settings.put(this.sheetItem.key, values.join(','));
    this.rowVersion++;
    this.closePreferenceDialog();
  }

  /** 文本输入确认 → Settings.put(key, string)。 */
  onTextConfirm(): void {
    Settings.put(this.sheetItem.key, this.textDraft);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 颜色选择确认 → Settings.put(key, int 颜色值)。 */
  onColorConfirm(color: number): void {
    Settings.put(this.sheetItem.key, color);
    this.sheetOpen = false;
    this.sheetKind = '';
  }

  /** 当前 list/multiselect 的默认选中索引(供弹窗初始态)。 */
  currentNumberValue(item: PreferenceItem): number {
    return typeof item.defaultValue === 'number' ? item.defaultValue : 0;
  }

  /** 禁用历史/续播开关的确认 BottomSheet(PreferenceConfirmDialog 宽度 100%)。 */
  @Builder
  confirmSheet() {
    Column() {
      PreferenceConfirmDialog({
        preferenceKey: this.confirmItem.key,
        titleText: this.confirmItem.title,
        warningText: this.confirmItem.key === Settings.ENABLE_PLAYBACK_HISTORY
          ?
          '禁用播放历史将隐藏历史记录、媒体进度和已看标记。应用将继续保存您的活动，并在历史记录重新启用时恢复这些记录。\n\n如果您想完全停止保存活动，请改用无痕模式。\n\n您还可以在历史记录界面或高级设置中清除历史记录。'
          : $r('app.string.clear_playback_history'),
        onAccept: () => this.confirmDisable(),
        onCancel: () => this.cancelDisable(),
      }).width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.list_title'))
  }

  /** 偏好选择器 BottomSheet:按 sheetKind 渲染 number/multi/text/color 选择器。 */
  @Builder
  preferenceSheet() {
    Column() {
      if (this.sheetKind === 'list') {
        this.listSheet()
      } else if (this.sheetKind === 'number') {
        PreferenceNumberPickerDialog({
          title: this.sheetItem.title,
          item: this.sheetItem,
          currentValue: this.currentNumberValue(this.sheetItem),
          min: this.sheetItem.numberMin ?? 1,
          max: this.sheetItem.numberMax ?? 100,
          onConfirm: (v: number) => this.onNumberConfirm(v),
          onDismiss: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
        }).width('100%')
      } else if (this.sheetKind === 'multi') {
        PreferenceMultiSelectDialog({
          title: this.sheetItem.title,
          item: this.sheetItem,
          onConfirm: (vs: string[]) => this.onMultiConfirm(vs),
          onDismiss: () => {
            this.sheetOpen = false;
            this.sheetKind = '';
          },
        }).width('100%')
      } else if (this.sheetKind === 'text') {
        this.textEditSheet()
      } else if (this.sheetKind === 'color') {
        this.colorSheet()
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
  }

  @Builder
  preferenceCustomDialog() {
    if (this.dialogKind === 'list') {
      PreferenceChoiceDialog({
        title: this.sheetItem.title,
        labels: this.sheetItem.options ?? [],
        values: this.sheetItem.optionValues ?? [],
        selectedValue: this.listValue,
        onSelect: (value: string) => this.onListConfirm(value),
        onCancel: () => this.closePreferenceDialog(),
      })
        .width('100%')
    } else if (this.dialogKind === 'multi') {
      PreferenceMultiSelectDialog({
        title: this.sheetItem.title,
        item: this.sheetItem,
        onConfirm: (vs: string[]) => this.onMultiConfirm(vs),
        onDismiss: () => this.closePreferenceDialog(),
      }).width('100%')
    }
  }

  @Builder
  sleepTimerSheet() {
    SleepTimerDialog({
      initialMillis: this.sleepMillis,
      initialWaitMediaEnd: this.sleepWaitMediaEnd,
      initialResetOnInteraction: this.sleepResetOnInteraction,
      onClose: () => {
        this.sleepSheetOpen = false;
      },
      onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) =>
      this.onSleepConfirm(millis, waitForMediaEnd, resetOnInteraction),
    })
      .width('100%')
  }

  @Builder
  listSheet() {
    Column() {
      Text(this.sheetItem.title).fontSize(16).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 8 })
      List() {
        Repeat(this.sheetItem.options ?? []).each((labelRepeatItem: RepeatItem<ResourceStr>) => {
          ListItem() {
            Row() {
              Text(labelRepeatItem.item).fontSize(14).fontColor($r('app.color.list_title')).layoutWeight(1)
              Image($r('app.media.ic_check'))
                .width(20).height(20).fillColor($r('app.color.orange500'))
                .visibility(this.optionValueAt(labelRepeatItem.index) === this.listValue ?
                  Visibility.Visible : Visibility.Hidden)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 14,
              bottom: 14
            })
            .onClick(() => this.onListConfirm(this.optionValueAt(labelRepeatItem.index)))
          }
        }).key((label: ResourceStr, idx: number) => `${idx}`)
      }
      .divider({ strokeWidth: 0.5, color: $r('app.color.card_background') })
      .width('100%')
      .height(360)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .alignItems(HorizontalAlign.Start)
  }

  /** sheetItem.optionValues[idx] 安全取值(避免 optional element access)。 */
  optionValueAt(idx: number): string {
    const vals: string[] = this.sheetItem.optionValues ?? [];
    return idx >= 0 && idx < vals.length ? vals[idx] : '';
  }

  @Builder
  textEditSheet() {
    Column() {
      Text(this.sheetItem.title).fontSize(16).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 12 })
      TextInput({ text: this.textDraft })
        .fontSize(15)
        .fontColor($r('app.color.list_title'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(4)
        .margin({ left: 16, right: 16 })
        .onChange((v: string) => {
          this.textDraft = v;
        })
      Button($r('app.string.ok'))
        .type(ButtonType.Normal)
        .borderRadius(4)
        .backgroundColor($r('app.color.orange500'))
        .fontColor($r('app.color.list_title'))
        .margin({ top: 16, bottom: 24 })
        .onClick(() => this.onTextConfirm())
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  colorSheet() {
    Column() {
      Text(this.sheetItem.title).fontSize(16).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 16 })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        Repeat(COLOR_PALETTE).each((cRepeatItem: RepeatItem<number>) => {
          Column()
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(cRepeatItem.item)
            .margin(8)
            .border({ width: this.colorDraft === cRepeatItem.item ? 3 : 0, color: $r('app.color.orange500') })
            .onClick(() => this.onColorConfirm(cRepeatItem.item))
        }).key((c: number) => `${c}`)
      }
      .width('90%')
      .margin({ bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .alignItems(HorizontalAlign.Center)
  }

  private setPersistentIncognito(enabled: boolean): void {
    if (!this.incognitoEnabled) {
      return;
    }
    this.persistentIncognitoEnabled = enabled;
    Settings.put('persistent_incognito', enabled);
  }

  /** 复制当前 toggleStates 并更新单个 key,返回新对象引用以触发 @Local 观察回调。 */
  private updateToggleState(key: string, value: boolean): Record<string, boolean> {
    const map: Record<string, boolean> = {};
    for (const g of this.groups) {
      for (const it of g.items) {
        if (it.type === 'toggle' || it.type === 'checkbox') {
          map[it.key] = this.toggleStates[it.key] === true;
        }
      }
    }
    map[key] = value;
    return map;
  }

  /** 将旧版空字符串兼容为 HarmonyOS 的系统语言标识 default。 */
  private appPreferredLanguage(value: string): string {
    if (value.length === 0 || value === 'default') {
      return 'default';
    }
    return value;
  }
}
