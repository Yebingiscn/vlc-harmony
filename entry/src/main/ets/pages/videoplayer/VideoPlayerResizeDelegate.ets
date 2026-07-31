import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

/**
 * VideoPlayerResizeDelegate —— 对齐 Android VideoPlayerResizeDelegate。
 * 本阶段落地 contain 缩放；宽高比面板 UI 仍为 stub。
 */
export class VideoPlayerResizeDelegate {
  isShowing: boolean = false;

  /**
   * 在容器内按视频原始宽高比做 contain 适配(不拉伸)。
   * 返回显示宽高(vp)。
   */
  fitContain(
    containerW: number,
    containerH: number,
    videoW: number,
    videoH: number
  ): [number, number] {
    if (containerW <= 0 || containerH <= 0) {
      return [containerW, containerH];
    }
    if (videoW <= 0 || videoH <= 0) {
      return [containerW, containerH];
    }
    const videoAspect = videoW / videoH;
    const viewAspect = containerW / containerH;
    if (videoAspect > viewAspect) {
      return [containerW, containerW / videoAspect];
    }
    return [containerH * videoAspect, containerH];
  }

  /** 计算 XComponent 显示尺寸。 */
  computeSurface(
    containerW: number,
    containerH: number,
    videoW: number,
    videoH: number
  ): [number, number] {
    return this.fitContain(containerW, containerH, videoW, videoH);
  }

  /** 对齐 Android showResizeOverlay —— 宽高比面板尚未实现。 */
  showResizeOverlay(): void {
    hilog.info(0x0001, 'VLC', '[VLC] ResizeDelegate.showResizeOverlay (stub)');
    promptAction.showToast({ message: 'Aspect ratio is not available yet' });
  }

  hideResizeOverlay(): void {
    this.isShowing = false;
  }

  displayResize(): void {
    this.showResizeOverlay();
  }

  resizeVideo(): void {
    this.showResizeOverlay();
  }

  setVideoScale(_scale: number): void {
    hilog.info(0x0001, 'VLC', '[VLC] ResizeDelegate.setVideoScale (stub)');
  }
}

/** 兼容旧导出名。 */
export function fitContain(
  containerW: number,
  containerH: number,
  videoW: number,
  videoH: number
): [number, number] {
  return new VideoPlayerResizeDelegate().fitContain(containerW, containerH, videoW, videoH);
}
