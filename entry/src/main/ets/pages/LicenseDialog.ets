import { AppColors } from '../common/constants/AppConstants';

/**
 * LicenseDialog —— 许可证全文 BottomSheet。
 * 18fp Medium 标题(licenseTitle,layoutWeight1)+ 右上角 24vp ic_website 图标(licenseLink 非空时)
 * + 14fp grey 版权行(copyright,marginTop 8)+ 14fp 白色许可证正文(licenseDescription,含 \n,marginTop 16)。
 * TODO(契约): openLinkInBrowser() → openLinkIfPossible(licenseLink) 唤起系统浏览器;由调用方实现。
 */
@ComponentV2
export struct LicenseDialog {
  @Param licenseTitle: string = 'GNU General Public License';
  @Param copyright: string = '';
  @Param licenseDescription: string = '';
  @Param licenseLink: string = '';
  @Event onClose: () => void = () => {};
  @Event onOpenLink: () => void = () => {};

  build() {
    Column() {
      Scroll() {
        Column() {
          // 标题 + 网站图标
          Row() {
            Text(this.licenseTitle)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.licenseLink.length > 0) {
              Image($r('app.media.ic_website'))
                .width(24).height(24)
                .fillColor('#FFFFFF')
                .padding(8)
                .margin({ top: 8 })
                .onClick(() => this.onOpenLink())
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .justifyContent(FlexAlign.SpaceBetween)

          // 版权行
          Text(this.copyright)
            .fontSize(14)
            .fontColor(AppColors.grey500)
            .width('100%')
            .margin({ top: 8 })

          // 许可证正文
          Text(this.licenseDescription)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .width('100%')
            .margin({ top: 16 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
