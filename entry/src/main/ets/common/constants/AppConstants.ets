/**
 * AppConstants — VLC 设计系统常量(逐字转录自 application/resources/.../values/{colors,dimens}.xml)。
 * 颜色:#AARRGGBB / #RRGGBB 字符串(与 resource_table 1:1)。
 * 尺寸:dp/sp/dip → vp/fp 数值 1:1 不换算;@dimen 引用已就地解析。
 */
export class AppColors {
  static readonly black: string = '#000000';
  static readonly white: string = '#ffffff';
  static readonly red: string = '#bb0000';
  static readonly orange50: string = '#fff3e0';
  static readonly orange100: string = '#ffdfae';
  static readonly orange200: string = '#ffca7d';
  static readonly orange300: string = '#ffb54c';
  static readonly orange400: string = '#ffa11a';
  static readonly orange500: string = '#FF8800';
  static readonly orange600: string = '#ff7d00';
  static readonly orange700: string = '#ff7200';
  static readonly orange800: string = '#ff610a';
  static readonly orange900: string = '#ff5014';
  static readonly orange500transparent: string = '#b4ff8800';
  static readonly orange500focus: string = '#86ff8800';
  static readonly orange200transparent: string = '#64ffca7d';
  static readonly orange_800_transparent_10: string = '#1aff610a';
  static readonly orange_800_transparent_20: string = '#33ff610a';
  static readonly orange_500_transparent_20: string = '#33FF8800';
  static readonly green500: string = '#50c8a3';
  static readonly grey50: string = '#fafafa';
  static readonly grey100: string = '#f5f5f5';
  static readonly grey200: string = '#eeeeee';
  static readonly grey300: string = '#e0e0e0';
  static readonly grey400: string = '#bdbdbd';
  static readonly grey500: string = '#9e9e9e';
  static readonly grey600: string = '#757575';
  static readonly grey700: string = '#616161';
  static readonly grey800: string = '#424242';
  static readonly grey850: string = '#323232';
  static readonly grey875: string = '#2a2a2a';
  static readonly grey900: string = '#212121';
  static readonly dark_background: string = '#131313';
  static readonly onboarding_grey: string = '#011422';
  static readonly onboarding_grey_transparent_75: string = '#BF011422';
  static readonly playerbackground: string = '#c0141414';
  static readonly status_bar_transparency: string = '#cb000000';
  static readonly black_more_transparent: string = '#88000000';
  static readonly blacktransparent: string = '#b4000000';
  static readonly black_transparent_80: string = '#cc000000';
  static readonly black_transparent_60: string = '#99000000';
  static readonly black_transparent_50: string = '#80000000';
  static readonly whitetransparent: string = '#b4ffffff';
  static readonly white_transparent_20: string = '#33ffffff';
  static readonly white_transparent_75: string = '#bfffffff';
  static readonly ripple_white: string = '#44ffffff';
  static readonly transparent: string = '#00000000';
  static readonly material_blue: string = '#2196f3';
}

export class AppDimens {
  static readonly default_margin: number = 8;
  static readonly half_default_margin: number = 4;
  static readonly kl_half: number = 4;
  static readonly kl_small: number = 8;
  static readonly kl_normal: number = 16;
  static readonly very_small_margin: number = 4;
  static readonly default_appbar_elevation: number = 4;
  static readonly info_default_margin: number = 16;
  static readonly info_progress_end_margin: number = 74;
  static readonly grid_card_thumb_width: number = 160;
  static readonly grid_card_thumb_height: number = 100;
  static readonly grid_card_title_text_size: number = 12;
  static readonly grid_card_subtitle_text_size: number = 10;
  static readonly tab_layout_height: number = 24;
  static readonly tab_layout_horizontal_padding: number = 5;
  static readonly navigation_margin: number = 0;
  static readonly player_peek_height: number = 72;
  static readonly audio_cover: number = 48;
  static readonly video_cover: number = 100;
  static readonly audio_browser_item_size: number = 40;
  static readonly audio_item_title_size: number = 14;
  static readonly option_width: number = 64;
  static readonly option_height: number = 72;
  static readonly player_option_width: number = 224;
  static readonly adv_options_margin: number = 16;
  static readonly overlay_margin: number = 4;
  static readonly overlay_padding_sides: number = 5;
  static readonly overlay_padding_top: number = 10;
  static readonly overlay_padding_bottom: number = 8;
  static readonly seekbar_height: number = 1;
  static readonly seek_margin_sides: number = 8;
  static readonly time_margin_sides: number = 16;
  static readonly media_ctrl_margin_top: number = 20;
  static readonly recycler_section_header_height: number = 36;
  static readonly recycler_section_header_spacing: number = 12;
  static readonly dialog_time_picker_width: number = 240;
  static readonly fastscroller_track_width: number = 8;
  static readonly info_appbar_height: number = 300;
}

/** Tab 定义(底部导航 5 项,来自 @menu/bottom_navigation)。 */
export interface TabItem {
  id: string;
  label: Resource;
  icon: Resource;
}

export const VLC_TABS: TabItem[] = [
  { id: 'video', label: $r('app.string.video'), icon: $r('app.media.ic_video') },
  { id: 'audio', label: $r('app.string.audio'), icon: $r('app.media.ic_menu_audio') },
  { id: 'browse', label: $r('app.string.browse'), icon: $r('app.media.ic_folder') },
  { id: 'playlists', label: $r('app.string.playlists'), icon: $r('app.media.ic_playlist') },
  { id: 'more', label: $r('app.string.more'), icon: $r('app.media.ic_nav_more') },
];

/** 路由名(NavPathStack)。 */
export class RouteName {
  static readonly FormatCompat: string = 'FormatCompat';
  static readonly Onboarding: string = 'Onboarding';
  static readonly Main: string = 'Main';
  static readonly VideoPlayer: string = 'VideoPlayer';
  static readonly AudioPlayer: string = 'AudioPlayer';
  static readonly Info: string = 'Info';
  static readonly Secondary: string = 'Secondary';
  static readonly Search: string = 'Search';
  // Phase B 新增可导航页路由名。
  static readonly HeaderMediaList: string = 'HeaderMediaList';
  static readonly Libraries: string = 'Libraries';
  static readonly EqualizerSettings: string = 'EqualizerSettings';
  static readonly PinCode: string = 'PinCode';
  static readonly OTPCode: string = 'OTPCode';
  static readonly Authors: string = 'Authors';
  static readonly Feedback: string = 'Feedback';
  static readonly BetaWelcome: string = 'BetaWelcome';
  static readonly FilePicker: string = 'FilePicker';
  static readonly Preferences: string = 'Preferences';
  static readonly PreferenceSearch: string = 'PreferenceSearch';
  static readonly DialogHost: string = 'DialogHost';
  static readonly MiniPlayerConfigure: string = 'MiniPlayerConfigure';
  static readonly DebugLog: string = 'DebugLog';
  static readonly Bench: string = 'Bench';
  static readonly PreferencesScreen: string = 'PreferencesScreen';
  static readonly PreferenceSearchScreen: string = 'PreferenceSearchScreen';
  static readonly About: string = 'About';
  static readonly History: string = 'History';
  static readonly FileBrowser: string = 'FileBrowser';
  static readonly MrlPanel: string = 'MrlPanel';
}
