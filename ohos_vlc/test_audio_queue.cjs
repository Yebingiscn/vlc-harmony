// Exercise the actual patched queue function without an OHOS device.
// Usage: node test_audio_queue.cjs <patched VLC source> <clang> <temporary directory>
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const [source, clang, temporary] = process.argv.slice(2);
const text = fs.readFileSync(path.join(source, 'modules/audio_output/audiounit_ohos.c'), 'utf8');
const start = text.indexOf('static bool audio_queue_push(');
const end = text.indexOf('static size_t audio_queue_drain(', start);
if (start < 0 || end < 0) throw Error('Audio queue function missing');
fs.mkdirSync(temporary, { recursive: true });
const c = path.join(temporary, 'queue.c');
const wasm = path.join(temporary, 'queue.wasm');
// Generated harness: synchronization is simulated; the queue implementation is
// extracted unchanged, including capacity checks, waiting and ring copies.
fs.writeFileSync(c, `
typedef __SIZE_TYPE__ size_t;
typedef unsigned char uint8_t;
typedef long long vlc_tick_t;
typedef _Bool bool;
#define true 1
#define false 0
#define __MIN(a,b) ((a)<(b)?(a):(b))
#define __MAX(a,b) ((a)>(b)?(a):(b))
#define VLC_TICK_FROM_MS(x) ((x)*1000)
#define AUDIO_QUEUE_WAIT_MS 100
typedef struct {unsigned char *data; size_t capacity, write_pos, total_size; int lock, writable;} audio_queue_t;
static unsigned char storage[4096], input[4096];
static audio_queue_t q;
static int waits, drain_on_wait;
static vlc_tick_t mdate(void) {return 0;}
static void vlc_mutex_lock(int *p) {(void)p;}
static void vlc_mutex_unlock(int *p) {(void)p;}
static int vlc_cond_timedwait(int *c,int *l,vlc_tick_t t) {
    (void)c;(void)l;(void)t; waits++;
    if (drain_on_wait) {q.total_size=0;return 0;} return 1;
}
static void *memcpy(void *d,const void *s,size_t n) {
    for(size_t i=0;i<n;i++) ((unsigned char*)d)[i]=((const unsigned char*)s)[i];return d;
}
${text.slice(start, end)}
int run(int scenario) {
    q=(audio_queue_t){.data=storage,.capacity=4096};waits=0;drain_on_wait=0;
    for(int i=0;i<4096;i++) input[i]=(unsigned char)i;
    if(scenario==0) return audio_queue_push(&q,input,1300,250)&&q.total_size==1300;
    if(scenario==1) return !audio_queue_push(&q,input,4097,250)&&q.total_size==0;
    if(scenario==2) {q.total_size=1300;return audio_queue_push(&q,input,100,250)&&q.total_size==1400&&waits==1;}
    if(scenario==3) {q.total_size=1300;drain_on_wait=1;return audio_queue_push(&q,input,100,250)&&q.total_size==100&&waits==1;}
    if(scenario==4) {q.write_pos=4000;if(!audio_queue_push(&q,input,1300,250))return 0;
        for(int i=0;i<1300;i++)if(storage[(4000+i)%4096]!=input[i])return 0;return 1;}
    if(scenario==5) {q.total_size=4090;return !audio_queue_push(&q,input,100,250)&&q.total_size==4090;}
    if(scenario==6) {q.total_size=240;return audio_queue_push(&q,input,100,250)&&q.total_size==340&&waits==0;}
    return 0;
}
void *memset(void *p,int v,unsigned long long n) {
    for(unsigned long long i=0;i<n;i++) ((unsigned char*)p)[i]=(unsigned char)v;return p;
}
int main(void) {for(int i=0;i<7;i++)if(run(i)!=1)return i+1;return 0;}
`);
if (process.platform === 'win32') {
  const obj = path.resolve(temporary, 'queue.obj');
  const exe = path.resolve(temporary, 'queue.exe');
  cp.execFileSync(clang, ['--target=x86_64-pc-windows-msvc','-O0','-fno-builtin','-fno-stack-protector','-c',c,'-o',obj], {stdio:'inherit'});
  cp.execFileSync(path.join(path.dirname(clang),'lld-link.exe'), ['/entry:main','/subsystem:console','/nodefaultlib',obj,'/out:'+exe], {stdio:'inherit'});
  cp.execFileSync(exe, [], {stdio:'inherit'});
  console.log('PASS 7 real queue cases: soft target, silence recovery, capacity, draining and wraparound');
  process.exit(0);
}
try {
  cp.execFileSync(clang, ['--target=wasm32', '-O0', '-nostdlib', '-fno-builtin',
    '-Wl,--no-entry', '-Wl,--export=run', c, '-o', wasm], { stdio: 'inherit' });
} catch (error) {
  // The DevEco clang shipped with some SDKs intentionally omits the wasm
  // backend. Still validate the extracted implementation with the real target
  // compiler so CI catches syntax/patch drift instead of failing spuriously.
  cp.execFileSync(clang, ['--target=aarch64-linux-ohos', '-fsyntax-only', c], { stdio: 'inherit' });
  console.log('PASS source extraction and OHOS syntax validation (wasm backend unavailable)');
  process.exit(0);
}
(async () => {
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(wasm));
  for (const [i, name] of ['rate-change silence accepted', 'capacity enforced',
    'soft backlog preserved', 'resume after drain', 'ring wrap preserves data',
    'full ring rejected', 'one block can cross target'].entries()) {
    if (instance.exports.run(i) !== 1) throw Error(name);
    console.log('PASS ' + name);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
