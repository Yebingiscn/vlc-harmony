import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/data/AppContext';
import { NavController } from '../common/data/NavController';
import { LibVLC, Media, MediaPlayer } from '../libvlc';
import { getProcessUsage, ProcessUsage } from 'libvlcnapi.so';
import { FORMAT_COMPAT_MANIFEST_JSON } from '../common/data/FormatCompatManifestData';

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'VLC_COMPAT';
const XCOMPONENT_ID: string = 'vlc_video_surface';
const NAPI_LIBRARY: string = 'libvlcnapi';

interface FormatCompatEntry {
  dir: string;
  file: string;
  container: string;
  codec: string;
  kind: string;
  url: string;
}

interface PassResult {
  pass: string;
  state: string;
  videoWidth: number;
  videoHeight: number;
  durationMs: number;
  parseOk: boolean;
  timeoutMs: number;
  firstFrame: boolean;
  fps: number;
  decodedFps: number;
  displayedFps: number;
  lostRate: number;
  cpuMsPerFrame: number;
  rssKb: number;
  firstFrameMs: number;
  playbackRate: number;
}

interface PlaybackOutcome {
  state: string;
  firstFrame: boolean;
  firstFrameMs: number;
}

interface SampleResult extends FormatCompatEntry {
  hardware: PassResult | null;
  software: PassResult | null;
}

function emptyPass(pass: string, state: string, timeoutMs: number = 15000): PassResult {
  return {
    pass: pass,
    state: state,
    videoWidth: 0,
    videoHeight: 0,
    durationMs: -1,
    parseOk: false,
    timeoutMs: timeoutMs,
    firstFrame: false,
    fps: 0,
    decodedFps: 0,
    displayedFps: 0,
    lostRate: 0,
    cpuMsPerFrame: 0,
    rssKb: 0,
    firstFrameMs: -1,
    playbackRate: 0,
  };
}

/**
 * FormatCompatibilityTestPage - debug-only automatic format compatibility runner.
 * It is launched with aa start --ps formatTest true and does not require UI interaction.
 */
@ComponentV2
export struct FormatCompatibilityTestPage {
  @Local status: string = 'initializing';
  @Local current: string = '';
  @Local progress: string = '';
  @Local resultCount: number = 0;
  private manifest: FormatCompatEntry[] = [];
  private results: SampleResult[] = [];
  private baseDir: string = '';
  private resultPath: string = '';
  private started: boolean = false;
  private hardwareLib: LibVLC | null = null;
  private softwareLib: LibVLC | null = null;

  aboutToAppear(): void {
    void this.loadManifest();
  }

  build() {
    NavDestination() {
      Stack() {
        XComponent({
          id: XCOMPONENT_ID,
          type: XComponentType.SURFACE,
          libraryname: NAPI_LIBRARY,
        })
          .width('100%')
          .height('100%')
          .onLoad(() => {
            if (!this.started) {
              this.started = true;
              void this.runAll();
            }
          })

        Column({ space: 8 }) {
          Text('VLC Format Compatibility Test')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
          Text(this.status)
            .fontSize(14)
            .fontColor('#FFCC66')
          Text(this.current)
            .fontSize(14)
            .fontColor('#FFFFFF')
          Text(this.progress)
            .fontSize(14)
            .fontColor('#FFFFFF')
          Text(`results: ${this.resultCount}/${this.manifest.length}`)
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#99000000')
        .position({ x: 0, y: 0 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      NavController.pop();
      return true;
    })
  }

  private async loadManifest(): Promise<void> {
    const ctx = AppContext.get();
    this.baseDir = `${ctx.filesDir}/format_compat`;
    this.resultPath = `${this.baseDir}/results.json`;
    try {
      try {
        fs.mkdirSync(this.baseDir, true);
      } catch (ignored) {
      }
      const text = FORMAT_COMPAT_MANIFEST_JSON;
      this.manifest = JSON.parse(text) as FormatCompatEntry[];
      this.status = `manifest ready: ${this.manifest.length} samples`;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[COMPAT] manifest loaded count=%{public}d', this.manifest.length);
    } catch (e) {
      this.status = `manifest error: ${(e as Error).message ?? String(e)}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, '[COMPAT] manifest error: %{public}s',
        (e as Error).message ?? String(e));
    }
  }

  private async runAll(): Promise<void> {
    for (let i = 0; i < 200 && this.manifest.length === 0; i++) {
      await new Promise<void>((r: () => void) => setTimeout(r, 50));
    }
    if (this.manifest.length === 0) {
      this.status = 'no manifest';
      return;
    }
    if (this.hardwareLib === null || this.hardwareLib.getHandle() === 0) {
      this.hardwareLib = new LibVLC(['--avcodec-hw=any', '--run-time=10']);
    }
    if (this.softwareLib === null || this.softwareLib.getHandle() === 0) {
      this.softwareLib = new LibVLC(['--avcodec-hw=none', '--run-time=10']);
    }
    const start: number = Math.max(0, AppContext.getFormatTestStart());
    const limit: number = AppContext.getFormatTestLimit();
    const end: number = limit > 0 ? Math.min(this.manifest.length, start + limit) : this.manifest.length;
    this.resultPath = `${this.baseDir}/results_${start}_${end}.json`;
    for (let i = start; i < end; i++) {
      const entry = this.manifest[i];
      this.current = `${i + 1}/${this.manifest.length} ${entry.container} ${entry.file}`;
      this.status = 'running';
      this.progress = 'hardware pass';
      const hw = entry.kind === 'video'
        ? await this.runPass(entry, 'hardware', this.buildPassOptions('hardware', entry.kind))
        : null;
      this.progress = 'software pass';
      const sw = entry.kind === 'subtitle'
        ? await this.parseEntry(entry)
        : await this.runPass(entry, 'software', this.buildPassOptions('software', entry.kind));
      const result: SampleResult = {
        dir: entry.dir,
        file: entry.file,
        container: entry.container,
        codec: entry.codec,
        kind: entry.kind,
        url: entry.url,
        hardware: hw,
        software: sw,
      };
      this.results.push(result);
      this.resultCount = this.results.length;
      this.saveResults();
      hilog.info(LOG_DOMAIN, LOG_TAG, '[COMPAT] RESULT %{public}s/%{public}s hw=%{public}s sw=%{public}s',
        entry.dir, entry.file, hw?.state ?? 'skip', sw?.state ?? 'skip');
    }
    this.progress = '';
    this.status = 'COMPLETED';
    hilog.info(LOG_DOMAIN, LOG_TAG, '[COMPAT] all done count=%{public}d', this.results.length);
  }

  private buildPassOptions(pass: string, kind: string): string[] {
    if (pass === 'hardware') {
      return ['--avcodec-hw=any', '--run-time=10'];
    }
    if (kind === 'audio') {
      return ['--avcodec-hw=none', '--run-time=5'];
    }
    return ['--avcodec-hw=none', '--run-time=10'];
  }

  private async runPass(entry: FormatCompatEntry, pass: string, options: string[]): Promise<PassResult> {
    const timeoutMs: number = entry.kind === 'video'
      ? AppContext.getFormatVideoTimeoutMs()
      : AppContext.getFormatAudioTimeoutMs();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[COMPAT] BEGIN pass=%{public}s dir=%{public}s file=%{public}s options=%{public}s',
      pass, entry.dir, entry.file, options.join(' '));
    const localPath = `${this.baseDir}/downloads/${entry.dir}/${entry.file}`;
    let lib: LibVLC | null = null;
    let player: MediaPlayer | null = null;
    let media: Media | null = null;
    try {
      lib = pass === 'hardware' ? this.hardwareLib : this.softwareLib;
      if (lib === null || lib.getHandle() === 0) {
        return emptyPass(pass, 'lib-create-fail', timeoutMs);
      }
      player = new MediaPlayer(lib);
      if (player.getHandle() === 0) {
        return emptyPass(pass, 'player-create-fail', timeoutMs);
      }
      try {
        fs.statSync(localPath);
        media = Media.fromPath(lib, localPath);
      } catch (ignored) {
      }
      if (media === null) {
        media = Media.fromUri(lib, entry.url);
      }
      if (media === null) {
        return emptyPass(pass, 'media-create-fail', timeoutMs);
      }
      media.addOption(pass === 'hardware' ? ':avcodec-hw=any' : ':avcodec-hw=none');
      const attached: boolean = await this.attachVideoOutput(player);
      if (!attached) {
        await this.cleanupPlayer(player);
        player = null;
        media.release();
        media = null;
        return emptyPass(pass, 'surface-bind-fail', timeoutMs);
      }
      if (!player.setMedia(media)) {
        await this.cleanupPlayer(player);
        player = null;
        media.release();
        media = null;
        return emptyPass(pass, 'media-bind-fail', timeoutMs);
      }
      const outcome = await this.waitForPlayback(player, timeoutMs);
      const size = player.getVideoSize();
      const duration = player.getLength();
      const fps = player.getFps();
      let decodedFps: number = 0;
      let displayedFps: number = 0;
      let lostRate: number = 0;
      let cpuMsPerFrame: number = 0;
      let rssKb: number = 0;
      let playbackRate: number = 0;
      if (outcome.state === 'playing') {
        // Let demux/decoder/vout leave their startup burst before measuring.
        await new Promise<void>((r: () => void) => setTimeout(r, 1000));
        const s0 = media.getStats();
        const t0 = player.getTime();
        const u0: ProcessUsage = getProcessUsage();
        const wall0: number = Date.now();
        await new Promise<void>((r: () => void) => setTimeout(r, 3000));
        const wall1: number = Date.now();
        const s1 = media.getStats();
        const t1 = player.getTime();
        const u1: ProcessUsage = getProcessUsage();
        const elapsed: number = wall1 - wall0;
        if (s0 !== null && s1 !== null && elapsed > 0) {
          const dDecoded: number = s1.decodedVideo - s0.decodedVideo;
          const dDisplayed: number = s1.displayedPictures - s0.displayedPictures;
          const dLost: number = s1.lostPictures - s0.lostPictures;
          decodedFps = dDecoded * 1000 / elapsed;
          displayedFps = dDisplayed * 1000 / elapsed;
          lostRate = dDecoded > 0 ? dLost / dDecoded : 0;
          const dCpuTicks: number = u1.cpuTicks - u0.cpuTicks;
          if (dDecoded > 0 && u1.clkTck > 0) {
            cpuMsPerFrame = dCpuTicks * 1000 / u1.clkTck / dDecoded;
          }
          if (t0 >= 0 && t1 >= 0) {
            playbackRate = (t1 - t0) / elapsed;
          }
          rssKb = u1.rssKb;
        }
      }
      await this.cleanupPlayer(player);
      player = null;
      media.release();
      media = null;
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[COMPAT] END pass=%{public}s dir=%{public}s file=%{public}s state=%{public}s video=%{public}dx%{public}d firstFrame=%{public}s fps=%{public}s decodedFps=%{public}s displayedFps=%{public}s lostRate=%{public}s cpuMs=%{public}s rssKb=%{public}s firstMs=%{public}s rate=%{public}s',
        pass, entry.dir, entry.file, outcome.state, String(size?.width ?? 0), String(size?.height ?? 0),
        String(outcome.firstFrame), String(fps), String(decodedFps), String(displayedFps),
        String(lostRate), String(cpuMsPerFrame), String(rssKb), String(outcome.firstFrameMs),
        String(playbackRate));
      return {
        pass: pass,
        state: outcome.state,
        videoWidth: size?.width ?? 0,
        videoHeight: size?.height ?? 0,
        durationMs: duration,
        parseOk: false,
        timeoutMs: timeoutMs,
        firstFrame: outcome.firstFrame,
        fps: fps,
        decodedFps: decodedFps,
        displayedFps: displayedFps,
        lostRate: lostRate,
        cpuMsPerFrame: cpuMsPerFrame,
        rssKb: rssKb,
        firstFrameMs: outcome.firstFrameMs,
        playbackRate: playbackRate,
      };
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[COMPAT] EXCEPTION pass=%{public}s file=%{public}s err=%{public}s',
        pass, entry.file, (e as Error).message ?? String(e));
      try {
        if (player !== null) {
          await this.cleanupPlayer(player);
        }
        media?.release();
        media = null;
      } catch (ignored) {
      }
      return emptyPass(pass, 'exception', timeoutMs);
    }
  }

  private async attachVideoOutput(player: MediaPlayer): Promise<boolean> {
    const deadline: number = Date.now() + 3000;
    while (Date.now() < deadline) {
      if (player.hasNativeWindow(XCOMPONENT_ID) && player.attachViews(XCOMPONENT_ID)) {
        return true;
      }
      await new Promise<void>((r: () => void) => setTimeout(r, 50));
    }
    hilog.error(LOG_DOMAIN, LOG_TAG, '[COMPAT] video surface bind timeout id=%{public}s', XCOMPONENT_ID);
    return false;
  }

  private async cleanupPlayer(player: MediaPlayer): Promise<void> {
    // A pass must stop owning the shared XComponent before the next pass starts.
    // releaseAsync already performs stop+release on a native worker. Calling
    // player.stop() here can block the ArkUI thread while VLC joins decoder/vout
    // threads, and would duplicate the stop performed by releaseAsync.
    try {
      player.detachViews();
    } catch (ignored) {
    }
    player.releaseAsync();
    // Give the detached release worker a scheduling turn before reusing the surface.
    await new Promise<void>((r: () => void) => setTimeout(r, 100));
  }

  private waitForPlayback(player: MediaPlayer, timeoutMs: number = 15000): Promise<PlaybackOutcome> {
    return new Promise<PlaybackOutcome>((resolve) => {
      let settled: boolean = false;
      let postPlayingTimer: number = -1;
      let sawVideo: boolean = false;
      let sawPlaying: boolean = false;
      let sawTime: boolean = false;
      let firstFrameLatencyMs: number = -1;
      const playStartMs: number = Date.now();
      const finish = (state: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (postPlayingTimer !== -1) {
          clearTimeout(postPlayingTimer);
        }
        clearTimeout(timer);
        resolve(
          { state: state, firstFrame: sawVideo && sawTime, firstFrameMs: firstFrameLatencyMs } as PlaybackOutcome);
      };
      const timer = setTimeout(() => finish('timeout'), timeoutMs);
      const finishOnFirstFrame = (): void => {
        if (sawPlaying && sawVideo && sawTime) {
          if (firstFrameLatencyMs === -1) {
            firstFrameLatencyMs = Date.now() - playStartMs;
          }
          finish('playing');
        }
      };
      player.setEventListener((event: string, value: number) => {
        if (event === 'error') {
          finish('error');
        } else if (event === 'vout' && value > 0) {
          sawVideo = true;
          finishOnFirstFrame();
        } else if (event === 'playing') {
          sawPlaying = true;
          postPlayingTimer = setTimeout(() => finish('playing'), 2000);
          finishOnFirstFrame();
        } else if (event === 'timeChanged') {
          sawTime = true;
          finishOnFirstFrame();
        }
      });
      player.play();
    });
  }

  private async parseEntry(entry: FormatCompatEntry): Promise<PassResult> {
    const localPath = `${this.baseDir}/downloads/${entry.dir}/${entry.file}`;
    let lib: LibVLC | null = null;
    try {
      lib = this.softwareLib;
      if (lib === null || lib.getHandle() === 0) {
        return emptyPass('software', 'lib-create-fail', AppContext.getFormatParseTimeoutMs());
      }
      let media: Media | null = null;
      try {
        fs.statSync(localPath);
        media = Media.fromPath(lib, localPath);
      } catch (ignored) {
      }
      if (media === null) {
        media = Media.fromUri(lib, entry.url);
      }
      if (media === null) {
        return emptyPass('software', 'media-create-fail', AppContext.getFormatParseTimeoutMs());
      }
      const parseTimeoutMs: number = AppContext.getFormatParseTimeoutMs();
      const ok = media.parse(parseTimeoutMs);
      media.release();
      return {
        pass: 'software',
        state: ok ? 'parsed' : 'parse-fail',
        videoWidth: 0,
        videoHeight: 0,
        durationMs: -1,
        parseOk: ok,
        timeoutMs: parseTimeoutMs,
        firstFrame: false,
        fps: 0,
        decodedFps: 0,
        displayedFps: 0,
        lostRate: 0,
        cpuMsPerFrame: 0,
        rssKb: 0,
        firstFrameMs: -1,
        playbackRate: 0,
      };
    } catch (e) {
      return emptyPass('software', 'exception', AppContext.getFormatParseTimeoutMs());
    }
  }

  private saveResults(): void {
    try {
      const file = fs.openSync(this.resultPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(this.results, null, 2));
      fs.closeSync(file);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[COMPAT] save results error: %{public}s',
        (e as Error).message ?? String(e));
    }
  }
}
