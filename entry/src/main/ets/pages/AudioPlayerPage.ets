import { PlaybackService, PlaybackState } from '../common/data/PlaybackService';
import { PlaybackHistory } from '../common/data/PlaybackHistory';
import { NavController } from '../common/data/NavController';
import { PlayState, formatDuration } from '../common/models/MediaModels';
import { PlaybackSpeedDialog } from './PlaybackSpeedDialog';
import { EqualizerDialog } from './EqualizerDialog';

import { SleepTimerDialog } from './SleepTimerDialog';
import { JumpToTimeDialog } from './JumpToTimeDialog';
import { BookmarkDialog } from './BookmarkDialog';
import { BookMark } from '../common/models/BookmarkModels';
import { AddToPlaylistDialog, AddToPlaylistAction } from './AddToPlaylistDialog';
import { MediaLibrary } from '../common/data/MediaLibrary';
import { promptAction } from '@kit.ArkUI';
import {
  buildPlayerAdvancedOptions,
  PlayerAdvancedOptionId,
  PlayerAdvancedOptions,
} from '../common/components/PlayerAdvancedOptions';

/**
 * AudioPlayerPage —— 音频播放详情页。
 * 封面 + 曲目标题/艺术家 + 时间轴 + 控制按钮。
 * 绑定 PlaybackService 事件驱动。
 */
@ObservedV2
class AudioPlayerViewModel {
  @Trace state: PlayState = PlayState.IDLE;
  @Trace duration: number = 0;
  @Trace position: number = 0;
  @Trace title: string = '';
  @Trace artist: string = '';
  @Trace artworkPath: string = '';
  @Trace shuffle: boolean = false;
  @Trace repeatMode: number = 0;
  @Trace speed: number = 1.0;
  @Trace locked: boolean = false;

  private listenerId: number = 0;
  private lastRecordedUri: string = '';

  /** A-B 循环回调：到 B 点时跳回 A。由 Page 层注入。 */
  onAbLoopCheck: (() => void) | null = null;

  attach(): void {
    this.listenerId = setInterval(() => {
      const s: PlaybackState = PlaybackService.snapshot();
      const prev = this.state;
      this.state = s.state;
      this.duration = s.duration;
      this.position = s.position;
      this.title = s.title;
      this.artist = s.artist;
      this.artworkPath = s.artworkPath;
      this.shuffle = s.shuffle;
      this.repeatMode = s.repeatMode;
      this.speed = s.speed;
      // 记录播放历史:状态转为 PLAYING 且非重复记录同一曲目
      if (s.state === PlayState.PLAYING && prev !== PlayState.PLAYING && this.title.length > 0) {
        const cur = PlaybackService.getCurrent();
        const uri = cur ? cur.uri : '';
        if (uri.length > 0 && uri !== this.lastRecordedUri) {
          this.lastRecordedUri = uri;
          void PlaybackHistory.record(uri, this.title, s.duration, this.artworkPath);
        }
      }
      if (this.onAbLoopCheck !== null) {
        this.onAbLoopCheck();
      }
    }, 300);
  }

  detach(): void {
    if (this.listenerId > 0) {
      clearInterval(this.listenerId);
      this.listenerId = 0;
    }
  }

  toggleLock(): void {
    this.locked = !this.locked;
  }
}

@ComponentV2
export struct AudioPlayerPage {
  @Local vm: AudioPlayerViewModel = new AudioPlayerViewModel();
  @Local advancedOptionsOpen: boolean = false;
  @Local bookmarkOpen: boolean = false;
  @Local speedOpen: boolean = false;
  @Local eqOpen: boolean = false;
  @Local sleepOpen: boolean = false;
  @Local jumpOpen: boolean = false;
  @Local savePlaylistOpen: boolean = false;
  private pendingAdvancedAction: PlayerAdvancedOptionId | null = null;

  /** 带动画打开覆盖层。 */
  private animateOpen(fn: () => void): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, fn);
  }
  /** 带动画关闭覆盖层。 */
  private animateClose(fn: () => void): void {
    animateTo({ duration: 250, curve: Curve.EaseIn }, fn);
  }

  // 睡眠定时器状态
  private sleepTimer: number = -1;
  private sleepMillis: number = 0;

  // 书签
  @Local bookmarks: BookMark[] = [];
  private bookmarkIdSeq: number = 1;

  // A-B 循环
  @Local abPointA: number = -1;
  @Local abPointB: number = -1;
  @Local abActive: boolean = false;

  aboutToAppear(): void {
    const s = PlaybackService.snapshot();
    this.vm.title = s.title;
    this.vm.artist = s.artist;
    this.vm.artworkPath = s.artworkPath;
    this.vm.duration = s.duration;
    this.vm.position = s.position;
    this.vm.state = s.state;
    this.vm.shuffle = s.shuffle;
    this.vm.repeatMode = s.repeatMode;
    this.vm.speed = s.speed;
    this.vm.onAbLoopCheck = () => {
      if (this.abActive && this.abPointB > this.abPointA && this.vm.position >= this.abPointB - 200) {
        PlaybackService.seek(this.abPointA);
      }
    };
    this.vm.attach();
  }

  aboutToDisappear(): void {
    this.vm.detach();
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 头部:返回 + 标题 + A-B 指示灯 + 更多
          Row() {
            Image($r('app.media.ic_arrow_back')).width(24).height(24).fillColor($r('app.color.list_title'))
              .onClick(() => NavController.pop())
            Text(this.vm.title).fontSize(16).fontColor($r('app.color.list_title')).layoutWeight(1).margin({ left: 8 })
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.abPointA >= 0) {
              Text('A-B')
                .fontSize(11).fontColor('#FFFFFF')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(8)
                .backgroundColor('#FF8800')
                .margin({ right: 8 })
                .onClick(() => this.resetAb())
            }
            Image($r('app.media.ic_player_more')).width(24).height(24).fillColor($r('app.color.list_title'))
              .onClick(() => { this.advancedOptionsOpen = true; })
              .bindMenu(this.advancedOptionsOpen!!, this.advancedOptionsMenu(), {
                placement: Placement.BottomLeft,
                showInSubWindow: true,
                backgroundColor: $r('app.color.background_default'),
              })
          }
          .width('100%').padding({ left: 12, right: 12, top: 44, bottom: 8 }).alignItems(VerticalAlign.Center)
          .linearGradient({ angle: 180, colors: [['#66000000', 0.0], ['#00000000', 1.0]] })

          // 睡眠定时器指示灯
          if (this.sleepTimer !== -1) {
            Row() {
              Image($r('app.media.ic_sleep'))
                .width(20).height(20).fillColor('#FF8800').margin({ right: 6 })
              Text('睡眠定时器已开启')
                .fontSize(12).fontColor('#FF8800')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            .onClick(() => this.clearSleepTimer())
          }

          // 专辑封面
          Column() {
            Image(this.vm.artworkPath.length > 0 ? this.vm.artworkPath : $r('app.media.ic_song_big'))
              .width('70%')
              .aspectRatio(1)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
              .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 12, bottom: 12 })

          // 曲目标题 + 艺术家
          Column() {
            Text(this.vm.title)
              .fontSize(18).fontColor($r('app.color.list_title')).fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ bottom: 4 })
            Text(this.vm.artist.length > 0 ? this.vm.artist : '未知艺术家')
              .fontSize(14).fontColor($r('app.color.list_subtitle'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%').padding({ left: 24, right: 24, bottom: 12 })
          .alignItems(HorizontalAlign.Center)

          // A-B 循环状态行（贴进度条上方，对齐视频端 bottomBar）
          if (this.abPointA >= 0) {
            Row() {
              Text(`A ${this.fmtAbPoint(this.abPointA)} → B ${this.abActive ? this.fmtAbPoint(this.abPointB) : '???'}`)
                .fontSize(12).fontColor('#FF8800')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.abActive) {
                Text('关闭')
                  .fontSize(12).fontColor('#FFFFFF')
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                  .borderRadius(12)
                  .backgroundColor('#33FFFFFF')
                  .onClick(() => this.resetAb())
              } else {
                Text('设置 B')
                  .fontSize(12).fontColor('#FFFFFF')
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                  .borderRadius(12)
                  .backgroundColor('#FF8800')
                  .onClick(() => this.setAbPointB())
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          }

          // 时间轴
          Row() {
            Text(formatDuration(this.vm.position)).fontSize(12).fontColor($r('app.color.list_subtitle')).width(48)
            Slider({
              value: this.vm.duration > 0 ? this.vm.position * 100 / this.vm.duration : 0,
              min: 0, max: 100, step: 1, style: SliderStyle.OutSet,
            })
              .layoutWeight(1)
              .blockColor($r('app.color.orange500'))
              .selectedColor($r('app.color.orange500'))
              .trackColor($r('app.color.card_border'))
              .enabled(!this.vm.locked)
              .onChange((v: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  const seekMs = Math.floor(this.vm.duration * v / 100);
                  PlaybackService.seek(seekMs);
                }
              })
            Text(formatDuration(this.vm.duration)).fontSize(12).fontColor($r('app.color.list_subtitle')).width(48).textAlign(TextAlign.End)
          }
          .width('100%').padding({ left: 12, right: 12, bottom: 12 }).alignItems(VerticalAlign.Center)

          // 控制按钮行
          Row() {
            Image($r('app.media.ic_shuffle_audio')).width(28).height(28)
              .fillColor(this.vm.shuffle ? $r('app.color.orange500') : $r('app.color.list_title'))
              .onClick(() => PlaybackService.toggleShuffle())
            Blank()
            Image($r('app.media.ic_player_previous')).width(40).height(40).fillColor($r('app.color.list_title'))
              .onClick(() => PlaybackService.prev())
            Blank()
            Image(this.vm.state === PlayState.PLAYING ? $r('app.media.ic_pause_player') : $r('app.media.ic_play_player'))
              .width(64).height(64).fillColor($r('app.color.orange500'))
              .onClick(() => PlaybackService.togglePlay())
            Blank()
            Image($r('app.media.ic_player_next')).width(40).height(40).fillColor($r('app.color.list_title'))
              .onClick(() => PlaybackService.next())
            Blank()
            Image(this.vm.repeatMode === 0 ? $r('app.media.ic_repeat_audio') :
              (this.vm.repeatMode === 2 ? $r('app.media.ic_repeat_one_audio') : $r('app.media.ic_repeat_all_audio')))
              .width(28).height(28)
              .fillColor(this.vm.repeatMode > 0 ? $r('app.color.orange500') : $r('app.color.list_title'))
              .onClick(() => PlaybackService.cycleRepeat())
          }
          .width('100%').padding({ left: 24, right: 24, top: 8, bottom: 32 }).alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')

        // 锁定遮罩：全屏拦截触摸 + 最左侧锁图标
        if (this.vm.locked) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('#33000000')
            .hitTestBehavior(HitTestMode.Block)
          Row() {
            Image($r('app.media.ic_lock_player'))
              .width(28).height(28)
              .fillColor('#FFFFFF')
          }
          .width(52).height(52)
          .borderRadius(26)
          .backgroundColor(Color.Transparent)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Default)
          .position({ x: 16, y: '50%' })
          .translate({ x: 0, y: -26 })
          .onClick(() => { this.vm.toggleLock(); })
        }

        // 书签覆盖层
        if (this.bookmarkOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.bookmarkOpen = false; }))
            BookmarkDialog({
              bookmarks: this.bookmarks,
              currentTimeMs: this.vm.position,
              durationMs: this.vm.duration,
              onClose: () => this.animateClose(() => { this.bookmarkOpen = false; }),
              onSeek: (timeMs: number) => PlaybackService.seek(timeMs),
              onAddAtCurrent: () => this.addBookmarkAtCurrent(),
              onDelete: (id: number) => this.deleteBookmark(id),
              onRename: (id: number) => this.renameBookmark(id),
            })
              .width('100%')
              .height('66.66%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 播放速度弹框
        if (this.speedOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.speedOpen = false; }))
            PlaybackSpeedDialog({
              onClose: () => this.animateClose(() => { this.speedOpen = false; }),
            }).width('100%').height('50%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 均衡器弹框
        if (this.eqOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.eqOpen = false; }))
            EqualizerDialog({
              onClose: () => this.animateClose(() => { this.eqOpen = false; }),
            }).width('100%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 睡眠定时器弹框
        if (this.sleepOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.sleepOpen = false; }))
            SleepTimerDialog({
              initialMillis: this.sleepMillis,
              onClose: () => this.animateClose(() => { this.sleepOpen = false; }),
              onConfirm: (millis: number, waitForMediaEnd: boolean, resetOnInteraction: boolean) => {
                this.onSleepConfirm(millis, waitForMediaEnd, resetOnInteraction);
              },
            }).width('100%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 跳转至时间弹框
        if (this.jumpOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.jumpOpen = false; }))
            JumpToTimeDialog({
              onClose: () => this.animateClose(() => { this.jumpOpen = false; }),
              onConfirm: (timeMs: number) => this.onJumpConfirm(timeMs),
            }).width('100%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }

        // 保存到播放列表弹框
        if (this.savePlaylistOpen) {
          Column() {
            Column()
              .width('100%').layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.animateClose(() => { this.savePlaylistOpen = false; }))
            AddToPlaylistDialog({
              mediaCount: 1,
              onClose: () => this.animateClose(() => { this.savePlaylistOpen = false; }),
              onConfirm: (action: AddToPlaylistAction) => {
                void this.onSavePlaylistConfirm(action);
              },
            }).width('100%').height('50%')
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.translate({ y: '100%' }).animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_default'))
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      if (this.vm.locked) {
        return true;
      }
      NavController.pop();
      return true;
    })
  }

  /** 当前激活选项 id（对齐视频播放器激活态高亮）。 */
  advancedActiveIds(): PlayerAdvancedOptionId[] {
    const ids: PlayerAdvancedOptionId[] = [];
    if (this.vm.locked) {
      ids.push('lock');
    }
    return ids;
  }

  @Builder
  advancedOptionsMenu() {
    PlayerAdvancedOptions({
      items: buildPlayerAdvancedOptions('audio'),
      activeIds: this.advancedActiveIds(),
      onSelect: (id: PlayerAdvancedOptionId): void => {
        this.pendingAdvancedAction = id;
        this.advancedOptionsOpen = false;
        this.runPendingAdvancedAction();
      },
    })
  }

  /** 菜单消失后执行暂存的动作（对齐视频播放器 bindMenu 模式）。 */
  runPendingAdvancedAction(): void {
    const id: PlayerAdvancedOptionId | null = this.pendingAdvancedAction;
    this.pendingAdvancedAction = null;
    if (id === null) {
      return;
    }
    if (id === 'lock') {
      this.vm.toggleLock();
      return;
    }
    if (id === 'sleep') {
      this.animateOpen(() => { this.sleepOpen = true; });
      return;
    }
    if (id === 'speed') {
      this.animateOpen(() => { this.speedOpen = true; });
      return;
    }
    if (id === 'jumpToTime') {
      this.animateOpen(() => { this.jumpOpen = true; });
      return;
    }
    if (id === 'equalizer') {
      this.animateOpen(() => { this.eqOpen = true; });
      return;
    }
    if (id === 'bookmark') {
      this.animateOpen(() => { this.bookmarkOpen = true; });
      return;
    }
    if (id === 'abRepeat') {
      if (this.abActive) {
        this.resetAb();
      } else if (this.abPointA < 0) {
        this.abPointA = Math.max(0, Math.floor(this.vm.position));
        this.abPointB = -1;
        this.abActive = false;
        promptAction.showToast({ message: '已设置 A 点，拖动进度条后再次点击 A-B 循环设 B 点' });
      } else {
        this.setAbPointB();
      }
      return;
    }
    if (id === 'savePlaylist') {
      this.animateOpen(() => { this.savePlaylistOpen = true; });
      return;
    }
    promptAction.showToast({ message: '该功能暂未实现' });
  }

  // ── A-B 循环 ──

  /** 标记终点 B(仿视频端 setAbPointB)。B 必须在 A 之后,否则忽略。 */
  setAbPointB(): void {
    if (this.abPointA < 0) {
      return;
    }
    const b: number = Math.max(0, Math.floor(this.vm.position));
    if (b <= this.abPointA) {
      promptAction.showToast({ message: 'B 点需在 A 点之后' });
      return;
    }
    this.abPointB = b;
    this.abActive = true;
    promptAction.showToast({ message: 'A-B 循环已开启' });
  }

  /** 关闭并重置 A-B 循环(仿视频端 resetAb)。 */
  resetAb(): void {
    this.abPointA = -1;
    this.abPointB = -1;
    this.abActive = false;
    promptAction.showToast({ message: '已关闭 A-B 循环' });
  }

  // ── 格式化 ──

  fmtAbPoint(ms: number): string {
    const safe = ms > 0 ? ms : 0;
    const totalSec = Math.floor(safe / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    const mm = m < 10 ? `0${m}` : `${m}`;
    const ss = s < 10 ? `0${s}` : `${s}`;
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  // ── 睡眠定时器 ──

  onSleepConfirm(millis: number, _waitForMediaEnd: boolean, _resetOnInteraction: boolean): void {
    this.clearSleepTimer();
    this.sleepMillis = millis;
    if (this.sleepMillis <= 0) {
      return;
    }
    this.sleepTimer = setTimeout(() => {
      this.sleepTimer = -1;
      PlaybackService.pause();
      promptAction.showToast({ message: '睡眠定时器：播放已暂停' });
    }, this.sleepMillis);
    const totalMin = Math.floor(millis / 60000);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    const span = h > 0 && m > 0 ? `${h}小时${m}分` : (h > 0 ? `${h}小时` : `${m}分钟`);
    promptAction.showToast({ message: `睡眠定时器已设为 ${span}` });
    this.animateClose(() => { this.sleepOpen = false; });
  }

  clearSleepTimer(): void {
    if (this.sleepTimer !== -1) {
      clearTimeout(this.sleepTimer);
      this.sleepTimer = -1;
    }
  }

  // ── 跳转至时间 ──

  onJumpConfirm(timeMs: number): void {
    PlaybackService.seek(timeMs);
    this.animateClose(() => { this.jumpOpen = false; });
  }

  // ── 书签 ──

  addBookmarkAtCurrent(): void {
    const timeMs = Math.max(0, Math.floor(this.vm.position));
    const bm = new BookMark(this.bookmarkIdSeq++, -1, timeMs, '');
    this.bookmarks = [...this.bookmarks, bm].sort((a, b) => a.timeMs - b.timeMs);
    promptAction.showToast({ message: '已保存书签' });
  }

  deleteBookmark(id: number): void {
    this.bookmarks = this.bookmarks.filter((b) => b.id !== id);
  }

  renameBookmark(_id: number): void {
    promptAction.showToast({ message: '书签重命名功能开发中' });
  }

  // ── 保存到播放列表 ──

  async onSavePlaylistConfirm(action: AddToPlaylistAction): Promise<void> {
    const svc = PlaybackService.getInstance();
    const cur = svc.getCurrent();
    const uri = cur?.uri ?? '';
    if (uri.length === 0) {
      promptAction.showToast({ message: '当前没有可保存的曲目' });
      this.animateClose(() => { this.savePlaylistOpen = false; });
      return;
    }
    await MediaLibrary.initPlaylistCache();
    for (const playlistId of action.selectedIds) {
      if (action.replace) {
        await MediaLibrary.replacePlaylist(playlistId, [uri]);
      } else {
        await MediaLibrary.addToPlaylist(playlistId, uri);
      }
    }
    const count = action.selectedIds.length;
    promptAction.showToast({ message: count === 1 ? '已保存到播放列表' : `已保存到 ${count} 个播放列表` });
    this.animateClose(() => { this.savePlaylistOpen = false; });
  }

}
