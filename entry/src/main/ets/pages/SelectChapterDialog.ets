import { AppColors } from '../common/constants/AppConstants';
import { PlaybackService } from '../common/data/PlaybackService';
import { VlcChapterInfo } from 'libvlcnapi.so';

function formatChapterTime(ms: number): string {
  const totalSec = Math.floor(Math.max(0, ms) / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/** 章节数据载体。 */
export class Chapter {
  name: string;
  time: string;
  constructor(name: string, time: string) {
    this.name = name;
    this.time = time;
  }
}

/** 章节行:标题(layoutWeight1,16vp 左右)+ 时间(右),高 48vp,选中态橙底。 */
@ComponentV2
struct ChapterItem {
  @Param item: Chapter = new Chapter('', '');
  @Param selected: boolean = false;
  @Event onItemClick: () => void = () => {};

  build() {
    Row() {
      Text(this.item.name)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16, right: 16 })
        .fontColor('#FFFFFF')
        .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Regular)
      Text(this.item.time)
        .fontColor('#FFFFFF')
        .margin({ right: 8 })
    }
    .width('100%')
    .height(48)
    .backgroundColor(this.selected ? AppColors.orange500 : AppColors.transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick())
  }
}

/**
 * SelectChapterDialog —— 章节选择 BottomSheet(默认全展开)。
 * 18fp Medium 标题(go_to_chapter,minHeight 56vp)+ 章节列表(单选高亮,选中态橙底 #FF8800)。
 * 进入时定位到当前章节(scrollToIndex);章节数<=1 时关闭。
 * TODO(契约): onServiceAvailable→initChapterList(): playbackService.getChapters(-1) 映射 Chapter(name=formatChapterTitle,time=millisToString);
 *   onChapterSelected(pos) → playbackService.chapterIdx=pos + dismiss。
 */
@ComponentV2
export struct SelectChapterDialog {
  @Event onClose: () => void = () => {};
  @Event onSelectChapter: (index: number) => void = () => {};

  @Local chapterData: Chapter[] = [];
  @Local selectedIndex: number = 0;

  aboutToAppear(): void {
    const svc = PlaybackService.getInstance();
    const chapters = svc.getChapters();
    if (chapters.length <= 1) {
      this.onClose();
      return;
    }
    this.chapterData = chapters.map((c: VlcChapterInfo, i: number) => {
      const title = c.name && c.name.length > 0 ? c.name : `Chapter ${i + 1}`;
      return new Chapter(title, formatChapterTime(c.timeOffset));
    });
    const cur = svc.getChapterIdx();
    this.selectedIndex = cur >= 0 ? cur : 0;
  }

  build() {
    Column() {
      Text($r('app.string.go_to_chapter'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .height(56)
        .margin({ left: 8, top: 8 })
        .maxLines(1)

      List({ space: 0 }) {
        ForEach(this.chapterData, (item: Chapter, index: number) => {
          ListItem() {
            ChapterItem({
              item: item,
              selected: index === this.selectedIndex,
              onItemClick: () => {
                this.selectedIndex = index;
                this.onSelectChapter(index);
                this.onClose();
              },
            })
          }
        }, (item: Chapter, index: number) => index.toString())
      }
      .lanes(1)
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 8, bottom: 8 })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_default'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
