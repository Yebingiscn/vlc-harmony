import { AppColors } from '../common/constants/AppConstants';

/**
 * VideoInfoDialog —— 「视频信息」全屏弹窗。
 * 参照 photos/获取视频信息.png:顶栏(标题+X)+ 三段(视频/音频/视频信息)+ 码率折线图。
 *
 * 数据来源:
 *   - 标题、时长(真值,从 vm.title / vm.duration 传进来)
 *   - 视频/音频编/语/分/帧(占位 —— AVPlayer 不暴露轨道详情,需 libVLC 的 mediaTrackInfo 才能真)
 *   - 码率图(占位 —— AVPlayer 不直接暴露码率,这里画一组稳定的样例曲线)
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
  @Event onClose: () => void = () => {};

  // ── 视觉常量(与 BookmarkDialog 对齐) ───────────────
  readonly cPanelBg: string = '#D91C1C1C';
  readonly cHeaderBg: string = '#E61C1C1C';
  readonly cTimelineBg: string = '#CC1C1C1C';
  readonly cDivider: string = '#33FFFFFF';
  readonly cSubtle: string = '#F2FFFFFF';
  readonly cDim: string = '#B3FFFFFF';
  readonly cAccent: string = '#FF8800';
  readonly cBlue: string = '#3FA9F5';
  readonly cRed: string = '#FF3B30';

  // ── 真值数据(从外面传进来) ──────────────────────────
  // 注:不能用 width/height 作 @Param 名,会与 ComponentV2 内置的 width/height 通用属性冲突。
  @Param title: string = '';
  @Param durationMs: number = 0;
  @Param videoWidth: number = 0;
  @Param videoHeight: number = 0;

  // ── 轨道详情(本期占位 —— 后续接 libVLC 媒体探针再换真值) ──
  readonly videoCodec: string = 'H264 – MPEG-4 AVC (part 10)';
  readonly videoLang: string = '英文';
  readonly videoFps: string = '25.000';
  readonly audioCodec: string = 'MPEG AAC Audio';
  readonly audioLang: string = '英文';
  readonly audioChannels: string = '2';
  readonly audioSampleRate: string = '48000 Hz';

  // 折线图相关字段(bitrateGraph)已删 —— 那部分是假数据,本轮不展示。
  // 等接 libVLC 真实 stats 后再加。

  /** 分辨率字符串:0 宽高时返回 --。 */
  private get resolution(): string {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return '--';
    }
    return `${this.videoWidth}x${this.videoHeight}`;
  }

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

  // ── 视觉子组件 ─────────────────────────────────────
  @Builder
  sectionHeader(text: string) {
    Text(text)
      .fontSize(15).fontWeight(FontWeight.Medium)
      .fontColor(this.cAccent)
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 6 })
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14).fontColor(this.cDim)
        .width(72)
      Text(value)
        .fontSize(14).fontColor('#FFFFFF')
        .layoutWeight(1)
    }
    .width('100%')
    .height(28)
    .padding({ left: 20, right: 20 })
  }

  /** 单条折线 SVG。points 是归一化后的像素坐标(基于 320x180 画布)。 */
  // bitrateGraph 整段删除 —— 等接 libVLC 真实 stats 后再加。

  @Builder
  panelHeader() {
    Row() {
      // 左 40 容器(对称,让标题视觉居中)
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(28).height(28).fillColor('#FFFFFF')
          .padding(2)
          .onClick(() => this.onClose())
      }
      .width(40)
      .justifyContent(FlexAlign.Start)

      Text(this.title.length > 0 ? this.title : '视频信息')
        .fontSize(17).fontWeight(600).fontColor('#FFFFFF')
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
          this.infoRow('编码', this.videoCodec)
          this.infoRow('语言', this.videoLang)
          this.infoRow('分辨率', this.resolution)
          this.infoRow('帧率', this.videoFps)
          this.infoRow('时长', this.fmtDuration(this.durationMs))

          // ── 音频段 ─────────────────────────────────────
          this.sectionHeader('音频')
          this.infoRow('编码', this.audioCodec)
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
}
