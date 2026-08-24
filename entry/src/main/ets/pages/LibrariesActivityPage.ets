import { UiFeedback } from '../common/utils/UiFeedback';
import { NavController } from '../common/data/NavController';
import { LibEntry, LicenseInfo, RawData } from '../common/data/RawData';
import { OpenLink } from '../common/data/OpenLink';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { LicenseDialog } from './LicenseDialog';
import { LengthMetrics } from '@kit.ArkUI';
import {
  DividerShowType,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

/** 库许可条目(LibraryWithLicense data class)。 */
export class LibraryWithLicense {
  title: string;
  copyright: string;
  licenseTitle: string;
  licenseDescription: string;
  licenseLink: string;

  constructor(
    title: string,
    copyright: string,
    licenseTitle: string,
    licenseDescription: string,
    licenseLink: string,
  ) {
    this.title = title;
    this.copyright = copyright;
    this.licenseTitle = licenseTitle;
    this.licenseDescription = licenseDescription;
    this.licenseLink = licenseLink;
  }
}

/**
 * LibrariesActivityPage —— 开源库许可列表(LibrariesActivity)。
 * 角色:pushed(关于 → 开源库许可详情页)。
 * 结构:AppBar(ic_close_up 关闭 + ic_incognito + "VLC" + "Libraries" 标题) + 库许可 List(ic_sources 24vp + title 16fp + copyright + licenseTitle)。
 * 交互:列表项整行点击 → LicenseDialog 底部抽屉(bindSheet,全展开)展示许可全文。
 * 数据:rawfile libraries.json(libraries[{title,copyright,license}] join licenses[{id,name,description,link}]) → RawData 解析;
 *      正文按 license id 匹配 description,无匹配则回退 RawData.loadLicenseText()(vlc_license.txt GPLv2 全文)。
 */
@ObservedV2
export class LibrariesVM {
  @Trace licenses: LibraryWithLicense[] = [];
  @Trace dialogItem: LibraryWithLicense | null = null;
  @Trace dialogVisible: boolean = false;

  refresh(): void {
    // 读 rawfile libraries.json,join by library.license==licenses[].id 拼成 LibraryWithLicense[]。
    // 许可证正文(licenseDescription)在弹窗打开时按需查表填充,这里列表行先用 licenseTitle=name。
    Promise.all([RawData.loadLibraries(), RawData.loadLicenses()])
      .then((result: [LibEntry[], LicenseInfo[]]) => {
        const libs: LibEntry[] = result[0];
        const lics: LicenseInfo[] = result[1];
        const list: LibraryWithLicense[] = [];
        for (const lib of libs) {
          // 按 license id 找到匹配的许可信息(标题用许可 name,正文用 description)。
          const matched: LicenseInfo | undefined = lics.find((l: LicenseInfo) => l.id === lib.license);
          list.push(new LibraryWithLicense(
            lib.title,
            lib.copyright,
            matched !== undefined ? matched.name : lib.license,
            matched !== undefined ? matched.description : '',
            matched !== undefined ? matched.link : '',
          ));
        }
        this.licenses = list;
      })
      .catch(() => {
        this.licenses = [];
      });
  }

  openLicenseDialog(item: LibraryWithLicense): void {
    this.dialogItem = item;
    if (item.licenseDescription.length > 0) {
      // licenses.json 已提供正文(按 license id 匹配到的 description)。
      this.dialogVisible = true;
    } else {
      // 无匹配许可 id → 回退用 vlc_license.txt(GPLv2)全文。
      RawData.loadLicenseText().then((text: string) => {
        this.dialogItem = new LibraryWithLicense(
          item.title,
          item.copyright,
          item.licenseTitle,
          text,
          item.licenseLink,
        );
        this.dialogVisible = true;
      }).catch(() => {
        this.dialogVisible = true;
      });
    }
  }
}

@ComponentV2
export struct LibrariesActivityPage {
  @Local vm: LibrariesVM = new LibrariesVM();

  aboutToAppear(): void {
    // 生命周期加载:launchWhenStarted → model.refresh() 读 raw asset JSON 解析。
    this.vm.refresh();
  }

  @Builder
  LicenseSheet() {
    // 底部抽屉(STATE_EXPANDED 全展开),复用 LicenseDialog 组件展示许可全文。
    // 自定义组件 builder 在 bindSheet 内必须给 .width('100%'),否则白屏。
    Column() {
      LicenseDialog({
        licenseTitle: this.vm.dialogItem === null ? '' : this.vm.dialogItem.licenseTitle,
        copyright: this.vm.dialogItem === null ? '' : this.vm.dialogItem.copyright,
        licenseDescription: this.vm.dialogItem === null ? '' : this.vm.dialogItem.licenseDescription,
        licenseLink: this.vm.dialogItem === null ? '' : this.vm.dialogItem.licenseLink,
        onClose: () => {
          this.vm.dialogVisible = false;
        },
        onOpenLink: () => {
          // openLinkIfPossible(licenseLink) → 系统浏览器打开许可官网。
          if (this.vm.dialogItem !== null && this.vm.dialogItem.licenseLink.length > 0) {
            if (!OpenLink.open(this.vm.dialogItem.licenseLink)) {
              UiFeedback.showToast({ message: this.vm.dialogItem.licenseLink });
            }
          }
        },
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LibraryItemRow(item: LibraryWithLicense) {
    Row() {
      Image($r('app.media.ic_sources'))
        .width(24)
        .height(24)
        .fillColor(AppColors.grey900)
        .margin({ left: AppDimens.kl_normal })
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontColor(AppColors.grey900)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.copyright)
          .fontColor(AppColors.grey700)
          .margin({ top: AppDimens.half_default_margin })
        Text(item.licenseTitle)
          .fontColor(AppColors.grey900)
          .margin({ top: AppDimens.half_default_margin, bottom: AppDimens.default_margin })
      }
      .layoutWeight(1)
      .margin({ left: 32, right: AppDimens.kl_normal })
      .align(Alignment.Center)
    }
    .width('100%')
    .margin({ top: AppDimens.kl_normal })
    .onClick(() => this.vm.openLicenseDialog(item))
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 库许可列表(纵向滚动,layoutWeight1,paddingBottom 48vp)
        Column() {
          List() {
            Repeat(this.vm.licenses).each((itemRepeatItem: RepeatItem<LibraryWithLicense>) => {
              ListItem() {
                this.LibraryItemRow(itemRepeatItem.item)
              }
            }).key((item: LibraryWithLicense) => item.title).virtualScroll()
          }
          .width('100%')
          .height('100%')
          .padding({ bottom: 48 })
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
      .bindSheet($$this.vm.dialogVisible, this.LicenseSheet(), {
        height: SheetSize.LARGE,
        dragBar: true,
        backgroundColor: $r('app.color.background_default'),
      })
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
          mainTitle: 'Libraries'
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
