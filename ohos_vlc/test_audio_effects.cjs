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
  `);
const bridge = source.slice(source.indexOf('bool ohos_effects_feed('), source.indexOf('static bool node_create('));
const render = source.slice(source.indexOf('ohos_effect_result ohos_effects_render('));
const output = path.resolve(buildDir);
fs.mkdirSync(output, {recursive: true});
const c = path.join(output, 'effects.c');
fs.writeFileSync(c, `
#include "ohos_audio_effects.h"
typedef int OH_AudioSuite_Result;
typedef void OH_AudioNode;
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
static int mode, calls, input_corrupted;

static uint8_t original(size_t offset) {
    return (uint8_t)((offset * 31u + (offset >> 8) * 13u) % 251u);
}

static int append(size_t bytes) {
    for (size_t i = 0; i < bytes; ++i)
        data[i] = original(fed + i);
    if (!ohos_effects_feed(&suite, data, bytes))
        return 0;
    fed += bytes;
    return 1;
}

static OH_AudioSuite_Result fake_render(void *p, void *out, int32_t len,
                                       int32_t *response, bool *finished) {
    ++calls;
    if (mode == ERROR) return -4;
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

static void start(unsigned rate, unsigned frame_bytes) {
    memset(&suite, 0, sizeof(suite));
    suite.frame_bytes = frame_bytes;
    suite.bytes_per_second = rate * frame_bytes;
    suite.pipeline = &suite;
    suite.engine_RenderFrame = fake_render;
    mode = NORMAL;
    calls = input_corrupted = 0;
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

int main(void) {
    if (!continuous(44100, 8, 0)) return 1;
    if (!continuous(48000, 4, 0)) return 2;
    if (!continuous(44100, 8, 1)) return 3;
    for (int k = STARVE; k <= STALL; ++k)
        if (!rejected(k)) return 4 + k;
    start(44100, 8);
    if (ohos_effects_feed(&suite, data, 7) || append(PCM_CAPACITY + 8) ||
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
console.log('PASS AudioSuite: 44.1/48 kHz, variable PCM chunks, prefetch, priming, short output, wraparound, ordered dry fallback, malformed input and bounded stalls.');
