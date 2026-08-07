import { promptAction } from '@kit.ArkUI';
import { VlcToolbar } from '../common/components/VlcToolbar';
import { NavController } from '../common/data/NavController';
import { RouteName } from '../common/constants/AppConstants';
import { PreferencesScreenParam } from '../common/models/MediaModels';
import { Settings } from '../common/data/Settings';
import {
  SettingsHomeCatalog,
  SettingsHomeItem,
  SettingsHomeSection,
} from '../common/models/SettingsHomeModels';
import {
  SCREEN_ORIENTATION_DEFAULT,
  SCREEN_ORIENTATION_LABELS,
  SCREEN_ORIENTATION_VALUES,
  screenOrientationLabel,
  ScreenOrientationDialog,
} from './ScreenOrientationDialog';
import {
  HARDWARE_ACCELERATION_DEFAULT,
  HARDWARE_ACCELERATION_LABELS,
  HARDWARE_ACCELERATION_VALUES,
  HardwareAccelerationDialog,
} from './HardwareAccelerationDialog';
import {
  BACKGROUND_PIP_DEFAULT,
  BACKGROUND_PIP_LABELS,
  BACKGROUND_PIP_VALUES,
  BackgroundPipDialog,
} from './BackgroundPipDialog';
import {
  METERED_CONNECTION_DEFAULT,
  METERED_CONNECTION_LABELS,
  METERED_CONNECTION_VALUES,
  meteredConnectionLabel,
  MeteredConnectionDialog,
} from './MeteredConnectionDialog';

/**
 * 更多 > 设置的首页。
 *
 * 本页只负责复刻安卓 VLC 设置列表的视觉结构和临时交互状态；具体设置、跳转和权限能力
 * 统一留在 onSettingAction/onSearch 两个接口中，后续接入时不需要重新调整页面布局。
 */
@ComponentV2
export struct PreferencesActivityPage {
  @Local sections: SettingsHomeSection[] = [];
  @Local toggleValues: Record<string, boolean> = {};
  /** 视频屏幕方向当前选中值(弹窗初始态 + 行摘要刷新)。 */
  @Local orientationValue: string = SCREEN_ORIENTATION_DEFAULT;
  @Local orientationDialogId: number = -1;
  /** 硬件加速当前选中值(弹窗初始态)。 */
  @Local hardwareAccelerationValue: string = HARDWARE_ACCELERATION_DEFAULT;
  @Local hardwareAccelerationDialogId: number = -1;
  /** 背景/画中画模式当前选中值(弹窗初始态)。 */
  @Local backgroundPipValue: string = BACKGROUND_PIP_DEFAULT;
  @Local backgroundPipDialogId: number = -1;
  /** 按流量计费的网络下对串流的处理当前选中值(弹窗初始态)。 */
  @Local meteredConnectionValue: string = METERED_CONNECTION_DEFAULT;
  @Local meteredConnectionDialogId: number = -1;
  /** 变更行摘要后重建列表项。 */
  @Local rowVersion: number = 0;
  @Local historyDisableConfirmOpen: boolean = false;
  @Local historyDisableSheetType: string = '';

  async aboutToAppear(): Promise<void> {
    this.sections = SettingsHomeCatalog.create();
    const values: Record<string, boolean> = {};
    // 启动时从 prefs 读 toggle 真值,缺省回退到 item.defaultOn。
    // 此前直接用 item.defaultOn,导致切换不持久化、重启后回退到硬编码默认。
    for (const section of this.sections) {
      for (const item of section.items) {
        if (item.type === 'toggle') {
          values[item.key] = await Settings.getBoolean(item.key, item.defaultOn);
        }
      }
    }
    this.toggleValues = values;
    await this.loadOrientationSummary();
    await this.loadMeteredConnectionSummary();
  }

  private async loadOrientationSummary(): Promise<void> {
    const value: string = await Settings.getString(Settings.SCREEN_ORIENTATION, SCREEN_ORIENTATION_DEFAULT);
    this.orientationValue = value;
    this.updateOrientationSummary(value);
  }

  private updateOrientationSummary(value: string): void {
    for (const section of this.sections) {
      for (const item of section.items) {
        if (item.key === Settings.SCREEN_ORIENTATION) {
          item.summary = screenOrientationLabel(value);
          this.rowVersion++;
          return;
        }
      }
    }
  }

  isItemEnabled(item: SettingsHomeItem): boolean {
    return SettingsHomeCatalog.isEnabled(item, this.toggleValues[Settings.ENABLE_PLAYBACK_HISTORY] === true);
  }

  isToggleOn(item: SettingsHomeItem): boolean {
    return this.toggleValues[item.key] === true;
  }

  async onToggle(item: SettingsHomeItem, value: boolean): Promise<void> {
    if (!this.isItemEnabled(item)) {
      return;
    }
    if (item.key === Settings.ENABLE_PLAYBACK_HISTORY && !value && this.isToggleOn(item)) {
      // ArkUI 会先切换 Toggle 的内部视觉状态；重建该行以回写仍为 true 的受控值。
      this.rowVersion++;
      this.historyDisableSheetType = 'playback';
      this.historyDisableConfirmOpen = true;
      return;
    }
    if (item.key === Settings.AUDIO_PLAY_QUEUE_HISTORY && !value && this.isToggleOn(item)) {
      this.rowVersion++;
      this.historyDisableSheetType = 'audio';
      this.historyDisableConfirmOpen = true;
      return;
    }
    this.toggleValues = this.updatedToggleValues(item.key, value);
    this.rowVersion++;
    // 落盘:对齐 PreferencesPage/PreferenceRow 的语义,所有 toggle 立即写 prefs,
    // 否则下次冷启动 aboutToAppear 又会从 defaultOn 重新填充,看似"没保存"。
    await Settings.put(item.key, value);
    if (item.key === Settings.ENABLE_PLAYBACK_HISTORY && value) {
      await Settings.put(Settings.VIDEO_PLAY_QUEUE_HISTORY, true);
      await Settings.put(Settings.AUDIO_PLAY_QUEUE_HISTORY, true);
    }
    if (item.key === Settings.KEY_INCOGNITO) {
      // 复用 PlaybackHistory 的通知管道,让订阅方(历史 tab 等)立即刷新。
    }
  }

  /** 后续接入子页、单选弹窗、权限页或业务设置的统一入口。 */
  private async confirmDisablePlaybackHistory(): Promise<void> {
    this.toggleValues = this.updatedToggleValues(Settings.ENABLE_PLAYBACK_HISTORY, false);
    this.rowVersion++;
    await Settings.put(Settings.ENABLE_PLAYBACK_HISTORY, false);
    this.historyDisableConfirmOpen = false;
    this.historyDisableSheetType = '';
  }

  private cancelDisablePlaybackHistory(): void {
    // Toggle 的原始值仍为 true；递增 key 强制重建该行，撤销控件自身的瞬时视觉切换。
    this.rowVersion++;
    this.historyDisableConfirmOpen = false;
    this.historyDisableSheetType = '';
  }

  private async confirmDisableAudioQueueHistory(): Promise<void> {
    this.toggleValues = this.updatedToggleValues(Settings.AUDIO_PLAY_QUEUE_HISTORY, false);
    this.rowVersion++;
    await Settings.put(Settings.AUDIO_PLAY_QUEUE_HISTORY, false);
    this.historyDisableConfirmOpen = false;
    this.historyDisableSheetType = '';
  }

  private cancelDisableAudioQueueHistory(): void {
    this.rowVersion++;
    this.historyDisableConfirmOpen = false;
    this.historyDisableSheetType = '';
  }

  /** 返回新对象引用，让播放历史与其子开关在同一帧重新计算可用状态。 */
  private updatedToggleValues(key: string, value: boolean): Record<string, boolean> {
    const next: Record<string, boolean> = {};
    for (const section of this.sections) {
      for (const item of section.items) {
        if (item.type === 'toggle') {
          if (key === Settings.ENABLE_PLAYBACK_HISTORY && value &&
            (item.key === Settings.VIDEO_PLAY_QUEUE_HISTORY || item.key === Settings.AUDIO_PLAY_QUEUE_HISTORY)) {
            next[item.key] = true;
          } else {
            next[item.key] = item.key === key ? value : this.toggleValues[item.key] === true;
          }
        }
      }
    }
    return next;
  }

  onSettingAction(item: SettingsHomeItem): void {
    if (item.key === Settings.SCREEN_ORIENTATION) {
      this.openOrientationDialog();
      return;
    }
    if (item.key === Settings.KEY_HARDWARE_ACCELERATION) {
      this.openHardwareAccelerationDialog();
      return;
    }
    // 设置首页目录项 key 为 background_pip;持久化 key 复用 KEY_VIDEO_APP_SWITCH。
    if (item.key === 'background_pip') {
      this.openBackgroundPipDialog();
      return;
    }
    // 设置首页目录项 key 与持久化 key 一致(metered_connection)。
    if (item.key === Settings.KEY_METERED_CONNECTION) {
      this.openMeteredConnectionDialog();
      return;
    }
    if (item.screenKey.length > 0) {
      const param: PreferencesScreenParam = { screenKey: item.screenKey };
      NavController.push(RouteName.PreferencesScreen, param);
      return;
    }
    promptAction.showToast({ message: `“${item.key}”功能暂未实现` });
  }

  private openOrientationDialog(): void {
    Settings.getString(Settings.SCREEN_ORIENTATION, SCREEN_ORIENTATION_DEFAULT).then((value: string) => {
      this.orientationValue = value;
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.orientationDialogContent();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.orientationDialogId = dialogId;
      });
    });
  }

  private closeOrientationDialog(): void {
    if (this.orientationDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.orientationDialogId);
    }
    this.orientationDialogId = -1;
  }

  private onOrientationSelect(value: string): void {
    this.orientationValue = value;
    Settings.put(Settings.SCREEN_ORIENTATION, value);
    this.updateOrientationSummary(value);
    this.closeOrientationDialog();
  }

  private openHardwareAccelerationDialog(): void {
    Settings.getString(Settings.KEY_HARDWARE_ACCELERATION, HARDWARE_ACCELERATION_DEFAULT).then((value: string) => {
      this.hardwareAccelerationValue = value;
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.hardwareAccelerationDialogContent();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.hardwareAccelerationDialogId = dialogId;
      });
    });
  }

  private closeHardwareAccelerationDialog(): void {
    if (this.hardwareAccelerationDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.hardwareAccelerationDialogId);
    }
    this.hardwareAccelerationDialogId = -1;
  }

  private onHardwareAccelerationSelect(value: string): void {
    this.hardwareAccelerationValue = value;
    Settings.put(Settings.KEY_HARDWARE_ACCELERATION, value);
    this.closeHardwareAccelerationDialog();
  }

  private openBackgroundPipDialog(): void {
    Settings.getString(Settings.KEY_VIDEO_APP_SWITCH, BACKGROUND_PIP_DEFAULT).then((value: string) => {
      this.backgroundPipValue = value;
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.backgroundPipDialogContent();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.backgroundPipDialogId = dialogId;
      });
    });
  }

  private closeBackgroundPipDialog(): void {
    if (this.backgroundPipDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.backgroundPipDialogId);
    }
    this.backgroundPipDialogId = -1;
  }

  private onBackgroundPipSelect(value: string): void {
    this.backgroundPipValue = value;
    Settings.put(Settings.KEY_VIDEO_APP_SWITCH, value);
    this.closeBackgroundPipDialog();
  }

  @Builder
  backgroundPipDialogContent() {
    Column() {
      BackgroundPipDialog({
        title: '背景/画中画模式',
        labels: BACKGROUND_PIP_LABELS,
        values: BACKGROUND_PIP_VALUES,
        selectedValue: this.backgroundPipValue,
        onSelect: (value: string) => this.onBackgroundPipSelect(value),
        onCancel: () => this.closeBackgroundPipDialog(),
      })
        .width('100%')
    }
    .width('100%')
  }

  private async loadMeteredConnectionSummary(): Promise<void> {
    const value: string = await Settings.getString(Settings.KEY_METERED_CONNECTION, METERED_CONNECTION_DEFAULT);
    this.meteredConnectionValue = value;
    this.updateMeteredConnectionSummary(value);
  }

  private updateMeteredConnectionSummary(value: string): void {
    for (const section of this.sections) {
      for (const item of section.items) {
        if (item.key === Settings.KEY_METERED_CONNECTION) {
          item.summary = meteredConnectionLabel(value);
          this.rowVersion++;
          return;
        }
      }
    }
  }

  private openMeteredConnectionDialog(): void {
    Settings.getString(Settings.KEY_METERED_CONNECTION, METERED_CONNECTION_DEFAULT).then((value: string) => {
      this.meteredConnectionValue = value;
      this.getUIContext().getPromptAction().openCustomDialog({
        builder: () => {
          this.meteredConnectionDialogContent();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        maskColor: $r('app.color.dialog_mask'),
        backgroundColor: Color.Transparent,
      }).then((dialogId: number) => {
        this.meteredConnectionDialogId = dialogId;
      });
    });
  }

  private closeMeteredConnectionDialog(): void {
    if (this.meteredConnectionDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.meteredConnectionDialogId);
    }
    this.meteredConnectionDialogId = -1;
  }

  private onMeteredConnectionSelect(value: string): void {
    this.meteredConnectionValue = value;
    Settings.put(Settings.KEY_METERED_CONNECTION, value);
    this.updateMeteredConnectionSummary(value);
    this.closeMeteredConnectionDialog();
  }

  @Builder
  meteredConnectionDialogContent() {
    Column() {
      MeteredConnectionDialog({
        title: '按流量计费的网络下对串流的处理',
        labels: METERED_CONNECTION_LABELS,
        values: METERED_CONNECTION_VALUES,
        selectedValue: this.meteredConnectionValue,
        onSelect: (value: string) => this.onMeteredConnectionSelect(value),
        onCancel: () => this.closeMeteredConnectionDialog(),
      })
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  hardwareAccelerationDialogContent() {
    Column() {
      HardwareAccelerationDialog({
        title: '硬件加速',
        labels: HARDWARE_ACCELERATION_LABELS,
        values: HARDWARE_ACCELERATION_VALUES,
        selectedValue: this.hardwareAccelerationValue,
        onSelect: (value: string) => this.onHardwareAccelerationSelect(value),
        onCancel: () => this.closeHardwareAccelerationDialog(),
      })
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  orientationDialogContent() {
    Column() {
      ScreenOrientationDialog({
        title: '视频屏幕方向',
        labels: SCREEN_ORIENTATION_LABELS,
        values: SCREEN_ORIENTATION_VALUES,
        selectedValue: this.orientationValue,
        onSelect: (value: string) => this.onOrientationSelect(value),
        onCancel: () => this.closeOrientationDialog(),
      })
        .width('100%')
    }
    .width('100%')
  }

  /** 后续接入 PreferenceSearchActivityPage 的统一入口。 */
  onSearch(): void {
    promptAction.showToast({ message: '设置搜索功能暂未实现' });
  }

  iconFor(item: SettingsHomeItem): Resource {
    if (item.iconKey === 'ui') {
      return $r('app.media.ic_ui');
    }
    if (item.iconKey === 'video') {
      return $r('app.media.ic_pref_video');
    }
    if (item.iconKey === 'subtitles') {
      return $r('app.media.ic_pref_subtitles');
    }
    if (item.iconKey === 'audio') {
      return $r('app.media.ic_pref_audio');
    }
    if (item.iconKey === 'equalizer') {
      return $r('app.media.ic_pref_equalizer');
    }
    if (item.iconKey === 'casting') {
      return $r('app.media.ic_renderer');
    }
    if (item.iconKey === 'parental') {
      return $r('app.media.ic_pref_parental_control');
    }
    if (item.iconKey === 'remote') {
      return $r('app.media.ic_pref_remote_access');
    }
    if (item.iconKey === 'android_auto') {
      return $r('app.media.ic_pref_android_auto');
    }
    return $r('app.media.ic_pref_advanced_settings');
  }

  @Builder
  SectionHeader(section: SettingsHomeSection) {
    Text(section.title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FF8800')
      .width('100%')
      .padding({ left: 16, right: 16, top: 26, bottom: 14 })
  }

  @Builder
  SettingRow(item: SettingsHomeItem) {
    Row() {
      if (item.iconKey.length > 0) {
        Image(this.iconFor(item))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor(this.isItemEnabled(item) ? $r('app.color.list_title') : $r('app.color.grey600'))
          .margin({ right: 20 })
      }
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontColor(this.isItemEnabled(item) ? $r('app.color.list_title') : $r('app.color.grey700'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.summary.length > 0) {
          Text(item.summary)
            .fontSize(14)
            .fontColor(this.isItemEnabled(item) ? $r('app.color.list_subtitle') : $r('app.color.grey600'))
            .lineHeight(20)
            .margin({ top: 4 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (item.type === 'toggle') {
        Toggle({ type: ToggleType.Checkbox, isOn: this.isToggleOn(item) })
          .selectedColor('#FF8800')
          .enabled(this.isItemEnabled(item))
          .margin({ left: 16 })
          .onChange((value: boolean) => this.onToggle(item, value))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.isItemEnabled(item) ? 1 : 0.45)
    .onClick(() => {
      if (item.type === 'navigation' && this.isItemEnabled(item)) {
        this.onSettingAction(item);
      }
      if (item.type === 'toggle') {
        this.onToggle(item, !this.isToggleOn(item));
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        VlcToolbar({
          title: $r('app.string.preferences'),
          showBack: true,
          showSearch: true,
          currentTab: '',
          onBack: () => NavController.pop(),
          onSearch: () => this.onSearch(),
        })
        Scroll() {
          Column() {
            ForEach(this.sections, (section: SettingsHomeSection) => {
              this.SectionHeader(section)
              ForEach(section.items, (item: SettingsHomeItem) => {
                this.SettingRow(item)
              }, (item: SettingsHomeItem) => `${item.key}-${this.rowVersion}`)
              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(1)
                .margin({ top: 6 })
            }, (section: SettingsHomeSection) => section.key)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 28 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .bindSheet(this.historyDisableConfirmOpen, this.historyDisableSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => this.cancelHistoryDisableSheet(),
    })
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  private cancelHistoryDisableSheet(): void {
    if (this.historyDisableSheetType === 'audio') {
      this.cancelDisableAudioQueueHistory();
      return;
    }
    this.cancelDisablePlaybackHistory();
  }

  @Builder
  historyDisableSheet() {
    if (this.historyDisableSheetType === 'audio') {
      this.audioQueueHistoryDisableSheet()
    } else {
      this.playbackHistoryDisableSheet()
    }
  }

  @Builder
  playbackHistoryDisableSheet() {
    Column() {
      Row() {
        Image($r('app.media.ic_warning'))
          .width(54)
          .height(54)
          .fillColor('#BDBDBD')
        Text('播放历史')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#212121')
          .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('禁用播放历史将隐藏历史记录、媒体进度和已看标记。应用将继续保存您的活动，并在历史记录重新启用时恢复这些记录。\n\n如果您想完全停止保存活动，请改用无痕模式。\n\n您还可以在历史记录界面或高级设置中清除历史记录。')
        .fontSize(16)
        .fontColor('#757575')
        .lineHeight(24)
        .width('100%')
        .margin({ top: 24 })

      Row() {
        Text('取消')
          .fontSize(16)
          .fontColor('#FF8800')
          .padding(12)
          .onClick(() => this.cancelDisablePlaybackHistory())
        Text('确定')
          .fontSize(16)
          .fontColor('#FF8800')
          .padding(12)
          .margin({ left: 22 })
          .onClick(() => this.confirmDisablePlaybackHistory())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 48 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  audioQueueHistoryDisableSheet() {
    Column() {
      Row() {
        Image($r('app.media.ic_warning'))
          .width(54)
          .height(54)
          .fillColor('#BDBDBD')
        Text('音频播放队列历史')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#212121')
          .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('禁用音频播放队列历史可能会引发异常行为。\n禁用以后，您将无法在以下位置执行继续播放操作：\n\n－ 蓝牙设备\n－ 小工具\n－ 媒体通知界面')
        .fontSize(16)
        .fontColor('#757575')
        .lineHeight(24)
        .width('100%')
        .margin({ top: 24 })

      Row() {
        Text('取消')
          .fontSize(16)
          .fontColor('#FF8800')
          .padding(12)
          .onClick(() => this.cancelDisableAudioQueueHistory())
        Text('确定')
          .fontSize(16)
          .fontColor('#FF8800')
          .padding(12)
          .margin({ left: 22 })
          .onClick(() => this.confirmDisableAudioQueueHistory())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 48 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 16 })
    .backgroundColor('#FFFFFF')
  }
}
