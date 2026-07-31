import { AppColors } from '../common/constants/AppConstants';
import { Playlist } from '../common/models/MediaModels';
import { inputMethod } from '@kit.IMEKit';

/** 保存动作载荷 —— ArkTS 不允许内联对象字面量做类型,提取到命名 interface。 */
export interface AddToPlaylistAction {
  newName: string;
  selectedIds: number[];
  replace: boolean;
}

/**
 * AddToPlaylistDialog —— 「保存到播放列表」弹窗(1/3 屏高,贴底)。
 *
 * 交互流程(本轮新):
 *   1. 输入框 + 「新建」按钮:点击后,新歌单**立刻**插入下面的列表并**自动勾选**;
 *      输入框清空,可继续新建。
 *   2. 列表:可点歌单 Radio 切换选中。
 *   3. 底部「保存」:把当前勾选 + 替换开关 一次性提交给宿主。
 *
 * 数据:in-memory(本期不持久化),关闭弹框不丢,退出 app 才丢。
 */

@ComponentV2
export struct AddToPlaylistDialog {
  @Event onClose: () => void = () => {};
  /** 保存:回调传出当前选中的歌单 id + 是否替换。 */
  @Event onConfirm: (action: AddToPlaylistAction) => void = () => {};

  @Param mediaCount: number = 1;

  // ── 视觉常量 ─────────────────────────────────────
  readonly cPanelBg: string = '#D91C1C1C';
  readonly cHeaderBg: string = '#E61C1C1C';
  readonly cInputBg: string = '#1F1F1F';
  readonly cInputBorder: string = '#FF8800';
  readonly cSubtle: string = '#F2FFFFFF';
  readonly cDim: string = '#B3FFFFFF';
  readonly cAccent: string = '#FF8800';
  readonly cDivider: string = '#33FFFFFF';

  @Local newName: string = '';
  @Local playlists: Playlist[] = [];
  @Local selected: Set<number> = new Set<number>();
  @Local replace: boolean = false;
  private idSeq: number = 1;

  private canCreate(): boolean {
    return this.newName.trim().length > 0;
  }

  private canSave(): boolean {
    return this.selected.size > 0;
  }

  private toggleSelect(id: number): void {
    const next: Set<number> = new Set<number>(this.selected);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selected = next;
  }

  /**
   * 新建:插到列表,自动勾选,清空输入框,隐藏输入法。
   * 不关闭弹框 —— 用户可能想连续新建。
   */
  private createNew(): void {
    const name: string = this.newName.trim();
    if (name.length === 0) {
      return;
    }
    const id: number = this.idSeq++;
    const p: Playlist = new Playlist(id, name);
    p.trackCount = 0;
    this.playlists = this.playlists.concat(p);
    // 单选:新建后只勾选这一条,旧的自动取消。
    this.selected = new Set<number>([id]);
    this.newName = '';
    // 隐藏软键盘 —— 不然新建完键盘还挡着列表,看不见刚新建的项。
    this.hideKeyboard();
  }

  /** 收起系统输入法。 */
  private hideKeyboard(): void {
    try {
      inputMethod.getInputMethodController().hideTextInput();
    } catch (e) {
      // 异常时静默 —— 没有键盘可隐藏不影响主流程
    }
  }

  // ── 顶栏 ─────────────────────────────────────────
  @Builder
  panelHeader() {
    Row() {
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(28).height(28).fillColor('#FFFFFF')
          .padding(2)
          .onClick(() => this.onClose())
      }
      .width(40)
      .justifyContent(FlexAlign.Start)

      Text('保存到播放列表')
        .fontSize(17).fontWeight(600).fontColor('#FFFFFF')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row().width(40)
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12, top: 20 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.cHeaderBg)
  }

  // ── 新建段:输入框 + 新建按钮并排 ─────────────────
  @Builder
  newPlaylistRow() {
    Column() {
      Text('播放列表名称')
        .fontSize(13).fontColor(this.cAccent)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 6 })

      Row() {
        TextInput({ text: this.newName, placeholder: $r('app.string.playlist_name_hint') })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .placeholderColor('#80FFFFFF')
          .backgroundColor(this.cInputBg)
          .borderRadius(2)
          .border({ width: 1.5, color: this.cInputBorder })
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => this.newName = v)
          .onSubmit(() => this.createNew())
          // 输入框失焦也顺手收键盘(更保险)
          .onBlur(() => this.hideKeyboard())

        Text('新建')
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.cAccent)
          .margin({ left: 16 })
          .opacity(this.canCreate() ? 1 : 0.4)
          .onClick(() => this.createNew())
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ top: 6 })
  }

  // ── 现有播放列表项 ─────────────────────────────
  @Builder
  playlistRow(p: Playlist) {
    Row() {
      Column() {
        Text(p.title)
          .fontSize(15).fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.media_count_suffix', p.trackCount))
          .fontSize(11).fontColor(this.cDim)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ right: 12 })

      Stack() {
        Row()
          .width(20).height(20)
          .borderRadius(10)
          .backgroundColor(this.selected.has(p.id) ? this.cAccent : Color.Transparent)
          .border({
            width: 1.5,
            color: this.selected.has(p.id) ? this.cAccent : this.cDim,
          })
        if (this.selected.has(p.id)) {
          Image($r('app.media.ic_check'))
            .width(12).height(12).fillColor('#FFFFFF')
        }
      }
      .width(20).height(20)
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.toggleSelect(p.id))
  }

  // ── 「替换播放列表」开关行 ─────────────────────
  @Builder
  replaceRow() {
    Row() {
      Text($r('app.string.replace_playlist'))
        .fontSize(14).fontColor('#FFFFFF')
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.replace })
        .selectedColor(this.cAccent)
        .onChange((on: boolean) => this.replace = on)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 6, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  // ── 段标 ─────────────────────────────────────────
  @Builder
  sectionHeader(text: ResourceStr) {
    Text(text)
      .fontSize(15).fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 4 })
  }

  build() {
    Column() {
      this.panelHeader()

      // 内容区:自带滚动 —— 1/3 屏高内可能装不下输入 + 列表 + 替换 + 保存。
      Scroll() {
        Column() {
          // 新建段
          this.newPlaylistRow()

          // 现有列表段
          this.sectionHeader($r('app.string.add_to_existing_playlist'))
          Text($r('app.string.media_count_suffix', this.mediaCount))
            .fontSize(12).fontColor(this.cDim)
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 4 })

          if (this.playlists.length === 0) {
            Column() {
              Text($r('app.string.noplaylist'))
                .fontSize(13).fontColor(this.cDim)
            }
            .width('100%')
            .padding({ top: 16, bottom: 12 })
            .alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              ForEach(this.playlists, (p: Playlist) => {
                this.playlistRow(p)
              }, (p: Playlist) => `pl${p.id}`)
            }
            .width('100%')
          }

          // 替换开关
          this.replaceRow()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      // 底部 [保存] 按钮(固定贴底)
      Row() {
        Button('保存')
          .type(ButtonType.Capsule)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .backgroundColor(this.cAccent)
          .fontColor('#FFFFFF')
          .height(42)
          .layoutWeight(1)
          .enabled(this.canSave())
          .opacity(this.canSave() ? 1 : 0.4)
          .onClick(() => {
            const a: AddToPlaylistAction = {
              newName: '',
              selectedIds: Array.from(this.selected),
              replace: this.replace,
            };
            this.onConfirm(a);
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 20 })
      .backgroundColor(this.cPanelBg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cPanelBg)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}
