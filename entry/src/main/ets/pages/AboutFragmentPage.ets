import { NavController } from '../common/data/NavController';
import { BackTitleBar } from '../common/components/BackTitleBar';
import { OpenLink } from '../common/data/OpenLink';
import { RawData } from '../common/data/RawData';
import { AboutVersionDialog } from './AboutVersionDialog';
import { LicenseDialog } from './LicenseDialog';

const APP_VERSION: string = '3.4.0';
const APP_VERSION_DATE: string = '2026-07-29';

@ComponentV2
export struct AboutLinkRow {
  @Param icon: Resource = $r('app.media.ic_link');
  @Param title: string = '';
  @Event onRowClick: () => void = () => {};

  build() {
    Row() {
      Image(this.icon)
        .width(32)
        .height(32)
        .fillColor($r('app.color.list_title'))
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
        .margin({ left: 28 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(76)
    .padding({ left: 40, right: 28 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onRowClick())
  }
}

/** 按安卓 VLC 截图重建的暗色关于页；链接和版权详情沿用现有业务入口。 */
@ComponentV2
export struct AboutFragmentPage {
  @Local showVersionSheet: boolean = false;
  @Local showLicenseSheet: boolean = false;
  @Local licenseText: string = '';

  private onVersionCardClick(): void {
    this.showVersionSheet = true;
  }

  private onWebsiteClick(): void {
    OpenLink.open('https://www.videolan.org/vlc/');
  }

  private onFeedbackClick(): void {
    NavController.push('Feedback');
  }

  private onSourcesClick(): void {
    OpenLink.open('https://code.videolan.org/videolan/vlc-android');
  }

  private onLibrariesClick(): void {
    NavController.push('Libraries');
  }

  private onAuthorsClick(): void {
    NavController.push('Authors');
  }

  private async onCopyleftCardClick(): Promise<void> {
    if (this.licenseText.length === 0) {
      this.licenseText = await RawData.loadLicenseText();
    }
    this.showLicenseSheet = true;
  }

  build() {
    NavDestination() {
      Column() {
        BackTitleBar({ title: '' })

        Scroll() {
          Column() {
            Image($r('app.media.icon'))
              .width(230)
              .height(230)
              .objectFit(ImageFit.Contain)
              .margin({ top: 54 })

            Text($r('app.string.app_name_full'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF8800')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 26 })

            Text($r('app.string.about_vlc_text'))
              .fontSize(14)
              .fontColor($r('app.color.list_subtitle'))
              .lineHeight(28)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ left: 40, right: 40, top: 26 })

            Row() {
              Text(APP_VERSION)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FF8800')
              Text(APP_VERSION_DATE)
                .fontSize(13)
                .fontColor($r('app.color.list_subtitle'))
                .margin({ left: 18 })
            }
            .width('100%')
            .height(84)
            .padding({ left: 24, right: 24 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(8)
            .margin({ left: 40, right: 40, top: 32 })
            .onClick(() => this.onVersionCardClick())

            Column() {
              AboutLinkRow({ icon: $r('app.media.ic_link'), title: '官方网站', onRowClick: () => this.onWebsiteClick() })
              AboutLinkRow({ icon: $r('app.media.ic_feedback'), title: '发送反馈', onRowClick: () => this.onFeedbackClick() })
              AboutLinkRow({ icon: $r('app.media.ic_sourcecode'), title: '源代码', onRowClick: () => this.onSourcesClick() })
              AboutLinkRow({ icon: $r('app.media.ic_sources'), title: '库', onRowClick: () => this.onLibrariesClick() })
              AboutLinkRow({ icon: $r('app.media.ic_authors'), title: '作者', onRowClick: () => this.onAuthorsClick() })
            }
            .width('100%')
            .margin({ top: 32 })

            Column() {
              Text($r('app.string.about_copyright'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.list_title'))
                .width('100%')
              Text($r('app.string.about_license'))
                .fontSize(13)
                .fontColor($r('app.color.list_subtitle'))
                .width('100%')
                .margin({ top: 10 })
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(8)
            .padding(24)
            .margin({ left: 40, right: 40, top: 12, bottom: 40 })
            .alignItems(HorizontalAlign.Start)
            .onClick(() => this.onCopyleftCardClick())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
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
    .bindSheet(this.showVersionSheet, this.versionSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => this.showVersionSheet = false,
    })
    .bindSheet(this.showLicenseSheet, this.licenseSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      onDisappear: () => this.showLicenseSheet = false,
    })
  }

  @Builder
  versionSheet() {
    AboutVersionDialog({ onClose: () => this.showVersionSheet = false, onOpenWhatsNew: () => {} })
      .width('100%')
  }

  @Builder
  licenseSheet() {
    LicenseDialog({
      licenseTitle: 'GNU General Public License',
      copyright: 'Copyright (C) 1989, 1991 Free Software Foundation, Inc.',
      licenseDescription: this.licenseText,
      licenseLink: 'https://www.gnu.org/licenses/old-licenses/gpl-2.0.html',
      onClose: () => this.showLicenseSheet = false,
      onOpenLink: () => OpenLink.open('https://www.gnu.org/licenses/old-licenses/gpl-2.0.html'),
    })
    .width('100%')
  }
}
