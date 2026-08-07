/** 设置首页仅用于展示的行类型。 */
export type SettingsHomeItemType = 'navigation' | 'toggle';

/** 设置首页的一行数据；业务处理由页面的统一入口负责。 */
export class SettingsHomeItem {
  key: string;
  title: string;
  summary: string;
  type: SettingsHomeItemType;
  defaultOn: boolean;
  dependsOnHistory: boolean;
  iconKey: string;
  screenKey: string;

  constructor(
    key: string,
    title: string,
    summary: string = '',
    type: SettingsHomeItemType = 'navigation',
    defaultOn: boolean = false,
    dependsOnHistory: boolean = false,
    iconKey: string = '',
    screenKey: string = '',
  ) {
    this.key = key;
    this.title = title;
    this.summary = summary;
    this.type = type;
    this.defaultOn = defaultOn;
    this.dependsOnHistory = dependsOnHistory;
    this.iconKey = iconKey;
    this.screenKey = screenKey;
  }
}

/** 设置首页的一个可滚动分组。 */
export class SettingsHomeSection {
  key: string;
  title: string;
  items: SettingsHomeItem[];

  constructor(key: string, title: string, items: SettingsHomeItem[]) {
    this.key = key;
    this.title = title;
    this.items = items;
  }
}

/** 与安卓 VLC 设置首页对齐的静态页面目录。 */
export class SettingsHomeCatalog {
  static create(): SettingsHomeSection[] {
    return [
      new SettingsHomeSection('media_library', '媒体库', [
        new SettingsHomeItem('directories', '媒体库文件夹', '选择要收录于媒体库的目录'),
        new SettingsHomeItem('auto_rescan', '自动重新扫描', '应用启动时，自动扫描设备中新增或删除的媒体文件', 'toggle', true),
      ]),
      new SettingsHomeSection('video', '视频', [
        new SettingsHomeItem('background_pip', '背景/画中画模式', '视频播放过程中切换到其他应用程序时 VLC 的行为'),
        new SettingsHomeItem('hardware_acceleration', '硬件加速', '禁用：稳定性更高\n解码：可能提升性能\n完全：可能进一步提升性能'),
        new SettingsHomeItem('screen_orientation', '视频屏幕方向', '自动（传感器感应）'),
      ]),
      new SettingsHomeSection('network', '网络', [
        new SettingsHomeItem('metered_connection', '按流量计费的网络下对串流的处理', '不执行任何操作'),
      ]),
      new SettingsHomeSection('permissions', '权限', [
        new SettingsHomeItem('permissions', '权限', '所有权限的列表'),
      ]),
      new SettingsHomeSection('history', '历史', [
        new SettingsHomeItem('enable_playback_history', '播放历史', '在「历史记录」下保留所有播放过的媒体', 'toggle', true),
        new SettingsHomeItem('video_resume_playback', '视频播放队列历史', '允许储存视频播放队列内容，以便稍后继续播放', 'toggle', true, true),
        new SettingsHomeItem('audio_resume_playback', '音频播放队列历史', '允许储存音频播放队列内容，以便稍后继续播放', 'toggle', true, true),
      ]),
      new SettingsHomeSection('additional', '附加设置', [
        new SettingsHomeItem('ui_category', '界面', '', 'navigation', false, false, 'ui', 'ui_category'),
        new SettingsHomeItem('video_category', '视频', '', 'navigation', false, false, 'video', 'video_category'),
        // 以下入口按需求隐藏(保留底层实现,仅不在此展示):
        // new SettingsHomeItem('subtitles_category', '字幕', '', 'navigation', false, false, 'subtitles'),
        // new SettingsHomeItem('audio_category', '音频', '', 'navigation', false, false, 'audio', 'audio_category'),
        // new SettingsHomeItem('equalizer', '均衡器', '', 'navigation', false, false, 'equalizer'),
        // new SettingsHomeItem('casting_category', '投屏', '', 'navigation', false, false, 'casting', 'casting_category'),
        // new SettingsHomeItem('parental_control', '家长控制', '', 'navigation', false, false, 'parental', 'parental_control'),
        // new SettingsHomeItem('remote_access_category', '远程访问', '', 'navigation', false, false, 'remote', 'remote_access_category'),
        // new SettingsHomeItem('android_auto_category', 'Android Auto', '', 'navigation', false, false, 'android_auto'),
        // new SettingsHomeItem('adv_category', '高级', '', 'navigation', false, false, 'advanced'),
      ]),
    ];
  }

  static isEnabled(item: SettingsHomeItem, historyOn: boolean): boolean {
    return !item.dependsOnHistory || !historyOn;
  }
}
