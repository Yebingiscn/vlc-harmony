// Exercise the production PCM bridge without running the proprietary DSP.
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const [clang = 'clang', output = '.tmp/audio-effects-test'] = process.argv.slice(2);
const source = fs.readFileSync(path.join(__dirname, 'audio/ohos_audio_effects.c'), 'utf8');
const request = source.slice(source.indexOf('static int32_t request_pcm('), source.indexOf('static bool node_create('));
const render = source.slice(source.indexOf('const uint8_t *ohos_effects_render('));
assert(request.includes('return bytes;') && render.includes('s->engine_RenderFrame'));
fs.mkdirSync(output, {recursive: true});
const c = path.resolve(output, 'effects.c');
fs.writeFileSync(c, `
typedef __SIZE_TYPE__ size_t;
typedef _Bool bool;
typedef unsigned char uint8_t;
typedef int int32_t;
typedef int OH_AudioSuite_Result;
typedef void OH_AudioNode;
#define NULL ((void *)0)
#define false 0
#define true 1
#define AUDIOSUITE_SUCCESS 0
void *memcpy(void *d, const void *s, size_t n) {
    for (size_t i=0;i<n;i++) ((uint8_t*)d)[i]=((const uint8_t*)s)[i];
    return d;
}
void *memset(void *d, int v, size_t n) {
    for (size_t i=0;i<n;i++) ((uint8_t*)d)[i]=v;
    return d;
}
typedef struct {
    unsigned frame_bytes;
    const uint8_t *input_data;
    size_t input_left;
    bool padded;
    uint8_t scratch[32];
    void *pipeline;
    OH_AudioSuite_Result (*engine_RenderFrame)(void *,void *,int32_t,int32_t *,bool *);
} ohos_audio_effects;
${request}
${render}
static int scenario, calls;
static OH_AudioSuite_Result fake_render(void *p, void *out, int32_t len, int32_t *response, bool *finished) {
    uint8_t input[32];
    ++calls;
    if (scenario == 1) return -1;
    if (scenario == 2) request_pcm(NULL,p,input,len+4,finished);
    else if (scenario == 3) request_pcm(NULL,p,input,len-4,finished);
    else if (scenario == 4) request_pcm(NULL,p,input,len-1,finished);
    else {
        request_pcm(NULL,p,input,len/2,finished);
        request_pcm(NULL,p,input+len/2,len/2,finished);
    }
    *response = scenario == 5 ? len-4 : len;
    *finished = scenario == 6;
    for (int i=0;i<len;i++) ((uint8_t *)out)[i]=42;
    return AUDIOSUITE_SUCCESS;
}
int run(int mode) {
    ohos_audio_effects s;
    memset(&s,0,sizeof(s));
    s.frame_bytes=4;
    s.pipeline=&s;
    s.engine_RenderFrame=fake_render;
    uint8_t input[32];
    memset(input,7,sizeof(input));
    calls=0;
    scenario=mode;
    size_t bytes=mode==7 ? 7 : mode==8 ? 36 : mode==9 ? 0 : 16;
    const uint8_t *result=ohos_effects_render(&s,input,bytes);
    for (int i=0;i<32;i++) if (input[i]!=7) return 0;
    if (mode >= 7) return result==NULL && calls==0;
    if (s.input_data!=NULL || calls!=1) return 0;
    if (mode!=0) return result==NULL;
    if (result!=s.scratch) return 0;
    for (int i=0;i<16;i++) if (result[i]!=42) return 0;
    return 1;
}
int main(void) {
    for (int i=0;i<10;i++) if(!run(i)) return i+1;
    return 0;
}
`);
if (process.platform === 'win32') {
  const obj = path.resolve(output, 'effects.obj');
  const exe = path.resolve(output, 'effects.exe');
  cp.execFileSync(clang, ['--target=x86_64-pc-windows-msvc', '-O0', '-fno-builtin', '-fno-stack-protector',
    '-c', c, '-o', obj], {stdio: 'inherit'});
  cp.execFileSync(path.join(path.dirname(clang), 'lld-link.exe'),
    ['/entry:main', '/subsystem:console', '/nodefaultlib', obj, '/out:'+exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
} else {
  const exe = path.resolve(output, 'effects');
  cp.execFileSync(clang, ['-O0', '-fno-builtin', c, '-o', exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
}
console.log('PASS AudioSuite PCM bridge: exact block, render error, overread, underread, misalignment, short output, EOF, and bounded buffer.');
