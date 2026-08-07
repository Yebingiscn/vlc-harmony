import { NavController } from '../common/data/NavController';
import { AppColors, AppDimens } from '../common/constants/AppConstants';

/** 偏好搜索项(PreferenceItem data class)。 */
export class PreferenceItem {
  key: string;
  title: string;
  summary: string;
  category: string;

  constructor(key: string, title: string, summary: string, category: string) {
    this.key = key;
    this.title = title;
    this.summary = summary;
    this.category = category;
  }
}

/**
 * PreferenceSearchActivityPage —— 设置搜索页(PreferenceSearchActivity)。
 * 角色:pushed(从设置页 startActivityForResult 进入)。
 * 结构:顶部搜索栏行(close ic_close_up + searchText + translate ic_translate) + 分隔线 + 结果 List(每项 title/desc/category + 底部分隔线)。
 * 搜索高亮:命中 query 子串加粗+下划线。
 */
@ObservedV2
export class PreferenceSearchVM {
  @Trace query: string = '';
  @Trace showTranslations: boolean = false;
  @Trace filteredItems: PreferenceItem[] = [];
  @Trace isEnglish: boolean = true;

  private dataset: PreferenceItem[] = [];

  load(): void {
    // TODO(契约): PreferenceParser.parsePreferences(context) 解析 10 个偏好 XML 构造 PreferenceItem 列表 +
    // PreferenceVisibilityManager.isPreferenceVisible 过滤。鸿蒙侧需等价偏好元数据源,这里用样例数据占位。
    this.dataset = [
      new PreferenceItem('auto_rescan', 'Auto rescan', 'Scan device for new media', 'Media library'),
      new PreferenceItem('hardware_acceleration', 'Hardware Acceleration', 'Decoding: may improve performance', 'Video'),
      new PreferenceItem('equalizer', 'Equalizer', 'Audio equalizer presets', 'Extra settings'),
      new PreferenceItem('enable_playback_history', 'Playback history', 'Save all media played in History', 'History'),
      new PreferenceItem('screen_orientation', 'Video screen orientation', 'Screen orientation', 'Video'),
    ];
    this.filter();
  }

  filter(): void {
    if (this.query.length === 0) {
      this.filteredItems = [];
      return;
    }
    const q = this.query.toLowerCase();
    this.filteredItems = this.dataset.filter(
      (it: PreferenceItem) => it.title.toLowerCase().includes(q) || it.summary.toLowerCase().includes(q),
    );
  }

  onQueryChange(text: string): void {
    this.query = text.toLowerCase();
    this.filter();
  }

  onTranslateClick(): void {
    this.showTranslations = !this.showTranslations;
    this.filter();
  }
}

@ComponentV2
export struct PreferenceSearchActivityPage {
  @Local vm: PreferenceSearchVM = new PreferenceSearchVM();

  aboutToAppear(): void {
    // 生命周期加载:IO 协程 parsePreferences + 可见性过滤 + showTranslations=false。
    this.vm.load();
  }

  @Builder
  PreferenceItemRow(item: PreferenceItem) {
    Column() {
      Text(item.title)
        .fontSize(16)
        .fontColor(AppColors.grey900)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 72, top: AppDimens.default_margin, right: AppDimens.default_margin })
      if (item.summary.length > 0) {
        Text(item.summary)
          .fontSize(13)
          .fontColor(AppColors.grey600)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 72, right: AppDimens.default_margin })
      }
      Text(item.category)
        .fontSize(11)
        .fontColor(AppColors.orange500)
        .margin({ left: 72 })
      Divider().height(1).color(AppColors.grey300).margin({ left: 72, top: AppDimens.default_margin })
    }
    .width('100%')
    .onClick(() => {
      // 选中项回传调用方(EXTRA_PREF_END_POINT)并关闭本页 → 调用方跳到对应偏好终点。
      // TODO(契约): setResult(RESULT_OK, Intent(ACTION_RESULT) putExtra(EXTRA_PREF_END_POINT, item))
      NavController.pop();
    })
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部搜索栏行(close — searchText — translate,垂直居中于同一 48vp 行)
        Row() {
          Image($r('app.media.ic_close_up'))
            .width(24)
            .height(24)
            .fillColor(AppColors.grey700)
            .margin({ left: AppDimens.default_margin })
            .padding(AppDimens.half_default_margin)
            .onClick(() => NavController.pop())
          TextInput({ text: this.vm.query, placeholder: $r('app.string.search_prefs') })
            .layoutWeight(1)
            .height(48)
            .margin({ left: AppDimens.default_margin, right: AppDimens.default_margin })
            .backgroundColor(AppColors.transparent)
            .fontSize(16)
            .placeholderColor(AppColors.grey500)
            .onChange((v: string) => this.vm.onQueryChange(v))
          if (!this.vm.isEnglish) {
            Image($r('app.media.ic_translate'))
              .width(24)
              .height(24)
              .fillColor(AppColors.grey700)
              .margin({ right: AppDimens.default_margin })
              .padding(AppDimens.default_margin)
              .borderRadius(20)
              .backgroundColor(this.vm.showTranslations ? AppColors.orange500transparent : AppColors.transparent)
              .onClick(() => this.vm.onTranslateClick())
          }
        }
        .width('100%')
        .padding({ top: AppDimens.default_margin, bottom: AppDimens.half_default_margin })
        .alignItems(VerticalAlign.Center)

        // separator
        Divider().height(1).color(AppColors.grey300).margin({ top: AppDimens.half_default_margin })

        // 结果列表
        List() {
          ForEach(this.vm.filteredItems, (item: PreferenceItem) => {
            ListItem() {
              this.PreferenceItemRow(item)
            }
          }, (item: PreferenceItem) => item.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
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
