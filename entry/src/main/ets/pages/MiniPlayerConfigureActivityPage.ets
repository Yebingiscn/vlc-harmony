import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { Settings } from '../common/data/Settings';
import { promptAction } from '@kit.ArkUI';

/** MiniPlayer 配置入参(EXTRA_APPWIDGET_ID)。 */
export class MiniPlayerConfigureParam {
  appWidgetId: number = -1;
}

/** Widget 主题条目(对应 widget_theme ListPreference entries)。 */
export class WidgetThemeEntry {
  label: string;
  value: number;
  constructor(label: string, value: number) {
    this.label = label;
    this.value = value;
  }
}

/**
 * MiniPlayerConfigureActivityPage —— Widget 配置页(MiniPlayerConfigureActivity)。
 * 角色:pushed(由桌面 widget host 拉起)。
 * 结构:Toolbar(ic_incognito + "VLC" 标题 + 右上 ic_information/ic_options_check 菜单)
 *   + 预览区(widget_preview 图 + 预览开关胶囊) + PreferencesWidgets 表单(11 项偏好)。
 */
@ObservedV2
export class WidgetVM {
  @Trace theme: number = 0; // 0=Material You,1=Palette,2=Custom
  @Trace widgetType: number = 0; // 0=Automatic,1=Pill,2=Normal,3=Circle,4=Large
  @Trace lightTheme: boolean = true;
  @Trace opacity: number = 100;
  @Trace backgroundColor: string = '#000000';
  @Trace foregroundColor: string = '#FFFFFF';
  @Trace showCover: boolean = true;
  @Trace showSeek: boolean = true;
  @Trace forwardDelay: number = 10;
  @Trace rewindDelay: number = 10;
  @Trace showConfigure: boolean = false;
  @Trace previewPlaying: boolean = true;

  readonly themeEntries: WidgetThemeEntry[] = [
    new WidgetThemeEntry('Palette (pulls colors from the media cover)', 1),
    new WidgetThemeEntry('Custom', 2),
  ];
  readonly typeEntries: string[] = ['Automatic', 'Pill', 'Normal', 'Circle', 'Large'];

  async loadPreview(): Promise<void> {
    // TODO(契约): WidgetRepository.getWidgetFlow(id)(Room widget_table) schema 不在 manifest。
    this.previewPlaying = await Settings.getBoolean('widgets_preview_playing', true);
  }
}

@ComponentV2
export struct MiniPlayerConfigureActivityPage {
  @Param param: MiniPlayerConfigureParam = new MiniPlayerConfigureParam();
  @Local vm: WidgetVM = new WidgetVM();

  aboutToAppear(): void {
    // appWidgetId == INVALID → finish()。
    if (this.param.appWidgetId === -1) {
      NavController.pop();
      return;
    }
    this.vm.loadPreview();
  }

  @Builder
  ToggleRow(title: Resource, summary: ResourceStr, isOn: boolean, onChange: (c: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
        Text(summary)
          .fontSize(12)
          .fontColor(AppColors.grey600)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((c: boolean) => onChange(c))
    }
    .width('100%')
    .padding({ top: AppDimens.default_margin, bottom: AppDimens.default_margin })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SliderRow(title: Resource, value: number, onChange: (v: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
          .layoutWeight(1)
        Text(`${value}%`)
          .fontSize(14)
          .fontColor(AppColors.grey700)
      }
      .width('100%')
      Slider({ value: value, min: 0, max: 100, step: 1 })
        .blockColor(AppColors.orange800)
        .selectedColor(AppColors.orange800)
        .width('100%')
        .onChange((v: number) => onChange(Math.round(v)))
    }
    .width('100%')
    .padding({ top: AppDimens.default_margin, bottom: AppDimens.default_margin })
  }

  @Builder
  NavRow(title: Resource, summary: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
        if (summary.length > 0) {
          Text(summary)
            .fontSize(12)
            .fontColor(AppColors.grey600)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Image($r('app.media.ic_chevron_right'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey600)
    }
    .width('100%')
    .padding({ top: AppDimens.default_margin, bottom: AppDimens.default_margin })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部工具栏(无返回箭头)
        Row() {
          Image($r('app.media.ic_incognito'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
          Text('VLC')
            .fontSize(20)
            .fontColor(AppColors.orange800)
            .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal })
          Blank()
          // widget_info → 弹 WidgetExplanationDialog
          Image($r('app.media.ic_information'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey700)
            .margin({ right: AppDimens.default_margin })
            .onClick(() => {
              // TODO(契约): WidgetExplanationDialog().show("fragment_widget_explanation")(3 步引导)
              promptAction.showToast({ message: 'Widget explanation' });
            })
          // widget_configure_done → onMenuDone() 后 finish()
          Image($r('app.media.ic_check'))
            .width(24)
            .height(24)
            .fillColor(AppColors.orange800)
            .margin({ right: AppDimens.default_margin })
            .onClick(() => {
              // TODO(契约): onWidgetContainerClicked()(清缓存 + 刷新 widget provider)+ setResult(RESULT_OK, EXTRA_APPWIDGET_ID)
              NavController.pop();
            })
        }
        .width('100%')
        .height(56)
        .backgroundColor(AppColors.white)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            // 预览区
            Column() {
              // TODO(契约): updatePreview() 内 provider.layoutWidget + bitmapFromView 生成预览位图;鸿蒙无 RemoteViews,用占位预览图。
              Image($r('app.media.widget_preview_mini'))
                .width(276)
                .height(94)
                .objectFit(ImageFit.Contain)
                .margin({ top: 24 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)

            // 预览开关胶囊(右下对齐)
            Column() {
              Text($r('app.string.widget_preview'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.grey900)
              Row() {
                Toggle({ type: ToggleType.Switch, isOn: this.vm.previewPlaying })
                  .onChange((c: boolean) => {
                    this.vm.previewPlaying = c;
                    Settings.put('widgets_preview_playing', c);
                    // TODO(契约): updatePreview()
                  })
                Text($r('app.string.playing'))
                  .margin({ left: AppDimens.default_margin })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(AppColors.grey200)
            .padding({ left: AppDimens.kl_normal, top: AppDimens.default_margin, right: AppDimens.kl_normal, bottom: AppDimens.default_margin })
            .margin({ top: 24, right: AppDimens.kl_normal })
            .borderRadius(8)

            // 配置项容器(PreferencesWidgets 11 项)
            Column() {
              Text($r('app.string.widget_theme'))
                .fontSize(13)
                .fontColor(AppColors.orange800)
                .margin({ top: AppDimens.kl_normal, bottom: AppDimens.half_default_margin })
              this.NavRow($r('app.string.widget_theme'), this.vm.themeEntries[this.vm.theme].label, () => {
                promptAction.showToast({ message: 'Choose widget theme' });
              })
              this.NavRow($r('app.string.widget_type'), this.vm.typeEntries[this.vm.widgetType], () => {
                promptAction.showToast({ message: 'Choose widget type' });
              })
              if (this.vm.theme !== 2) {
                this.ToggleRow($r('app.string.light_theme'), '', this.vm.lightTheme, (c: boolean) => { this.vm.lightTheme = c; })
              }
              this.SliderRow($r('app.string.opacity'), this.vm.opacity, (v: number) => { this.vm.opacity = v; })
              if (this.vm.theme === 2) {
                this.NavRow($r('app.string.widget_background'), this.vm.backgroundColor, () => promptAction.showToast({ message: 'Pick background color' }))
                this.NavRow($r('app.string.widget_foreground'), this.vm.foregroundColor, () => promptAction.showToast({ message: 'Pick foreground color' }))
              }
              this.ToggleRow($r('app.string.widget_show_cover'), '', this.vm.showCover, (c: boolean) => { this.vm.showCover = c; })
              this.ToggleRow($r('app.string.widget_show_seek'), '', this.vm.showSeek, (c: boolean) => { this.vm.showSeek = c; })
              this.ToggleRow($r('app.string.widget_show_configure'), $r('app.string.widget_show_configure_summary'), this.vm.showConfigure, (c: boolean) => { this.vm.showConfigure = c; })
            }
            .width('100%')
            .padding({ left: AppDimens.kl_normal, right: AppDimens.kl_normal })
            .backgroundColor(AppColors.white)
          }
          .width('100%')
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
      // finish(): onWidgetContainerClicked() + super.finish()。
      NavController.pop();
      return true;
    })
  }
}
