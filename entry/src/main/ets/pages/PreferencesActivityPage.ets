import { VlcToolbar } from '../common/components/VlcToolbar';
import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';
import { promptAction } from '@kit.ArkUI';

/** 设置分组标题(PreferenceCategory)。 */
export class PrefHeader {
  title: Resource;
  constructor(title: Resource) {
    this.title = title;
  }
}

/** 设置导航条目(PrefNav:带图标跳转行)。 */
export class PrefNav {
  title: Resource;
  icon: Resource;
  key: string;
  constructor(title: Resource, icon: Resource, key: string) {
    this.title = title;
    this.icon = icon;
    this.key = key;
  }
}

/** 设置开关条目(PrefToggle:CheckBoxPreference)。 */
export class PrefToggle {
  title: ResourceStr;
  summary: ResourceStr;
  key: string;
  checked: boolean;
  constructor(title: ResourceStr, summary: ResourceStr, key: string, checked: boolean) {
    this.title = title;
    this.summary = summary;
    this.key = key;
    this.checked = checked;
  }
}

/** 设置列表条目(PrefList/PrefRow)。 */
export class PrefRow {
  title: ResourceStr;
  summary: ResourceStr;
  key: string;
  constructor(title: ResourceStr, summary: ResourceStr, key: string) {
    this.title = title;
    this.summary = summary;
    this.key = key;
  }
}

/**
 * PreferencesActivityPage —— 设置宿主页(PreferencesActivity)。
 * 角色:pushed。VlcToolbar + 渲染 PreferencesFragment 的根 screenKey='root'(设置根列表)。
 * 结构:Toolbar(返回箭头 + "Settings" + 搜索 ic_search) + 设置分组列表(Media library / Video / Network / Permissions / History / Extra settings)。
 */
@ObservedV2
export class PreferencesVM {
  @Trace autoRescan: boolean = true;
  @Trace playbackHistory: boolean = true;
  @Trace videoResume: boolean = true;
  @Trace audioResume: boolean = true;

  async loadDefaults(): Promise<void> {
    // 默认值:auto_rescan/playback_history/video_resume_playback/audio_resume_playback 默认 true。
    this.autoRescan = await Settings.getBoolean(Settings.KEY_MEDIALIBRARY_AUTO_RESCAN, true);
    this.playbackHistory = await Settings.getBoolean(Settings.PLAYBACK_HISTORY, true);
  }
}

@ComponentV2
export struct PreferencesActivityPage {
  @Local vm: PreferencesVM = new PreferencesVM();

  aboutToAppear(): void {
    // TODO(契约): KEY_RESTRICT_SETTINGS → 若为 true 启动 PinCodeActivity(CHECK) 校验,回调非 RESULT_OK → finish()。
    this.vm.loadDefaults();
  }

  @Builder
  HeaderItem(title: Resource) {
    Text(title)
      .fontSize(13)
      .fontColor(AppColors.orange800)
      .width('100%')
      .textAlign(TextAlign.Start)
      .margin({ left: AppDimens.kl_normal, top: AppDimens.kl_normal, bottom: AppDimens.half_default_margin })
  }

  @Builder
  NavRow(item: PrefNav, onClick: () => void) {
    Row() {
      Image(item.icon)
        .width(24)
        .height(24)
        .fillColor(AppColors.grey700)
        .margin({ right: AppDimens.kl_normal })
      Text(item.title)
        .fontSize(16)
        .fontColor(AppColors.grey900)
        .layoutWeight(1)
      Image($r('app.media.ic_chevron_right'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey600)
    }
    .width('100%')
    .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin, right: AppDimens.kl_normal })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  @Builder
  ToggleRow(item: PrefToggle) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
        Text(item.summary)
          .fontSize(12)
          .fontColor(AppColors.grey600)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: item.checked })
        .onChange((c: boolean) => {
          // TODO(契约): 关闭 playback_history/audio_resume_playback 弹 ConfirmPreferenceChangeDialog;video_resume 清队列 prefs。
          item.checked = c;
          Settings.put(item.key, c);
        })
    }
    .width('100%')
    .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin, right: AppDimens.kl_normal })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ListRow(item: PrefRow, onClick: () => void) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
        Text(item.summary)
          .fontSize(12)
          .fontColor(AppColors.grey600)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Image($r('app.media.ic_chevron_right'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey600)
    }
    .width('100%')
    .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin, right: AppDimens.kl_normal })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  build() {
    NavDestination() {
      Column() {
        VlcToolbar({
          title: $r('app.string.preferences'),
          showBack: true,
          onBack: () => NavController.pop(),
          showSearch: true,
          onSearch: () => {
            // TODO(契约): startActivityForResult(PreferenceSearchActivity, searchRequestCode=167)
            NavController.push('PreferenceSearchPage');
          },
        })

        Scroll() {
          Column() {
            // ========== Media library ==========
            this.HeaderItem($r('app.string.medialibrary_scan'))
            this.ListRow(
              new PrefRow($r('app.string.medialibrary_scan'), $r('app.string.medialibrary_scan_explanation'), 'directories'),
              () => {
                // TODO(契约): SecondaryActivity(STORAGE_BROWSER) + setResult(RESULT_RESTART)
                NavController.pushSecondary('STORAGE_BROWSER');
              })
            this.ToggleRow(new PrefToggle($r('app.string.medialibrary_scan'), $r('app.string.medialibrary_scan_explanation'),
              Settings.KEY_MEDIALIBRARY_AUTO_RESCAN, this.vm.autoRescan))

            // ========== Video ==========
            this.HeaderItem($r('app.string.video'))
            this.ListRow(new PrefRow($r('app.string.video'), '', 'video_action_switch'),
              () => promptAction.showToast({ message: 'video_action_switch' }))
            this.ListRow(new PrefRow($r('app.string.opengl_title'), $r('app.string.opengl_summary'), 'hardware_acceleration'),
              () => promptAction.showToast({ message: 'hardware_acceleration' }))

            // ========== Network ==========
            this.HeaderItem($r('app.string.network_browsing'))
            this.ListRow(new PrefRow($r('app.string.network_caching'), $r('app.string.network_caching_summary'), 'metered_connection'),
              () => promptAction.showToast({ message: 'metered_connection' }))

            // ========== Permissions ==========
            this.HeaderItem($r('app.string.permissions'))
            this.ListRow(new PrefRow($r('app.string.permissions'), $r('app.string.permission_expanation_allow'), 'permissions'),
              () => promptAction.showToast({ message: 'PermissionListDialog' }))

            // ========== History ==========
            this.HeaderItem($r('app.string.history'))
            this.ToggleRow(new PrefToggle($r('app.string.clear_playback_history'), $r('app.string.clear_history_message'),
              Settings.PLAYBACK_HISTORY, this.vm.playbackHistory))
            this.ToggleRow(new PrefToggle($r('app.string.video'), '', Settings.VIDEO_RESUME_TIME, this.vm.videoResume))
            this.ToggleRow(new PrefToggle($r('app.string.audio'), '', Settings.KEY_AUDIO_LAST_PLAYLIST, this.vm.audioResume))

            // ========== Extra settings ==========
            this.HeaderItem($r('app.string.advanced_prefs_category'))
            this.NavRow(new PrefNav($r('app.string.interface_prefs_screen'), $r('app.media.ic_ui'), 'ui_category'),
              () => promptAction.showToast({ message: 'PreferencesUi' }))
            this.NavRow(new PrefNav($r('app.string.video'), $r('app.media.ic_pref_video'), 'video_category'),
              () => promptAction.showToast({ message: 'PreferencesVideo' }))
            this.NavRow(new PrefNav($r('app.string.subtitles'), $r('app.media.ic_pref_subtitles'), 'subtitles_category'),
              () => promptAction.showToast({ message: 'PreferencesSubtitles' }))
            this.NavRow(new PrefNav($r('app.string.audio'), $r('app.media.ic_pref_audio'), 'audio_category'),
              () => promptAction.showToast({ message: 'PreferencesAudio' }))
            this.NavRow(new PrefNav($r('app.string.equalizer'), $r('app.media.ic_pref_equalizer'), 'equalizer'),
              () => NavController.push('EqualizerSettingsActivityPage'))
            this.NavRow(new PrefNav($r('app.string.casting_connected_renderer'), $r('app.media.ic_renderer'), 'casting_category'),
              () => promptAction.showToast({ message: 'PreferencesCasting' }))
            this.NavRow(new PrefNav($r('app.string.permission_media_title'), $r('app.media.ic_pref_parental_control'), 'parental_control'),
              () => promptAction.showToast({ message: 'PreferencesParentalControl' }))
            this.NavRow(new PrefNav($r('app.string.remote_access_version'), $r('app.media.ic_pref_remote_access'), 'remote_access_category'),
              () => promptAction.showToast({ message: 'PreferencesRemoteAccess' }))
            this.NavRow(new PrefNav($r('app.string.android_auto'), $r('app.media.ic_pref_android_auto'), 'android_auto_category'),
              () => promptAction.showToast({ message: 'PreferencesAndroidAuto' }))
            this.NavRow(new PrefNav($r('app.string.advanced_prefs_category'), $r('app.media.ic_pref_advanced_settings'), 'adv_category'),
              () => promptAction.showToast({ message: 'PreferencesAdvanced' }))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 54 })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppColors.white)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.white)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
