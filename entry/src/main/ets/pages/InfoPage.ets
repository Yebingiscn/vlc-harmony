import { NavController } from '../common/data/NavController';
import { formatDuration, formatSize, MediaInfoItem } from '../common/models/MediaModels';
import { AppColors } from '../common/constants/AppConstants';
import { VideoParam } from './VideoPlayerPage';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface InfoParam {
  uri?: string;
  title?: string;
}

/**
 * InfoPage —— InfoActivity(媒体信息详情)。
 * 可折叠封面 AppBar(视差封面 + 黑渐变蒙层 + 分辨率角标)+ 固定白 Toolbar 返回/标题 +
 * 滚动区(路径/时长/文件大小/附加信息/轨道 List)+ 右下橙底圆形 FAB(ic_fab_play)。
 */
@ComponentV2
export struct InfoPage {
  @Param param: InfoParam = { uri: '', title: '' };
  @Local title: string = '';
  @Local infoItems: MediaInfoItem[] = [];
  @Local length: number = 0;
  @Local fileSize: number = 0;
  @Local resolution: string = '';

  aboutToAppear(): void {
    this.title = this.param.title ?? '';
    this.infoItems = [
      new MediaInfoItem($r('app.string.length').toString(),
        this.length > 0 ? formatDuration(this.length) : '—'),
      new MediaInfoItem('File size', this.fileSize > 0 ? formatSize(this.fileSize) : '—'),
      new MediaInfoItem('Resolution', this.resolution.length > 0 ? this.resolution : '—'),
    ];
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 封面区(info_appbar_height=300)
          Stack() {
            Image($r('app.media.ic_no_thumbnail_1610'))
              .width('100%')
              .height(300)
              .objectFit(ImageFit.Cover)
              .fillColor('#212121')
            // 黑渐变蒙层
            Column().width('100%').height(100).linearGradient({
              angle: 90, colors: [['#cb000000', 0.0], ['#00000000', 1.0]],
            }).align(Alignment.Bottom)
            if (this.resolution.length > 0) {
              Text(this.resolution)
                .fontSize(10)
                .fontColor('#FFFFFF')
                .backgroundColor($r('app.color.rounded_corners_black_more_transparent'))
                .borderRadius(5)
                .padding({
                  left: 4,
                  top: 2,
                  right: 4,
                  bottom: 2
                })
                .margin({ left: 12, top: 60 })
                .align(Alignment.TopStart)
            }
          }
          .width('100%')
          .height(300)

          // 滚动信息区
          Scroll() {
            Column() {
              Text(this.title)
                .fontSize(20).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                .margin({
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 8
                })
              List() {
                Repeat(this.infoItems).each((itRepeatItem: RepeatItem<MediaInfoItem>) => {
                  ListItem() {
                    Column() {
                      Text(itRepeatItem.item.title).fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                      Text(itRepeatItem.item.subtitle).fontSize(12).fontColor('#9E9E9E').margin({ top: 2 })
                    }
                    .width('100%').alignItems(HorizontalAlign.Start).padding(16)
                  }
                }).key((it: MediaInfoItem, idx: number) => `${idx}`)
              }
              .divider({
                strokeWidth: 0.5,
                color: $r('app.color.divider'),
                startMargin: 16,
                endMargin: 16
              })
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor($r('app.color.background_default'))
        }
        .width('100%')
        .height('100%')

        // 顶部固定 Toolbar(透明叠加)
        Row() {
          Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor('#FFFFFF')
            .onClick(() => NavController.pop())
          Blank()
        }
        .width('100%')
        .height(56)
        .padding({ left: 12 })
        .alignItems(VerticalAlign.Center)

        // 右下橙底圆形 FAB(ic_fab_play)
        Image($r('app.media.ic_fab_play'))
          .width(56)
          .height(56)
          .fillColor('#FFFFFF')
          .backgroundColor(AppColors.orange500)
          .borderRadius(28)
          .padding(16)
          .shadow({ radius: 12, color: '#33000000', offsetY: 6 })
          .align(Alignment.BottomEnd)
          .margin({ right: 16, bottom: 16 })
          .onClick(() => {
            const uri: string = this.param.uri ?? '';
            hilog.info(0x0001, 'VLC', '[VLC] InfoPage play uri=%{public}s', uri);
            const vparam: VideoParam = { uri: uri, title: this.title };
            // bindAndPlay 会用 fallbackUri 建队列;此处不提前 play
            NavController.push('VideoPlayer', vparam);
          })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
