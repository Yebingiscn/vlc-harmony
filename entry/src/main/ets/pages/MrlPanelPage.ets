import { promptAction } from '@kit.ArkUI';
import { NavController } from '../common/data/NavController';
import { PlaybackService } from '../common/data/PlaybackService';
import { AppColors, AppDimens } from '../common/constants/AppConstants';
import { MediaWrapper, VideoNavParam } from '../common/models/MediaModels';

/**
 * MrlPanelPage —— MRLPanelFragment(网络串流面板页)。
 * URL 输入框 + ic_send 按钮 + 串流历史 List(样例 MediaWrapper[])。
 * 文案/数值逐字照搬 .harmonyos/spec/pages/MRLPanelFragment.md。
 * 外部运行时契约(StreamsModel 历史源/上下文菜单/RenameDialog/VideoPlayerActivity.start 等)标 TODO 注释。
 */

function showToast(msg: string): void {
  promptAction.showToast({ message: msg });
}

/** 串流历史样例(对应 medialibrary.history(HISTORY_TYPE_NETWORK),未迁移)。 */
function sampleStreams(): MediaWrapper[] {
  const list: MediaWrapper[] = [
    new MediaWrapper(1, 'Big Buck Bunny', 'https://example.com/bbb.mp4', 0),
    new MediaWrapper(2, 'RTSP Demo Stream', 'rtsp://demo.example.com/stream', 0),
    new MediaWrapper(3, 'Sintel Movie', 'http://example.com/sintel.mp4', 0),
  ];
  return list;
}

@ComponentV2
export struct MrlPanelPage {
  @Local searchText: string = '';
  @Local streamList: MediaWrapper[] = sampleStreams();

  private processUri(): void {
    const text = this.searchText.trim();
    if (text.length === 0) {
      return;
    }
    // TODO(契约):MLServiceLocator.getAbstractMediaWrapper(text.toUri()) 构造 MediaWrapper。
    const mw = new MediaWrapper(Date.now(), text, text, 0);
    this.playMedia(mw);
    this.searchText = '';
  }

  private playMedia(mw: MediaWrapper): void {
    // TODO(契约):scheme 以 rtsp 开头 → VideoPlayerActivity.start;否则 MediaUtils.openMedia(PlaybackService)。
    if (mw.uri.startsWith('rtsp')) {
      const p: VideoNavParam = { uri: mw.uri, title: mw.title };
      NavController.push('VideoPlayer', p);
    } else {
      // PlaybackService 仅有 append(items)/play(),用 append 加入播放队列。
      const list: MediaWrapper[] = [mw];
      PlaybackService.getInstance().append(list);
    }
  }

  private onItemClick(item: MediaWrapper): void {
    this.playMedia(item);
  }

  private onMoreClick(): void {
    // TODO(契约):showContext(position) 弹上下文菜单(重命名/追加/加入播放列表/复制/删除/添加快捷方式)。
    showToast('More actions');
  }

  build() {
    NavDestination() {
      Column() {
        // 返回导航栏(标题 = "Streams")
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(AppColors.white)
            .margin({ left: 12 })
            .onClick(() => NavController.pop())
          Text($r('app.string.streams'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.white)
            .margin({ left: AppDimens.kl_half })
          Blank()
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppColors.orange800)

        Scroll() {
          Column() {
            // 顶部输入栏 mrlbar(elevation=4dp)
            Column() {
              Row() {
                TextInput({ text: this.searchText, placeholder: $r('app.string.open_mrl_dialog_msg') })
                  .type(InputType.URL)
                  .layoutWeight(1)
                  .margin({ left: AppDimens.default_margin, top: AppDimens.default_margin, bottom: AppDimens.default_margin })
                  .backgroundColor(AppColors.grey50)
                  .onChange((v: string) => {
                    this.searchText = v;
                  })
                  .onSubmit(() => this.processUri())
                Image($r('app.media.ic_send'))
                  .width(24)
                  .height(24)
                  .objectFit(ImageFit.CENTER)
                  .fillColor(AppColors.orange800)
                  .margin({ right: AppDimens.kl_normal })
                  .onClick(() => this.processUri())
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding({ top: AppDimens.kl_half, bottom: AppDimens.kl_half })
            .backgroundColor(AppColors.white)
            .shadow({ radius: 4, color: AppColors.black_transparent_50, offsetY: 2 })

            // 串流历史列表 mrl_list
            List({ space: 0 }) {
              ForEach(this.streamList, (item: MediaWrapper, index: number) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(item.title)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(AppColors.grey900)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(item.uri)
                        .fontSize(14)
                        .fontColor(AppColors.grey600)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                        .margin({ top: 2 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: AppDimens.kl_normal, top: AppDimens.default_margin, right: AppDimens.kl_normal, bottom: AppDimens.default_margin })

                    Image($r('app.media.ic_more'))
                      .width(24)
                      .height(24)
                      .objectFit(ImageFit.CENTER)
                      .fillColor(AppColors.grey700)
                      .padding(AppDimens.default_margin)
                      .onClick(() => this.onMoreClick())
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => this.onItemClick(item))
                }
              }, (item: MediaWrapper, index: number) => `${index}`)
            }
            .width('100%')
            .padding({ left: AppDimens.kl_half, top: 24, right: AppDimens.kl_half })
            .scrollBar(BarState.Off)
          }
          .width('100%')
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
  }
}
