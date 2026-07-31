import { promptAction } from '@kit.ArkUI';
import { NavController } from '../common/data/NavController';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { Settings } from '../common/data/Settings';
import { streamSubmissionMessage } from '../common/models/StreamInputModels';

/** 串流入口：保留地址输入 UX，当前不发起播放或保存网络串流。 */
@ComponentV2
export struct MrlPanelPage {
  @Local address: string = '';
  @Local incognitoMode: boolean = false;
  @Local menuOpen: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.incognitoMode = await Settings.getBoolean(Settings.KEY_INCOGNITO, false);
  }

  private submitAddress(): void {
    const message = streamSubmissionMessage(this.address);
    if (message.length > 0) {
      promptAction.showToast({ message: message });
    }
  }

  private async setIncognito(enabled: boolean): Promise<void> {
    await PlaybackHistory.setIncognito(enabled);
    this.incognitoMode = enabled;
    promptAction.showToast({ message: enabled ? '无痕模式已开启' : '无痕模式已关闭' });
  }

  private refresh(): void {
    this.menuOpen = false;
    promptAction.showToast({ message: '已刷新' });
  }

  @Builder
  streamMenu() {
    Column() {
      Row() {
        Text('无痕模式')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
        Toggle({ type: ToggleType.Checkbox, isOn: this.incognitoMode })
          .selectedColor('#FF8800')
          .onChange((enabled: boolean) => this.setIncognito(enabled))
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 12 })
      .alignItems(VerticalAlign.Center)
      Divider()
        .color('#3A3A3A')
        .strokeWidth(1)
      Text('刷新')
        .fontSize(16)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => this.refresh())
    }
    .width(220)
    .backgroundColor('#242424')
    .borderRadius(12)
    .shadow({ radius: 16, color: '#66000000', offsetY: 6 })
    .position({ right: 12, top: 64 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Row() {
            Image($r('app.media.ic_arrow_back'))
              .width(24)
              .height(24)
              .fillColor('#FFFFFF')
              .margin({ left: 16 })
              .onClick(() => NavController.pop())
            Text('串流')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF8800')
              .margin({ left: 16 })
            Blank()
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Image($r('app.media.ic_more_w'))
                .width(28)
                .height(28)
            }
            .width(56)
            .height(56)
            .backgroundColor(Color.Transparent)
            .margin({ right: 4 })
            .onClick(() => this.menuOpen = !this.menuOpen)
          }
          .width('100%')
          .height(56)
          .alignItems(VerticalAlign.Center)
          .backgroundColor('#121212')

          Column() {
            Text('打开网络串流')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .width('100%')
            Text('输入网络地址后点击发送')
              .fontSize(14)
              .fontColor('#BDBDBD')
              .width('100%')
              .margin({ top: 8 })
            Row() {
              TextInput({ text: this.address, placeholder: 'https://example.com/live.m3u8' })
                .type(InputType.URL)
                .fontColor('#FFFFFF')
                .placeholderColor('#8E8E8E')
                .layoutWeight(1)
                .height(52)
                .backgroundColor('#252525')
                .border({ width: 1, color: '#454545', radius: 8 })
                .padding({ left: 14, right: 12 })
                .onChange((value: string) => this.address = value)
                .onSubmit(() => this.submitAddress())
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Image($r('app.media.ic_send'))
                  .width(26)
                  .height(26)
                  .fillColor('#FFFFFF')
              }
              .width(52)
              .height(52)
              .backgroundColor('#FF8800')
              .borderRadius(8)
              .margin({ left: 12 })
              .onClick(() => this.submitAddress())
            }
            .width('100%')
            .margin({ top: 24 })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 28 })
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#121212')

        if (this.menuOpen) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .onClick(() => this.menuOpen = false)
          this.streamMenu()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }
}
