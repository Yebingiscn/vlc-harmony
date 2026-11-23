// Exercise the production browser model with successive import snapshots.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../main/ets/pages/AudioBrowserPage.ets'), 'utf8');
const logic = source.slice(0, source.indexOf('// ---- 页面 ----'))
  .replace(/@ObservedV2\s+|@Trace\s+/g, '')
  .replace('class AudioBrowserVM', 'export class AudioBrowserVM');
const output = {};
let media = [];
vm.runInNewContext(ts.transpileModule(logic, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2018 }
}).outputText, {
  exports: output,
  require: name => {
    if (name.endsWith('/MediaLibrary')) return { MediaLibrary: { getAudios: () => media } };
    if (name.endsWith('/MediaModels')) return { EmptyLoadingState: { LOADING: 1, EMPTY_SEARCH: 2, NONE: 3 } };
    if (name === '@ohos/pinyin4js') return { pinyin4js: { getShortPinyin: value => value } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info: () => {} } };
    return {};
  },
});
const { AudioBrowserVM } = output;
const track = (number, title = `Track ${number}`) => ({
  id: number, uri: `file://media/${number}`, title, artistName: 'Artist', albumName: 'Album',
  genre: 'Pop', artworkPath: `cover-${number}`
});
const browser = new AudioBrowserVM();
const two = track(2);
const ten = track(10);
media = [ten, two];
browser.syncData();
assert.deepEqual(Array.from(browser.tracks, item => item.id), [2, 10]);

// Newly imported entries can land before and between existing visible cards.
media = [ten, two, track(1), track(3), track(11)];
browser.syncData(true);
assert.deepEqual(Array.from(browser.tracks, item => item.id), [1, 2, 3, 10, 11]);
assert.equal(browser.tracks[1], two);
assert.equal(browser.tracks[3], ten);
media = media.map(item => item.id === 2 ? { ...item, title: 'Track 12', artworkPath: 'new-cover' } : item);
browser.syncData();
assert.deepEqual(Array.from(browser.tracks, item => item.id), [1, 3, 10, 11, 2]);
assert.equal(browser.tracks[4].uri, two.uri);
assert.equal(browser.tracks[4].artworkPath, 'new-cover');

const grid = source.slice(source.indexOf('  trackGrid()'), source.indexOf('  trackCard('));
assert.match(grid, /this\.trackCard\(trackRepeatItem\)/, 'pass the whole live RepeatItem');
assert.match(grid, /\.key\(\(track: Track\) => track\.uri\)\.virtualScroll\(\)/);
assert.match(grid, /\.lanes\(2, 8\)/);
assert.doesNotMatch(grid, /renderVersion/);
console.log('PASS audio import: sorted insertions, stable track identity, metadata updates, and lazy two-column binding.');
