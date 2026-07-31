import { Settings } from '../common/data/Settings';
import { PlaybackService } from '../common/data/PlaybackService';
import { AppColors } from '../common/constants/AppConstants';

/**
 * PlaybackSpeedDialog —— 播放速度 BottomSheet。
 * 标题 + This video/All 二选一切换组 + 速度值/加减按钮(长按连续 ±0.01)+
 * 指数映射滑杆(progress=100 即 1.0x)+ 0.8/1.0/1.25/1.5/2.0 圆形预设 + 流式告警条(orange500)。
 * rate↔progress 指数映射:rate = 4^(progress/100 - 1)。
 */
@ComponentV2
export struct PlaybackSpeedDialog {
  @Local rate: number = 1.0;
  @Local forVideo: boolean = true;
  @Local progress: number = 50; // 0..200, 100=1.0x
  @Event onClose: () => void = () => {};

  aboutToAppear(): void {
    this.rate = PlaybackService.speedToNumber();
    this.progress = this.rateToProgress(this.rate);
  }

  // 指数映射:progress 100 = 1.0x;0→0.25x,200→4x(rate = 4^((p-100)/100))
  rateToProgress(r: number): number {
    const p = Math.round(100 + Math.log(r) / Math.log(4) * 100);
    return Math.max(0, Math.min(200, p));
  }

  progressToRate(p: number): number {
    return Math.pow(4, (p - 100) / 100);
  }

  formatRate(r: number): string {
    return `${r.toFixed(2)}x`;
  }

  applyRate(r: number): void {
    this.rate = Math.max(0.25, Math.min(4.0, r));
    this.progress = this.rateToProgress(this.rate);
    PlaybackService.setSpeed(this.rate);
    if (this.forVideo) {
      Settings.put(Settings.KEY_PLAYBACK_SPEED_VIDEO_GLOBAL_VALUE, this.rate);
      Settings.put(Settings.KEY_PLAYBACK_SPEED_VIDEO_GLOBAL, true);
    } else {
      Settings.put(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL_VALUE, this.rate);
      Settings.put(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL, true);
    }
  }

  build() {
    Column() {
      // 标题
      Text($r('app.string.fastplay_title', this.rate.toFixed(2)))
        .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
        .margin({ top: 16, bottom: 12 })

      // This video / All 切换组
      Row() {
        this.segItem($r('app.string.video'), this.forVideo, () => {
          this.forVideo = true;
        })
        this.segItem($r('app.string.apply_to_all'), !this.forVideo, () => {
          this.forVideo = false;
        })
      }
      .margin({ bottom: 16 })

      // 速度值 + 加减按钮
      Row() {
        Image($r('app.media.ic_fav_remove')).width(32).height(32).fillColor('#FFFFFF')
          .onClick(() => this.applyRate(this.rate - 0.01))
        Text(this.formatRate(this.rate)).fontSize(28).fontColor('#FFFFFF').layoutWeight(1).textAlign(TextAlign.Center)
        Image($r('app.media.ic_add')).width(32).height(32).fillColor('#FFFFFF')
          .onClick(() => this.applyRate(this.rate + 0.01))
      }
      .width('80%').alignItems(VerticalAlign.Center).margin({ bottom: 16 })

      // 指数映射滑杆
      Slider({ value: this.progress, min: 0, max: 200, step: 1, style: SliderStyle.OutSet })
        .blockColor(AppColors.orange500)
        .selectedColor(AppColors.orange500)
        .trackColor('#424242')
        .width('80%')
        .onChange((v: number, mode: SliderChangeMode) => {
          this.applyRate(this.progressToRate(Math.round(v)));
        })
        .margin({ bottom: 16 })

      // 圆形预设
      Row() {
        this.preset(0.8)
        this.preset(1.0)
        this.preset(1.25)
        this.preset(1.5)
        this.preset(2.0)
      }
      .width('80%').justifyContent(FlexAlign.SpaceAround).margin({ bottom: 16 })

      // 流式告警条(orange500)
      Text($r('app.string.developing'))
        .fontSize(12).fontColor('#FFFFFF').backgroundColor(AppColors.orange500)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 }).margin({ bottom: 16 })

      Button($r('app.string.ok'))
        .type(ButtonType.Normal).borderRadius(4).backgroundColor(AppColors.orange500).fontColor('#FFFFFF')
        .width('80%').onClick(() => this.onClose())
        .margin({ bottom: 24 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  segItem(title: Resource, selected: boolean, onTap: () => void) {
    Text(title)
      .fontSize(13)
      .fontColor(selected ? '#FFFFFF' : '#9E9E9E')
      .backgroundColor(selected ? AppColors.orange500 : '#2A2A2A')
      .borderRadius(4)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .layoutWeight(1)
      .margin({ left: 4, right: 4 })
      .textAlign(TextAlign.Center)
      .onClick(() => onTap())
  }

  @Builder
  preset(r: number) {
    Text(this.formatRate(r))
      .fontSize(12)
      .fontColor(Math.abs(this.rate - r) < 0.001 ? '#FFFFFF' : '#9E9E9E')
      .backgroundColor(Math.abs(this.rate - r) < 0.001 ? AppColors.orange800 : '#1AFF610A')
      .borderRadius(24)
      .width(48)
      .height(48)
      .textAlign(TextAlign.Center)
      .onClick(() => this.applyRate(r))
  }
}
