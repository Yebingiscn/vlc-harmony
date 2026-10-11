const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
let now = 0, sequence = 0;
const timers = new Map();
const exportsObject = {};
const source = fs.readFileSync(path.join(__dirname, '../main/ets/common/data/VideoRefreshPolicy.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS}}).outputText, {
  exports: exportsObject, Date: {now: () => now},
  setTimeout: (fn, delay) => {const id = ++sequence; timers.set(id, {fn, at: now + delay}); return id;},
  clearTimeout: id => timers.delete(id),
});
function advance(ms) {
  now += ms;
  for (const [id, t] of [...timers]) if(t.at <= now) {timers.delete(id); t.fn();}
}
const calls = [];
const policy = new exportsObject.VideoRefreshPolicy(value => calls.push(value));
policy.update(true); advance(799); assert.deepEqual(calls, []);
policy.update(true); advance(1); assert.deepEqual(calls, [true], 'repeat updates do not postpone activation');
policy.update(false); assert.deepEqual(calls, [true, false], 'HUD/interaction disable immediately');
policy.update(true); advance(400); policy.update(false); advance(1000);
assert.deepEqual(calls, [true, false], 'hidden scene cancels stale activation');
policy.update(true); policy.blockFor(1200); advance(1000);
assert.equal(calls.at(-1), false); advance(200); assert.equal(calls.at(-1), true);
policy.blockFor(1200); advance(600); policy.blockFor(1200); advance(600);
assert.equal(calls.at(-1), false, 'repeated resize extends settling time');
advance(600); assert.equal(calls.at(-1), true);
policy.dispose(); advance(5000); assert.equal(calls.at(-1), false, 'exit cancels activation');
const page = fs.readFileSync(path.join(__dirname, '../main/ets/pages/VideoPlayerPage.ets'), 'utf8');
for (const gate of ['refreshFullScreen', 'refreshForeground', 'refreshPageVisible', 'refreshFastPlay',
  'refreshPipActive', 'vm.hudVisible', 'sheetOpen', 'seeking', 'refreshTouchActive'])
  assert(page.slice(page.indexOf('private updateVideoRefreshScene()'), page.indexOf('/** 打开高级选项菜单')).includes(gate));
assert(page.includes("off('windowStatusChange', this.refreshWindowStatus)"), 'window observer cleaned up');
console.log('PASS video refresh scene debounce, immediate disable, resize settling, disposal and page gating.');
