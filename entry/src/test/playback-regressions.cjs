// Run with: node playback-regressions.cjs <path to TypeScript's typescript.js>
// Platform APIs are stubbed; these checks exercise the actual ArkTS state logic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
let now = 10000;
let nextTimer = 0;
const timers = new Map();
const intervals = new Map();
const settings = new Map();
const Settings = new Proxy({
  incognitoMode: false,
  getBoolean: async (key, fallback) => settings.get(key) ?? fallback,
  getInt: async (key, fallback) => settings.get(key) ?? fallback,
  getString: async (key, fallback) => settings.get(key) ?? fallback,
  put: async (key, value) => settings.set(key, value),
}, { get: (target, key) => target[key] ?? key });
const TouchType = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
function advance(ms) {
  now += ms;
  for (const [id, timer] of [...timers]) {
    if (timer.at <= now) {
      timers.delete(id);
      timer.fn();
    }
  }
}
function load(relative) {
  const source = fs.readFileSync(path.join(__dirname, '../main/ets', relative), 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  vm.runInNewContext(output, {
    exports, TouchType, Date: { now: () => now },
    setTimeout: (fn, delay) => { const id = ++nextTimer; timers.set(id, { fn, at: now + delay }); return id; },
    clearTimeout: id => timers.delete(id),
    setInterval: (fn, delay) => { const id = ++nextTimer; intervals.set(id, { fn, delay }); return id; },
    clearInterval: id => intervals.delete(id),
    require: name => name === './VideoResumeStore' ? load('common/data/VideoResumeStore.ets') :
      ({ Settings, PlayState: { IDLE: 0, PLAYING: 1 }, hilog: { info() {}, warn() {} } }),
  });
  return exports;
}
async function main() {
  const { VideoTouchDelegate } = load('pages/videoplayer/VideoTouchDelegate.ets');
  const calls = [];
  const touch = new VideoTouchDelegate();
  touch.bind({
    getContainerWidth: () => 800, getContainerHeight: () => 600,
    getPosition: () => 60000, getDuration: () => 600000,
    isHudVisible: () => false,
    onFastPlay: (active, rate) => calls.push(['speed', active, rate]),
    onSingleTap: () => calls.push(['tap']), onPanBegan() {},
    onPanEnded: (_mode, cancelled) => { if (!cancelled) calls.push(['seek']); }, onSeekPan() {},
  });
  const event = (type, x = 400, y = 300) => touch.onTouchEvent({ type, changedTouches: [{ x, y }] });
  settings.set('enable_fastplay', false); // Legacy opt-out must no longer disable long press.
  settings.set('FASTPLAY_SPEED', 30);
  await touch.refreshPrefs();
  event(TouchType.Down);
  advance(500);
  event(TouchType.Up);
  advance(500);
  assert.deepEqual(calls, [['speed', true, 3], ['speed', false, 3]], 'release restores speed without a tap');
  calls.length = 0;
  event(TouchType.Down);
  advance(500);
  touch.clearTouchAction();
  assert.deepEqual(calls, [['speed', true, 3], ['speed', false, 3]], 'leaving restores speed');
  calls.length = 0;
  event(TouchType.Down);
  event(TouchType.Move, 450);
  advance(600);
  event(TouchType.Cancel);
  assert.deepEqual(calls, [], 'cancelled swipe neither seeks nor starts fast play');
  event(TouchType.Down);
  event(TouchType.Cancel);
  advance(600);
  assert.deepEqual(calls, [], 'cancelled tap does not toggle controls');

  const { PlaybackService } = load('common/data/PlaybackService.ets');
  const svc = new PlaybackService();
  svc.queueHistoryType = 'video';
  svc.activeVideoUri = 'movie.mkv';
  svc.getCurrent = () => ({ uri: 'movie.mkv' });
  svc.duration = 600000;
  const updates = [];
  svc.emitTime = () => updates.push(svc.position);
  svc.onTimeChangedThrottled(10000);
  advance(100);
  svc.onTimeChangedThrottled(12000);
  assert.equal(svc.position, 12000, 'actual position is never dropped by UI throttling');
  advance(200);
  assert.deepEqual(updates, [10000, 12000], 'last event in a burst reaches the UI');
  await svc.resumeSaveChain;
  const { VideoResumeStore } = load('common/data/VideoResumeStore.ets');
  assert.equal(await VideoResumeStore.load('movie.mkv'), 10000, 'progress saved without leaving the page');
  await VideoResumeStore.save('second.mkv', 30000, 600000);
  assert.equal(await VideoResumeStore.load('movie.mkv'), 10000, 'opening another video preserves the first position');
  assert.equal(await VideoResumeStore.load('second.mkv'), 30000);
  await VideoResumeStore.save('second.mkv', 0, 0);
  assert.equal(await VideoResumeStore.load('second.mkv'), 30000, 'failed startup does not erase progress');
  await VideoResumeStore.save('second.mkv', 570000, 600000);
  assert.equal(await VideoResumeStore.load('second.mkv'), 0, '95 percent restarts from the beginning');
  await VideoResumeStore.save('short.mkv', 1000, 10000);
  assert.equal(await VideoResumeStore.load('short.mkv'), 1000, 'short valid progress is preserved');
  svc.saveVideoResume(true);
  await svc.resumeSaveChain;
  assert.equal(await VideoResumeStore.load('movie.mkv'), 0, 'completion clears the resume offset');
  const previous = settings.get('video_resume:movie.mkv');
  Settings.incognitoMode = true;
  svc.activeVideoUri = 'movie.mkv';
  svc.position = 20000;
  svc.saveVideoResume();
  await svc.resumeSaveChain;
  assert.equal(settings.get('video_resume:movie.mkv'), previous, 'incognito playback is not persisted');
  const subtitleSelections = [];
  let subtitleTracks = [];
  svc.emitTracksChanged = () => {};
  svc.player = {
    getSpuTrack: () => -1,
    getSpuTracks: () => subtitleTracks,
    setSpuTrack: id => { subtitleSelections.push(id); return true; },
  };
  svc.ensureSubtitleSelected();
  assert.equal(subtitleSelections.length, 0, 'no subtitle before track discovery');
  subtitleTracks = [{ id: -1 }, { id: 2 }];
  advance(1000);
  svc.ensureSubtitleSelected();
  assert.deepEqual(subtitleSelections, [2], 'select discovered subtitle, not disable entry');
  advance(1000);
  svc.ensureSubtitleSelected();
  assert.deepEqual(subtitleSelections, [2], 'automatic selection happens once');
  svc.setSpuTrack(-1);
  advance(1000);
  svc.ensureSubtitleSelected();
  assert.deepEqual(subtitleSelections, [2, -1], 'explicit subtitle disable remains respected');
  svc.subtitleChoiceMade = false;
  svc.player.getSpuTrack = () => 4;
  advance(1000);
  svc.ensureSubtitleSelected();
  assert.deepEqual(subtitleSelections, [2, -1], 'keep native default subtitle selection');
  svc.state = 1;
  svc.player.getTime = () => 34567;
  svc.player.getLength = () => 900000;
  svc.startSessionSync();
  assert.equal(intervals.size, 2, 'progress watchdog and session sync started');
  const watchdog = intervals.get(svc.progressWatchdog).fn;
  advance(1000);
  watchdog();
  assert.equal(svc.position, 34567, 'missing time event recovers actual native position');
  assert.equal(svc.duration, 900000, 'watchdog updates native duration');
  svc.player.getTime = () => -1;
  advance(1000);
  watchdog();
  assert.equal(svc.position, 34567, 'invalid native time does not invent progress');
  svc.state = 0;
  svc.player.getTime = () => 45678;
  advance(1000);
  watchdog();
  assert.equal(svc.position, 34567, 'stopped player is not polled');
  svc.stopSessionSync();
  assert.equal(intervals.size, 0, 'both timers released');
  console.log('Playback regression checks passed (gestures, progress coalescing, resume, incognito, subtitle selection, progress watchdog).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
