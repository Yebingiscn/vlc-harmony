const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');

const source = fs.readFileSync(path.join(__dirname, '../main/ets/pages/AudioEffectsDialog.ets'), 'utf8');
const logic = source.slice(0, source.indexOf('  @Builder'))
  .replace(/@ComponentV2\s+|@(?:Param|Event|Local)\s+/g, '')
  .replace('export struct AudioEffectsDialog', 'export class AudioEffectsDialog') + '\n}';
const output = {};
const modes = {};
vm.runInNewContext(ts.transpileModule(
  fs.readFileSync(path.join(__dirname, '../main/ets/common/constants/AudioEffectModes.ets'), 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }
).outputText, { exports: modes });
const { AUDIO_EFFECT_ACCOMPANIMENT, AUDIO_EFFECT_SEPARATION_BIT, AUDIO_EFFECT_VOCALS } = modes;
let mask = 31;
let stored = 0;
let accepted = true;
const applied = [];
const toasts = [];
const playback = {
  getAudioEffectPreset: () => stored,
  getAudioEffectSupport: () => mask,
  getAudioEffectStatus: () => 0,
  setAudioEffectPreset: id => {
    applied.push(id);
    return accepted;
  },
};
vm.runInNewContext(ts.transpileModule(logic, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, {
  exports: output,
  require: name => name.endsWith('/AudioEffectModes') ? modes : name.endsWith('/PlaybackService')
    ? { PlaybackService: { getInstance: () => playback } }
    : { UiFeedback: { showToast: value => toasts.push(value) } },
  $r: name => ({ id: -1, name }), // Resource identifiers need not be unique keys.
  Scroller: class {
    resets = 0;
    scrollTo(options) {
      assert.equal(options.yOffset, 0);
      assert.equal(options.animation, false);
      this.resets++;
    }
  },
  setInterval: () => 1,
  clearInterval: () => {},
});

const { AudioEffectsDialog } = output;
const visibleIds = dialog => Array.from(dialog.visiblePresets, item => item.id);
const dialog = new AudioEffectsDialog();
dialog.aboutToAppear();
assert.deepEqual(visibleIds(dialog), [1, 2, 3, 4]);
assert.equal(dialog.presetScroller.resets, 0, 'initial load does not call an unmounted scroller');
dialog.switchFamily(4);
const voiceFirst = dialog.visiblePresets[0];
assert.deepEqual(visibleIds(dialog), [16, 17, 18, 19, 20, 21, 22, 23, 24, 25]);
dialog.switchFamily(1);
assert.deepEqual(visibleIds(dialog), [5, 6, 7], 'long-to-short category replaces the entire list');
assert.equal(dialog.presetScroller.resets, 2);
assert.equal(voiceFirst.id, 16, 'a row from the previous category retains its own identity');
assert.deepEqual(applied, [], 'browsing tabs does not change playback');
assert.deepEqual(Array.from(dialog.visiblePresets, item => item.label.name), [
  'app.string.audio_fx_position', 'app.string.audio_fx_rotation', 'app.string.audio_fx_extension'
]);
dialog.selectPreset(dialog.visiblePresets[1].id);
assert.deepEqual(applied, [6], 'Rotation maps to its native preset');
dialog.switchFamily(0);
dialog.switchFamily(1);
assert.equal(dialog.selected, 6, 'returning to a category preserves the active effect');
accepted = false;
dialog.selectPreset(7);
assert.equal(dialog.selected, 6, 'a failed application must not highlight the wrong row');
assert.equal(toasts.length, 1);
dialog.aboutToDisappear();

stored = 6;
mask = 1 << 1;
const limited = new AudioEffectsDialog();
limited.aboutToAppear();
assert.equal(limited.family, 1, 'open at the active supported category');
limited.switchFamily(4);
assert.deepEqual(visibleIds(limited), [5, 6, 7], 'unsupported tabs never replace supported rows');
mask = 0;
const unavailable = new AudioEffectsDialog();
unavailable.aboutToAppear();
assert.equal(unavailable.family, -1);
assert.deepEqual(visibleIds(unavailable), []);
assert.equal(unavailable.equalizerOpened, true, 'Equalizer remains available without optional native effects');
unavailable.selectPreset(AUDIO_EFFECT_VOCALS);
assert.equal(unavailable.selected, 6, 'unsupported separation never changes playback');

stored = AUDIO_EFFECT_ACCOMPANIMENT;
mask = 31 | AUDIO_EFFECT_SEPARATION_BIT;
accepted = true;
const karaoke = new AudioEffectsDialog();
karaoke.aboutToAppear();
assert.equal(karaoke.section, 2, 'open AI Karaoke if a stem is active');
assert.equal(karaoke.supportsSeparation(), true);
const beforeTabChange = applied.length;
karaoke.switchSection(1);
karaoke.switchSection(2);
assert.equal(karaoke.equalizerOpened, true);
assert.equal(applied.length, beforeTabChange, 'switching sections does not apply or clear a preset');
karaoke.selectPreset(AUDIO_EFFECT_VOCALS);
karaoke.selectPreset(4);
karaoke.selectPreset(0);
assert.deepEqual(applied.slice(beforeTabChange), [AUDIO_EFFECT_VOCALS, 4, 0],
  'stem, ordinary preset and original audio share one mutually exclusive selection');
assert(source.includes('.key((preset: EffectPreset) => preset.id.toString())'));
assert(source.includes('this.selectPreset(item.item.id)'));
console.log('PASS audio effects dialog: stable presets, section switching, EQ availability, and mutually exclusive AI Karaoke.');

async function checkEqualizer() {
  const eqSource = fs.readFileSync(path.join(__dirname, '../main/ets/pages/EqualizerDialog.ets'), 'utf8');
  const eqLogic = (eqSource.slice(0, eqSource.indexOf('  build()')) +
    eqSource.slice(eqSource.indexOf('  private pushToPlayer(')))
    .replace(/@ComponentV2\s+|@Local\s+/g, '')
    .replace('export struct EqualizerDialog', 'export class EqualizerDialog');
  const eqExports = {};
  const saved = new Map([['id', 1], ['enabled', true]]);
  const eqApplied = [];
  const kv = async (key, def) => saved.get(key) ?? def;
  vm.runInNewContext(ts.transpileModule(eqLogic, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2018 }
  }).outputText, {
    exports: eqExports,
    require: name => {
      if (name.endsWith('/MediaModels')) {
        return { EqualizerPreset: class {
          constructor(id, name, bands) { Object.assign(this, { id, name, bands }); }
        }};
      }
      if (name.endsWith('/Settings')) {
        return { Settings: {
          KEY_CURRENT_EQUALIZER_ID: 'id', KEY_EQUALIZER_ENABLED: 'enabled', KEY_EQUALIZER_PANEL: 'panel',
          getInt: kv, getBoolean: kv, getString: kv, put: async (key, value) => saved.set(key, value),
        }};
      }
      if (name.endsWith('/PlaybackService')) {
        return { PlaybackService: { getInstance: () => ({
          applyEqualizer: (...args) => eqApplied.push(args)
        }) }};
      }
      if (name.endsWith('/libvlc')) {
        return { Equalizer: {
          getPresetCount: () => 2, getBandCount: () => 10, getPresetName: id => `Preset ${id}`,
          fromPreset: id => ({ getAmp: () => id * 3, getPreAmp: () => id * 2, release: () => {} }),
        }};
      }
      return {};
    },
  });
  const equalizer = new eqExports.EqualizerDialog();
  await equalizer.aboutToAppear();
  assert.equal(equalizer.presetIndex, 1);
  assert.equal(equalizer.preamp, 2, 'use the real native preset preamp');
  assert.deepEqual(Array.from(equalizer.bands), Array(8).fill(3), 'use the real native gain curve');
  equalizer.setBand(0, 7);
  equalizer.pushToPlayer();
  equalizer.aboutToDisappear();
  const reopened = new eqExports.EqualizerDialog();
  await reopened.aboutToAppear();
  assert.equal(reopened.bands[0], 7, 'reopening the shared panel does not reset the gain');
  assert.deepEqual(eqApplied.at(-1).slice(0, 3), [true, 1, 2]);
  assert.equal(eqApplied.at(-1)[3][0], 7);
  console.log('PASS embedded equalizer: native preset values and edited gains persist across panel visits.');
}

checkEqualizer().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
