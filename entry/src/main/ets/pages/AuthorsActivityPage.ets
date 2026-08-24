import { NavController } from '../common/data/NavController';
import { RawData } from '../common/data/RawData';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

/** 作者列表项(对应 authors.json 的 String,样例数据)。 */
export class AuthorEntry {
  name: string;

  constructor(name: string) {
    this.name = name;
  }
}

/**
 * AuthorsActivityPage —— 作者名列表(AuthorsActivity)。
 * 角色:pushed(从「关于」页 push 进入)。
 * 结构:AppBar(返回关闭图标 ic_close_up + ic_incognito + "VLC" + "Authors" 标题) + 作者 List(ic_author 24vp + 名字 16fp)。
 * 数据:rawfile authors.json(30 项 String 数组) → RawData.loadAuthors() 解析。
 */
@ObservedV2
export class AuthorsVM {
  @Trace authors: AuthorEntry[] = [];

  loadAuthors(): void {
    // 读 rawfile authors.json(30 项 String 数组),解析后映射为 AuthorEntry[]。
    RawData.loadAuthors().then((names: string[]) => {
      const list: AuthorEntry[] = [];
      for (const n of names) {
        list.push(new AuthorEntry(n));
      }
      this.authors = list;
    }).catch(() => {
      this.authors = [];
    });
  }
}

@ComponentV2
export struct AuthorsActivityPage {
  @Local vm: AuthorsVM = new AuthorsVM();

  aboutToAppear(): void {
    // 生命周期加载:launchWhenStarted → loadAuthors() 读 raw 资源 JSON 解析。
    this.vm.loadAuthors();
  }

  @Builder
  AuthorItem(name: string) {
    Row() {
      Image($r('app.media.ic_author'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey700)
        .margin({ left: AppDimens.kl_normal, top: AppDimens.default_margin, bottom: AppDimens.default_margin })
      Text(name)
        .fontSize(16)
        .fontColor(AppColors.grey900)
        .margin({ left: 32 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColors.white)
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 作者列表(纵向滚动,layoutWeight1,paddingBottom 54vp)
        List() {
          Repeat(this.vm.authors).each((itemRepeatItem: RepeatItem<AuthorEntry>) => {
            ListItem() {
              this.AuthorItem(itemRepeatItem.item.name)
            }
          }).key((author: AuthorEntry) => author.name).virtualScroll()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ bottom: 54 })
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
          mainTitle: $r('app.string.about')
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
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

}
