import { NavController } from '../common/data/NavController';
import { OpenLink } from '../common/data/OpenLink';
import { LengthMetrics } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  DividerShowType,
  ScrollEffectType,
  hdsMaterial
} from '@kit.UIDesignKit';

const SOURCE_CODE_URL: string = 'https://github.com/Yebingiscn/vlc-harmony';
const DOMAIN: number = 0x0001;
const TAG: string = 'AboutFragmentPage';

/** 精简的应用信息页。 */
@ComponentV2
export struct AboutFragmentPage {
  @Local versionText: string = '';

  aboutToAppear(): void {
    this.loadVersion();
  }

  private async loadVersion(): Promise<void> {
    try {
      if (canIUse('SystemCapability.BundleManager.BundleFramework.Core')) {
        const bundleInfo = await bundleManager.getBundleInfoForSelf(
          bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
        this.versionText = `${bundleInfo.versionName}(${bundleInfo.versionCode})`;
      } else {
        this.versionText = '未知版本';
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'get bundleInfo failed, error is %{public}s', JSON.stringify(error));
      this.versionText = '未知版本';
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Column({ space: 16 }) {
          Image($r('app.media.sweet_vlc'))
            .width(120)
            .height(120)
            .objectFit(ImageFit.Contain)
            .borderRadius(4)
            .margin({ bottom: 12 })

          Text('流心VLC')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.list_title'))

          Text('基于 VLC')
            .fontSize(16)
            .fontColor($r('app.color.list_subtitle'))

          Text(this.versionText)
            .fontSize(14)
            .fontColor($r('app.color.list_subtitle'))

          Text('MIT 协议')
            .fontSize(14)
            .fontColor($r('app.color.list_subtitle'))

          Button('源代码')
            .height(44)
            .padding({ left: 32, right: 32 })
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.colorOnPrimary'))
            .backgroundColor($r('app.color.orange500'))
            .margin({ top: 16 })
            .onClick(() => OpenLink.open(SOURCE_CODE_URL))

          // 版权信息
          Text('郴州液态科技有限公司 版权所有 © 2025')
            .fontSize(14)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32, bottom: 72 })
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
          mainTitle: '关于'
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
