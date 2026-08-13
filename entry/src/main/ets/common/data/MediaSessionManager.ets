import { avSession } from '@kit.AVSessionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';
import { PlayState } from '../models/MediaModels';
import { image } from '@kit.ImageKit';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC';

/** 媒体会话控制回调(由 PlaybackService 注入,处理通知栏/锁屏命令)。 */
export interface MediaSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onStop: () => void;
  onNext: () => void;
  onPrevious: () => void;
  onSeek: (ms: number) => void;
  onSetSpeed: (speed: number) => void;
}

/**
 * MediaSessionManager —— AVSession(媒体会话)封装,对应 Android MediaSessionCallback。
 * 作用:1) 后台播放时系统通过会话识别"正在播放媒体",配合 backgroundModes 不被冻结;
 *       2) 通知栏/锁屏展示媒体信息与控制按钮(用户看到的媒体通知)。
 */
export class MediaSessionManager {
  private static session: avSession.AVSession | null = null;
  private static creatingPromise: Promise<avSession.AVSession | null> | null = null;
  private static callbacks: MediaSessionCallbacks | null = null;
  private static lastStateUpdate: number = 0;
  /** 最近一次上报的媒体信息,供时长就绪后补报 metadata.duration。 */
  private static lastTitle: string = '';
  private static lastArtist: string = '';
  private static lastAlbum: string = '';
  private static lastArtworkPath: string = '';
  private static artworkPixelMap: image.PixelMap | null = null;
  private static metadataVersion: number = 0;

  static setCallbacks(cb: MediaSessionCallbacks | null): void {
    MediaSessionManager.callbacks = cb;
  }

  /** 懒创建并激活会话(失败不阻塞播放,仅打日志)。 */
  static async ensure(): Promise<avSession.AVSession | null> {
    if (MediaSessionManager.session !== null) {
      return MediaSessionManager.session;
    }
    if (MediaSessionManager.creatingPromise !== null) {
      return MediaSessionManager.creatingPromise;
    }
    const creating: Promise<avSession.AVSession | null> = MediaSessionManager.createSession();
    MediaSessionManager.creatingPromise = creating;
    try {
      return await creating;
    } finally {
      MediaSessionManager.creatingPromise = null;
    }
  }

  private static async createSession(): Promise<avSession.AVSession | null> {
    try {
      if (!AppContext.isReady()) {
        return null;
      }
      const session: avSession.AVSession = await avSession.createAVSession(AppContext.get(), 'VLC Audio', 'audio');
      session.on('play', () => {
        MediaSessionManager.callbacks?.onPlay();
      });
      session.on('pause', () => {
        MediaSessionManager.callbacks?.onPause();
      });
      session.on('stop', () => {
        MediaSessionManager.callbacks?.onStop();
      });
      session.on('playNext', () => {
        MediaSessionManager.callbacks?.onNext();
      });
      session.on('playPrevious', () => {
        MediaSessionManager.callbacks?.onPrevious();
      });
      session.on('seek', (time: number) => {
        MediaSessionManager.callbacks?.onSeek(time);
      });
      session.on('setSpeed', (speed: number) => {
        MediaSessionManager.callbacks?.onSetSpeed(speed);
      });
      await session.activate();
      MediaSessionManager.session = session;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession created & activated');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession create failed: %{public}s',
        (e as Error).message ?? String(e));
    }
    return MediaSessionManager.session;
  }

  /** 更新媒体信息(标题/艺术家)。 */
  static async updateMetadata(title: string, artist: string = '', duration: number = 0,
    artworkPath: string = '', album: string = ''): Promise<void> {
    MediaSessionManager.lastTitle = title;
    MediaSessionManager.lastArtist = artist;
    MediaSessionManager.lastAlbum = album;
    MediaSessionManager.lastArtworkPath = artworkPath;
    const version: number = ++MediaSessionManager.metadataVersion;
    const s: avSession.AVSession | null = MediaSessionManager.session ?? await MediaSessionManager.ensure();
    if (s === null) {
      return;
    }
    try {
      const nextImage: image.PixelMap | null = await MediaSessionManager.loadArtwork(artworkPath);
      if (version !== MediaSessionManager.metadataVersion) {
        nextImage?.release();
        return;
      }
      MediaSessionManager.releaseArtwork();
      MediaSessionManager.artworkPixelMap = nextImage;
      const metadata: avSession.AVMetadata = {
        assetId: title.length > 0 ? title : 'vlc-media',
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      };
      if (nextImage !== null) {
        metadata.mediaImage = nextImage;
      }
      await s.setAVMetadata(metadata);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession setAVMetadata failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** 时长就绪/变化时补报 metadata(播控中心进度条依赖 metadata.duration)。 */
  static async updateMetadataDuration(duration: number): Promise<void> {
    if (MediaSessionManager.lastTitle.length === 0 && MediaSessionManager.lastArtist.length === 0) {
      return;
    }
    await MediaSessionManager.updateMetadata(MediaSessionManager.lastTitle, MediaSessionManager.lastArtist, duration,
      MediaSessionManager.lastArtworkPath, MediaSessionManager.lastAlbum);
  }

  /** 更新播放状态(播放中高频位置刷新节流到 1s 一次)。 */
  static async updatePlaybackState(state: PlayState, position: number, duration: number, speed: number): Promise<void> {
    const s: avSession.AVSession | null = MediaSessionManager.session ?? await MediaSessionManager.ensure();
    if (s === null) {
      return;
    }
    const now: number = Date.now();
    if (state === PlayState.PLAYING && now - MediaSessionManager.lastStateUpdate < 500) {
      return;
    }
    MediaSessionManager.lastStateUpdate = now;
    try {
      const ps: avSession.AVPlaybackState = {
        state: MediaSessionManager.toAVState(state),
        position: { elapsedTime: position, updateTime: now },
        duration: duration,
        speed: speed,
      };
      await s.setAVPlaybackState(ps);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession setAVPlaybackState failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  /** 销毁会话(播放服务 release 时调用)。 */
  static async release(): Promise<void> {
    const s: avSession.AVSession | null = MediaSessionManager.session;
    MediaSessionManager.session = null;
    MediaSessionManager.creatingPromise = null;
    MediaSessionManager.callbacks = null;
    MediaSessionManager.metadataVersion++;
    MediaSessionManager.releaseArtwork();
    if (s === null) {
      return;
    }
    try {
      s.off('play');
      s.off('pause');
      s.off('stop');
      s.off('playNext');
      s.off('playPrevious');
      s.off('seek');
      s.off('setSpeed');
      await s.deactivate();
      await s.destroy();
      hilog.info(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession released');
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession release failed: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  private static toAVState(state: PlayState): avSession.PlaybackState {
    switch (state) {
      case PlayState.PLAYING:
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
      case PlayState.PAUSED:
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      case PlayState.STOPPED:
        return avSession.PlaybackState.PLAYBACK_STATE_STOP;
      case PlayState.ERROR:
        return avSession.PlaybackState.PLAYBACK_STATE_ERROR;
      case PlayState.PREPARED:
        return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
      case PlayState.IDLE:
      default:
        return avSession.PlaybackState.PLAYBACK_STATE_IDLE;
    }
  }

  /** SweetVideo also decodes the local cover into PixelMap before assigning AVMetadata.mediaImage. */
  private static async loadArtwork(artworkPath: string): Promise<image.PixelMap | null> {
    if (artworkPath.length > 0) {
      let source: image.ImageSource | null = null;
      try {
        source = image.createImageSource(artworkPath);
        return await source.createPixelMap({
          desiredSize: { width: 512, height: 512 },
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        });
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession artwork decode failed path=%{public}s err=%{public}s',
          artworkPath, (e as Error).message ?? String(e));
      } finally {
        try {
          source?.release();
        } catch (_e) {
          // ignore already released source
        }
      }
    }
    let defaultSource: image.ImageSource | null = null;
    try {
      const content: Uint8Array = AppContext.get().resourceManager.getMediaContentSync($r('app.media.ic_launcher').id);
      defaultSource = image.createImageSource(content.buffer);
      return await defaultSource.createPixelMap({
        desiredSize: { width: 512, height: 512 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      });
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[VLC] AVSession default artwork decode failed: %{public}s',
        (e as Error).message ?? String(e));
      return null;
    } finally {
      try {
        defaultSource?.release();
      } catch (_e) {
        // ignore already released source
      }
    }
  }

  private static releaseArtwork(): void {
    try {
      MediaSessionManager.artworkPixelMap?.release();
    } catch (_e) {
      // ignore already released image
    }
    MediaSessionManager.artworkPixelMap = null;
  }
}
