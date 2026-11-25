import { PlaybackListener, PlaybackService, QueueItem } from '../data/PlaybackService';
import { UiFeedback } from '../utils/UiFeedback';

@ObservedV2
class PlayerQueueViewModel implements PlaybackListener {
  @Trace items: QueueItem[] = [];
  @Trace currentIndex: number = -1;

  onQueueChanged(): void {
    this.items = PlaybackService.getQueue();
    this.currentIndex = PlaybackService.getCurrentIndex();
  }
}

@ComponentV2
export struct PlayerQueuePanel {
  @Local vm: PlayerQueueViewModel = new PlayerQueueViewModel();
  @Local selecting: boolean = false;

  aboutToAppear(): void {
    PlaybackService.addListener(this.vm);
    this.vm.onQueueChanged();
  }

  aboutToDisappear(): void {
    PlaybackService.removeListener(this.vm);
  }

  private async select(index: number, uri: string): Promise<void> {
    if (this.selecting) {
      return;
    }
    this.selecting = true;
    try {
      await PlaybackService.getInstance().playQueueIndex(index, uri);
    } catch (_error) {
      UiFeedback.showToast({ message: $r('app.string.encountered_error_message') });
    } finally {
      this.selecting = false;
    }
  }

  build() {
    Column() {
      Text($r('app.string.player_queue'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.list_title'))
        .width('100%')
        .padding({ left: 16, right: 56, top: 12, bottom: 12 })
      if (this.vm.items.length === 0) {
        Text($r('app.string.player_queue_empty'))
          .fontSize(15)
          .fontColor($r('app.color.list_subtitle'))
          .padding(24)
      } else {
        List({ initialIndex: Math.max(0, this.vm.currentIndex) }) {
          Repeat(this.vm.items).each((row: RepeatItem<QueueItem>) => {
            ListItem() {
              Row({ space: 12 }) {
                if (row.index === this.vm.currentIndex) {
                  Image($r('app.media.ic_play_player'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.orange500'))
                } else {
                  Text(String(row.index + 1))
                    .fontSize(13)
                    .fontColor($r('app.color.list_subtitle'))
                    .width(24)
                    .textAlign(TextAlign.Center)
                }
                Column({ space: 3 }) {
                  Text(row.item.title || row.item.uri)
                    .fontSize(16)
                    .fontColor(row.index === this.vm.currentIndex ?
                      $r('app.color.orange500') : $r('app.color.list_title'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (row.item.artistName.length > 0) {
                    Text(row.item.artistName)
                      .fontSize(13)
                      .fontColor($r('app.color.list_subtitle'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(row.index === this.vm.currentIndex ? '#14FF8800' : Color.Transparent)
              .accessibilitySelected(row.index === this.vm.currentIndex)
              .onClick(() => void this.select(row.index, row.item.uri))
            }
          }).key((item: QueueItem, index: number): string => `${index}:${item.uri}`).virtualScroll()
        }
        .width('100%')
        .layoutWeight(1)
        .contentEndOffset(12)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 52, endMargin: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_default'))
  }
}
