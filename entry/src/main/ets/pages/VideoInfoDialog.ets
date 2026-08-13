
/**
 * VideoInfoDialog —— 「视频信息」全屏弹窗。
 * 数据来源:
 *   - 标题、时长、分辨率:从 vm.title / vm.duration / vm.videoWidth|Height 传入。
 *   - 视频/音频编码(language):从 libVLC 当前选中轨道描述(`getCurrentVideoTrackInfo/AudioTrackInfo`)传入。
 *   - 码率 / 帧率 / 采样率 / 声道:libVLC 未在 d.ts 暴露,继续用占位('—')。
 *
 * 形态:与 BookmarkDialog 一样作为主 Stack 子节点渲染,不走 bindSheet。
 */

interface VideoInfoState {
  title: string;
  durationMs: number;
  width: number;
  height: number;

  /** 解码码率(蓝)序列,数值单位 kb/s,数组长度 = 曲线点数。 */
  decodedSeries: number[];

  /** 输入码率(红)序列。 */
  inputSeries: number[];
}

@ComponentV2
export struct VideoInfoDialog {
  // 主题感知:浅色=白底深字,深色=深底浅字。资源定义见 base/dark element/color.json。
  readonly cPanelBg: Resource = $r('app.color.background_default');
  // ── 视觉常量(与 BookmarkDialog 对齐) ───────────────
  readonly cHeaderBg: Resource = $r('app.color.background_default');
  readonly cTimelineBg: Resource = $r('app.color.card_background');
  readonly cDivider: Resource = $r('app.color.divider');
  readonly cSubtle: Resource = $r('app.color.font_light');
  readonly cDim: Resource = $r('app.color.list_subtitle');
  readonly cAccent: string = '#FF8800';
  readonly cBlue: string = '#3FA9F5';
  readonly cRed: string = '#FF3B30';
  // 注:不能用 width/height 作 @Param 名,会与 ComponentV2 内置的 width/height 通用属性冲突。
  @Param title: string = '';
  // ── 真值数据(从外面传进来) ──────────────────────────
  @Param durationMs: number = 0;
  @Param videoWidth: number = 0;
  @Param videoHeight: number = 0;
  /** libVLC 当前选中的视频轨道描述(name 即 codec 描述)。空表示无。 */
  @Param videoCodec: string = '';
  /** libVLC 当前选中的音频轨道描述(name 即 codec 描述)。空表示无。 */
  @Param audioCodec: string = '';
  /** 视频语言(BCP-47,如 'en')。空='—' */
  @Param videoLang: string = '';
  /** 视频帧率(如 '25.000')。空='—' */
  @Param videoFps: string = '';
  /** 音频语言(BCP-47,如 'en')。空='—' */
  @Param audioLang: string = '';
  /** 音频声道(如 '2'=立体声, '6'=5.1)。空='—' */
  @Param audioChannels: string = '';
  /** 音频采样率(Hz,如 '48000')。空='—' */
  @Param audioSampleRate: string = '';
  /** 总码率(bits/s),空='—' */
  @Param bitrate: string = '';

  /** 分辨率字符串:0 宽高时返回 --。 */
  private get resolution(): string {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return '--';
    }
    return `${this.videoWidth}x${this.videoHeight}`;
  }

  // 折线图相关字段(bitrateGraph)已删 —— 那部分是假数据,本轮不展示。
  // 等接 libVLC 真实 stats 后再加。

  @Event onClose: () => void = () => {
  };

  // ── 视觉子组件 ─────────────────────────────────────
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

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14).fontColor(this.cDim)
        .width(72)
      Text(value)
        .fontSize(14).fontColor($r('app.color.list_title'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(28)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  panelHeader() {
    Row() {
      // 左 40 容器(对称,让标题视觉居中)
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

      Text(this.title.length > 0 ? this.title : '视频信息')
        .fontSize(17)
        .fontWeight(600)
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 右 40 占位(与左对称)
      Row().width(40)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12, top: 20 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.cHeaderBg)
  }

  build() {
    Column() {
      this.panelHeader()

      // 滚动区:两段内容(视频/音频),后续接真数据时可能超过一屏
      Scroll() {
        Column() {
          // ── 视频段 ─────────────────────────────────────
          this.sectionHeader('视频')
          this.infoRow('编码', this.videoCodec.length > 0 ? this.videoCodec : '—')
          this.infoRow('语言', this.videoLang)
          this.infoRow('分辨率', this.resolution)
          this.infoRow('帧率', this.videoFps)
          this.infoRow('码率', this.fmtBitrate(this.bitrate))
          this.infoRow('时长', this.fmtDuration(this.durationMs))

          // ── 音频段 ─────────────────────────────────────
          this.sectionHeader('音频')
          this.infoRow('编码', this.audioCodec.length > 0 ? this.audioCodec : '—')
          this.infoRow('语言', this.audioLang)
          this.infoRow('声道', this.audioChannels)
          this.infoRow('采样率', this.audioSampleRate)

          // 底部留白(避让手势条)
          Row().width('100%').height(28)
        }
        .width('100%')
        // 显式声明:子项全部从顶部开始堆叠,不被 Column 居中。
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cPanelBg)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  /** 单条折线 SVG。points 是归一化后的像素坐标(基于 320x180 画布)。 */
  // bitrateGraph 整段删除 —— 等接 libVLC 真实 stats 后再加。

  /** 时长字符串 mm:ss / h:mm:ss。 */
  private fmtDuration(ms: number): string {
    if (ms <= 0) {
      return '--:--';
    }
    const totalSec: number = Math.floor(ms / 1000);
    const h: number = Math.floor(totalSec / 3600);
    const m: number = Math.floor((totalSec % 3600) / 60);
    const s: number = totalSec % 60;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const ss: string = s < 10 ? `0${s}` : `${s}`;
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  /** 码率格式化:bits/s → kb/s / Mb/s;空串返回 '—'。 */
  private fmtBitrate(raw: string): string {
    if (raw.length === 0) {
      return '—';
    }
    const bps: number = parseInt(raw);
    if (isNaN(bps) || bps <= 0) {
      return '—';
    }
    if (bps >= 1000000) {
      return `${(bps / 1000000).toFixed(1)} Mb/s`;
    }
    return `${Math.round(bps / 1000)} kb/s`;
  }
}
