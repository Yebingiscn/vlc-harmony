import { NavController } from '../common/data/NavController';
import { AppColors } from '../common/constants/AppConstants';
import { MediaWrapper, Track } from '../common/models/MediaModels';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { PlaybackService, QueueItem } from '../common/data/PlaybackService';
import { VideoParam, VideoPlayItem } from './VideoPlayerPage';

/** HeaderMediaList 入参(album/playlist MediaLibraryItem)。 */
export class HeaderMediaListParam {
  title: string = '';
  description: string = '';
  isPlaylist: boolean = false;
  /** 播放列表 ID:传递后按 URI 匹配真实音频/视频轨道,而非加载全部。 */
  playlistId: number = -1;
}

function fmtTrackDuration(ms: number): string {
  if (ms <= 0) { return ''; }
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return `${m}:${ss}`;
}

/** 根据文件扩展名判断是否为视频。 */
function isVideoUri(uri: string): boolean {
  const lower = uri.toLowerCase();
  const videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.ts', '.iso', '.3gp', '.wmv', '.flv'];
  return videoExts.some((e: string) => lower.endsWith(e));
}

/** 检查 URI 是否为当前正在播放的曲目。 */
function isTrackNowPlaying(uri: string): boolean {
  const cur = PlaybackService.getCurrent();
  return cur !== null && cur.uri === uri;
}

/**
 * HeaderMediaListActivityPage —— 专辑/播放列表详情页。
 * 结构:顶部返回栏 + 封面/标题/副标题 + 操作按钮行(播放全部/随机) + 曲目列表。
 */
@ObservedV2
class HeaderMediaListVM {
  @Trace title: string = '';
  @Trace description: string = '';
  @Trace isPlaylist: boolean = false;
  @Trace tracks: Track[] = [];
  @Trace totalDuration: number = 0;

  load(param: HeaderMediaListParam): void {
    this.title = param.title.length > 0 ? param.title : 'Playlist';
    this.description = param.description;
    this.isPlaylist = param.isPlaylist;
    let list: Track[] = [];
    let total = 0;

    if (this.isPlaylist && param.playlistId >= 0) {
      const uriSet = new Set(MediaLibrary.getPlaylistUris(param.playlistId));
      const audios = MediaLibrary.getAudios();
      const videos = MediaLibrary.getVideos();
      for (const t of audios) {
        if (uriSet.has(t.uri)) {
          list.push(t);
          total += t.length;
        }
      }
      for (const v of videos) {
        if (uriSet.has(v.uri)) {
          const vt = new Track(v.id, v.title, v.uri);
          vt.length = v.length;
          vt.artworkPath = v.artworkUrl;
          list.push(vt);
          total += v.length;
        }
      }
    } else {
      const audios = MediaLibrary.getAudios();
      for (const t of audios) {
        list.push(t);
        total += t.length;
      }
    }

    this.tracks = list;
    this.totalDuration = total;
  }
}

@ComponentV2
export struct HeaderMediaListActivityPage {
  @Param param: HeaderMediaListParam = new HeaderMediaListParam();
  @Local vm: HeaderMediaListVM = new HeaderMediaListVM();
  /** 竖条可视化动画:3 根音频柱的高度(0~1)。 */
  @Local barHeights: number[] = [0.3, 0.7, 0.5];
  private eqAnimTimer: number = -1;

  aboutToAppear(): void {
    this.vm.load(this.param);
    // 竖条可视化动画:3 根柱高度正弦摆动,相位各差 1/3 周期。
    // 步进 30ms → 约 33fps,快节奏以肉眼明显能看到柱长在跳。
    let tick = 0;
    this.eqAnimTimer = setInterval(() => {
      tick++;
      const t = tick * 0.35; // 频率提升约 3 倍
      this.barHeights = [
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t)),
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t + Math.PI * 2 / 3)),
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t + Math.PI * 4 / 3)),
      ];
    }, 30);
  }

  aboutToDisappear(): void {
    if (this.eqAnimTimer !== -1) {
      clearInterval(this.eqAnimTimer);
      this.eqAnimTimer = -1;
    }
  }

  /** 构建播放队列并开始播放(不跳转页面)。 */
  private async playAll(startPos: number = 0): Promise<void> {
    if (this.vm.tracks.length === 0) { return; }
    const items: MediaWrapper[] = [];
    for (const t of this.vm.tracks) {
      // 根据扩展名区分音频/视频类型
      const mw = new MediaWrapper(t.id, t.title, t.uri, isVideoUri(t.uri) ? 0 : 1);
      mw.artistName = t.artistName;
      mw.artworkPath = t.artworkPath;
      items.push(mw);
    }
    // 始终用同一个播放队列,准备好后调用 play() 触发真实播放。
    // 第一次播放前先 load 队列(等同 append 后再切换到 startPos),后续切换曲目只需 seek + play。
    await PlaybackService.playList(MediaLibrary.toQueueItems(items), startPos, true);
    await PlaybackService.play();
  }

  private async shuffleAll(): Promise<void> {
    if (this.vm.tracks.length === 0) { return; }
    const start = Math.floor(Math.random() * this.vm.tracks.length);
    await this.playAll(start);
    PlaybackService.toggleShuffle();
  }

  /** 点击三点菜单:播放单曲并跳转到对应详情页。 */
  private async playSingleAndNavigate(item: Track): Promise<void> {
    const isVideo = isVideoUri(item.uri);
    const mw = new MediaWrapper(0, item.title, item.uri, isVideo ? 0 : 1);
    mw.artistName = item.artistName;
    mw.artworkPath = item.artworkPath;
    const qi = QueueItem.fromMediaWrapper(mw);
    await PlaybackService.playList([qi], 0, true);
    await PlaybackService.play();
    if (isVideo) {
      const param: VideoParam = {
        uri: item.uri,
        title: item.title,
        list: [{ uri: item.uri, title: item.title } as VideoPlayItem],
        index: 0,
      };
      NavController.push('VideoPlayer', param);
    } else {
      NavController.push('AudioPlayer');
    }
  }

  @Builder
  TrackItem(item: Track, position: number) {
    Row() {
      // 封面:优先用实际图片,回退到歌曲线框图标
      Image(item.artworkPath.length > 0 ? item.artworkPath : $r('app.media.ic_song'))
        .width(44).height(44)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
        .fillColor(item.artworkPath.length > 0 ? Color.Transparent : $r('app.color.font_light'))

      Column() {
        Text(item.title)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(isTrackNowPlaying(item.uri)
            ? AppColors.orange500 : $r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          if (item.artistName.length > 0) {
            Text(item.artistName)
              .fontSize(12).fontColor($r('app.color.list_subtitle'))
              .maxLines(1)
          }
          if (item.artistName.length > 0 && item.length > 0) {
            Text(' · ')
              .fontSize(12).fontColor($r('app.color.list_subtitle'))
          }
          if (item.length > 0) {
            Text(fmtTrackDuration(item.length))
              .fontSize(12).fontColor($r('app.color.list_subtitle'))
          }
        }
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })
      .alignItems(HorizontalAlign.Start)

      // 正在播放的曲目显示 3 条音频柱动画(相位各差 1/3 周期)
      if (isTrackNowPlaying(item.uri)) {
        Row({ space: 1.5 }) {
          Column()
            .width(3)
            .height(Math.max(2, Math.round(this.barHeights[0] * 18)))
            .borderRadius(2)
            .backgroundColor(AppColors.orange500)
            .animation({ duration: 80, curve: Curve.Linear })
          Column()
            .width(3)
            .height(Math.max(2, Math.round(this.barHeights[1] * 18)))
            .borderRadius(2)
            .backgroundColor(AppColors.orange500)
            .animation({ duration: 80, curve: Curve.Linear })
          Column()
            .width(3)
            .height(Math.max(2, Math.round(this.barHeights[2] * 18)))
            .borderRadius(2)
            .backgroundColor(AppColors.orange500)
            .animation({ duration: 80, curve: Curve.Linear })
        }
        .alignItems(VerticalAlign.Bottom)
        .height(20)
        .margin({ right: 2 })
      }

      Image($r('app.media.ic_more'))
        .width(24).height(24)
        .fillColor($r('app.color.list_subtitle'))
        .padding(4)
        .onClick(() => {
          void this.playSingleAndNavigate(item);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      void this.playAll(position);
    })
  }

  @Builder
  emptyState() {
    Column() {
      Image($r('app.media.ic_playlist_big'))
        .width(80).height(80)
        .fillColor($r('app.color.font_light'))
        .margin({ bottom: 16 })
      Text('播放列表为空')
        .fontSize(16).fontColor($r('app.color.list_subtitle'))
      Text('从视频或音频页面添加曲目到播放列表')
        .fontSize(13).fontColor($r('app.color.font_light'))
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        // ── 顶部返回栏(渐变从状态栏顶覆盖到标题下方) ──
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(28).height(28)
            .fillColor('#FFFFFF')
            .onClick(() => NavController.pop())

          Text(this.vm.title)
            .fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(28).height(28)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 44, bottom: 16 })
        .alignItems(VerticalAlign.Center)
        .linearGradient({ angle: 180, colors: [['#99000000', 0.0], ['#00000000', 1.0]] })

        Scroll() {
          Column() {
            // ── 头部信息区 ──
            Column() {
              // 封面图
              Image(this.vm.tracks.length > 0 && this.vm.tracks[0].artworkPath.length > 0
                ? this.vm.tracks[0].artworkPath
                : $r('app.media.ic_playlist_big'))
                .width(140).height(140)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .fillColor($r('app.color.card_background'))
                .margin({ bottom: 12 })

              // 标题/副标题
              Text(this.vm.title)
                .fontSize(22).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.list_title'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(`${this.vm.tracks.length} 首曲目 · ${this.vm.description}`)
                .fontSize(13)
                .fontColor($r('app.color.list_subtitle'))
                .margin({ top: 4 })

              // 操作按钮行
              Row({ space: 16 }) {
                Button() {
                  Row() {
                    Image($r('app.media.ic_play_player'))
                      .width(18).height(18).fillColor('#FFFFFF')
                    Text('播放全部')
                      .fontSize(14).fontColor('#FFFFFF')
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Capsule)
                .backgroundColor(AppColors.orange500)
                .height(38)
                .layoutWeight(1)
                .onClick(() => { void this.playAll(); })

                Button() {
                  Row() {
                    Image($r('app.media.ic_shuffle'))
                      .width(18).height(18).fillColor($r('app.color.list_title'))
                    Text('随机播放')
                      .fontSize(14).fontColor($r('app.color.list_title'))
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Capsule)
                .backgroundColor($r('app.color.card_background'))
                .height(38)
                .layoutWeight(1)
                .onClick(() => { void this.shuffleAll(); })
              }
              .width('100%')
              .margin({ top: 16 })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 16 })
            .alignItems(HorizontalAlign.Center)

            // ── 分隔 ──
            Row()
              .width('100%').height(6)
              .backgroundColor($r('app.color.background_default_darker'))

            // ── 曲目列表 ──
            if (this.vm.tracks.length === 0) {
              this.emptyState()
            } else {
              List({ space: 0 }) {
                ForEach(this.vm.tracks, (item: Track, idx: number) => {
                  ListItem() {
                    this.TrackItem(item, idx)
                  }
                }, (item: Track) => `${item.id}`)
              }
              .width('100%')
              .layoutWeight(1)
              .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 72, endMargin: 16 })
              .scrollBar(BarState.Off)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
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
  }
}
