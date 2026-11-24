// Exercise the production PCM bridge without loading the proprietary DSP.
const cp = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const [clang = 'clang', buildDir = '.tmp/audio-effects-test'] = process.argv.slice(2);
const include = path.join(__dirname, 'audio');
const source = fs.readFileSync(path.join(include, 'ohos_audio_effects.c'), 'utf8').replace(/\r\n/g, '\n');
const state = source.slice(source.indexOf('#define RENDER_MS'), source.indexOf('static OH_AudioNode_Type'))
  .replace(/^    (?:void|OH_AudioSuiteEngine|OH_AudioSuitePipeline|OH_AudioNode) \*.*;\n/gm, '')
  .replace(/#define DECLARE_ENGINE[\s\S]*?#undef DECLARE_BUILDER/, `
    void *pipeline;
    OH_AudioSuite_Result (*engine_RenderFrame)(void *, void *, int32_t, int32_t *, bool *);
    OH_AudioSuite_Result (*engine_MultiRenderFrame)(void *, OH_AudioDataArray *, int32_t *, bool *);
  `);
const bridge = source.slice(source.indexOf('static bool buffer_pcm('), source.indexOf('static bool node_create('));
const render = source.slice(source.indexOf('ohos_effect_result ohos_effects_render('));
const aoutPatch = fs.readFileSync(path.join(__dirname, 'patches', '0032-vlc-ohaudiosuite-effects.patch'), 'utf8');
const additions = aoutPatch.split(/\r?\n/).filter(line => line.startsWith('+')).map(line => line.slice(1)).join('\n');
const driver = additions.slice(additions.indexOf('static void QueueDryEffectTail('),
  additions.indexOf('/* True means the bridge has handled the block'));
const output = path.resolve(buildDir);
fs.mkdirSync(output, {recursive: true});
const c = path.join(output, 'effects.c');
fs.writeFileSync(c, `
#include "ohos_audio_effects.h"
typedef int OH_AudioSuite_Result;
typedef void OH_AudioNode;
typedef struct { void **audioDataArray; int32_t arraySize, requestFrameSize; } OH_AudioDataArray;
#define AUDIOSUITE_SUCCESS 0
void *memcpy(void *d, const void *s, size_t n) {
    for (size_t i = 0; i < n; i++) ((uint8_t*)d)[i] = ((const uint8_t*)s)[i];
    return d;
}
void *memset(void *d, int v, size_t n) {
    for (size_t i = 0; i < n; i++) ((uint8_t*)d)[i] = v;
    return d;
}
${state}
${bridge}
${render}

enum test_mode { NORMAL, ERROR, STARVE, BAD_PULL, BAD_SIZE, EOF_, STALL };
static ohos_audio_effects suite;
static uint8_t data[PCM_CAPACITY + 8], input[OUTPUT_CAPACITY * 2];
static size_t fed, pulled, played;
static int mode, calls, input_corrupted, error_call;

static uint8_t original(size_t offset) {
    return (uint8_t)((offset * 31u + (offset >> 8) * 13u) % 251u);
}

static int append(size_t bytes) {
    for (size_t i = 0; i < bytes; ++i)
        data[i] = original(fed + i);
    if (!buffer_pcm(&suite, data, bytes))
        return 0;
    fed += bytes;
    return 1;
}

static OH_AudioSuite_Result fake_render(void *p, void *out, int32_t len,
                                       int32_t *response, bool *finished) {
    ++calls;
    if (mode == ERROR || calls == error_call) return -4;
    if (mode == STALL) return AUDIOSUITE_SUCCESS;
    if (mode == EOF_) {
        *finished = true;
        return AUDIOSUITE_SUCCESS;
    }
    if (mode == BAD_PULL || mode == STARVE) {
        request_pcm(NULL, p, input, mode == BAD_PULL ? len - 1 : len * 2, finished);
        if (mode == STARVE)
            request_pcm(NULL, p, input, len * 2, finished);
        return AUDIOSUITE_SUCCESS;
    }
    // Prime with two 20 ms pulls despite a single 20 ms output request.
    // Return zero initially, then a short frame; later use already pulled
    // input without requiring a new pull on every render.
    int32_t count = calls == 1 ? 2 : pulled - played < (size_t)len ? 1 : 0;
    for (int i = 0; i < count; ++i) {
        if (request_pcm(NULL, p, input, len, finished) != len || *finished)
            input_corrupted = 1;
        for (int j = 0; j < len; ++j)
            if (input[j] != original(pulled + j))
                input_corrupted = 1;
        pulled += len;
    }
    if (mode == BAD_SIZE) {
        *response = len - 1;
        return AUDIOSUITE_SUCCESS;
    }
    *response = calls == 1 ? 0 : calls == 2 ? len / 2 : len;
    for (int32_t i = 0; i < *response; ++i)
        ((uint8_t *)out)[i] = original(played + i) ^ 0xff;
    return AUDIOSUITE_SUCCESS;
}

static OH_AudioSuite_Result fake_multi_render(void *p, OH_AudioDataArray *array,
                                             int32_t *response, bool *finished) {
    if (array->arraySize != 2 || array->audioDataArray[0] == array->audioDataArray[1])
        return -1;
    OH_AudioSuite_Result rc = fake_render(p, array->audioDataArray[0], array->requestFrameSize, response, finished);
    for (int32_t i = 0; i < *response; ++i)
        ((uint8_t *)array->audioDataArray[1])[i] = original(played + i) ^ 0x55;
    return rc;
}

static void start(unsigned rate, unsigned frame_bytes) {
    memset(&suite, 0, sizeof(suite));
    suite.frame_bytes = frame_bytes;
    suite.bytes_per_second = rate * frame_bytes;
    suite.pipeline = &suite;
    suite.engine_RenderFrame = fake_render;
    suite.engine_MultiRenderFrame = fake_multi_render;
    suite.stem = -1;
    mode = NORMAL;
    calls = input_corrupted = error_call = 0;
    fed = pulled = played = 0;
}

static int drain_dry(void) {
    while (ohos_effects_pending(&suite) != 0) {
        size_t bytes;
        const uint8_t *pcm = ohos_effects_dry(&suite, &bytes);
        if (!bytes) return 0;
        for (size_t i = 0; i < bytes; ++i)
            if (pcm[i] != original(played + i)) return 0;
        ohos_effects_consume(&suite, bytes);
        played += bytes;
    }
    return played == fed;
}

static int continuous(unsigned rate, unsigned frame_bytes, int fail_late) {
    start(rate, frame_bytes);
    for (int i = 0; i < 140; ++i) {
        const unsigned frames[] = {1152, 166, 512, 1024, 347};
        if (!append(frames[i % 5] * frame_bytes)) return 0;
        if (fail_late && i == 15) mode = ERROR;
        for (;;) {
            const uint8_t *output;
            size_t bytes;
            ohos_effect_report report;
            ohos_effect_result result = ohos_effects_render(&suite, &output, &bytes, &report);
            if (input_corrupted || ohos_effects_pending(&suite) != fed - played) return 0;
            if (result == OHOS_EFFECT_ERROR)
                return mode == ERROR && played != 0 && report.status == -4 && drain_dry();
            if (result == OHOS_EFFECT_WAIT) {
                if (bytes != 0 || output != NULL || (i == 0 && calls != 0)) return 0;
                break;
            }
            if (calls == 2 && bytes != rate * frame_bytes / 100u) return 0;
            for (size_t j = 0; j < bytes; ++j)
                if (output[j] != (uint8_t)(original(played + j) ^ 0xff)) return 0;
            ohos_effects_consume(&suite, bytes);
            played += bytes;
        }
    }
    return !fail_late && played > PCM_CAPACITY * 2 && drain_dry();
}

static int rejected(int kind) {
    start(44100, 8);
    mode = kind;
    unsigned duration = kind == STALL ? STALL_MS : LOOKAHEAD_MS;
    if (!append(suite.bytes_per_second * duration / 1000u)) return 0;
    const uint8_t *output;
    size_t bytes;
    ohos_effect_report report;
    if (ohos_effects_render(&suite, &output, &bytes, &report) != OHOS_EFFECT_ERROR ||
        bytes != 0 || output != NULL || !report.reason)
        return 0;
    if (kind == STARVE && report.padded == 0) return 0;
    if (kind == EOF_ && !report.finished) return 0;
    return drain_dry();
}

static int separation(unsigned rate, unsigned frame_bytes) {
    start(rate, frame_bytes);
    if (ohos_effects_select_stem(&suite, VLC_OHOS_EFFECT_ACCOMPANIMENT)) return 0;
    suite.stem = stem_index(VLC_OHOS_EFFECT_ACCOMPANIMENT);
    suite.engine_RenderFrame = NULL; // A separation graph must never call the single-output API.
    const size_t half = suite.bytes_per_second * SEPARATION_LOOKAHEAD_MS / 2000u;
    const uint8_t *output;
    size_t bytes;
    ohos_effect_report report;
    if (!append(half) || ohos_effects_render(&suite, &output, &bytes, &report) != OHOS_EFFECT_WAIT || calls != 0)
        return 0;
    if (!append(half) || ohos_effects_render(&suite, &output, &bytes, &report) != OHOS_EFFECT_WAIT || calls != 1)
        return 0;
    for (int i = 0; i < 3; ++i) {
        const bool vocals = i == 1;
        const int preset = vocals ? VLC_OHOS_EFFECT_VOCALS : VLC_OHOS_EFFECT_ACCOMPANIMENT;
        if (!ohos_effects_select_stem(&suite, preset) || ohos_effects_select_stem(&suite, 1) ||
            !append(suite.bytes_per_second / 50u) ||
            ohos_effects_render(&suite, &output, &bytes, &report) != OHOS_EFFECT_READY ||
            !bytes || calls != i + 2 || input_corrupted)
            return 0;
        for (size_t j = 0; j < bytes; ++j)
            if (output[j] != (uint8_t)(original(played + j) ^ (vocals ? 0xff : 0x55))) return 0;
        ohos_effects_consume(&suite, bytes);
        played += bytes;
    }
    return drain_dry();
}

// Execute the actual output loop with the fake processor and a byte-exact sink.
typedef struct {
    ohos_audio_effects *suite;
    unsigned sample_rate;
    bool suite_rendered;
} aout_sys_t;
typedef struct { aout_sys_t *sys; int status; } audio_output_t;
typedef struct { uint8_t *p_buffer; size_t i_buffer, i_nb_samples; } block_t;
typedef int64_t vlc_tick_t;
#define __MAX(a, b) ((a) > (b) ? (a) : (b))
#define VLC_TICK_FROM_MS(ms) ((vlc_tick_t)(ms) * 1000)
#define msg_Dbg(...) ((void)0)
#define msg_Warn(...) ((void)0)

static uint8_t decoder[PCM_CAPACITY * 2];
static uint8_t queued[PCM_CAPACITY * 6];
static bool closed, queue_overflow;
static vlc_tick_t mdate(void) { static vlc_tick_t now; return ++now; }
static vlc_tick_t vlc_tick_from_samples(uint64_t count, uint32_t rate) {
    return VLC_TICK_FROM_MS(1000) * count / rate;
}
static void var_SetInteger(audio_output_t *aout, const char *key, int value) {
    (void)key;
    aout->status = value;
}
void ohos_effects_close(ohos_audio_effects *s) { closed = s == &suite; }
static void QueuePCM(audio_output_t *aout, const uint8_t *pcm, size_t bytes) {
    (void)aout;
    if (bytes > sizeof(queued) - played) {
        queue_overflow = true;
        return;
    }
    memcpy(queued + played, pcm, bytes);
    played += bytes;
}

${driver}

static int decoder_blocks(unsigned rate, size_t block_bytes, int count, bool fail) {
    start(rate, 8);
    int preset = VLC_OHOS_EFFECT_ACCOMPANIMENT;
    suite.stem = stem_index(preset);
    suite.engine_RenderFrame = NULL;
    error_call = fail ? 3 : 0; // Prime, produce one short frame, then fail.
    closed = queue_overflow = false;
    aout_sys_t sys = { .suite = &suite, .sample_rate = rate };
    audio_output_t aout = { .sys = &sys };
    block_t block = { .p_buffer = decoder, .i_buffer = block_bytes,
                      .i_nb_samples = block_bytes / 8 };
    size_t switch_at = 0;
    for (int i = 0; i < count; ++i) {
        if (!fail && i == 2) {
            switch_at = played;
            preset = VLC_OHOS_EFFECT_VOCALS;
            if (!switch_at || !ohos_effects_select_stem(&suite, preset)) return 0;
            sys.suite_rendered = false;
        }
        for (size_t j = 0; j < block_bytes; ++j)
            decoder[j] = original(fed + j);
        fed += block_bytes;
        ProcessEffectBlock(&aout, &block, preset);
        if (queue_overflow || input_corrupted) return 0;
        if (i == 0 && block_bytes < lookahead_bytes(&suite) &&
            (calls || played || ohos_effects_pending(sys.suite) != block_bytes)) return 0;
        if (closed) {
            if (!fail || sys.suite || aout.status != preset * 4 + 3 || played != fed ||
                calls != error_call || !sys.suite_rendered || suite.pending) return 0;
            const size_t short_frame = rate * 8 / 100;
            for (size_t j = 0; j < played; ++j)
                if (queued[j] != (uint8_t)(original(j) ^ (j < short_frame ? 0x55 : 0))) return 0;
            return 1;
        }
        if (!sys.suite || played + suite.pending != fed) return 0;
    }
    if (fail || !switch_at || played <= switch_at || aout.status != preset * 4 + 2) return 0;
    const size_t wet_end = played;
    QueueDryEffectTail(&aout);
    if (queue_overflow || played != fed) return 0;
    for (size_t j = 0; j < played; ++j) {
        uint8_t mask = j < switch_at ? 0x55 : j < wet_end ? 0xff : 0;
        if (queued[j] != (uint8_t)(original(j) ^ mask)) return 0;
    }
    return 1;
}

int main(void) {
    if (!continuous(44100, 8, 0)) return 1;
    if (!continuous(48000, 4, 0)) return 2;
    if (!continuous(44100, 8, 1)) return 3;
    if (!separation(44100, 8) || !separation(48000, 4)) return 13;
    // Two consecutive blocks from the device log exceeded the 64 KiB ring.
    if (!decoder_blocks(44100, 32944, 4, false)) return 14;
    if (!decoder_blocks(48000, PCM_CAPACITY + 32000, 3, false)) return 15;
    if (!decoder_blocks(44100, 32944, 2, true) ||
        !decoder_blocks(48000, PCM_CAPACITY + 32000, 1, true)) return 16;
    for (int k = STARVE; k <= STALL; ++k)
        if (!rejected(k)) return 4 + k;
    start(44100, 8);
    if (ohos_effects_feed_chunk(&suite, data, 7) || append(PCM_CAPACITY + 8) ||
        !append(PCM_CAPACITY) || append(8) || !drain_dry()) return 12;
    return 0;
}
`);
const flags = ['-std=c11', '-ffreestanding', '-O0', '-fno-builtin', '-I', include];
if (process.platform === 'win32') {
  const obj = path.join(output, 'effects.obj');
  const exe = path.join(output, 'effects.exe');
  cp.execFileSync(clang, ['--target=x86_64-pc-windows-msvc', ...flags, '-fno-stack-protector',
    '-c', c, '-o', obj], {stdio: 'inherit'});
  cp.execFileSync(path.join(path.dirname(clang), 'lld-link.exe'),
    ['/entry:main', '/subsystem:console', '/nodefaultlib', obj, '/out:' + exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
} else {
  const exe = path.join(output, 'effects');
  cp.execFileSync(clang, [...flags, c, '-o', exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
}
console.log('PASS AudioSuite: single and dual output, live stem switching, 44.1/48 kHz, and partial PCM ingestion. Reproduced 32944-byte blocks and oversized blocks; mid-block failure preserves audio order without duplication.');
