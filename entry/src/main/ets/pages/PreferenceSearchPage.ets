import { PreferenceScreen, PreferenceSearchEntry } from '../common/models/PreferenceModels';
import { NavController } from '../common/data/NavController';
import { PreferencesPage } from './PreferencesPage';
import { PreferencesScreenParam } from '../common/models/MediaModels';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

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

  build() {
    HdsNavDestination() {
      Column() {
        // 搜索栏
        Row() {
          TextInput({ text: this.query, placeholder: $r('app.string.search_prefs') })
            .layoutWeight(1)
            .height(48)
            .margin({ left: 12, right: 12 })
            .fontSize(16)
            .fontColor($r('app.color.list_title'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(24)
            .onChange((v: string) => {
              this.query = v;
              this.applyFilter();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 8, bottom: 4 })

        Divider().color($r('app.color.divider')).strokeWidth(1).margin({ top: 4 })
        // 结果列表
        List() {
          Repeat(this.results).each((entryRepeatItem: RepeatItem<PreferenceSearchEntry>) => {
            ListItem() {
              Column() {
                Text(this.highlightText(entryRepeatItem.item.title))
                  .fontSize(16)
                  .fontColor($r('app.color.list_title'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 72, top: 8, right: 8 })
                if (entryRepeatItem.item.summary !== '') {
                  Text(this.highlightText(entryRepeatItem.item.summary))
                    .fontSize(13)
                    .fontColor($r('app.color.font_light'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 72, right: 8 })
                }
                Text(entryRepeatItem.item.category)
                  .fontSize(11)
                  .fontColor($r('app.color.orange500'))
                  .margin({ left: 72 })
                Divider().color($r('app.color.divider')).strokeWidth(0.5).margin({ left: 72, top: 8 })
              }
              .width('100%')
              .onClick(() => this.onItemClick(entryRepeatItem.item))
            }
          }).key((entry: PreferenceSearchEntry) => entry.key).virtualScroll()
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
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
          mainTitle: $r('app.string.search_prefs')
        },
        backIcon: {
          icon: $r('app.media.ic_arrow_back'),
          label: '返回',
          action: () => NavController.pop()
        },
        divider: {
          showType: DividerShowType.AUTO
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideTitleBar(false)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
