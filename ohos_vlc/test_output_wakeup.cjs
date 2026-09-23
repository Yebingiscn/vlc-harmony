// Exercise the actual input-wait block with deterministic callback scheduling.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const [sourceDir, clang, temporary] = process.argv.slice(2);
const source = fs.readFileSync(path.join(sourceDir, 'libavcodec/ohdec.c'), 'utf8');
const begin = source.indexOf('// Output must preempt an input wait');
const end = source.indexOf('if (buffer.generation', begin);
assert(begin >= 0 && end > begin);
const callback = source.slice(source.indexOf('static void oh_decode_on_output('), source.indexOf('static void oh_decode_on_output(') + 6500);
assert(callback.indexOf('ff_mutex_unlock(&s->output_mutex);') < callback.indexOf('ff_mutex_lock(&s->input_mutex);'));
assert(callback.includes('ff_cond_signal(&s->input_cond);'));
fs.mkdirSync(temporary, {recursive:true});
const c = path.resolve(temporary, 'wakeup.c');
fs.writeFileSync(c, `
typedef _Bool bool;
void *memset(void *p,int value,__SIZE_TYPE__ n) { for(__SIZE_TYPE__ i=0;i<n;i++) ((unsigned char*)p)[i]=value; return p; }
#define false 0
#define EAGAIN 11
#define ETIMEDOUT 110
#define AVERROR(x) (-(x))
typedef struct { int buffer; } Item;
typedef struct { int decode_status, input_mutex, output_mutex, input_cond; int *input_queue, *output_queue; } Context;
static int scenario, waits, badlock;
static Context *active;
void ff_mutex_lock(int *m) { if (*m) badlock=1; *m=1; }
void ff_mutex_unlock(int *m) { if (!*m) badlock=1; *m=0; }
int av_fifo_can_read(int *q) { return *q; }
int av_fifo_read(int *q, Item *item, int n) { if (!*q) return -1; --*q; item->buffer=1; return 0; }
int oh_decode_cond_wait(int *cond, int *mutex) {
    ++waits;
    if (!*mutex) badlock=1;
    if (scenario==2) *active->output_queue=1;
    else if (scenario==3) *active->input_queue=1;
    else if (scenario==5) active->decode_status=-55;
    else return ETIMEDOUT;
    return 0;
}
int receive(Context *s) {
    int iteration=0;
    for (;;) {
        if (iteration++) return 2; /* next iteration drains output */
        Item buffer={0}; int ret;
        ${source.slice(begin, end)}
        return 1; /* input acquired */
    }
}
int run(int which) {
    int input=which==0, output=which==1;
    Context ctx={0,0,0,0,&input,&output};
    scenario=which; waits=badlock=0; active=&ctx;
    int result=receive(&ctx);
    int expected=which==0||which==3?1:which==4?-11:which==5?-55:2;
    return result==expected && !badlock && !ctx.input_mutex && !ctx.output_mutex && waits==(which>=2);
}
int main(void) {for(int i=0;i<6;i++)if(!run(i))return i+1;return 0;}
`);
if (process.platform === 'win32') {
  const obj=path.resolve(temporary,'wakeup.obj'), exe=path.resolve(temporary,'wakeup.exe');
  cp.execFileSync(clang,['--target=x86_64-pc-windows-msvc','-O0','-fno-builtin','-fno-stack-protector','-c',c,'-o',obj],{stdio:'inherit'});
  cp.execFileSync(path.join(path.dirname(clang),'lld-link.exe'),['/entry:main','/subsystem:console','/nodefaultlib',obj,'/out:'+exe],{stdio:'inherit'});
  cp.execFileSync(exe,[],{stdio:'inherit'});
} else {
  const wasm=path.resolve(temporary,'wakeup.wasm');
  cp.execFileSync(clang,['--target=wasm32','-O0','-nostdlib','-fno-builtin','-Wl,--no-entry','-Wl,--export=run',c,'-o',wasm],{stdio:'inherit'});
  const instance=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(wasm)));
  for(let i=0;i<6;i++) assert.equal(instance.exports.run(i),1,`scenario ${i}`);
}
console.log('PASS 6 output-wakeup cases: input, ready output, output wake, input wake, timeout, error; balanced locks.');
