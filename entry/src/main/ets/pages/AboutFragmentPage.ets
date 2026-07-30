import { NavController } from '../common/data/NavController';
import { OpenLink } from '../common/data/OpenLink';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { RawData } from '../common/data/RawData';
import { AboutVersionDialog } from './AboutVersionDialog';
import { LicenseDialog } from './LicenseDialog';

/**
 * AboutFragmentPage —— AboutFragment(「关于」页)。
 * Scroll 列(限宽 600vp):logo + app 名 24fp + 描述 + 版本卡(点击弹 AboutVersionDialog)+ 5 链接行
 * (官网/反馈/源码/库/作者,点击外链/路由)+ 版权卡(点击异步读 rawfile vlc_license 弹 LicenseDialog)。
 * 文案/数值/颜色逐字照搬 .harmonyos/spec/pages/AboutFragment.md。
 * 外部运行时契约(AboutVersionDialog/LicenseDialog/FeedbackActivity/外链打开等)标 TODO 注释。
 */

/** VLC 版本号常量(对应 VLC_VERSION_NAME,运行期注入)。 */
const APP_VERSION: string = '3.4.0';
/** 构建日期(对应 build_time Revision 字符串)。 */
const APP_VERSION_DATE: string = '2026-07-29';

@ComponentV2
export struct AboutLinkRow {
  @Param icon: Resource = $r('app.media.ic_about_logo');
  @Param title: string = '';
  @Event onRowClick: () => void = () => {};

  build() {
    Row() {
      Image(this.icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor(AppColors.grey900)
        .margin({ left: AppDimens.kl_normal })
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.grey900)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 24, right: AppDimens.kl_normal })
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .borderRadius(4)
    .backgroundColor(AppColors.transparent)
    .onClick(() => this.onRowClick())
  }
}

@ComponentV2
export struct AboutFragmentPage {
  @Local logoAnimationRunning: boolean = false;
  /** 版本详情 / 许可证全文弹窗状态。 */
  @Local showVersionSheet: boolean = false;
  @Local showLicenseSheet: boolean = false;
  /** GPLv2 许可证正文(点击版权卡时异步预读)。 */
  @Local licenseText: string = '';

  /** 异步读 rawfile/vlc_license.txt 为许可证正文(空串容错)。 */
  async preloadLicense(): Promise<void> {
    if (this.licenseText.length === 0) {
      this.licenseText = await RawData.loadLicenseText();
    }
  }

  private onLogoClick(): void {
    // 彩蛋:logo 旋转 + Konfetti 粒子动画(spec §6)。粒子层占位,此处仅播轻量旋转近似。
    if (this.logoAnimationRunning) {
      return;
    }
    this.logoAnimationRunning = true;
    // TODO(契约):Konfetti 粒子动画(orange200/800/500)未迁移,鸿蒙粒子/自绘近似需补充。
    setTimeout(() => {
      this.logoAnimationRunning = false;
    }, 800);
  }

  private onVersionCardClick(): void {
    // 弹 AboutVersionDialog(版本详情)。版本/构建/签名信息由 dialog 内 aboutToAppear 注入(BuildConfig 契约)。
    this.showVersionSheet = true;
  }

  private onWebsiteClick(): void {
    // openLinkIfPossible → 拉起系统浏览器(Want viewData + uri)。
    OpenLink.open('https://www.videolan.org/vlc/');
  }

  private onFeedbackClick(): void {
    // 跳转 FeedbackActivity(已注册路由 'Feedback')。
    NavController.push('Feedback');
  }

  private onSourcesClick(): void {
    // openLinkIfPossible → 拉起系统浏览器。
    OpenLink.open('https://code.videolan.org/videolan/vlc-android');
  }

  private onLibrariesClick(): void {
    // 跳转 LibrariesActivity(已注册路由 'Libraries')。
    NavController.push('Libraries');
  }

  private onAuthorsClick(): void {
    // 跳转 AuthorsActivity(已注册路由 'Authors')。
    NavController.push('Authors');
  }

  private async onCopyleftCardClick(): Promise<void> {
    // 异步读 rawfile/vlc_license.txt → 弹 LicenseDialog(licenseText 注入 licenseDescription)。
    await this.preloadLicense();
    this.showLicenseSheet = true;
  }

  build() {
    NavDestination() {
      Column() {
        // 返回导航栏(宿主顶栏由本页承载,标题留空)
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.grey900)
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Blank()
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppColors.white)

        Scroll() {
          Column() {
            // §2 LogoHeader
            Stack() {
              Image($r('app.media.ic_about_logo'))
                .width('100%')
                .objectFit(ImageFit.Contain)
                .fillColor(AppColors.orange500)
                .margin({ left: AppDimens.kl_half, right: AppDimens.kl_half })
                .rotate({ angle: this.logoAnimationRunning ? 360 : 0 })
                .onClick(() => this.onLogoClick())
            }
            .width('100%')

            // §3 app 名
            Text($r('app.string.app_name_full'))
              .fontSize(24)
              .fontWeight(FontWeight.Bolder)
              .fontColor(AppColors.grey900)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_normal })

            // §3 描述
            Text($r('app.string.about_vlc_text'))
              .fontSize(14)
              .fontColor(AppColors.grey600)
              .textAlign(TextAlign.Center)
              .width('100%')
              .constraintSize({ maxWidth: 600 })
              .margin({ left: 24, right: 24, top: AppDimens.kl_half })

            // §4 版本卡
            Row() {
              Text(APP_VERSION)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.grey900)
                .margin({ left: AppDimens.kl_normal })
              Text(APP_VERSION_DATE)
                .fontSize(12)
                .fontColor(AppColors.grey700)
                .margin({ left: AppDimens.kl_half })
                .layoutWeight(1)
            }
            .width('100%')
            .height(52)
            .alignItems(VerticalAlign.Center)
            .borderRadius(4)
            .backgroundColor(AppColors.grey200)
            .constraintSize({ maxWidth: 600 })
            .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_normal })
            .onClick(() => this.onVersionCardClick())

            // §5 链接行(官网 / 反馈 / 源码 / 库 / 作者)
            AboutLinkRow({
              icon: $r('app.media.ic_link'),
              title: 'Official website',
              onRowClick: () => this.onWebsiteClick(),
            })
            AboutLinkRow({
              icon: $r('app.media.ic_feedback'),
              title: 'Send feedback',
              onRowClick: () => this.onFeedbackClick(),
            })
            AboutLinkRow({
              icon: $r('app.media.ic_about_logo'),
              title: 'Source code',
              onRowClick: () => this.onSourcesClick(),
            })
            AboutLinkRow({
              icon: $r('app.media.ic_about_logo'),
              title: 'Libraries',
              onRowClick: () => this.onLibrariesClick(),
            })
            AboutLinkRow({
              icon: $r('app.media.ic_about_logo'),
              title: 'Authors',
              onRowClick: () => this.onAuthorsClick(),
            })

            // §6 版权卡
            Column() {
              Text($r('app.string.about_copyright'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.grey900)
                .margin({
                  left: AppDimens.kl_normal, right: AppDimens.kl_normal,
                  top: AppDimens.kl_normal, bottom: 2,
                })
              Text($r('app.string.about_license'))
                .fontSize(12)
                .fontColor(AppColors.grey700)
                .margin({
                  left: AppDimens.kl_normal, right: AppDimens.kl_normal,
                  top: 2, bottom: AppDimens.kl_normal,
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .borderRadius(4)
            .backgroundColor(AppColors.grey200)
            .constraintSize({ maxWidth: 600 })
            .margin({ left: AppDimens.kl_normal, right: AppDimens.kl_normal, top: AppDimens.kl_half, bottom: AppDimens.kl_half })
            .onClick(() => this.onCopyleftCardClick())
          }
          .width('100%')
          .constraintSize({ maxWidth: 600 })
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(AppColors.white)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
    .bindSheet(this.showVersionSheet, this.versionSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => {
        this.showVersionSheet = false;
      },
    })
    .bindSheet(this.showLicenseSheet, this.licenseSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => {
        this.showLicenseSheet = false;
      },
    })
  }

  /** 版本详情 sheet(AboutVersionDialog 宽度 100%)。 */
  @Builder
  versionSheet() {
    Column() {
      AboutVersionDialog({
        onClose: () => {
          this.showVersionSheet = false;
        },
        onOpenWhatsNew: () => {
          // TODO(契约): Changelog/whats-new 全文页跳转(当前 dialog 已内联展示精简 changelog)。
        },
      }).width('100%')
    }
    .width('100%')
    .backgroundColor(AppColors.white)
  }

  /** 许可证全文 sheet(LicenseDialog 宽度 100%,licenseText 注入 licenseDescription)。 */
  @Builder
  licenseSheet() {
    Column() {
      LicenseDialog({
        licenseTitle: 'GNU General Public License',
        copyright: 'Copyright (C) 1989, 1991 Free Software Foundation, Inc.',
        licenseDescription: this.licenseText,
        licenseLink: 'https://www.gnu.org/licenses/old-licenses/gpl-2.0.html',
        onClose: () => {
          this.showLicenseSheet = false;
        },
        onOpenLink: () => {
          OpenLink.open('https://www.gnu.org/licenses/old-licenses/gpl-2.0.html');
        },
      }).width('100%')
    }
    .width('100%')
    .backgroundColor(AppColors.white)
  }
}
