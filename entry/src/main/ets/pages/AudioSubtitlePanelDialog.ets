import { AppColors } from '../common/constants/AppConstants';
import { PlaybackService } from '../common/data/PlaybackService';
import { VlcTrackInfo } from 'libvlcnapi.so';

/**
 * AudioSubtitlePanelDialog —— 音频 / 字幕信息面板。
 *
 * 任务 #6 容器骨架 + 任务 #7 字幕延迟子视图。
 *
 * 内部 view 切换：
 *   - 'main'         默认视图:当前音频 / 音频轨道 / 当前字幕 / 字幕轨道 / 字幕延迟入口行 / 操作行
 *   - 'subtitleDelay' 子视图:返回上一级 + 当前值显示 + Slider + 步进按钮 + 重置
 *
 * 设计要点:
 *   - 字幕延迟入口点击直接在面板内切到子视图,避免 bindSheet 嵌套抖动。
 *   - 切换轨道不自动关闭面板(传 onTrackChange 而非 onTrackSelect),便于连续试听。
 *   - 时序:host 在 sheetKind='audioSubInfo' 时同步 spuDelayUs,改延迟时回调 onSetSpuDelay,
 *     host 调用 PlaybackService.setSpuDelay(us) + 回写本地 + 写 libvlc。
 *
 * 复用策略:本文件自包含 VlcTrack / TrackRow / TrackSection / MetaRow(与 VideoTracksDialog 同型),
 *   未对 VideoTracksDialog 做改动,避免影响已有面板行为。
 */

// ─── 复用结构（与 VideoTracksDialog 同型） ──────────────────────────────────────

class VlcTrack {
  id: number;
  name: string;
  constructor(id: number, name: string) {
    this.id = id;
    this.name = name;
  }
}

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
        Text(this.title).fontSize(16).fontColor($r('app.color.list_title'))
          .margin({ left: 16, top: 16, right: 8 }).layoutWeight(1)
        if (this.showMore && this.tracks.length > 0) {
          Image($r('app.media.ic_collapse_arrow')).width(24).height(24)
            .fillColor($r('app.color.list_title'))
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
      } else if (!this.collapsed) {
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

@ComponentV2
struct MetaRow {
  @Param label: ResourceStr = '';
  @Param value: ResourceStr = '';

  build() {
    Row() {
      Text(this.label).fontSize(13).fontColor(AppColors.grey500)
      Blank().layoutWeight(1)
      Text(this.value).fontSize(13).fontColor($r('app.color.list_title'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').padding({ left: 24, right: 24, top: 6, bottom: 6 })
  }
}

// ─── 字幕/音频延迟子视图：步进按钮直接在 build 内 inline 写 ───────────────────
// 注:ArkTS 严格模式下 @Builder 函数参数不接受函数类型,
//   所以步进按钮不能抽 builder 函数,只能 inline 写。

// ─── 面板主体 ────────────────────────────────────────────────────────────────

/**
 * SPU 延迟边界与步长。常量化避免 magic number 散落。
 * 微秒级上下限 -5s..+5s,与步进按钮共同锁定同一约束。
 */
const SPU_DELAY_MIN_US: number = -5_000_000;
const SPU_DELAY_MAX_US: number = 5_000_000;
const STEP_100_MS_US: number = 100_000;
const STEP_10_MS_US: number = 10_000;

@ComponentV2
export struct AudioSubtitlePanelDialog {
  @Event onClose: () => void = () => {};
  /** 切换轨道但保留 sheet(让用户多次试听)。 */
  @Event onTrackChange: (id: number, type: string) => void = () => {};
  /** 设置字幕延迟(单位:微秒)。host 应调用 PlaybackService.setSpuDelay 并回写 spuDelayUs。 */
  @Event onSetSpuDelay: (us: number) => void = () => {};
  /** 设置音频延迟(单位:微秒)。host 应调用 PlaybackService.setAudioDelay 并回写 audioDelayUs。 */
  @Event onSetAudioDelay: (us: number) => void = () => {};
  @Event onPickSubtitle: () => void = () => {};
  @Event onDownloadSubtitle: () => void = () => {};

  // 当前音频元数据(由 VideoPlayerPage 注入,与 VideoInfoDialog 同源)。
  @Require @Param audioCodec: string = '';
  @Require @Param audioLang: string = '';
  @Require @Param audioChannels: string = '';
  @Require @Param audioSampleRate: string = '';
  @Require @Param bitrate: string = '';
  /** 当前字幕延迟(微秒)。滑动/步进时由 host 回写。 */
  @Param spuDelayUs: number = 0;
  /** 当前音频延迟(微秒)。 */
  @Param audioDelayUs: number = 0;

  @Local audioTracks: VlcTrack[] = [];
  @Local subtitleTracks: VlcTrack[] = [];
  @Local selectedAudio: number = -1;
  @Local selectedSubtitle: number = -1;
  /** 子视图切换;默认在主视图。 */
  @Local view: 'main' | 'subtitleDelay' | 'audioDelay' = 'main';

  aboutToAppear(): void {
    // 防御：bindSheet 可能在某些场景下复用 Dialog 实例(而非销毁重建),
    // @Local view 残留上次关闭时的值会让第二次进入直接落在子视图里。
    // 每次挂载都强制回到主视图,从入口行开始走流程。
    this.view = 'main';
    const svc = PlaybackService.getInstance();
    this.audioTracks = svc.getAudioTracks().map((t: VlcTrackInfo) => new VlcTrack(t.id, t.name));
    this.subtitleTracks = svc.getSpuTracks().map((t: VlcTrackInfo) => new VlcTrack(t.id, t.name));
    this.selectedAudio = svc.getAudioTrack();
    this.selectedSubtitle = svc.getSpuTrack();
  }

  build() {
    Column() {
      if (this.view === 'subtitleDelay') {
        this.subtitleDelayView()
      } else if (this.view === 'audioDelay') {
        this.audioDelayView()
      } else {
        this.mainView()
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  // ── 主视图 ────────────────────────────────────────────────────────────────

  @Builder
  private mainView(): void {
    Column() {
      this.topBar('音频', () => this.onClose())

      Scroll() {
        Column() {
          this.sectionHeader('当前音频', $r('app.media.ic_player_audiotrack'))
          MetaRow({ label: '编码', value: this.audioCodec.length > 0 ? this.audioCodec : '—' })
          MetaRow({ label: '语言', value: this.audioLang.length > 0 ? this.audioLang : '—' })
          MetaRow({ label: '声道', value: this.audioChannels.length > 0 ? this.audioChannels : '—' })
          MetaRow({
            label: '采样率',
            value: this.audioSampleRate.length > 0 ? `${this.audioSampleRate} Hz` : '—',
          })
          MetaRow({
            label: '码率',
            value: this.bitrate.length > 0 ? `${this.bitrate} bps` : '—',
          })
          // this.divider()
          //
          // TrackSection({
          //   title: '音频轨道',
          //   showMore: false,
          //   emptyText: $r('app.string.no_track'),
          //   tracks: this.audioTracks,
          //   selectedId: this.selectedAudio,
          //   onTrackClick: (id: number): void => {
          //     this.selectedAudio = id;
          //     this.onTrackChange(id, 'audio');
          //   },
          // })
          // this.divider()
          //
          // this.sectionHeader('当前字幕', $r('app.media.ic_subtitles'))
          // MetaRow({
          //   label: '字幕轨',
          //   value: this.subtitleName(this.selectedSubtitle),
          // })
          // this.divider()
          //
          // TrackSection({
          //   title: '字幕轨道',
          //   showMore: false,
          //   emptyText: $r('app.string.no_track'),
          //   tracks: this.subtitleTracks,
          //   selectedId: this.selectedSubtitle,
          //   onTrackClick: (id: number): void => {
          //     this.selectedSubtitle = id;
          //     this.onTrackChange(id, 'spu');
          //   },
          // })
          // this.divider()
          //
          // // 字幕延迟入口行:点击切到 'subtitleDelay' 子视图,显示当前值。
          // this.subtitleDelayEntryRow()
          // this.divider()
          //
          // // 音频延迟入口行:点击切到 'audioDelay' 子视图。
          // this.audioDelayEntryRow()
          // this.divider()
          //
          // this.actionRow('选择字幕文件', $r('app.media.ic_subtitles_file'), () => this.onPickSubtitle())
          // this.actionRow('下载字幕', $r('app.media.ic_download_subtitles'), () => this.onDownloadSubtitle())
        }
        .width('100%').padding({ bottom: 32 }).alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }
    .width('100%').height('100%')
  }

  // ── 字幕延迟子视图 ────────────────────────────────────────────────────────

  @Builder
  private subtitleDelayView(): void {
    Column() {
      this.topBar('字幕延迟', () => {
        this.view = 'main';
      })

      Column() {
        // 当前值大卡片
        Row() {
          Blank().layoutWeight(1)
          Text(this.formatDelayUs(this.spuDelayUs))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.spuDelayUs === 0 ? $r('app.color.list_title') : AppColors.orange500)
          Blank().layoutWeight(1)
        }
        .width('100%').height(110)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ left: 20, right: 20, top: 24 })
        .alignItems(VerticalAlign.Center)

        Text('调节范围 -5.0s ～ +5.0s,Slider 步长 100ms')
          .fontSize(11).fontColor(AppColors.grey500)
          .margin({ top: 8 })

        // Slider
        Slider({
          value: Math.max(SPU_DELAY_MIN_US, Math.min(SPU_DELAY_MAX_US, this.spuDelayUs)) / 1000,
          min: SPU_DELAY_MIN_US / 1000,
          max: SPU_DELAY_MAX_US / 1000,
          step: 0.1,
          style: SliderStyle.OutSet,
        })
          .width('90%')
          .blockColor('#FF8800')
          .selectedColor('#FF8800')
          .trackColor('#61FFFFFF')
          .margin({ top: 24 })
          .onChange((v: number, _mode: SliderChangeMode): void => {
            this.onSetSpuDelay(Math.floor(v * 1000) * 1000);
          })

        // 步进按钮 — 直接 inline 4 个 Button,每个 .onClick 闭包捕获 this。
        Row({ space: 12 }) {
          Button('-100ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetSpuDelay(this.clampDelay(this.spuDelayUs - STEP_100_MS_US)))
          Button('-10ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetSpuDelay(this.clampDelay(this.spuDelayUs - STEP_10_MS_US)))
          Button('+10ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetSpuDelay(this.clampDelay(this.spuDelayUs + STEP_10_MS_US)))
          Button('+100ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetSpuDelay(this.clampDelay(this.spuDelayUs + STEP_100_MS_US)))
        }
        .width('100%').padding({ left: 20, right: 20, top: 24 })

        // 重置
        Button('重置')
          .width(120).height(40)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.list_title'))
          .margin({ top: 32 })
          .onClick(() => this.onSetSpuDelay(0))

        Blank().layoutWeight(1)
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
  }

  // ── 音频延迟子视图 ────────────────────────────────────────────────────────

  @Builder
  private audioDelayView(): void {
    Column() {
      this.topBar('音频延迟', () => {
        this.view = 'main';
      })

      Column() {
        // 当前值大卡片
        Row() {
          Blank().layoutWeight(1)
          Text(this.formatDelayUs(this.audioDelayUs))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.audioDelayUs === 0 ? $r('app.color.list_title') : AppColors.orange500)
          Blank().layoutWeight(1)
        }
        .width('100%').height(110)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ left: 20, right: 20, top: 24 })
        .alignItems(VerticalAlign.Center)

        Text('调节范围 -5.0s ～ +5.0s,Slider 步长 100ms')
          .fontSize(11).fontColor(AppColors.grey500)
          .margin({ top: 8 })

        // Slider —— 与字幕延迟同样的范围和步长,只是绑定 audioDelayUs。
        Slider({
          value: Math.max(SPU_DELAY_MIN_US, Math.min(SPU_DELAY_MAX_US, this.audioDelayUs)) / 1000,
          min: SPU_DELAY_MIN_US / 1000,
          max: SPU_DELAY_MAX_US / 1000,
          step: 0.1,
          style: SliderStyle.OutSet,
        })
          .width('90%')
          .blockColor('#FF8800')
          .selectedColor('#FF8800')
          .trackColor('#61FFFFFF')
          .margin({ top: 24 })
          .onChange((v: number, _mode: SliderChangeMode): void => {
            this.onSetAudioDelay(Math.floor(v * 1000) * 1000);
          })

        // 步进按钮 — 直接 inline 4 个 Button,每个 .onClick 闭包捕获 this。
        Row({ space: 12 }) {
          Button('-100ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetAudioDelay(this.clampDelay(this.audioDelayUs - STEP_100_MS_US)))
          Button('-10ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetAudioDelay(this.clampDelay(this.audioDelayUs - STEP_10_MS_US)))
          Button('+10ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetAudioDelay(this.clampDelay(this.audioDelayUs + STEP_10_MS_US)))
          Button('+100ms')
            .type(ButtonType.Normal).borderRadius(8)
            .backgroundColor($r('app.color.card_background')).fontColor($r('app.color.list_title'))
            .fontSize(13).height(40).layoutWeight(1)
            .onClick((): void => this.onSetAudioDelay(this.clampDelay(this.audioDelayUs + STEP_100_MS_US)))
        }
        .width('100%').padding({ left: 20, right: 20, top: 24 })

        // 重置
        Button('重置')
          .width(120).height(40)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.list_title'))
          .margin({ top: 32 })
          .onClick(() => this.onSetAudioDelay(0))

        Blank().layoutWeight(1)
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
  }

  // ── 顶栏通用 ──────────────────────────────────────────────────────────────

  @Builder
  private topBar(title: string, onBack: () => void): void {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(28).height(28)
        .fillColor($r('app.color.list_title'))
        .padding(2)
        .onClick(() => onBack())
      Text(title)
        .fontSize(18).fontWeight(600)
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Row().width(28)
    }
    .width('100%').height(56).padding({ left: 16, right: 16, top: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // 主视图中"字幕延迟"入口行,点击切到子视图。
  @Builder
  private subtitleDelayEntryRow(): void {
    Column() {
      this.sectionHeader('字幕延迟', $r('app.media.ic_subtitles'))
      Row() {
        Text('当前值').fontSize(13).fontColor(AppColors.grey500)
        Blank().layoutWeight(1)
        Text(this.formatDelayUs(this.spuDelayUs))
          .fontSize(13).fontColor($r('app.color.list_title'))
        Image($r('app.media.ic_arrow_right')).width(20).height(20)
          .fillColor('#9E9E9E').margin({ left: 8 })
      }
      .width('100%').height(44).padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.view = 'subtitleDelay';
      })
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  // 主视图中"音频延迟"入口行,与 subtitleDelayEntryRow 同构。
  @Builder
  private audioDelayEntryRow(): void {
    Column() {
      this.sectionHeader('音频延迟', $r('app.media.ic_player_audiotrack'))
      Row() {
        Text('当前值').fontSize(13).fontColor(AppColors.grey500)
        Blank().layoutWeight(1)
        Text(this.formatDelayUs(this.audioDelayUs))
          .fontSize(13).fontColor($r('app.color.list_title'))
        Image($r('app.media.ic_arrow_right')).width(20).height(20)
          .fillColor('#9E9E9E').margin({ left: 8 })
      }
      .width('100%').height(44).padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.view = 'audioDelay';
      })
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  // ── 主视图通用 builder ────────────────────────────────────────────────────

  @Builder
  private divider(): void {
    Divider().color($r('app.color.divider')).strokeWidth(1)
      .margin({ top: 8, bottom: 8 }).width('100%')
  }

  @Builder
  private sectionHeader(title: string, icon: Resource): void {
    Row() {
      Image(icon).width(18).height(18).fillColor($r('app.color.list_title'))
        .margin({ right: 8 })
      Text(title).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.list_title'))
    }
    .width('100%').padding({ left: 24, top: 16, bottom: 4, right: 16 })
  }

  @Builder
  private actionRow(title: ResourceStr, icon: Resource, onTap: () => void): void {
    Row() {
      Image(icon).width(20).height(20).fillColor($r('app.color.list_title'))
        .margin({ right: 12 })
      Text(title).fontSize(15).fontColor($r('app.color.list_title')).layoutWeight(1)
      Image($r('app.media.ic_arrow_right')).width(20).height(20).fillColor('#9E9E9E')
    }
    .width('100%').height(52).padding({ left: 24, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onTap())
  }

  // ── 工具 ──────────────────────────────────────────────────────────────────

  // 当前选中字幕轨的可读名;id=-1 表示关闭。
  private subtitleName(id: number): ResourceStr {
    if (id < 0) {
      return '关闭';
    }
    const found = this.subtitleTracks.find((t: VlcTrack): boolean => t.id === id);
    return found ? found.name : '—';
  }

  private formatDelayUs(us: number): string {
    const ms = us / 1000;
    const sign = ms >= 0 ? '+' : '';
    return `${sign}${ms.toFixed(2)}s`;
  }

  private clampDelay(us: number): number {
    return Math.max(SPU_DELAY_MIN_US, Math.min(SPU_DELAY_MAX_US, us));
  }
}
