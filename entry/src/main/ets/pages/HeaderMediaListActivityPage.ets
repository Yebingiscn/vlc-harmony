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

/** 把 URI 哈希成 0~2π 的相位偏移,让不同歌曲有不同视觉模式。 */
function uriPhase(uri: string): number {
  let h: number = 0;
  for (let i = 0; i < uri.length; i++) {
    h = (h * 31 + uri.charCodeAt(i)) | 0;
  }
  // 0~2π 之间
  return ((h % 1000) / 1000) * Math.PI * 2;
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
  @Local barHeights: number[] = [0.15, 0.15, 0.15];
  /**
   * 当前正在播放的曲目 URI(@Local,作为响应式中介)。
   * TrackItem 模板里用 `this.nowPlayingUri === item.uri` 判断高亮与柱状图,
   * 这样 setInterval 每次检测到切换时更新它,触发 build() 重新求值,柱状图跟着切。
   */
  @Local nowPlayingUri: string = '';
  /** 是否处于随机播放模式:由 setInterval 轮询 PlaybackService.isShuffle() 同步,驱动随机按钮背景色。 */
  @Local isShuffle: boolean = false;
  private eqAnimTimer: number = -1;
  private animTick: number = 0;
  /** 动画正在"跟随"播放队列里的哪一首 URI:变化时重置 tick,让竖条"跳"一下。 */
  private lastAnimatedUri: string = '';

  aboutToAppear(): void {
    this.vm.load(this.param);
    // 竖条可视化动画:绑定到 PlaybackService.getCurrent()。
    // - 无播放 → 静止低位
    // - 切歌 → reset tick,柱子从低位跳起来
    // - 不同歌 → URI 哈希做 phase 偏移,视觉模式不同
    this.eqAnimTimer = setInterval(() => {
      // 同步随机播放状态(用于按钮背景色高亮)
      const shuffle = PlaybackService.isShuffle();
      if (shuffle !== this.isShuffle) {
        this.isShuffle = shuffle;
      }
      const cur = PlaybackService.getCurrent();
      if (cur === null) {
        this.barHeights = [0.15, 0.15, 0.15];
        if (this.nowPlayingUri !== '') {
          this.nowPlayingUri = '';
        }
        this.lastAnimatedUri = '';
        return;
      }
      // 切歌时同步更新 nowPlayingUri(响应式),触发 TrackItem 重新判断"是否当前曲目"。
      if (cur.uri !== this.nowPlayingUri) {
        this.nowPlayingUri = cur.uri;
        this.animTick = 0;
        this.lastAnimatedUri = cur.uri;
      } else if (cur.uri !== this.lastAnimatedUri) {
        // 兜底:外部改了 current 但 nowPlayingUri 跟上了,仍重置 tick
        this.animTick = 0;
        this.lastAnimatedUri = cur.uri;
      }
      this.animTick++;
      const t = this.animTick * 0.35 + uriPhase(cur.uri);
      this.barHeights = [
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t)),
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t + Math.PI * 2 / 3)),
        0.15 + 0.85 * (0.5 + 0.5 * Math.sin(t + Math.PI * 4 / 3)),
      ];
    }, 30);
    // 进入页面默认:播放全部按钮高亮 + 从第一首开始播放
    void this.playAll(0);
  }

  aboutToDisappear(): void {
    if (this.eqAnimTimer !== -1) {
      clearInterval(this.eqAnimTimer);
      this.eqAnimTimer = -1;
    }
    // 离开播放列表详情页时停止播放(只在本页触发的播放,不影响其他来源)。
    // 此回调仅当用户从本详情页 pop 回主页时触发,推到子播放页不触发。
    PlaybackService.stop();
  }

  /** 构建播放队列并在当前页开始播放(不跳转播放页)。同时关掉随机,UI 立即切到"播放全部"高亮。 */
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
    // 显式关掉随机模式,让顶部按钮高亮切回"播放全部"
    PlaybackService.setShuffle(false);
    await PlaybackService.play();
    // 立刻同步响应式状态(不等 setInterval 的 30ms 延迟)
    this.isShuffle = false;
    this.nowPlayingUri = items[startPos].uri;
    this.animTick = 0;
  }

  private async shuffleAll(): Promise<void> {
    if (this.vm.tracks.length === 0) { return; }
    const start = Math.floor(Math.random() * this.vm.tracks.length);
    await this.playAll(start);
    // playAll 已经关了 shuffle,这里再开
    PlaybackService.setShuffle(true);
    this.isShuffle = true;
  }

  /** 点击三点菜单:单曲播放并跳转到对应播放页(音频→AudioPlayer,视频→VideoPlayer)。 */
  private async playSingle(item: Track): Promise<void> {
    const isVideo = isVideoUri(item.uri);
    const mw = new MediaWrapper(0, item.title, item.uri, isVideo ? 0 : 1);
    mw.artistName = item.artistName;
    mw.artworkPath = item.artworkPath;
    const qi = QueueItem.fromMediaWrapper(mw);
    await PlaybackService.playList([qi], 0, true);
    await PlaybackService.play();
    this.nowPlayingUri = item.uri;
    this.animTick = 0;
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
          .fontColor(this.nowPlayingUri === item.uri
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
      if (this.nowPlayingUri === item.uri) {
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
          // 三点菜单:单曲播放,不离开当前页(用单元素队列覆盖)
          void this.playSingle(item);
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

              // 操作按钮行(互斥分段选择器样式:isShuffle on → 随机高亮,off → 播放全部高亮)
              Row({ space: 16 }) {
                Button() {
                  Row() {
                    Image($r('app.media.ic_play_player'))
                      .width(18).height(18)
                      .fillColor(this.isShuffle ? $r('app.color.list_title') : '#FFFFFF')
                    Text('播放全部')
                      .fontSize(14)
                      .fontColor(this.isShuffle ? $r('app.color.list_title') : '#FFFFFF')
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Capsule)
                .backgroundColor(this.isShuffle ? $r('app.color.card_background') : AppColors.orange500)
                .height(38)
                .layoutWeight(1)
                .onClick(() => { void this.playAll(); })

                Button() {
                  Row() {
                    Image($r('app.media.ic_shuffle'))
                      .width(18).height(18)
                      .fillColor(this.isShuffle ? '#FFFFFF' : $r('app.color.list_title'))
                    Text('随机播放')
                      .fontSize(14)
                      .fontColor(this.isShuffle ? '#FFFFFF' : $r('app.color.list_title'))
                      .margin({ left: 6 })
                  }
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .type(ButtonType.Capsule)
                .backgroundColor(this.isShuffle ? AppColors.orange500 : $r('app.color.card_background'))
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
