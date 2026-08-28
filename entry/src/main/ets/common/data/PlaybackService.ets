import { UiFeedback } from '../utils/UiFeedback';
/**
 * PlaybackService —— 全局单例播放业务层。
 * 通过 ArkTS LibVLC/Media/MediaPlayer 对接 libVLC(不再直接 import libvlcnapi.so)。
 * 另提供 QueueItem / PlaybackState / 静态方法门面,兼容 origin/dev 音频 UI 调用方式。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { audio } from '@kit.AudioKit';
import { call, observer as telephonyObserver } from '@kit.TelephonyKit';
import { MediaWrapper, PlayState } from '../models/MediaModels';
import { Settings } from './Settings';
import { AppContext } from './AppContext';
import { MediaSessionManager } from './MediaSessionManager';
import { NetworkConnectionManager } from './NetworkConnectionManager';
import { Equalizer, LibVLC, Media, MediaPlayer, MediaSlaveType, RendererDiscoverer } from '../../libvlc';
import { VlcChapterInfo, VlcMediaTrackInfo, VlcRendererInfo, VlcTrackInfo } from 'libvlcnapi.so';
import { PlaybackQueueHistory, PlaybackQueueHistoryType } from './PlaybackQueueHistory';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

function needsFdOpen(uri: string): boolean {
  // HarmonyOS 沙箱 picker URI:非标准 file://,host 部分非空(如 file://docs/...、file://media/...),
  // 走 VLC MRL 解析器会把 host 误识别,必须用 fs.openSync + Media.fromFd。
  if (uri.startsWith('file://') && !uri.startsWith('file:///')) {
    return true;
  }
  if (uri.startsWith('datashare://')) {
    return true;
  }
  if (uri.startsWith('file://') && uri.indexOf('/Photo/') >= 0) {
    return true;
  }
  return false;
}

/** 是否为网络串流 URI(对齐 Android isSchemeStreaming)。 */
function isStreamingUri(uri: string): boolean {
  return uri.startsWith('http://') || uri.startsWith('https://') ||
    uri.startsWith('mms') || uri.startsWith('rtsp');
}

/** 播放队列条目(兼容 origin/dev 音频列表 API;内部仍转 MediaWrapper 走 libVLC)。 */
export class QueueItem {
  id: number;
  title: string;
  uri: string;
  artistName: string;
  albumName: string;
  artworkPath: string;

  constructor(id: number, title: string, uri: string, artistName: string, albumName: string, artworkPath: string) {
    this.id = id;
    this.title = title;
    this.uri = uri;
    this.artistName = artistName;
    this.albumName = albumName;
    this.artworkPath = artworkPath;
  }

  static fromMediaWrapper(mw: MediaWrapper): QueueItem {
    return new QueueItem(mw.id, mw.title, mw.uri, mw.artistName, mw.albumName, mw.artworkPath);
  }

  toMediaWrapper(type: number = 1): MediaWrapper {
    const mw = new MediaWrapper(this.id, this.title, this.uri, type);
    mw.artistName = this.artistName;
    mw.albumName = this.albumName;
    mw.artworkPath = this.artworkPath;
    return mw;
  }
}

/** 播放器可观察快照(兼容 MiniPlayer / AudioPlayer onChange)。 */
export interface PlaybackState {
  state: PlayState;
  title: string;
  artist: string;
  album: string;
  artworkPath: string;
  duration: number;
  position: number;
  speed: number;
  shuffle: boolean;
  repeatMode: number;

  /** 全局音频播放速度是否开启(速度弹窗默认作用域:开→所有曲目,关→此曲目)。 */
  globalSpeedEnabled: boolean;
  queueSize: number;
  currentIndex: number;

  /** 当前播放是否处于"仅播放音频"模式(视频文件当音频播),让 MiniPlayer 也能显示视频。 */
  playAsAudio: boolean;
}

export interface PlaybackListener {
  onStateChange?(state: PlayState): void;

  /** LibVLC 发出 ended 时触发，早于队列切换，适合保存当前媒体的完成状态。 */
  onMediaEnded?(): void;

  onTimeUpdate?(current: number, duration: number): void;

  onQueueChanged?(): void;

  onVideoSize?(width: number, height: number): void;

  onTracksChanged?(): void;

  /** 兼容 origin/dev:一次推送完整快照。 */
  onChange?(s: PlaybackState): void;
}

export class PlaybackService {
  private static instance: PlaybackService | null = null;
  private queue: MediaWrapper[] = [];
  private currentIndex: number = -1;
  private state: PlayState = PlayState.IDLE;
  private speed: number = 1.0;
  /** 全局音频播放速度开关(设置页 Use the global playback speed):开 → 所有曲目用 globalSpeedValue。 */
  private globalSpeedEnabled: boolean = false;
  /** 全局音频播放速度值。 */
  private globalSpeedValue: number = 1.0;
  /** 每曲目独立播放速度(按 URI):仅在全局开关关闭时生效。 */
  private trackSpeeds: Map<string, number> = new Map();
  private shuffle: boolean = false;
  private repeatMode: number = 0;
  private playAsAudio: boolean = false;
  /** AUDIO_PLAYBACK 长时任务激活标记(播放中申请,暂停/停止时取消)。 */
  private continuousTaskActive: boolean = false;
  /** 长时任务通知点击使用的 WantAgent(复用,避免重复构建)。 */
  private wantAgentObj: WantAgent | null = null;
  private duration: number = 0;
  private position: number = 0;
  private listeners: PlaybackListener[] = [];
  private inited: boolean = false;
  private initializing: boolean = false;
  private videoOutId: string = '';
  private videoWidth: number = 0;
  private videoHeight: number = 0;
  private volume: number = 100;
  /** 睡眠计时「先等当前媒体播完」:播完后 stop,不自动下一首。 */
  private stopAfterCurrent: boolean = false;
  /** 随机播放历史(对齐 Android PlaylistManager.previous):记录已播放过的索引,
   *  随机时不与历史重复,全部播完一轮后 repeat-all 清空重洗 / 否则停止。 */
  private shuffleHistory: number[] = [];
  /** Identifies the current queue's history bucket, so index changes are persisted too. */
  private queueHistoryType: PlaybackQueueHistoryType | null = null;
  private lib: LibVLC | null = null;
  private player: MediaPlayer | null = null;
  private equalizer: Equalizer | null = null;
  private rendererDiscoverer: RendererDiscoverer | null = null;
  private currentRendererHandle: number = -1;
  // ── 音频环境监听(耳机侦测 / 通知闪避 / 通话恢复)──
  private audioManager: audio.AudioManager | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private audioSessionManager: audio.AudioSessionManager | null = null;
  /** 耳机拔出时是否正在播放(对齐安卓 ACTION_AUDIO_BECOMING_NOISY 的 wasPlaying)。 */
  private headsetWasPlaying: boolean = false;
  /** 通知/打断是否处于「临时让出」(对齐安卓 AudioFocusHelper.lossTransient)。 */
  private lossTransient: boolean = false;
  private lossTransientWasPlaying: boolean = false;
  /** 闪避时保存的原音量;-1 表示未闪避。 */
  private duckedVolume: number = -1;
  /** 通话期间是否暂停了播放(通话结束按 resume_playback 恢复)。 */
  private pausedByCall: boolean = false;
  private audioEnvSubscribed: boolean = false;
  private lastTimeEmit: number = 0;
  /** AVSession 播放中进度同步定时器(确保通知栏进度条持续推进)。 */
  private sessionSyncTimer: number = -1;
  /**
   * SPU / 音频延迟的本地缓存。
   * libvlc 已桥接 set/get_spu_delay 与 set/get_audio_delay(任务 #8);本字段保留
   * 作为快速 UI 显示路径,仅由 set* 回写,避免每次 getter 过 native 桥。
   * 切换媒体/release 时外部需将两值重置为 0。
   */
  private spuDelayUs: number = 0;
  private audioDelayUs: number = 0;

  static getInstance(): PlaybackService {
    if (!PlaybackService.instance) {
      PlaybackService.instance = new PlaybackService();
    }
    return PlaybackService.instance;
  }

  static getState(): PlayState {
    return PlaybackService.getInstance().getState();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 音频环境监听(业务层 · 对齐安卓 PlaybackService / VLCAudioFocusHelper):
  //   1. 耳机侦测     —— AudioRoutingManager deviceChange → 拔出暂停 / 插入按设置续播
  //   2. 通知闪避     —— AudioManager legacy 'interrupt' 焦点回调 → 降音量(duck) / 恢复 + 打断暂停恢复
  //   3. 通话恢复     —— telephony callStateChange → 通话中暂停 / 结束按 resume_playback 恢复
  // 所有回调在触发时动态读设置,开关切换即时生效;订阅在 ensureInit 成功后一次性建立,
  // release 时移除。API 12+ 将 audioInterrupt 从 AudioStreamManager 移到 AudioRenderer
  // (libVLC 的 aout 为原生流,JS 侧无 renderer 句柄),应用层仅剩 AudioManager 的 legacy
  // 'interrupt' 焦点回调(自 API 9 弃用)可尝试对接,命中与否存在不确定性,故全程
  // try/catch 兜底,耳机/通话两条路径不依赖它。
  // ─────────────────────────────────────────────────────────────────────────────

  static getQueue(): QueueItem[] {
    return PlaybackService.getInstance().getQueue().map((mw: MediaWrapper) => QueueItem.fromMediaWrapper(mw));
  }

  static getCurrentIndex(): number {
    return PlaybackService.getInstance().getCurrentIndex();
  }

  static getCurrent(): QueueItem | null {
    const cur = PlaybackService.getInstance().getCurrent();
    return cur ? QueueItem.fromMediaWrapper(cur) : null;
  }

  static snapshot(): PlaybackState {
    return PlaybackService.getInstance().snapshot();
  }

  static addListener(l: PlaybackListener): void {
    PlaybackService.getInstance().addListener(l);
  }

  static removeListener(l: PlaybackListener): void {
    PlaybackService.getInstance().removeListener(l);
  }

  static async playList(items: QueueItem[], startIndex: number, replace: boolean): Promise<void> {
    await PlaybackService.getInstance().playQueueItems(items, startIndex, replace);
  }

  static async append(items: QueueItem[]): Promise<void> {
    await PlaybackService.getInstance().appendQueueItems(items);
  }

  static async play(): Promise<void> {
    await PlaybackService.getInstance().play();
  }

  static async pause(): Promise<void> {
    PlaybackService.getInstance().pause();
  }

  static async togglePlay(): Promise<void> {
    PlaybackService.getInstance().togglePlay();
  }

  static async stop(): Promise<void> {
    PlaybackService.getInstance().stop();
  }

  static async seek(ms: number): Promise<void> {
    PlaybackService.getInstance().seek(ms);
  }

  static async setSpeed(rate: number): Promise<void> {
    PlaybackService.getInstance().setSpeed(rate);
  }

  /** 仅当前曲目生效的速度(关全局开关)。 */
  static setTrackSpeed(uri: string, rate: number): void {
    PlaybackService.getInstance().setTrackSpeed(uri, rate);
  }

  /** 所有曲目统一的速度(开全局开关)。 */
  static setGlobalSpeed(rate: number): void {
    PlaybackService.getInstance().setGlobalSpeed(rate);
  }

  static isGlobalSpeedEnabled(): boolean {
    return PlaybackService.getInstance().isGlobalSpeedEnabled();
  }

  static async next(auto: boolean = false): Promise<void> {
    await PlaybackService.getInstance().next(auto);
  }

  static async prev(): Promise<void> {
    await PlaybackService.getInstance().prev();
  }

  static toggleShuffle(): void {
    PlaybackService.getInstance().toggleShuffle();
  }

  static isShuffle(): boolean {
    return PlaybackService.getInstance().getShuffle();
  }

  static setShuffle(value: boolean): void {
    PlaybackService.getInstance().setShuffle(value);
  }

  static isPlayAsAudio(): boolean {
    return PlaybackService.getInstance().getPlayAsAudio();
  }

  static setPlayAsAudio(value: boolean): void {
    PlaybackService.getInstance().setPlayAsAudio(value);
  }

  static cycleRepeat(): void {
    PlaybackService.getInstance().cycleRepeat();
  }

  static speedToNumber(): number {
    return PlaybackService.getInstance().getSpeed();
  }

  static async release(): Promise<void> {
    PlaybackService.getInstance().release();
  }

  /** 按文件名把 .iso 文件 MRL 转换为光盘访问 MRL(dvdnav:// / bluray:// / vcd://)。
   *  libVLC 无 UDF/iso9660 文件系统插件,直接 file:// 打开 ISO 无法解析 BD 导航结构。 */
  private static isoToDiscMrl(uri: string): string {
    if (!uri.toLowerCase().endsWith('.iso')) {
      return uri;
    }
    let path = uri;
    if (path.startsWith('file://')) {
      path = path.substring('file://'.length);
    }
    const lower = path.toLowerCase();
    if (lower.indexOf('dvd') >= 0) {
      return `dvdnav://${path}`;
    }
    if (lower.indexOf('bd') >= 0 || lower.indexOf('bluray') >= 0) {
      return `bluray://${path}`;
    }
    if (lower.indexOf('vcd') >= 0) {
      return `vcd://${path}`;
    }
    return uri;
  }

  refreshVideoSize(): void {
    if (!this.player) {
      return;
    }
    try {
      const size = this.player.getVideoSize();
      if (size && size.width > 0 && size.height > 0) {
        if (size.width !== this.videoWidth || size.height !== this.videoHeight) {
          this.videoWidth = size.width;
          this.videoHeight = size.height;
          hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] videoSize %{public}dx%{public}d',
            this.videoWidth, this.videoHeight);
          this.emitVideoSize();
        }
      } else {
        const cur = this.getCurrent();
        if (cur && cur.width > 0 && cur.height > 0) {
          if (cur.width !== this.videoWidth || cur.height !== this.videoHeight) {
            this.videoWidth = cur.width;
            this.videoHeight = cur.height;
            this.emitVideoSize();
          }
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] refreshVideoSize: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** Applies libVLC's decoder-side display aspect ratio. Empty string restores the media value. */
  setVideoAspectRatio(aspect: string): void {
    this.player?.setAspectRatio(aspect);
  }

  /** Applies libVLC video scaling. Zero enables automatic scaling; one keeps source pixel size. */
  setVideoScale(scale: number): void {
    this.player?.setScale(scale);
  }

  getVideoWidth(): number {
    return this.videoWidth;
  }

  getVideoHeight(): number {
    return this.videoHeight;
  }

  getState(): PlayState {
    return this.state;
  }

  getDuration(): number {
    return this.duration;
  }

  getPosition(): number {
    return this.position;
  }

  getQueue(): MediaWrapper[] {
    return this.queue;
  }

  getCurrentIndex(): number {
    return this.currentIndex;
  }

  getCurrent(): MediaWrapper | null {
    return this.currentIndex >= 0 && this.currentIndex < this.queue.length ? this.queue[this.currentIndex] : null;
  }

  getSpeed(): number {
    return this.speed;
  }

  getShuffle(): boolean {
    return this.shuffle;
  }

  getRepeatMode(): number {
    return this.repeatMode;
  }

  getPlayAsAudio(): boolean {
    return this.playAsAudio;
  }

  setPlayAsAudio(value: boolean): void {
    if (this.playAsAudio === value) {
      return;
    }
    this.playAsAudio = value;
    this.emitQueue();
  }

  getVolume(): number {
    return this.player ? this.player.getVolume() : this.volume;
  }

  setVolume(v: number): void {
    this.volume = v;
    this.player?.setVolume(v);
  }

  getAudioTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getAudioTracks() : [];
  }

  getSpuTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getSpuTracks() : [];
  }

  getVideoTracks(): VlcTrackInfo[] {
    return this.player ? this.player.getVideoTracks() : [];
  }

  getAudioTrack(): number {
    return this.player ? this.player.getAudioTrack() : -1;
  }

  getSpuTrack(): number {
    return this.player ? this.player.getSpuTrack() : -1;
  }

  getVideoTrack(): number {
    return this.player ? this.player.getVideoTrack() : -1;
  }

  /**
   * 当前选中的音频轨道描述(name 即 libVLC 给的 codec 描述,如 'MPEG AAC Audio (mp4a)')。
   * 返回 null 表示无音频轨道或未选中。
   */
  getCurrentAudioTrackInfo(): VlcTrackInfo | null {
    if (!this.player) {
      return null;
    }
    const id: number = this.player.getAudioTrack();
    if (id < 0) {
      return null;
    }
    const tracks: VlcTrackInfo[] = this.player.getAudioTracks();
    return tracks.find((t: VlcTrackInfo) => t.id === id) ?? null;
  }

  /**
   * 当前选中的视频轨道描述(name 即 codec 描述,如 'H264 - MPEG-4 AVC (part 10) (avc1)')。
   */
  getCurrentVideoTrackInfo(): VlcTrackInfo | null {
    if (!this.player) {
      return null;
    }
    const id: number = this.player.getVideoTrack();
    if (id < 0) {
      return null;
    }
    const tracks: VlcTrackInfo[] = this.player.getVideoTracks();
    return tracks.find((t: VlcTrackInfo) => t.id === id) ?? null;
  }

  /**
   * 获取当前媒体的轨道元数据(libvlc_media_get_tracks_info)。
   * 返回原始数组,调用方自行筛选 audio/video/text。
   */
  getMediaTracksInfo(): VlcMediaTrackInfo[] {
    if (!this.player) {
      return [];
    }
    const media = this.player.getMedia();
    if (!media || media.isReleased()) {
      return [];
    }
    return media.getTracksInfo();
  }

  setAudioTrack(id: number): boolean {
    return this.player ? this.player.setAudioTrack(id) : false;
  }

  setSpuTrack(id: number): boolean {
    return this.player ? this.player.setSpuTrack(id) : false;
  }

  setVideoTrack(id: number): boolean {
    return this.player ? this.player.setVideoTrack(id) : false;
  }

  getChapters(): VlcChapterInfo[] {
    return this.player ? this.player.getChapters(-1) : [];
  }

  getChapterIdx(): number {
    return this.player ? this.player.getChapter() : -1;
  }

  setChapter(index: number): void {
    this.player?.setChapter(index);
  }

  addSubtitleSlave(uri: string): boolean {
    return this.player ? this.player.addSlave(MediaSlaveType.Subtitle, uri, true) : false;
  }

  setSpuDelay(us: number): boolean {
    const ok: boolean = this.player ? this.player.setSpuDelay(us) : false;
    if (ok) {
      this.spuDelayUs = us;
    }
    return ok;
  }

  getSpuDelay(): number {
    return this.spuDelayUs;
  }

  setAudioDelay(us: number): boolean {
    const ok: boolean = this.player ? this.player.setAudioDelay(us) : false;
    if (ok) {
      this.audioDelayUs = us;
    }
    return ok;
  }

  getAudioDelay(): number {
    return this.audioDelayUs;
  }

  applyEqualizer(enabled: boolean, presetIndex: number, preamp: number, bands: number[]): void {
    if (!this.player) {
      return;
    }
    if (!enabled) {
      this.player.setEqualizer(null);
      if (this.equalizer) {
        this.equalizer.release();
        this.equalizer = null;
      }
      return;
    }
    if (this.equalizer) {
      this.equalizer.release();
      this.equalizer = null;
    }
    this.equalizer = Equalizer.fromPreset(presetIndex) ?? Equalizer.create();
    if (!this.equalizer) {
      return;
    }
    this.equalizer.setPreAmp(preamp);
    for (let i = 0; i < bands.length; i++) {
      this.equalizer.setAmp(i, bands[i]);
    }
    this.player.setEqualizer(this.equalizer);
  }

  async startRendererDiscovery(): Promise<VlcRendererInfo[]> {
    await this.ensureInit();
    if (!this.lib) {
      return [];
    }
    if (this.rendererDiscoverer) {
      return this.rendererDiscoverer.getItems();
    }
    const names = RendererDiscoverer.listNames(this.lib);
    const name = names.length > 0 ? names[0] : 'microdns';
    this.rendererDiscoverer = new RendererDiscoverer(this.lib, name);
    if (this.rendererDiscoverer.getHandle() === 0) {
      this.rendererDiscoverer.release();
      this.rendererDiscoverer = null;
      return [];
    }
    this.rendererDiscoverer.start();
    await new Promise<void>((r: () => void) => setTimeout(r, 800));
    return this.rendererDiscoverer.getItems();
  }

  setRenderer(handle: number): boolean {
    if (!this.player) {
      return false;
    }
    const ok = this.player.setRenderer(handle);
    if (ok) {
      this.currentRendererHandle = handle;
    }
    return ok;
  }

  clearRenderer(): boolean {
    if (!this.player) {
      return false;
    }
    const ok = this.player.clearRenderer();
    if (ok) {
      this.currentRendererHandle = -1;
    }
    return ok;
  }

  getCurrentRendererHandle(): number {
    return this.currentRendererHandle;
  }

  hasRenderer(): boolean {
    return this.currentRendererHandle >= 0;
  }

  getMediaPlayer(): MediaPlayer | null {
    return this.player;
  }

  getLibVLC(): LibVLC | null {
    return this.lib;
  }

  addListener(l: PlaybackListener): void {
    if (!this.listeners.includes(l)) {
      this.listeners.push(l);
    }
  }

  removeListener(l: PlaybackListener): void {
    this.listeners = this.listeners.filter((x) => x !== l);
  }

  snapshot(): PlaybackState {
    const cur = this.getCurrent();
    return {
      state: this.state,
      title: cur?.title ?? '',
      artist: cur?.artistName ?? '',
      album: cur?.albumName ?? '',
      artworkPath: cur?.artworkPath ?? '',
      duration: this.duration,
      position: this.position,
      speed: this.speed,
      shuffle: this.shuffle,
      repeatMode: this.repeatMode,
      globalSpeedEnabled: this.globalSpeedEnabled,
      queueSize: this.queue.length,
      currentIndex: this.currentIndex,
      playAsAudio: this.playAsAudio,
    };
  }

  /** QueueItem[] → MediaWrapper[] 后播放(音频列表入口)。 */
  async playQueueItems(items: QueueItem[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.playList(mws, startIndex, replace, 'audio');
  }

  async appendQueueItems(items: QueueItem[]): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.append(mws);
  }

  async prepareList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true,
    historyType: PlaybackQueueHistoryType | null = null): Promise<void> {
    if (items.length === 0) {
      return;
    }
    await this.ensureInit();
    if (!this.inited) {
      return;
    }
    this.queue = replace ? items.slice() : this.queue.concat(items);
    this.currentIndex = replace ? startIndex : this.queue.length - items.length + startIndex;
    if (historyType !== null) {
      this.queueHistoryType = historyType;
    }
    // 任何"换队列"动作(替换)都意味着重新进入正常播放流程,清掉"仅播放音频"标记,
    // 避免之前打开的 playAsAudio 状态泄漏到下一首。
    if (replace) {
      this.playAsAudio = false;
      this.shuffleHistory = [];
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] prepareList size=%{public}d index=%{public}d uri=%{public}s',
      this.queue.length, this.currentIndex, this.getCurrent()?.uri ?? '');
    this.emitQueue();
    this.saveQueueHistory();
  }

  async playList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true,
    historyType: PlaybackQueueHistoryType | null = null): Promise<void> {
    await this.prepareList(items, startIndex, replace, historyType);
    if (!this.inited) {
      return;
    }
    await this.loadCurrent();
  }

  append(items: MediaWrapper[]): Promise<void> {
    return this.playList(items, 0, false);
  }

  async bindAndPlay(xcomponentId: string, fallbackUri?: string, fallbackTitle?: string): Promise<boolean> {
    await this.ensureInit();
    if (!this.inited || !this.player) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] bindAndPlay aborted: not inited');
      return false;
    }
    this.videoOutId = xcomponentId;

    if ((!this.getCurrent() || (fallbackUri && this.getCurrent()?.uri !== fallbackUri)) && fallbackUri) {
      const mw = new MediaWrapper(Date.now(), fallbackTitle ?? fallbackUri, fallbackUri, 0);
      this.queue = [mw];
      this.currentIndex = 0;
      this.emitQueue();
    }

    // 若此前 stop() 已使 player 失效,先重建再走 attach 重试循环,否则循环全打在已释放的 player 上必失败
    this.player = await this.ensureLivePlayer();
    if (!this.player) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] bindAndPlay aborted: player unavailable');
      return false;
    }

    let bound = false;
    for (let i = 0; i < 30; i++) {
      const hasWin = this.player.hasNativeWindow(xcomponentId);
      bound = this.player.attachViews(xcomponentId);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] setVideoOut try=%{public}d hasWin=%{public}s bound=%{public}s id=%{public}s',
        i, String(hasWin), String(bound), xcomponentId);
      if (bound) {
        break;
      }
      await new Promise<void>((r: () => void) => setTimeout(r, 50));
    }

    await this.loadCurrent();
    return bound;
  }

  /** 设置单曲速度:关闭全局开关,为该 URI 写入独立速度(仅当前曲目生效)。 */
  setTrackSpeed(uri: string, rate: number): void {
    const r: number = Math.max(0.25, Math.min(8.0, rate));
    this.globalSpeedEnabled = false;
    this.trackSpeeds.set(uri, r);
    this.speed = r;
    this.player?.setRate(r);
    this.persistTrackSpeeds();
    void Settings.put(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL, false);
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] setTrackSpeed uri=%{public}s rate=%{public}f', uri, r);
  }

  /** 设置全局速度:开启全局开关、清空独立速度,所有曲目统一使用该速度(持久化)。 */
  setGlobalSpeed(rate: number): void {
    const r: number = Math.max(0.25, Math.min(8.0, rate));
    this.globalSpeedEnabled = true;
    this.globalSpeedValue = r;
    this.trackSpeeds.clear();
    this.speed = r;
    this.player?.setRate(r);
    this.persistTrackSpeeds();
    void Settings.put(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL, true);
    void Settings.put(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL_VALUE, r);
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] setGlobalSpeed rate=%{public}f', r);
  }

  /** 全局音频速度开关当前状态(供弹窗默认作用域)。 */
  isGlobalSpeedEnabled(): boolean {
    return this.globalSpeedEnabled;
  }

  setStopAfterCurrent(v: boolean): void {
    this.stopAfterCurrent = v;
  }

  async play(): Promise<void> {
    await this.ensureInit();
    if (!this.inited || !this.player) {
      return;
    }
    if (this.state === PlayState.IDLE || this.state === PlayState.STOPPED || this.state === PlayState.ERROR) {
      await this.loadCurrent();
      return;
    }
    this.player.play();
  }

  pause(): void {
    this.player?.pause();
  }

  togglePlay(): void {
    if (this.state === PlayState.PLAYING) {
      this.pause();
    } else {
      this.play();
    }
  }

  /**
   * 停止播放(对标 Android PlaybackService.stop(video=true))。
   * stop 在 native 侧为后台异步 stop+release(防止解码线程卡死时阻塞主线程 AppFreeze),
   * 本方法仅做同步簿记,立即返回;player 被标记失效,下次加载由 loadCurrent→ensureLivePlayer 重建。
   */
  stop(): void {
    this.stopSessionSync();
    void this.stopContinuousTask();
    this.player?.stop();
    this.state = PlayState.STOPPED;
    this.shuffleHistory = [];
    this.emitState();
    void MediaSessionManager.updatePlaybackState(PlayState.STOPPED, 0, 0, this.speed);
  }

  /** 解绑视频 Surface(对标 Android cleanUI → detachViews)。 */
  detachViews(): void {
    if (this.player) {
      this.player.detachViews();
    }
    this.videoOutId = '';
  }

  async next(auto: boolean = false): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }
    const forceManual = !auto;
    const nextIdx = this.computeNextIndex(forceManual);
    if (nextIdx < 0) {
      // 没有下一首:自动播完到队尾且未开循环时才 stop
      this.stop();
      return;
    }
    // 注意:循环模式在手动跳转时保持不变(持久化),不再像 Android 那样从单曲循环复位
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] next auto=%{public}s from=%{public}d -> %{public}d (shuffle=%{public}s repeat=%{public}d history=%{public}d)',
      auto ? 'auto' : 'manual', this.currentIndex, nextIdx,
      this.shuffle ? 'on' : 'off', this.repeatMode, this.shuffleHistory.length);
    this.currentIndex = nextIdx;
    this.emitQueue();
    this.saveQueueHistory();
    await this.loadCurrent();
  }

  async prev(): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }
    // 对齐 Android PREVIOUS_LIMIT_DELAY:当前已播放超过 5s 时,上一首按钮先重播当前
    if (this.position > 5000) {
      this.seek(0);
      this.player?.play();
      return;
    }
    // 单曲循环:上一曲也重播当前(对齐 Android REPEAT_ONE → prev 也返回 currentIndex)
    if (this.repeatMode === 2) {
      this.seek(0);
      this.player?.play();
      return;
    }
    let prevIdx: number;
    if (this.shuffle) {
      // 随机模式:从历史回退(Android previous.pop())
      if (this.shuffleHistory.length > 0) {
        prevIdx = this.shuffleHistory[this.shuffleHistory.length - 1];
        this.shuffleHistory.pop();
      } else {
        prevIdx = this.currentIndex;
      }
    } else {
      prevIdx = this.currentIndex - 1;
      if (prevIdx < 0) {
        prevIdx = this.queue.length - 1;
      }
    }
    if (prevIdx < 0 || prevIdx >= this.queue.length) {
      this.seek(0);
      this.player?.play();
      return;
    }
    this.currentIndex = prevIdx;
    this.emitQueue();
    this.saveQueueHistory();
    await this.loadCurrent();
  }

  seek(ms: number): void {
    this.position = ms;
    this.player?.setTime(ms);
  }

  /** 按 0.0-1.0 位置 seek(bluray/dvdnav 的 navigator 会覆盖 setTime,position seek 更可靠)。 */
  seekPosition(pos: number): void {
    const clamped: number = Math.max(0, Math.min(1, pos));
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] seekPosition pos=%{public}f clamped=%{public}f duration=%{public}d',
      pos, clamped, this.duration);
    this.player?.setPosition(clamped);
  }

  setSpeed(rate: number): void {
    this.speed = rate;
    this.player?.setRate(rate);
  }

  toggleShuffle(): void {
    this.shuffle = !this.shuffle;
    // 对齐 Android shuffle():切换后清空历史,随机从当前曲目重新开始
    this.shuffleHistory = [];
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] toggleShuffle -> %{public}s',
      this.shuffle ? 'on' : 'off');
    void Settings.put(Settings.AUDIO_SHUFFLING, this.shuffle);
    this.emitQueue();
  }

  setShuffle(value: boolean): void {
    if (this.shuffle === value) {
      return;
    }
    this.shuffle = value;
    this.shuffleHistory = [];
    void Settings.put(Settings.AUDIO_SHUFFLING, this.shuffle);
    this.emitQueue();
  }

  cycleRepeat(): void {
    this.repeatMode = (this.repeatMode + 1) % 3;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] cycleRepeat -> %{public}d (0=none 1=all 2=one)',
      this.repeatMode);
    void Settings.put(Settings.KEY_PLAYBACK_REPEAT_MODE, this.repeatMode);
    this.emitQueue();
  }

  release(): void {
    this.teardownAudioEnvironment();
    if (this.rendererDiscoverer) {
      this.rendererDiscoverer.stop();
      this.rendererDiscoverer.release();
      this.rendererDiscoverer = null;
    }
    if (this.equalizer) {
      this.equalizer.release();
      this.equalizer = null;
    }
    if (this.player) {
      this.player.release();
      this.player = null;
    }
    if (this.lib) {
      this.lib.release();
      this.lib = null;
    }
    this.inited = false;
    this.videoOutId = '';
    this.currentRendererHandle = -1;
    this.shuffleHistory = [];
    this.state = PlayState.IDLE;
    this.emitState();
    this.stopSessionSync();
    void this.stopContinuousTask();
    NetworkConnectionManager.offMeteredChange(this.meteredChangeListener);
    void MediaSessionManager.release();
  }

  /** 网络计费变化监听(init 注册,release 注销)。 */
  private meteredChangeListener: (metered: boolean) => void = () => {
  };

  private async ensureInit(): Promise<void> {
    if (this.inited) {
      return;
    }
    if (this.initializing) {
      while (this.initializing) {
        await new Promise<void>((r: () => void) => setTimeout(r, 20));
      }
      return;
    }
    this.initializing = true;
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init start');
      this.lib = new LibVLC(await this.buildLibVlcAudioOptions());
      if (this.lib.getHandle() === 0) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] LibVLC create FAILED');
        this.lib.release();
        this.lib = null;
        return;
      }
      this.player = new MediaPlayer(this.lib);
      if (this.player.getHandle() === 0) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] MediaPlayer create FAILED');
        this.player.release();
        this.player = null;
        this.lib.release();
        this.lib = null;
        return;
      }
      this.player.setEventListener((event: string, value: number) => this.onNativeEvent(event, value));
      this.inited = true;
      // 订阅音频环境事件(耳机/通知闪避/通话),各回调内动态读设置,开关即时生效
      this.setupAudioEnvironment();
      // 恢复上次会话持久化的随机/循环状态(对齐 Android setRepeatTypeFromSettings)
      this.shuffle = await Settings.getBoolean(Settings.AUDIO_SHUFFLING, false);
      this.repeatMode = await Settings.getInt(Settings.KEY_PLAYBACK_REPEAT_MODE, 0);
      // 恢复全局音频播放速度(对齐 Android 设置项 Use the global playback speed)
      this.globalSpeedEnabled = await Settings.getBoolean(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL, false);
      this.globalSpeedValue = await Settings.getFloat(Settings.KEY_PLAYBACK_SPEED_AUDIO_GLOBAL_VALUE, 1.0);
      if (this.globalSpeedValue < 0.25 || this.globalSpeedValue > 8.0) {
        this.globalSpeedValue = 1.0;
      }
      // 恢复每曲目独立速度 {uri: speed}
      const savedSpeeds = await Settings.getString(Settings.KEY_AUDIO_TRACK_SPEEDS, '');
      if (savedSpeeds.length > 0) {
        try {
          const obj = JSON.parse(savedSpeeds) as Record<string, number>;
          this.trackSpeeds = new Map();
          for (const k of Object.keys(obj)) {
            const v = Number(obj[k]);
            if (v >= 0.25 && v <= 8.0) {
              this.trackSpeeds.set(k, v);
            }
          }
        } catch (e) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] trackSpeeds parse failed: %{public}s',
            (e as Error).message ?? String(e));
        }
      }
      MediaSessionManager.setCallbacks({
        onPlay: () => {
          void this.play();
        },
        onPause: () => {
          this.pause();
        },
        onStop: () => {
          this.stop();
        },
        onNext: () => {
          void this.next();
        },
        onPrevious: () => {
          void this.prev();
        },
        onSeek: (ms: number) => {
          this.seek(ms);
        },
        onSetSpeed: (rate: number) => {
          this.setSpeed(rate);
        },
      });
      // 等待播控会话完成创建，避免首次音频的 metadata 在创建竞态中丢失。
      await MediaSessionManager.ensure();
      this.meteredChangeListener = (metered: boolean) => {
        void this.checkMeteredNetwork(metered);
      };
      NetworkConnectionManager.onMeteredChange(this.meteredChangeListener);
      NetworkConnectionManager.start();
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] PlaybackService.init ok shuffle=%{public}s repeatMode=%{public}d globalSpeed=%{public}s speed=%{public}f tracks=%{public}d',
        this.shuffle ? 'on' : 'off', this.repeatMode,
        this.globalSpeedEnabled ? 'on' : 'off', this.speed, this.trackSpeeds.size);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] PlaybackService.init exception: %{public}s',
        (e as Error).message ?? String(e));
    } finally {
      this.initializing = false;
    }
  }

  /**
   * 确保 player 存活。
   * stop() 会触发原生异步 stop+release 并使当前 MediaPlayer 失效(isReleased),下次加载前必须重建;
   * 重建时重挂事件回调、重放音量/速度,并把 videoOutId 的视频面重绑回来(自动接续不经过 bindAndPlay,
   * 若不重绑,播完切下一首会黑屏只剩音频)。
   */
  private async ensureLivePlayer(): Promise<MediaPlayer | null> {
    await this.ensureInit();
    if (!this.inited || !this.lib) {
      return null;
    }
    if (this.player !== null && !this.player.isReleased()) {
      return this.player;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] ensureLivePlayer: recreate player after async stop');
    const np = new MediaPlayer(this.lib);
    if (np.getHandle() === 0) {
      np.release();
      this.player = null;
      return null;
    }
    np.setEventListener((event: string, value: number) => this.onNativeEvent(event, value));
    np.setVolume(this.volume);
    np.setRate(this.speed);
    if (this.videoOutId.length > 0) {
      const bound = np.attachViews(this.videoOutId);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] ensureLivePlayer re-attach videoOut=%{public}s bound=%{public}s',
        this.videoOutId, String(bound));
    }
    this.player = np;
    return np;
  }

  /**
   * 音频设置 → libVLC 实例选项(对齐安卓 PreferencesAudio 的 onSharedPreferenceChanged →
   * restartLibVLC,启动时按设置注入 libvlc_new)。仅对接 libvlccore.so 实际编译进库的选项:
   *  - 回放增益 audio-replay-gain-*(mode/preamp/default/peak-protection)已编译 ✓
   *  - 偏好的音频语言 --audio-language 已编译 ✓
   *  aout(opensles/audiotrack)/soundfont/audio-passthrough 未编译进库,不注入。
   * 生效时机:下次播放服务创建 libVLC 实例时(设置变更后重启应用/播放器)。
   */
  private async buildLibVlcAudioOptions(): Promise<string[]> {
    const opts: string[] = [];
    try {
      // ── 回放增益(对齐安卓 replaygain 分组)──
      const rgEnabled: boolean = await Settings.getBoolean('audio-replay-gain-enable', false);
      const rgMode: string = await Settings.getString('audio-replay-gain-mode', 'track');
      // enable 关 → mode=none(不处理增益);开 → 使用 track/album
      const mode: string = (rgEnabled && (rgMode === 'track' || rgMode === 'album')) ? rgMode : 'none';
      opts.push(`--audio-replay-gain-mode=${mode}`);
      const rgPreamp: string = await Settings.getString('audio-replay-gain-preamp', '0.0');
      const rgDefault: string = await Settings.getString('audio-replay-gain-default', '-7.0');
      this.pushFloatOption(opts, '--audio-replay-gain-preamp', rgPreamp);
      this.pushFloatOption(opts, '--audio-replay-gain-default', rgDefault);
      const peakProtection: boolean = await Settings.getBoolean('audio-replay-gain-peak-protection', true);
      opts.push(peakProtection ? '--audio-replay-gain-peak-protection' : '--no-audio-replay-gain-peak-protection');
      // ── 偏好的音频语言(对齐安卓 audio_preferred_language,BCP-47,空=无偏好)──
      const lang: string = await Settings.getString('audio_preferred_language', '');
      if (lang.length > 0) {
        opts.push(`--audio-language=${lang}`);
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] libvlc audio options: %{public}s', JSON.stringify(opts));
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] buildLibVlcAudioOptions fallback: %{public}s',
        (e as Error).message ?? String(e));
    }
    return opts;
  }

  /** 浮点文本选项(回放增益 preamp/default):仅当值可解析为有限数字时注入,否则跳过。 */
  private pushFloatOption(opts: string[], flag: string, raw: string): void {
    const v = Number.parseFloat(raw);
    if (Number.isFinite(v)) {
      opts.push(`${flag}=${v}`);
    }
  }

  /** 订阅音频环境事件。无权限要求,设备/系统事件。 */
  private setupAudioEnvironment(): void {
    if (this.audioEnvSubscribed) {
      return;
    }
    try {
      const mgr: audio.AudioManager = audio.getAudioManager();
      const routing: audio.AudioRoutingManager = mgr.getRoutingManager();
      const session: audio.AudioSessionManager = mgr.getSessionManager();
      this.audioManager = mgr;
      this.routingManager = routing;
      this.audioSessionManager = session;
      routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.onDeviceChange);
      session.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
      session.on('audioSessionStateChanged', this.onAudioSessionStateChanged);
      session.activateAudioSession({
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT,
      }).catch((error: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] activateAudioSession: %{public}s', error.message);
      });
      telephonyObserver.on('callStateChange', this.onCallStateChange);
      this.audioEnvSubscribed = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] audio environment listeners subscribed');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] setupAudioEnvironment: %{public}s',
        (e as Error).message ?? String(e));
      this.audioManager = null;
      this.routingManager = null;
      this.audioSessionManager = null;
    }
  }

  private teardownAudioEnvironment(): void {
    if (!this.audioEnvSubscribed) {
      return;
    }
    try {
      this.routingManager?.off('deviceChange', this.onDeviceChange);
      if (this.audioSessionManager) {
        this.audioSessionManager.off('audioSessionStateChanged', this.onAudioSessionStateChanged);
        this.audioSessionManager.deactivateAudioSession().catch((error: Error) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] deactivateAudioSession: %{public}s', error.message);
        });
      }
      telephonyObserver.off('callStateChange', this.onCallStateChange);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] teardownAudioEnvironment: %{public}s',
        (e as Error).message ?? String(e));
    }
    this.audioManager = null;
    this.routingManager = null;
    this.audioSessionManager = null;
    this.audioEnvSubscribed = false;
    this.headsetWasPlaying = false;
    this.lossTransient = false;
    this.lossTransientWasPlaying = false;
    this.duckedVolume = -1;
    this.pausedByCall = false;
  }

  // ---- 静态门面(兼容 origin/dev 页面调用;底层仍是 libVLC 单例) ----

  /** 有线/无线耳机设备类型(WIRED/BT/USB)。 */
  private isHeadsetDeviceType(t: audio.DeviceType): boolean {
    return t === audio.DeviceType.WIRED_HEADSET
      || t === audio.DeviceType.WIRED_HEADPHONES
      || t === audio.DeviceType.BLUETOOTH_SCO
      || t === audio.DeviceType.BLUETOOTH_A2DP
      || t === audio.DeviceType.USB_HEADSET;
  }

  private onDeviceChange = (action: audio.DeviceChangeAction): void => {
    void this.handleDeviceChange(action);
  };

  /** 耳机侦测:拔出 → 暂停(记住 wasPlaying);插入 → 按 enable_play_on_headset_insertion 恢复。
   *  对齐安卓 ACTION_AUDIO_BECOMING_NOISY / ACTION_HEADSET_PLUG。 */
  private async handleDeviceChange(action: audio.DeviceChangeAction): Promise<void> {
    try {
      const enabled: boolean = await Settings.getBoolean('enable_headset_detection', true);
      if (!enabled) {
        return;
      }
      const devices: audio.AudioDeviceDescriptor[] = action.deviceDescriptors ?? [];
      // 变化后设备列表是否仍含耳机:拔出后不含 → 音频路由被移除(对齐 Becoming Noisy)。
      const headsetPresent: boolean = devices.some((d: audio.AudioDeviceDescriptor) =>
      this.isHeadsetDeviceType(d.deviceType));
      if (action.type === audio.DeviceChangeType.CONNECT) {
        if (headsetPresent && this.headsetWasPlaying && this.getCurrent() !== null) {
          const resume: boolean = await Settings.getBoolean('enable_play_on_headset_insertion', false);
          if (resume) {
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] headset inserted -> resume playback');
            this.headsetWasPlaying = false;
            this.play();
          }
        }
      } else if (action.type === audio.DeviceChangeType.DISCONNECT) {
        if (!headsetPresent) {
          this.headsetWasPlaying = this.state === PlayState.PLAYING;
          if (this.headsetWasPlaying && this.getCurrent() !== null) {
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] headset removed -> pause playback');
            this.pause();
          }
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] handleDeviceChange: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  private onAudioSessionStateChanged = (event: audio.AudioSessionStateChangedEvent): void => {
    void this.handleAudioInterrupt(event.stateChangeHint);
  };

  /** 通知/来电打断(对齐安卓 VLCAudioFocusHelper.onAudioFocusChange):
   *  INTERRUPT_HINT_PAUSE/STOP → 临时暂停;RESUME → 恢复音量 + 按 resume_playback 恢复播放;
   *  INTERRUPT_HINT_DUCK → 按 audio_ducking 降为 1/3;UNDUCK → 恢复原音量。 */
  private async handleAudioInterrupt(hint: audio.AudioSessionStateChangeHint): Promise<void> {
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] audioSessionStateChanged hint=%{public}d', hint);
      if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE
        || hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP
        || hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP) {
        if (!this.lossTransient) {
          this.lossTransient = true;
          this.lossTransientWasPlaying = this.state === PlayState.PLAYING;
          if (this.lossTransientWasPlaying) {
            this.pause();
          }
        }
      } else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
        // 先恢复被闪避降低的音量
        if (this.duckedVolume >= 0) {
          this.setVolume(this.duckedVolume);
          this.duckedVolume = -1;
        }
        if (this.lossTransient) {
          const resume: boolean = await Settings.getBoolean(Settings.RESUME_PLAYBACK, true);
          if (this.lossTransientWasPlaying && resume && this.state !== PlayState.PLAYING) {
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] audioInterrupt resume playback');
            this.play();
          }
          this.lossTransient = false;
          this.lossTransientWasPlaying = false;
        }
      } else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_DUCK) {
        if (this.state === PlayState.PLAYING && this.duckedVolume < 0) {
          const duck: boolean = await Settings.getBoolean(Settings.AUDIO_DUCKING, true);
          if (duck) {
            this.duckedVolume = this.getVolume();
            const ducked: number = Math.max(1, Math.floor(this.duckedVolume / 3));
            this.setVolume(ducked);
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] audioInterrupt duck %{public}d -> %{public}d',
              this.duckedVolume, ducked);
          }
        }
      } else if (hint === audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK) {
        if (this.duckedVolume >= 0) {
          this.setVolume(this.duckedVolume);
          this.duckedVolume = -1;
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] handleAudioInterrupt: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  private onCallStateChange = (info: telephonyObserver.CallStateInfo): void => {
    void this.handleCallStateChange(info);
  };

  /** 通话状态:进入通话(RINGING/OFFHOOK/ANSWERED) → 暂停;结束(IDLE) → 按 resume_playback 恢复。
   *  对齐安卓 来电打断 + RESUME_PLAYBACK 设置(通话结束继续播放)。 */
  private async handleCallStateChange(info: telephonyObserver.CallStateInfo): Promise<void> {
    try {
      const inCall: boolean = info.state !== call.CallState.CALL_STATE_IDLE
        && info.state !== call.CallState.CALL_STATE_UNKNOWN;
      if (inCall) {
        if (this.state === PlayState.PLAYING) {
          this.pausedByCall = true;
          hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] call state=%{public}d -> pause playback', info.state);
          this.pause();
        }
      } else {
        if (this.pausedByCall) {
          const resume: boolean = await Settings.getBoolean(Settings.RESUME_PLAYBACK, true);
          if (resume && this.state !== PlayState.PLAYING) {
            hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] call ended -> resume playback');
            this.play();
          }
          this.pausedByCall = false;
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] handleCallStateChange: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** timeChanged 节流:libVLC 在 seek/定位时会爆发高频 timeChanged,逐条刷新
   *  position 会触发 ArkUI 渲染风暴并积压 tsfn 队列;合并到 300ms 一刷。 */
  private onTimeChangedThrottled(ms: number): void {
    const now = Date.now();
    if (now - this.lastTimeEmit < 300) {
      return;
    }
    this.lastTimeEmit = now;
    this.position = ms;
    this.emitTime();
  }

  private startSessionSync(): void {
    if (this.sessionSyncTimer !== -1) {
      return;
    }
    this.sessionSyncTimer = setInterval(() => {
      void MediaSessionManager.updatePlaybackState(this.state, this.position, this.duration, this.speed);
    }, 10000);
  }

  private stopSessionSync(): void {
    if (this.sessionSyncTimer !== -1) {
      clearInterval(this.sessionSyncTimer);
      this.sessionSyncTimer = -1;
    }
  }

  /** 构建长时任务通知的 WantAgent(点击通知回到应用)。 */
  private async getContinuousWantAgent(): Promise<WantAgent | null> {
    if (this.wantAgentObj !== null) {
      return this.wantAgentObj;
    }
    try {
      const ctx = AppContext.get();
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: 'EntryAbility',
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      this.wantAgentObj = await wantAgent.getWantAgent(info);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] build continuous-task wantAgent failed: %{public}s',
        (e as Error).message ?? String(e));
    }
    return this.wantAgentObj;
  }

  /** 申请 AUDIO_PLAYBACK 长时任务,保证退后台后音频不被系统静音/挂起。 */
  private async startContinuousTask(): Promise<void> {
    if (this.continuousTaskActive || !AppContext.isReady()) {
      return;
    }
    const agent: WantAgent | null = await this.getContinuousWantAgent();
    if (agent === null) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] startBackgroundRunning skipped: wantAgent unavailable');
      return;
    }
    try {
      await backgroundTaskManager.startBackgroundRunning(
        AppContext.get(), backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      this.continuousTaskActive = true;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] continuous task started (AUDIO_PLAYBACK)');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] startBackgroundRunning failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** 取消长时任务(暂停/停止/出错/释放时)。 */
  private async stopContinuousTask(): Promise<void> {
    if (!this.continuousTaskActive) {
      return;
    }
    this.continuousTaskActive = false;
    if (!AppContext.isReady()) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(AppContext.get());
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] continuous task stopped');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] stopBackgroundRunning failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** 按流量计费的网络下对串流的处理(对齐 Android checkMetered)。 */
  private async checkMeteredNetwork(meteredOverride?: boolean): Promise<void> {
    if (this.state !== PlayState.PLAYING && this.state !== PlayState.PREPARED) {
      return;
    }
    const action: string = await Settings.getString(Settings.KEY_METERED_CONNECTION, '0');
    if (action === '0') {
      return;
    }
    const cur: MediaWrapper | null = this.getCurrent();
    const uri: string = cur?.uri ?? '';
    if (!isStreamingUri(uri)) {
      return;
    }
    let metered: boolean;
    if (meteredOverride !== undefined) {
      metered = meteredOverride;
    } else {
      metered = await NetworkConnectionManager.isMetered();
    }
    if (!metered) {
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] metered stream action=%{public}s uri=%{public}s',
      action, uri);
    if (action === '1') {
      this.stop();
      UiFeedback.showToast({ message: '已停止播放（按流量计费的网络上的串流）' });
    } else {
      UiFeedback.showToast({ message: '警告：正在按流量计费的网络上播放串流，可能产生流量费用' });
    }
  }

  private onNativeEvent(event: string, value: number): void {
    // 注意:这里不要对每个事件打 hilog —— seek 后 libVLC 会爆发大量 timeChanged,
    // 逐条打日志会把 hilog socket 写满导致 writev 阻塞,JS 主线程卡死(AppFreeze)。
    switch (event) {
      case 'playing':
        this.state = PlayState.PLAYING;
        this.emitState();
        this.refreshVideoSize();
        this.startSessionSync();
        void this.startContinuousTask();
        void this.checkMeteredNetwork();
        void MediaSessionManager.updatePlaybackState(PlayState.PLAYING, this.position, this.duration, this.speed);
        break;
      case 'paused':
        this.state = PlayState.PAUSED;
        this.emitState();
        this.stopSessionSync();
        void this.stopContinuousTask();
        void MediaSessionManager.updatePlaybackState(PlayState.PAUSED, this.position, this.duration, this.speed);
        break;
      case 'stopped':
        this.state = PlayState.STOPPED;
        this.emitState();
        this.stopSessionSync();
        void this.stopContinuousTask();
        void MediaSessionManager.updatePlaybackState(PlayState.STOPPED, this.position, this.duration, this.speed);
        break;
      case 'ended':
        this.emitMediaEnded();
        this.onComplete();
        this.stopSessionSync();
        void this.stopContinuousTask();
        void MediaSessionManager.updatePlaybackState(PlayState.STOPPED, this.position, this.duration, this.speed);
        break;
      case 'error':
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] MediaPlayerEncounteredError');
        this.state = PlayState.ERROR;
        this.emitState();
        this.stopSessionSync();
        void this.stopContinuousTask();
        void MediaSessionManager.updatePlaybackState(PlayState.ERROR, this.position, this.duration, this.speed);
        break;
      case 'timeChanged':
        this.onTimeChangedThrottled(value);
        break;
      case 'lengthChanged':
        this.duration = value;
        this.emitTime();
        void MediaSessionManager.updateMetadataDuration(value);
        void MediaSessionManager.updatePlaybackState(this.state, this.position, this.duration, this.speed);
        break;
      case 'vout':
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] vout count=%{public}s videoOutId=%{public}s',
          String(value), this.videoOutId);
        this.refreshVideoSize();
        break;
      case 'esAdded':
      case 'esDeleted':
      case 'esSelected':
        this.emitTracksChanged();
        break;
      default:
        break;
    }
  }

  private notifyChange(): void {
    const s = this.snapshot();
    for (const l of this.listeners) {
      if (l.onChange) {
        l.onChange(s);
      }
    }
  }

  private emitState(): void {
    for (const l of this.listeners) {
      if (l.onStateChange) {
        l.onStateChange(this.state);
      }
    }
    this.notifyChange();
  }

  private emitMediaEnded(): void {
    for (const l of this.listeners) {
      if (l.onMediaEnded) {
        l.onMediaEnded();
      }
    }
  }

  private emitTime(): void {
    for (const l of this.listeners) {
      if (l.onTimeUpdate) {
        l.onTimeUpdate(this.position, this.duration);
      }
    }
    this.notifyChange();
  }

  private emitQueue(): void {
    for (const l of this.listeners) {
      if (l.onQueueChanged) {
        l.onQueueChanged();
      }
    }
    this.notifyChange();
  }

  private emitVideoSize(): void {
    for (const l of this.listeners) {
      if (l.onVideoSize) {
        l.onVideoSize(this.videoWidth, this.videoHeight);
      }
    }
  }

  private emitTracksChanged(): void {
    for (const l of this.listeners) {
      if (l.onTracksChanged) {
        l.onTracksChanged();
      }
    }
  }

  private saveQueueHistory(): void {
    if (this.queueHistoryType !== null) {
      void PlaybackQueueHistory.save(this.queueHistoryType, this.queue, this.currentIndex);
    }
  }

  private async loadCurrent(): Promise<void> {
    const item = this.getCurrent();
    if (!item || !this.lib) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent: empty queue or lib');
      return;
    }
    // stop() 可能已使 player 失效(异步收尾),加载前必须重建,否则 setMedia 落在已释放的原生句柄上
    this.player = await this.ensureLivePlayer();
    if (!this.player) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent: player unavailable');
      return;
    }
    // ISO 文件按文件名识别为光盘 MRL(与 Android 对 .iso 强制 demux 一致)
    const mrl = PlaybackService.isoToDiscMrl(item.uri);
    if (mrl !== item.uri) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] iso disc MRL: %{public}s -> %{public}s', item.uri, mrl);
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent uri=%{public}s videoOut=%{public}s',
      item.uri, this.videoOutId);

    let media: Media | null = null;
    if (needsFdOpen(item.uri)) {
      try {
        const file = fs.openSync(item.uri, fs.OpenMode.READ_ONLY);
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] openSync ok fd=%{public}d uri=%{public}s', file.fd, item.uri);
        media = Media.fromFd(this.lib, file.fd);
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] closeSync after fromFd: %{public}s',
            (closeErr as Error).message ?? String(closeErr));
        }
      } catch (e) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] openSync FAILED uri=%{public}s err=%{public}s',
          item.uri, (e as Error).message ?? String(e));
      }
    } else {
      media = Media.fromMrl(this.lib, mrl);
    }

    if (!media) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] Media create FAILED uri=%{public}s', item.uri);
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }

    // file://docs 通过文档提供方的 fd 读取。OHCodec 输出队列现在会主动施加
    // 背压，无需再用 4 秒缓存掩盖卡顿；保留 VLC 标准的一秒缓冲，让 4K 硬解
    // 在时钟启动前完成预热。普通本地文件和网络串流不受影响。
    if (needsFdOpen(item.uri)) {
      media.addOption(':file-caching=1000');
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] document fd file cache: 1000 ms');
    }

    // 硬件加速(对应 Android VLCOptions.setMediaOptions):-1 自动不干预(OHOS 默认优先硬解,
    // 失败自动回退软解);0 禁用强制软解;1 解码加速=硬解+关闭直渲;2 完全加速=硬解+直渲。
    // iso/bluray 光碟不进此分支,保持下方强制软解(对应 Android MEDIA_NO_HWACCEL)。
    const isDiscMrl: boolean = mrl.startsWith('bluray://') || mrl.toLowerCase().endsWith('.iso');
    if (!isDiscMrl) {
      // Prefer the nearest synchronization point for interactive seeks. Exact
      // preroll on long-GOP 4K HEVC files can otherwise stall OHCodec for
      // several seconds after every scrub/double-tap operation.
      media.addOption(':input-fast-seek');
      const hwAccel: string = await Settings.getString(
        Settings.KEY_HARDWARE_ACCELERATION, Settings.HARDWARE_ACCELERATION_DEFAULT);
      if (hwAccel === '0') {
        media.addOption(':avcodec-hw=disabled');
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] hardware acceleration: disabled (software decode)');
      } else if (hwAccel === '1') {
        media.addOption(':avcodec-hw=any');
        media.addOption(':no-avcodec-dr');
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] hardware acceleration: decoding (hw decode, no direct render)');
      } else if (hwAccel === '2') {
        media.addOption(':avcodec-hw=any');
        hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] hardware acceleration: full (hw decode + direct render)');
      } else {
        // 自动模式下，普通视频保留 Buffer 输出供 VLC 合成内置/外挂字幕；4K 及
        // 更高负载的视频改走 OHCodec Surface 直出。否则 P010 10-bit 内容会在
        // CPU 上执行全分辨率 P010 -> I420 转换，4K120 时必然持续丢帧。
        media.addOption(':avcodec-hw=any');
        const useDirectRender: boolean = item.width >= 3840 && item.height >= 1600;
        if (useDirectRender) {
          media.addOption(':avcodec-dr');
          hilog.info(LOG_DOMAIN, LOG_TAG,
            '[VLC] hardware acceleration: auto high-load Surface direct render (%{public}dx%{public}d)',
            item.width, item.height);
        } else {
          media.addOption(':no-avcodec-dr');
          hilog.info(LOG_DOMAIN, LOG_TAG,
            '[VLC] hardware acceleration: auto buffer decode + subtitle vout (%{public}dx%{public}d)',
            item.width, item.height);
        }
      }
    }

    // Blu-ray 主视频为 H.264/HEVC。OHOS 补丁默认优先 h264_ohcodec 硬解,
    // 但该硬解器对部分流(实测 H.264 m2ts)会 "cannot start codec" 导致黑屏且不回退。
    // 按媒体注入软解选项(必须在 setMedia 前),对齐 Android Media.setHWDecoderEnabled 的 per-media 开关。
    // 注意: .iso 一律注入 —— libbluray access_demux 会自动探测 ISO(文件名可能被 MediaLibrary
    // 重命名而失去 bd/bluray 标识),DVD/VCD 的 MPEG-1/2 本就软解,不受 avcodec-hw 影响。
    if (mrl.startsWith('bluray://') || mrl.toLowerCase().endsWith('.iso')) {
      media.addOption(':avcodec-hw=none');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[VLC] iso/bluray MRL: force software decode (:avcodec-hw=none) mrl=%{public}s', mrl);
    }

    if (!this.player.setMedia(media)) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[VLC] setMedia FAILED uri=%{public}s', item.uri);
      media.release();
      this.state = PlayState.ERROR;
      this.emitState();
      return;
    }

    this.duration = 0;
    this.position = 0;
    this.videoWidth = 0;
    this.videoHeight = 0;
    if (item.width > 0 && item.height > 0) {
      this.videoWidth = item.width;
      this.videoHeight = item.height;
      this.emitVideoSize();
    }
    // 按当前媒体的音视频语境应用速度:音频按 全局/单曲 优先级,视频沿用 this.speed(视频页自行管理)
    this.applyEffectiveSpeed();
    this.player.setScale(0);
    this.player.setVolume(this.volume);
    this.player.play();
    this.state = PlayState.PREPARED;
    this.emitState();
    const artwork: string = item.artworkPath.length > 0 ? item.artworkPath : item.artworkUrl;
    // metadata 先于播放状态写入，保证播控中心第一次出现时就带完整曲目信息和封面。
    await MediaSessionManager.updateMetadata(item.title, item.artistName, this.duration, artwork, item.albumName);
    await MediaSessionManager.updatePlaybackState(this.state, this.position, this.duration, this.speed);
  }

  /**
   * 计算并应用当前媒体的有效播放速度。
   * - 音频(或仅播放音频):全局开关开 → 全局值;否则该曲目独立速度,没有则 1.0。
   * - 视频:沿用 this.speed(视频播放页通过 setSpeed 自行管理,不受音频全局/单曲速度影响)。
   */
  private applyEffectiveSpeed(): void {
    const item = this.getCurrent();
    if (!item || !this.player) {
      return;
    }
    let eff: number = 1.0;
    if (item.type === 1 || this.playAsAudio) {
      if (this.globalSpeedEnabled) {
        eff = this.globalSpeedValue;
      } else {
        eff = this.trackSpeeds.get(item.uri) ?? 1.0;
      }
    } else {
      eff = this.speed;
    }
    eff = Math.max(0.25, Math.min(8.0, eff));
    if (Math.abs(eff - this.speed) > 0.001) {
      this.speed = eff;
    }
    this.player.setRate(eff);
  }

  /** 持久化每曲目独立速度 {uri: speed}。 */
  private persistTrackSpeeds(): void {
    const obj: Record<string, number> = {};
    this.trackSpeeds.forEach((v: number, k: string) => {
      obj[k] = v;
    });
    void Settings.put(Settings.KEY_AUDIO_TRACK_SPEEDS, JSON.stringify(obj));
  }

  private onComplete(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] onComplete stopAfterCurrent=%{public}s repeatMode=%{public}d currentIndex=%{public}d queueLen=%{public}d',
      String(this.stopAfterCurrent), this.repeatMode, this.currentIndex, this.queue.length);
    if (this.stopAfterCurrent) {
      this.stopAfterCurrent = false;
      this.stop();
      return;
    }
    // 对齐 Android PlaylistManager.EndReached → determinePrevAndNextIndices + next():
    // 自动播完时 repeat-one 重播当前,其余按队列/随机继续或停止。
    const nextIdx = this.computeNextIndex(false);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[VLC] onComplete -> nextIdx=%{public}d (cur=%{public}d len=%{public}d shuffle=%{public}s repeat=%{public}d)',
      nextIdx, this.currentIndex, this.queue.length,
      this.shuffle ? 'on' : 'off', this.repeatMode);
    if (nextIdx < 0) {
      // 没有下一首(随机全部播完且未开循环 / 顺序到队尾且未开循环)→ 停止
      this.stop();
      return;
    }
    // libVLC 在 EndReached 后 player 进入 Ended 终止态,直接 setMedia+play 在本 port
    // 不保证重启(旧版 setTime(0)+play 同样无效)。先复位 native player 状态机,
    // 再 setMedia+play 重载,对齐 Android 播放完自动接续的标准做法。
    this.player?.stop();
    if (nextIdx === this.currentIndex) {
      // 单曲循环:重播当前(重新加载媒体最可靠,避免 ended 后 setTime 无效)
      void this.loadCurrent();
      return;
    }
    this.currentIndex = nextIdx;
    this.emitQueue();
    this.saveQueueHistory();
    void this.loadCurrent();
  }

  /**
   * 计算下一首索引(对齐 Android PlaylistManager.determinePrevAndNextIndices + next)。
   * @param forceManual 是否用户手动点“下一首”。单曲循环(repeatMode===2)时无论手动还是自动
   *                    都重播当前(IndexPair(currentIndex,currentIndex));其余模式 forceManual
   *                    只影响队尾是否回卷(手动永不停止)。
   * @returns 下一首索引;返回 -1 表示应停止(队列空 / 随机播完未循环 / 顺序队尾未循环)。
   */
  private computeNextIndex(forceManual: boolean): number {
    const size = this.queue.length;
    if (size === 0) {
      return -1;
    }
    // 单曲循环:手动下一曲与自动播完都重播当前(对齐 Android REPEAT_ONE → IndexPair(currentIndex,currentIndex)),
    // 不切换曲目、不复位模式。
    if (this.repeatMode === 2) {
      return this.currentIndex;
    }
    if (this.shuffle) {
      // 随机不重复:shuffleHistory 记录已播放过的索引。全部播完一轮后,
      // 手动跳过永不停止(清空重洗);自动播完且未开循环时停止。
      if (this.shuffleHistory.length + 1 >= size) {
        if (!forceManual && this.repeatMode === 0) {
          this.shuffleHistory = [];
          return -1;
        }
        this.shuffleHistory = [];
      }
      let idx: number = this.currentIndex;
      let guard: number = 0;
      do {
        idx = Math.floor(Math.random() * size);
        guard++;
      } while ((idx === this.currentIndex || this.shuffleHistory.includes(idx)) && guard < 200);
      this.shuffleHistory.push(this.currentIndex);
      return idx;
    }
    // 顺序播放
    const nextIdx: number = this.currentIndex + 1;
    if (nextIdx < size) {
      return nextIdx;
    }
    // 已到队尾:手动跳转永远回卷到第 0 首(不暂停);
    // 自动播完仅在开循环(全部/单曲)时回卷,否则停止。
    if (forceManual || this.repeatMode !== 0) {
      return 0;
    }
    return -1;
  }
}
