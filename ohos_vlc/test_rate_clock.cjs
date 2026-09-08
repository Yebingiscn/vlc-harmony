// Execute the actual VLC rate-change function with a controlled clock.
// Usage (Windows): node test_rate_clock.cjs <VLC source> <SDK clang.exe> <temp dir>
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const [source, clang, temp] = process.argv.slice(2);
const sourceText = fs.readFileSync(path.join(source, 'src/input/clock.c'), 'utf8');
const start = sourceText.indexOf('void input_clock_ChangeRate(');
const end = sourceText.indexOf('\n}', start) + 2;
if (start < 0 || end < start) throw Error('Rate change function not found');
fs.mkdirSync(temp, { recursive: true });
const c = path.resolve(temp, 'clock.c');
const obj = path.resolve(temp, 'clock.obj');
const exe = path.resolve(temp, 'clock.exe');
fs.writeFileSync(c, `
typedef long long vlc_tick_t;
void *memset(void *p, int v, unsigned long long n) {
    for(unsigned long long i=0;i<n;i++) ((unsigned char *)p)[i]=(unsigned char)v;
    return p;
}
typedef struct { vlc_tick_t i_system; } point;
typedef struct { int lock, b_has_reference, b_paused, i_rate;
    point ref, last; vlc_tick_t i_pause_date; } input_clock_t;
static vlc_tick_t now = 20000000;
static vlc_tick_t mdate(void) { return now; }
static void vlc_mutex_lock(int *p) { (void)p; }
static void vlc_mutex_unlock(int *p) { (void)p; }
${sourceText.slice(start, end)}
static vlc_tick_t present(input_clock_t *c, vlc_tick_t stream) {
    /* Includes VLC's rate-scaled one-second timestamp delay. */
    return c->ref.i_system + (stream + 1000000) * c->i_rate / 1000;
}
int main(void) {
    int rates[] = {250, 500, 1000, 1500, 2000};
    for (int paused=0; paused<2; paused++)
    for (int old=0; old<5; old++)
    for (int next=0; next<5; next++) {
        input_clock_t c = {0};
        c.b_has_reference=1; c.b_paused=paused; c.i_pause_date=12000000;
        c.ref.i_system=2000000; c.last.i_system=7000000; c.i_rate=rates[old];
        vlc_tick_t anchor=paused ? c.i_pause_date : now;
        vlc_tick_t stream=(anchor-c.ref.i_system)*1000/c.i_rate-1000000;
        vlc_tick_t before=present(&c,stream);
        input_clock_ChangeRate(&c,rates[next]);
        vlc_tick_t delta=present(&c,stream)-before;
        if(delta < -2 || delta > 2) return 1;
        if(present(&c,stream+1000000)-present(&c,stream)!=rates[next]*1000LL) return 2;
        /* A paused rate change must remain continuous after resume. */
        if(paused) {
            c.ref.i_system += now-c.i_pause_date;
            delta=present(&c,stream)-now;
            if(delta < -2 || delta > 2) return 3;
        }
    }
    input_clock_t empty={0}; empty.i_rate=1000; empty.ref.i_system=123;
    input_clock_ChangeRate(&empty,500);
    return empty.ref.i_system!=123 || empty.i_rate!=500 ? 4 : 0;
}
`);
cp.execFileSync(clang, ['--target=x86_64-pc-windows-msvc', '-O0', '-fno-stack-protector', '-c', c, '-o', obj], {stdio:'inherit'});
cp.execFileSync(path.join(path.dirname(clang),'lld-link.exe'), ['/entry:main','/subsystem:console','/nodefaultlib', obj, '/out:'+exe], {stdio:'inherit'});
cp.execFileSync(exe, [], {stdio:'inherit'});
console.log('PASS 50 running/paused rate transitions, resume continuity, uninitialized clock');
