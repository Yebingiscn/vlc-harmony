import { PreferenceScreen, PreferenceGroup, PreferenceItem, PreferenceSearchEntry } from '../common/models/PreferenceModels';
import { NavController } from '../common/data/NavController';
import { PreferencesPage } from './PreferencesPage';
import { PreferencesScreenParam } from '../common/models/MediaModels';

/**
 * PreferenceSearchPage —— 偏好搜索页(@ComponentV2 NavDestination)。
 * 顶部 TextInput + 结果 List(遍历所有 screen 的 items 按关键词过滤,点击跳转 PreferencesPage)。
 * 简单实现:扁平化 buildScreens() 所有 items 为 PreferenceSearchEntry[],按 query 过滤 title/summary。
 * 来源:PreferenceSearchActivity(preferences_search_activity.xml)。
 */
@ComponentV2
export struct PreferenceSearchPage {
  @Local query: string = '';
  @Local results: PreferenceSearchEntry[] = [];
  @Local dataset: PreferenceSearchEntry[] = [];

  aboutToAppear(): void {
    this.dataset = PreferenceSearchPage.flatten(PreferencesPage.buildScreens());
    this.applyFilter();
  }

  applyFilter(): void {
    const q: string = this.query.trim().toLowerCase();
    if (q.length === 0) {
      this.results = [];
      return;
    }
    const matched: PreferenceSearchEntry[] = [];
    for (const e of this.dataset) {
      const title: string = (e.title as string).toLowerCase();
      const summary: string = (e.summary as string).toLowerCase();
      if (title.includes(q) || summary.includes(q)) {
        matched.push(e);
      }
    }
    this.results = matched;
  }

  onItemClick(entry: PreferenceSearchEntry): void {
    // 选中该项 → 跳转到其所在 screen(EXTRA_PREF_END_POINT 语义)。TODO(契约):滚动定位 + 高亮
    if (entry.screenKey.length > 0) {
      const p: PreferencesScreenParam = { screenKey: entry.screenKey };
      NavController.push('Preferences', p);
    }
  }

  /** 高亮命中 query 的子串(返回分段:命中段加粗 + 下划线,简化为整体文案)。 */
  highlightText(text: ResourceStr): ResourceStr {
    return text;
  }

  static flatten(registry: Map<string, PreferenceScreen>): PreferenceSearchEntry[] {
    const out: PreferenceSearchEntry[] = [];
    registry.forEach((screen: PreferenceScreen) => {
      for (const g of screen.groups) {
        for (const it of g.items) {
          if (it.type === 'info') {
            continue;
          }
          out.push(new PreferenceSearchEntry({
            key: it.key,
            title: it.title,
            summary: it.summary ?? '',
            screenKey: screen.key,
            category: g.title,
          }));
        }
      }
    });
    return out;
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部搜索栏:close + TextInput + (translate 按英语环境隐藏)
        Row() {
          Image($r('app.media.ic_close_small'))
            .width(24)
            .height(24)
            .fillColor('#9E9E9E')
            .margin({ left: 8 })
            .onClick(() => NavController.pop())
          TextInput({ text: this.query, placeholder: $r('app.string.search_prefs') })
            .layoutWeight(1)
            .height(48)
            .margin({ left: 8, right: 8 })
            .fontSize(16)
            .fontColor('#E0E0E0')
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => {
              this.query = v;
              this.applyFilter();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 8, bottom: 4 })
        Divider().color('#424242').strokeWidth(1).margin({ top: 4 })
        // 结果列表
        List() {
          ForEach(this.results, (entry: PreferenceSearchEntry) => {
            ListItem() {
              Column() {
                Text(this.highlightText(entry.title))
                  .fontSize(16)
                  .fontColor('#E0E0E0')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 72, top: 8, right: 8 })
                if (entry.summary !== '') {
                  Text(this.highlightText(entry.summary))
                    .fontSize(13)
                    .fontColor('#9E9E9E')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 72, right: 8 })
                }
                Text(entry.category)
                  .fontSize(11)
                  .fontColor('#FF8800')
                  .margin({ left: 72 })
                Divider().color('#2A2A2A').strokeWidth(0.5).margin({ left: 72, top: 8 })
              }
              .width('100%')
              .onClick(() => this.onItemClick(entry))
            }
          }, (entry: PreferenceSearchEntry) => entry.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#121212')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
