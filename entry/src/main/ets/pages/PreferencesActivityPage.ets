import { promptAction } from '@kit.ArkUI';
import { VlcToolbar } from '../common/components/VlcToolbar';
import { NavController } from '../common/data/NavController';
import { RouteName } from '../common/constants/AppConstants';
import { PreferencesScreenParam } from '../common/models/MediaModels';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
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
  /** 变更行摘要后重建列表项。 */
  @Local rowVersion: number = 0;

  async aboutToAppear(): Promise<void> {
    this.sections = SettingsHomeCatalog.create();
    const values: Record<string, boolean> = {};
    for (const section of this.sections) {
      for (const item of section.items) {
        if (item.type === 'toggle') {
          values[item.key] = item.defaultOn;
        }
      }
    }
    values[Settings.KEY_INCOGNITO] = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
    this.toggleValues = values;
    await this.loadOrientationSummary();
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
    return SettingsHomeCatalog.isEnabled(item, this.toggleValues.playback_history === true);
  }

  isToggleOn(item: SettingsHomeItem): boolean {
    return this.toggleValues[item.key] === true;
  }

  async onToggle(item: SettingsHomeItem, value: boolean): Promise<void> {
    if (!this.isItemEnabled(item)) {
      return;
    }
    const next: Record<string, boolean> = this.toggleValues;
    next[item.key] = value;
    this.toggleValues = next;
    if (item.key === Settings.KEY_INCOGNITO) {
      await PlaybackHistory.setIncognito(value);
    }
  }

  /** 后续接入子页、单选弹窗、权限页或业务设置的统一入口。 */
  onSettingAction(item: SettingsHomeItem): void {
    if (item.key === Settings.SCREEN_ORIENTATION) {
      this.openOrientationDialog();
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
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
