import { AppColors } from '../common/constants/AppConstants';
import { PlaybackService } from '../common/data/PlaybackService';
import { VlcTrackInfo } from 'libvlcnapi.so';

/** 轨道数据载体。 */
export class VlcTrack {
  id: number;
  name: string;
  constructor(id: number, name: string) {
    this.id = id;
    this.name = name;
  }
}

/** 轨道单选行:选中态橙字 + 勾选图标。 */
@ComponentV2
struct TrackRow {
  @Param name: ResourceStr = '';
  @Param selected: boolean = false;
  @Event onRowClick: () => void = () => {};

  build() {
    Row() {
      Text(this.name)
        .fontSize(14)
        .fontColor(this.selected ? AppColors.orange500 : $r('app.color.list_title'))
        .layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.selected) {
        Image($r('app.media.ic_check_large')).width(20).height(20).fillColor(AppColors.orange500)
      }
    }
    .width('100%').height(44).padding({ left: 24, right: 16 }).alignItems(VerticalAlign.Center)
    .onClick(() => this.onRowClick())
  }
}

/** 轨道段:标题 + 折叠箭头(可选)+ 空态/轨道单选列表。 */
@ComponentV2
struct TrackSection {
  @Param title: string = '';
  @Param showMore: boolean = true;
  @Param emptyText: ResourceStr = '';
  @Param tracks: VlcTrack[] = [];
  @Param selectedId: number = -1;
  @Event onTrackClick: (id: number) => void = () => {};
  @Local collapsed: boolean = true;

  build() {
    Column() {
      Row() {
        Text(this.title).fontSize(16).fontColor($r('app.color.list_title')).margin({ left: 16, top: 16, right: 8 }).layoutWeight(1)
        if (this.showMore && this.tracks.length > 0) {
          Image($r('app.media.ic_collapse_arrow')).width(24).height(24).fillColor($r('app.color.list_title'))
            .padding(8).margin({ right: 8 })
            .rotate({ angle: this.collapsed ? 0 : 180 })
            .onClick(() => this.collapsed = !this.collapsed)
        }
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Center)

      if (this.tracks.length === 0) {
        Text(this.emptyText)
          .fontSize(14).fontColor(AppColors.grey500)
          .width('100%').padding({ left: 24, top: 8, bottom: 8 })
      } else {
        ForEach(this.tracks, (item: VlcTrack) => {
          TrackRow({
            name: item.name,
            selected: item.id === this.selectedId,
            onRowClick: () => this.onTrackClick(item.id),
          })
        }, (item: VlcTrack) => `${item.id}`)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }
}

/**
 * VideoTracksDialog —— 视频/音频/字幕轨道选择 BottomSheet(播放器黑色半透明卡)。
 * 三段(Audio / Subtitles / Video)纵向排列,段间 1vp white_transparent_10 分隔线。Video 段不显示折叠菜单。
 * TODO(契约): trackSelectionListener(id, TrackType) → PlaybackService 切换轨道;menuItemListener(opt)→延迟/选择字幕文件/下载字幕(由宿主决定)。
 */
@ComponentV2
export struct VideoTracksDialog {
  @Event onClose: () => void = () => {};
  @Event onTrackSelect: (id: number, type: string) => void = () => {};

  @Local audioTracks: VlcTrack[] = [];
  @Local subtitleTracks: VlcTrack[] = [];
  @Local videoTracks: VlcTrack[] = [];
  @Local selectedAudio: number = -1;
  @Local selectedSubtitle: number = -1;
  @Local selectedVideo: number = -1;

  aboutToAppear(): void {
    const svc = PlaybackService.getInstance();
    this.audioTracks = svc.getAudioTracks().map((t: VlcTrackInfo) => new VlcTrack(t.id, t.name));
    this.subtitleTracks = svc.getSpuTracks().map((t: VlcTrackInfo) => new VlcTrack(t.id, t.name));
    this.videoTracks = svc.getVideoTracks().map((t: VlcTrackInfo) => new VlcTrack(t.id, t.name));
    this.selectedAudio = svc.getAudioTrack();
    this.selectedSubtitle = svc.getSpuTrack();
    this.selectedVideo = svc.getVideoTrack();
  }

  build() {
    Scroll() {
      Column() {
        TrackSection({
          title: 'Audio',
          showMore: true,
          emptyText: $r('app.string.no_track'),
          tracks: this.audioTracks,
          selectedId: this.selectedAudio,
          onTrackClick: (id: number) => {
            this.selectedAudio = id;
            this.onTrackSelect(id, 'audio');
            this.onClose();
          },
        })
        Divider().color($r('app.color.divider')).strokeWidth(1).width('100%')
          .margin({ top: 8, bottom: 8 })
        TrackSection({
          title: 'Subtitles',
          showMore: true,
          emptyText: $r('app.string.no_track'),
          tracks: this.subtitleTracks,
          selectedId: this.selectedSubtitle,
          onTrackClick: (id: number) => {
            this.selectedSubtitle = id;
            this.onTrackSelect(id, 'spu');
            this.onClose();
          },
        })
        Divider().color($r('app.color.divider')).strokeWidth(1).width('100%')
          .margin({ top: 8, bottom: 8 })
        TrackSection({
          title: 'Video',
          showMore: false,
          emptyText: $r('app.string.no_track'),
          tracks: this.videoTracks,
          selectedId: this.selectedVideo,
          onTrackClick: (id: number) => {
            this.selectedVideo = id;
            this.onTrackSelect(id, 'video');
            this.onClose();
          },
        })
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
