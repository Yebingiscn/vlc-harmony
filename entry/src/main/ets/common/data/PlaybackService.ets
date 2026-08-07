/**
 * PlaybackService —— 全局单例播放业务层。
 * 通过 ArkTS LibVLC/Media/MediaPlayer 对接 libVLC(不再直接 import libvlcnapi.so)。
 * 另提供 QueueItem / PlaybackState / 静态方法门面,兼容 origin/dev 音频 UI 调用方式。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { promptAction } from '@kit.ArkUI';
import { MediaWrapper, PlayState } from '../models/MediaModels';
import { Settings } from './Settings';
import { AppContext } from './AppContext';
import { MediaSessionManager } from './MediaSessionManager';
import { NetworkConnectionManager } from './NetworkConnectionManager';
import { LibVLC, Media, MediaPlayer, Equalizer, RendererDiscoverer, MediaSlaveType } from '../../libvlc';
import { VlcTrackInfo, VlcChapterInfo, VlcRendererInfo, VlcMediaTrackInfo } from 'libvlcnapi.so';

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

  toMediaWrapper(type: number = 1): MediaWrapper {
    const mw = new MediaWrapper(this.id, this.title, this.uri, type);
    mw.artistName = this.artistName;
    mw.albumName = this.albumName;
    mw.artworkPath = this.artworkPath;
    return mw;
  }

  static fromMediaWrapper(mw: MediaWrapper): QueueItem {
    return new QueueItem(mw.id, mw.title, mw.uri, mw.artistName, mw.albumName, mw.artworkPath);
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
  /** 网络计费变化监听(init 注册,release 注销)。 */
  private meteredChangeListener: (metered: boolean) => void = () => {};
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

  private lib: LibVLC | null = null;
  private player: MediaPlayer | null = null;
  private equalizer: Equalizer | null = null;
  private rendererDiscoverer: RendererDiscoverer | null = null;
  private currentRendererHandle: number = -1;

  static getInstance(): PlaybackService {
    if (!PlaybackService.instance) {
      PlaybackService.instance = new PlaybackService();
    }
    return PlaybackService.instance;
  }

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
      this.lib = new LibVLC();
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
        onPlay: () => { void this.play(); },
        onPause: () => { this.pause(); },
        onStop: () => { this.stop(); },
        onNext: () => { void this.next(); },
        onPrevious: () => { void this.prev(); },
        onSeek: (ms: number) => { this.seek(ms); },
        onSetSpeed: (rate: number) => { this.setSpeed(rate); },
      });
      void MediaSessionManager.ensure();
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

  private lastTimeEmit: number = 0;
  /** AVSession 播放中进度同步定时器(确保通知栏进度条持续推进)。 */
  private sessionSyncTimer: number = -1;

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
    void MediaSessionManager.updatePlaybackState(this.state, ms, this.duration, this.speed);
  }

  private startSessionSync(): void {
    if (this.sessionSyncTimer !== -1) {
      return;
    }
    this.sessionSyncTimer = setInterval(() => {
      void MediaSessionManager.updatePlaybackState(this.state, this.position, this.duration, this.speed);
    }, 1000);
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
      promptAction.showToast({ message: '已停止播放（按流量计费的网络上的串流）' });
    } else {
      promptAction.showToast({ message: '警告：正在按流量计费的网络上播放串流，可能产生流量费用' });
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

  refreshVideoSize(): void {
    if (!this.player) {
      return;
    }
    try {
      this.player.setScale(0);
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
    if (this.playAsAudio === value) { return; }
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

  /**
   * SPU / 音频延迟的本地缓存。
   * libvlc 已桥接 set/get_spu_delay 与 set/get_audio_delay(任务 #8);本字段保留
   * 作为快速 UI 显示路径,仅由 set* 回写,避免每次 getter 过 native 桥。
   * 切换媒体/release 时外部需将两值重置为 0。
   */
  private spuDelayUs: number = 0;
  private audioDelayUs: number = 0;

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

  /** QueueItem[] → MediaWrapper[] 后播放(音频列表入口)。 */
  async playQueueItems(items: QueueItem[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.playList(mws, startIndex, replace);
  }

  async appendQueueItems(items: QueueItem[]): Promise<void> {
    const mws = items.map((q: QueueItem) => q.toMediaWrapper(1));
    await this.append(mws);
  }

  async prepareList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    if (items.length === 0) {
      return;
    }
    await this.ensureInit();
    if (!this.inited) {
      return;
    }
    this.queue = replace ? items.slice() : this.queue.concat(items);
    this.currentIndex = replace ? startIndex : this.queue.length - items.length + startIndex;
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
  }

  async playList(items: MediaWrapper[], startIndex: number = 0, replace: boolean = true): Promise<void> {
    await this.prepareList(items, startIndex, replace);
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

  private async loadCurrent(): Promise<void> {
    const item = this.getCurrent();
    if (!item || !this.lib || !this.player) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] loadCurrent: empty queue or player');
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

    // 硬件加速(对应 Android VLCOptions.setMediaOptions):-1 自动不干预(OHOS 默认优先硬解,
    // 失败自动回退软解);0 禁用强制软解;1 解码加速=硬解+关闭直渲;2 完全加速=硬解+直渲。
    // iso/bluray 光碟不进此分支,保持下方强制软解(对应 Android MEDIA_NO_HWACCEL)。
    const isDiscMrl: boolean = mrl.startsWith('bluray://') || mrl.toLowerCase().endsWith('.iso');
    if (!isDiscMrl) {
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
      }
    }

    // Blu-ray 主视频为 H.264/HEVC。OHOS 补丁默认优先 h264_ohosavcodec 硬解,
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
    void MediaSessionManager.updateMetadata(item.title, item.artistName, this.duration);
    void MediaSessionManager.updatePlaybackState(this.state, this.position, this.duration, this.speed);
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

  /** 持久化每曲目独立速度 {uri: speed}。 */
  private persistTrackSpeeds(): void {
    const obj: Record<string, number> = {};
    this.trackSpeeds.forEach((v: number, k: string) => {
      obj[k] = v;
    });
    void Settings.put(Settings.KEY_AUDIO_TRACK_SPEEDS, JSON.stringify(obj));
  }

  /** 全局音频速度开关当前状态(供弹窗默认作用域)。 */
  isGlobalSpeedEnabled(): boolean {
    return this.globalSpeedEnabled;
  }

  setStopAfterCurrent(v: boolean): void {
    this.stopAfterCurrent = v;
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
   * NAPI 侧已保证 stop 不持全局锁,可在返回路径上同步调用。
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
    if (this.shuffle === value) { return; }
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

  // ---- 静态门面(兼容 origin/dev 页面调用;底层仍是 libVLC 单例) ----

  static getState(): PlayState {
    return PlaybackService.getInstance().getState();
  }

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
}
