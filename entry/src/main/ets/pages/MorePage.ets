import { NavController } from '../common/data/NavController';
import { TitleListView } from '../common/components/TitleListView';
import { SheetItem } from '../common/models/MediaModels';
import { AppColors } from '../common/constants/AppConstants';
import { promptAction } from '@kit.ArkUI';

/**
 * MorePage —— More Tab 根(MoreFragment)。
 * settings/about 双 OutlinedButton + 捐赠卡片 + Streams/History 两个 TitleListView。
 */
@ObservedV2
class MoreViewModel {
  @Trace streams: SheetItem[] = [];
  @Trace history: SheetItem[] = [];
}

@ComponentV2
export struct MorePage {
  @Local vm: MoreViewModel = new MoreViewModel();

  build() {
    Scroll() {
      Column() {
        // settings + about 双按钮
        Row() {
          Column() {
            Image($r('app.media.ic_more_preferences')).width(24).height(24).fillColor('#FF8800')
            Text($r('app.string.preferences')).fontSize(13).fontColor($r('app.color.list_title')).margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
          .constraintSize({ maxWidth: 200 })
          .padding(12)
          .borderWidth(1)
          .borderColor($r('app.color.default_separator'))
          .borderRadius(4)
          .margin({ right: 8 })
          .onClick(() => NavController.push('Preferences'))

          Column() {
            Image($r('app.media.ic_more_about')).width(24).height(24).fillColor('#FF8800')
            Text($r('app.string.about')).fontSize(13).fontColor($r('app.color.list_title')).margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .layoutWeight(1)
          .constraintSize({ maxWidth: 200 })
          .padding(12)
          .borderWidth(1)
          .borderColor($r('app.color.default_separator'))
          .borderRadius(4)
          .onClick(() => NavController.push('About'))
        }
        .width('100%')
        .padding(12)

        // 捐赠卡片(orange500 圆角4)
        Row() {
          Column() {
            Text($r('app.string.donate')).fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            Text($r('app.string.donate_desc')).fontSize(12).fontColor('#E6FFFFFF').margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Blank()
          Image($r('app.media.ic_donate')).width(40).height(40).objectFit(ImageFit.Contain).fillColor('#FFFFFF')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(AppColors.orange500)
        .borderRadius(4)
        .margin({ left: 12, right: 12, bottom: 8 })
        .onClick(() => promptAction.showToast({ message: $r('app.string.developing') }))

        TitleListView({
          title: $r('app.string.streams'),
          items: this.vm.streams,
          emptyText: $r('app.string.noplaylist'),
          onItemClick: (item: SheetItem) => NavController.push('MrlPanel'),
        })
        TitleListView({
          title: $r('app.string.history'),
          items: this.vm.history,
          emptyText: $r('app.string.nomedia'),
          onItemClick: (item: SheetItem) => NavController.push('History'),
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
    .scrollBar(BarState.Auto)
  }
}
