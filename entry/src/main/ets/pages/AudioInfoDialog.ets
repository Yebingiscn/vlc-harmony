import { formatDuration, formatSize } from '../common/models/MediaModels';

/** 信息弹窗入参载体(ArkTS 数据载体一律 class,避免对象字面量赋 interface)。 */
export class AudioInfoParams {
  title: string = '';
  artist: string = '';
  album: string = '';
  genre: string = '';
  trackNumber: number = 0;
  year: string = '';
  durationMs: number = 0;
  uri: string = '';
  fileSize: number = 0;

  constructor() {
  }
}

/**
 * AudioInfoDialog —— 「信息展示」弹窗(对齐 Android CTX_INFORMATION → InfoActivity)。
 * 数据来源:
 *   - 标题/艺术家/专辑/时长:PlaybackService 当前曲目(MediaWrapper)。
 *   - 流派/音轨号/年份:从 MediaLibrary.getAudios() 按 URI 反查 Track 补齐。
 *   - 文件大小/路径:MediaWrapper.size / uri。
 *
 * 形态:与 PlaybackSpeedDialog 一致作为主 Stack 子节点渲染(底部弹层),不走 bindSheet。
 */
@ComponentV2
export struct AudioInfoDialog {
  // ── 视觉常量(与 PlaybackSpeedDialog / VideoInfoDialog 对齐) ──────────
  readonly cPanelBg: Resource = $r('app.color.background_default');
  readonly cHeaderBg: Resource = $r('app.color.background_default');
  readonly cDivider: Resource = $r('app.color.divider');
  readonly cDim: Resource = $r('app.color.list_subtitle');
  readonly cSubtle: Resource = $r('app.color.font_light');
  readonly cAccent: string = '#FF8800';
  // ── 真值数据(从外面传进来) ──────────────────────────
  @Param title: string = '';
  @Param artist: string = '';
  @Param album: string = '';
  @Param genre: string = '';
  @Param trackNumber: number = 0;
  @Param year: string = '';
  @Param durationMs: number = 0;
  @Param uri: string = '';
  @Param fileSize: number = 0;

  @Event onClose: () => void = () => {
  };

  // ── 顶栏 ──────────────────────────────────────
  @Builder
  header() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .backgroundColor($r('app.color.font_light'))
        .borderRadius(2)
        .margin({ top: 8, bottom: 10 })
      Row() {
        Row() {
          Image($r('app.media.ic_arrow_back'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.list_title'))
            .padding(2)
            .onClick(() => this.onClose())
        }
        .width(40)
        .justifyContent(FlexAlign.Start)

        Text('信息展示')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.list_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row().width(40)
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(this.cHeaderBg)
  }

  // ── 小节标题 ──────────────────────────────────
  @Builder
  sectionHeader(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.cAccent)
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: 18,
        bottom: 6
      })
  }

  // ── 单行信息 ──────────────────────────────────
  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14).fontColor(this.cDim)
        .width(76)
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 7,
      bottom: 7
    })
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      this.header()

      // 滚动区:媒体段 + 文件段,路径较长时可能超一屏
      Scroll() {
        Column() {
          // ── 媒体段 ─────────────────────────────────────
          this.sectionHeader('媒体')
          this.infoRow('标题', this.safe(this.title))
          this.infoRow('艺术家', this.safe(this.artist))
          this.infoRow('专辑', this.safe(this.album))
          this.infoRow('流派', this.safe(this.genre))
          this.infoRow('音轨号', this.trackNumber > 0 ? `${this.trackNumber}` : '—')
          this.infoRow('年份', this.safe(this.year))
          this.infoRow('时长', formatDuration(this.durationMs).length > 0 ? formatDuration(this.durationMs) : '—')

          // ── 文件段 ─────────────────────────────────────
          this.sectionHeader('文件')
          this.infoRow('大小', formatSize(this.fileSize).length > 0 ? formatSize(this.fileSize) : '—')
          this.infoRow('路径', this.safe(this.uri))

          // 底部留白(避让手势条)
          Row().width('100%').height(28)
        }
        .width('100%')
        // 显式声明:子项全部从顶部开始堆叠,不被 Column 居中。
        .alignItems(HorizontalAlign.Start)
      }
      .clip(false)
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      // 底部分隔(视觉封闭)
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(this.cDivider)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cPanelBg)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  /** 空值兜底 '—'(对齐 VideoInfoDialog)。 */
  private safe(v: string): string {
    return v.length > 0 ? v : '—';
  }
}
