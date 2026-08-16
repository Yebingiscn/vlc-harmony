import { AppColors } from '../common/constants/AppConstants';
import { BookMark } from '../common/models/BookmarkModels';

/**
 * BookmarkDialog —— 书签全屏 BottomSheet(非模态:背后播放进度条/控制条不挡)。
 * 参照 photos/添加到书签.png:顶栏「X 书签 +」+ 列表区 + 空态 + 底部时间线(进度 + 书签点)。
 *
 * 交互契约:
 *   点列表项     = 通知宿主 seek 到该时间
 *   点 +         = 通知宿主「当前时间点加书签」—— **不再关闭弹框**,列表实时更新
 *   长按列表项   = 通知宿主「请求改名 id」
 *   点右侧删除   = 直接删
 *   点 X / 关闭  = 仅关闭
 *   底部时间线   = 进度条 + 红色书签点(可视化当前 bookmarks),帮助用户判断「在哪个时间点加」
 */

@ComponentV2
export struct BookmarkDialog {
  @Param bookmarks: BookMark[] = [];
  /** 当前播放位置(毫秒)—— 用来画底部时间线上的"当前点"。 */
  @Param currentTimeMs: number = 0;
  /** 总时长(毫秒)—— 0 表示未知,时间线不画。 */
  @Param durationMs: number = 0;
  @Param mediaId: number = -1;
  // 面板用实色 background_default(原 #CC1C1C1C 半透黑在浅色下改为实白,更清晰)。
  readonly cPanelBg: Resource = $r('app.color.background_default');
  readonly cHeaderBg: Resource = $r('app.color.background_default');
  readonly cTimelineBg: Resource = $r('app.color.background_default');
  readonly cDivider: Resource = $r('app.color.divider');
  readonly cSubtle: Resource = $r('app.color.font_light');
  // ── 视觉常量 ─────────────────────────────────────────
  // 主题感知:浅色=白底深字,深色=深底浅字。资源定义见 base/dark element/color.json。
  readonly cDim: Resource = $r('app.color.list_subtitle');
  readonly cAccent: string = '#FF3B30';
  // 保留 panelHeight 仅给时间线计算 / 旧引用兜底(实际未使用)。
  readonly panelHeight: number = 0;

  @Event onClose: () => void = () => {
  };

  @Event onSeek: (timeMs: number) => void = () => {
  };

  @Event onAddAtCurrent: () => void = () => {
  };

  @Event onRename: (id: number) => void = () => {
  };
  // 全屏:不再使用固定高度,内容用 layoutWeight(1) 撑开,时间线固定在底。

  @Event onDelete: (id: number) => void = () => {
  };

  @Builder
  panelHeader() {
    Row() {
      // 左侧返回:36×36 深灰圆形底,白色 X 图标。
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(22).height(22)
          .fillColor($r('app.color.list_title'))
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor($r('app.color.divider'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onClose())

      // 中间:标题
      Text('书签')
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.list_title'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // 右侧保存书签:36×36 深灰圆形底,橙色 + 图标。
      Row() {
        Image($r('app.media.ic_bookmark_add'))
          .width(22).height(22)
          .fillColor(AppColors.orange500)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('#33FF8800')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => this.onAddAtCurrent())
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.cHeaderBg)
  }

  @Builder
  thinDivider() {
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.cDivider)
  }

  /** 底部时间线 + 书签点。高度 36,作为面板最底下一条。 */
  @Builder
  timeline() {
    Column() {
      // 进度条(实际播放进度)+ 红色书签点叠加
      Stack({ alignContent: Alignment.Start }) {
        // 底槽
        Row()
          .width('100%').height(4)
          .backgroundColor(this.cDivider)
          .borderRadius(2)

        // 已播放进度
        if (this.durationMs > 0) {
          Row()
            .width(`${Math.min(100, Math.max(0, this.currentTimeMs * 100 / this.durationMs))}%`)
            .height(4)
            .backgroundColor(AppColors.orange500)
            .borderRadius(2)
        }

        // 当前播放点(小竖线)
        if (this.durationMs > 0) {
          Column()
            .width(2).height(16)
            .backgroundColor(AppColors.orange500)
            .offset({ x: `${Math.min(100, Math.max(0, this.currentTimeMs * 100 / this.durationMs))}%` })
        }

        // 书签点(红心形)
        Repeat(this.bookmarks).each((bRepeatItem: RepeatItem<BookMark>) => {
          if (this.durationMs > 0) {
            Image($r('app.media.ic_bookmark_marker'))
              .width(14)
              .height(14)
              .fillColor(this.cAccent)
              .offset({ x: `${Math.min(100, Math.max(0, bRepeatItem.item.timeMs * 100 / this.durationMs))}%`, y: -5 })
              .onClick(() => this.onSeek(bRepeatItem.item.timeMs))
          }
        }).key((b: BookMark): string => `${b.id}`)
      }
      .width('100%')
      .height(16)
      .padding({ left: 0, right: 0 })
      .margin({ top: 4 })

      // 时间文字行
      Row() {
        Text(this.fmtTime(this.currentTimeMs))
          .fontSize(11).fontColor($r('app.color.list_title'))
        Blank()
        Text(this.durationMs > 0 ? this.fmtTime(this.durationMs) : '--:--')
          .fontSize(11).fontColor(this.cSubtle)
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    // bottom: 28 避让手势条;top: 10 普通内边距
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 28
    })
    .backgroundColor(this.cTimelineBg)
  }

  @Builder
  listItem(b: BookMark, index: number) {
    Row() {
      Image($r('app.media.ic_bookmark_marker'))
        .width(22).height(22)
        .fillColor(this.cAccent)
      Column() {
        Text(b.name.length > 0 ? b.name : `书签 ${index + 1}`)
          .fontSize(15).fontColor($r('app.color.list_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.fmtTime(b.timeMs))
          .fontSize(12).fontColor(this.cSubtle)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14, right: 12 })

      Image($r('app.media.ic_playlist_delete'))
        .width(20)
        .height(20)
        .fillColor(this.cSubtle)
        .padding(4)
        .onClick(() => this.onDelete(b.id))
    }
    .width('100%')
    .height(60)
    .padding({ left: 20, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onClick(() => this.onSeek(b.timeMs))
    .gesture(
      LongPressGesture().onAction(() => this.onRename(b.id))
    )
  }

  @Builder
  emptyState() {
    Column() {
      Blank().layoutWeight(1)
      Image($r('app.media.ic_fav_empty'))
        .width(120).height(120)
        .objectFit(ImageFit.Contain)
        .fillColor(this.cDim)
      Text('暂无书签')
        .fontSize(16).fontColor($r('app.color.list_title'))
        .margin({ top: 16 })
      Text('但那些真正喜欢的')
        .fontSize(12).fontColor(this.cSubtle)
        .margin({ top: 6 })
      Text('While the content they truly love')
        .fontSize(11).fontColor(this.cSubtle)
        .margin({ top: 2 })

      // 提示用户顶部有「+ 添加」按钮
      Text('点右上角「+」添加当前时间为书签')
        .fontSize(12)
        .fontColor(AppColors.orange500)
        .margin({ top: 18 })
        .padding({
          left: 14,
          right: 14,
          top: 8,
          bottom: 8
        })
        .backgroundColor('#33FF8800')
        .borderRadius(14)
      Blank().layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    // 直接渲染面板 Column 作为 sheet 内容 —— 不再套 Stack。
    // 之前那个全屏遮罩 Column(100% 高度)把整个 sheet 撑成了全屏,
    // 导致 panel 620 + 上面 700+ 像素空白,看起来"全屏但内容没填满"。
    // 现在 sheet 高度 = panel 高度(620),自动贴屏幕底,半透明背景让视频透出。
    Column() {
      this.panelHeader()
      this.thinDivider()
      // 始终渲染 List(不再 if/else 切换 empty/list),保证 sheet 内容高度稳定,
      // 避免 bindSheet FIT_CONTENT 模式下空态/列表切换触发 onDisappear → closeSheet。
      List({ space: 0 }) {
        if (this.bookmarks.length === 0) {
          ListItem() {
            this.emptyState()
          }
        } else {
          Repeat(this.bookmarks).each((bRepeatItem: RepeatItem<BookMark>) => {
            ListItem() {
              this.listItem(bRepeatItem.item, bRepeatItem.index)
            }
          }).key((b: BookMark): string => `${b.id}`).virtualScroll()
        }
        // 列表底部留白,避免最后一项贴边
        ListItem() {
          Row().width('100%').height(20)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({
        strokeWidth: 0.5,
        color: this.cDivider,
        startMargin: 56,
        endMargin: 12,
      })

      this.thinDivider()
      this.timeline()
    }
    .width('100%')
    .height('100%')
    // 85% 透黑底 —— 接近实色,只留一丝视频透出。
    .backgroundColor(this.cPanelBg)
    .alignItems(HorizontalAlign.Start)
  }

  /** 时间格式 mm:ss / h:mm:ss。 */
  private fmtTime(ms: number): string {
    const totalSec: number = Math.floor(ms / 1000);
    const h: number = Math.floor(totalSec / 3600);
    const m: number = Math.floor((totalSec % 3600) / 60);
    const s: number = totalSec % 60;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const ss: string = s < 10 ? `0${s}` : `${s}`;
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }
}
