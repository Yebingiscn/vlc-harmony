// Execute actual FFmpeg policy/PTS functions with deterministic native API stubs.
// node test_codec_policy.cjs <patched ffmpeg tree> <clang> <temporary directory>
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const [tree, clang = 'clang', temporary = '.tmp/codec-policy-test'] = process.argv.slice(2);
const source = fs.readFileSync(path.join(tree, 'libavcodec/ohdec.c'), 'utf8');
function extract(name) {
  const pattern = new RegExp(`^(?:static (?:av_cold )?)?(?:void|int|int64_t|bool) ${name}\\([^;{]*\\)\\s*\\{`, 'm');
  const match = pattern.exec(source);
  assert(match, `actual implementation of ${name} exists`);
  const start = source.indexOf('{', match.index);
  let depth = 1, end = start + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(match.index, end);
}
const names = ['oh_decode_supports_smart_fluency', 'oh_decode_set_format',
  'oh_decode_update_playback_policy', 'oh_decode_queue_pts', 'oh_decode_resolve_output_pts',
  'avcodec_ohcodec_set_playback_speed', 'avcodec_ohcodec_set_video_vrr_allowed'];
assert(source.indexOf('oh_decode_update_playback_policy(avctx);', source.indexOf('static int oh_decode_start')) <
  source.indexOf('static av_cold int oh_decode_init'), 'FULL applied during Start before first input');
assert(source.includes('s->policy_retry_after_us = 0;'), 'seek/speed can supersede delayed retry');
fs.mkdirSync(temporary, {recursive: true});
const c = path.resolve(temporary, 'policy.c');
fs.writeFileSync(c, `
typedef _Bool bool;
typedef long long int64_t;
typedef unsigned long long uint64_t;
int _fltused=0;
void *memset(void *p,int value,__SIZE_TYPE__ n) { for(__SIZE_TYPE__ i=0;i<n;i++)((unsigned char *)p)[i]=value;return p; }
void *memcpy(void *p,const void *q,__SIZE_TYPE__ n) { for(__SIZE_TYPE__ i=0;i<n;i++)((unsigned char *)p)[i]=((const unsigned char *)q)[i];return p; }
#define true 1
#define false 0
#define NULL ((void *)0)
#define AV_NOPTS_VALUE (-9223372036854775807LL-1)
#define AVERROR(x) (-(x))
#define AVERROR_EXTERNAL -100
#define AVERROR_ENOMEM -12
#define ENOMEM 12
#define EINVAL 22
#define ENOSYS 38
#define AV_LOG_INFO 1
#define AV_LOG_WARNING 2
#define AV_LOG_ERROR 3
#define AV_HWDEVICE_TYPE_OHCODEC 1
#define AV_PIXEL_FORMAT_NV12 1
#define AV_PIXEL_FORMAT_SURFACE_FORMAT 2
#define AV_CODEC_ID_H264 1
#define AV_CODEC_ID_HEVC 2
#define AV_CODEC_ID_VVC 3
#define OH_PTS_QUEUE_SIZE 256
#define AV_ERR_OK 0
#define AV_ERR_INVALID_VAL 1
#define OH_MD_KEY_WIDTH "width"
#define OH_MD_KEY_HEIGHT "height"
#define OH_MD_KEY_PIXEL_FORMAT "pixel"
typedef int OH_AVErrCode;
typedef enum { OH_FRAME_RETENTION_MODE_FULL=0, OH_FRAME_RETENTION_MODE_ADAPTIVE=1 } OH_FrameRetentionMode;
typedef struct { int num, den; } Rational;
typedef struct { const char *wrapper_name; } Codec;
typedef struct { void *data; } Buffer;
typedef struct { void *native_window; bool direct_surface; } AVOHCodecDeviceContext;
typedef struct { int type; void *hwctx; } AVHWDeviceContext;
typedef void OHNativeWindow;
typedef struct {
  struct { const char *frame_rate, *enable_vrr, *retention_mode, *decoder_speed; } keys;
  void *dec, *dec_ref;
  bool output_to_window, direct_surface_output, hardware_decoder;
  bool smart_fluency_failed, smart_fluency_active, playback_policy_pending;
  bool vrr_allowed, vrr_active, vrr_failed;
  bool output_pts_unreliable;
  double requested_playback_speed, configured_frame_rate;
  int64_t policy_retry_after_us, last_pts_fallback_log_us;
  int output_mutex;
  unsigned nb_pending_pts;
  int64_t pending_pts[OH_PTS_QUEUE_SIZE];
} OHCodecDecContext;
typedef struct {
  void *priv_data; Codec *codec; int codec_id, width, height;
  Buffer *hw_device_ctx; Rational framerate;
} AVCodecContext;
typedef struct { int mode, vrr, has_mode, has_vrr; double speed, fps; } OH_AVFormat;
static OH_AVFormat pool[8]; static int occupied[8];
static int64_t now=10000000;
static int attempts, failures, fail_full, fail_vrr_off, fail_config, allocations_fail;
static int configured_mode=-1, runtime_mode=-1, runtime_vrr=-1, recreated, unlocked_errors;
static int64_t av_gettime_relative(void) { return now; }
static double fabs(double x) { return x<0?-x:x; }
static int isfinite(double x) { return x==x && x<1e300 && x>-1e300; }
static double av_q2d(Rational q) { return q.den ? (double)q.num/q.den : 0; }
static int strcmp(const char *a,const char *b) { while(*a && *a==*b) {a++;b++;} return *a-*b; }
static const char *avcodec_get_name(int id) { return "codec"; }
static const char *av_hwdevice_get_type_name(int id) { return "ohcodec"; }
static const char *av_err2str(int code) { return "error"; }
static void av_log(void *ctx,int level,const char *message,...) {}
static int ff_oh_err_to_ff_err(int err) { return -err; }
static void ff_mutex_lock(int *m) { if(*m) unlocked_errors++; *m=1; }
static void ff_mutex_unlock(int *m) { if(!*m) unlocked_errors++; *m=0; }
static OH_AVFormat *OH_AVFormat_Create(void) {
  if (allocations_fail) { allocations_fail--; return NULL; }
  for(int i=0;i<8;i++) if(!occupied[i]) { occupied[i]=1; pool[i]=(OH_AVFormat){0}; return &pool[i]; }
  return NULL;
}
static void OH_AVFormat_Destroy(OH_AVFormat *p) { occupied[p-pool]=0; }
static bool OH_AVFormat_SetIntValue(OH_AVFormat *p,const char *key,int value) {
  if(!strcmp(key,"retention")) {p->has_mode=1;p->mode=value;}
  if(!strcmp(key,"vrr")) {p->has_vrr=1;p->vrr=value;}
  return true;
}
static bool OH_AVFormat_SetDoubleValue(OH_AVFormat *p,const char *key,double value) {
  if(!strcmp(key,"speed"))p->speed=value; if(!strcmp(key,"fps"))p->fps=value; return true;
}
static int OH_VideoDecoder_SetParameter(void *dec,OH_AVFormat *p) {
  attempts++;
  if (failures) {failures--;return 1;}
  if (p->has_mode && p->mode==0 && fail_full) {fail_full--;return 1;}
  if (p->has_vrr && !p->vrr && fail_vrr_off) {fail_vrr_off--;return 1;}
  if (p->has_mode)runtime_mode=p->mode;
  if (p->has_vrr)runtime_vrr=p->vrr;
  return 0;
}
static int OH_VideoDecoder_Configure(void *dec,OH_AVFormat *p) {
  configured_mode=p->has_mode?p->mode:-1;
  if(p->has_mode && fail_config) {fail_config--;return 1;} return 0;
}
static int OH_VideoDecoder_SetSurface(void *dec,void *win) {return 0;}
static void av_refstruct_unref(void **ref) { *ref=NULL; }
static int oh_decode_create(OHCodecDecContext *s,AVCodecContext *c) {recreated++;s->dec=(void *)1;return 0;}
${names.map(extract).join('\n')}
static Codec codec={"ohcodec"};
static OHCodecDecContext ctx;
static AVCodecContext avctx;
static void reset(void) {
  ctx=(OHCodecDecContext){0};
  ctx.keys.frame_rate="fps"; ctx.keys.enable_vrr="vrr";
  ctx.keys.retention_mode="retention"; ctx.keys.decoder_speed="speed";
  ctx.hardware_decoder=ctx.direct_surface_output=true; ctx.dec=(void *)1;
  ctx.requested_playback_speed=1;ctx.playback_policy_pending=true;
  avctx=(AVCodecContext){.priv_data=&ctx,.codec=&codec,.codec_id=1,.width=1920,.height=1080,.framerate={60000,1001}};
  attempts=failures=fail_full=fail_vrr_off=fail_config=allocations_fail=recreated=unlocked_errors=0;
  runtime_mode=runtime_vrr=configured_mode=-1;now=10000000;
  for(int i=0;i<8;i++)occupied[i]=0;
}
int run(int test) {
  reset();
  switch(test) {
  case 0: // Configure MV, then FULL at normal speed.
    if(oh_decode_set_format(&ctx,&avctx)!=0 || configured_mode!=1 || !ctx.smart_fluency_active)return 0;
    oh_decode_update_playback_policy(&avctx);return runtime_mode==0 && !ctx.smart_fluency_active;
  case 1: // Legacy OS keys: plain Configure, no runtime call.
    ctx.keys.retention_mode=ctx.keys.decoder_speed=NULL;
    oh_decode_set_format(&ctx,&avctx);oh_decode_update_playback_policy(&avctx);
    return configured_mode==-1 && !attempts;
  case 2: // Unsupported codec.
    avctx.codec_id=4;oh_decode_set_format(&ctx,&avctx);avcodec_ohcodec_set_playback_speed(&avctx,2);
    oh_decode_update_playback_policy(&avctx);return configured_mode==-1 && !attempts;
  case 3: // Software OHCodec must not receive these policies.
    ctx.hardware_decoder=false;ctx.vrr_allowed=true;
    oh_decode_set_format(&ctx,&avctx);avcodec_ohcodec_set_playback_speed(&avctx,2);
    oh_decode_update_playback_policy(&avctx);return configured_mode==-1 && !attempts;
  case 4: // Optional MV Configure rejection retries plain decoder.
    fail_config=1;return oh_decode_set_format(&ctx,&avctx)==0 && recreated==1 && ctx.smart_fluency_failed && configured_mode==-1;
  case 5: // 2x -> 1x restoration.
    oh_decode_set_format(&ctx,&avctx);avcodec_ohcodec_set_playback_speed(&avctx,2);
    oh_decode_update_playback_policy(&avctx);if(runtime_mode!=1)return 0;
    avcodec_ohcodec_set_playback_speed(&avctx,1);oh_decode_update_playback_policy(&avctx);
    return runtime_mode==0 && !ctx.smart_fluency_active;
  case 6: // Failed FULL restores are retried, not permanently disabled.
    ctx.smart_fluency_active=true;fail_full=1;oh_decode_update_playback_policy(&avctx);
    if(!ctx.playback_policy_pending || ctx.smart_fluency_failed)return 0;
    oh_decode_update_playback_policy(&avctx);if(attempts!=1)return 0;
    now+=250000;oh_decode_update_playback_policy(&avctx);return runtime_mode==0 && !ctx.playback_policy_pending;
  case 7: // Idle fullscreen Surface, real fractional source fps.
    avcodec_ohcodec_set_video_vrr_allowed(&avctx,1);oh_decode_update_playback_policy(&avctx);
    return runtime_vrr==1 && fabs(ctx.configured_frame_rate-59.94005994)<0.000001;
  case 8: // Buffer/indirect Surface excluded.
    ctx.direct_surface_output=false;ctx.vrr_allowed=true;oh_decode_update_playback_policy(&avctx);return !attempts;
  case 9: // Low/unknown frame rate excluded; no guessed 60Hz.
    ctx.vrr_allowed=true;avctx.framerate=(Rational){24,1};oh_decode_update_playback_policy(&avctx);
    ctx.playback_policy_pending=true;avctx.framerate=(Rational){0,0};oh_decode_update_playback_policy(&avctx);return !attempts;
  case 10: // VRR off in fast/slow playback, smart fast remains available.
    ctx.vrr_allowed=true;ctx.vrr_active=true;avcodec_ohcodec_set_playback_speed(&avctx,2);
    oh_decode_update_playback_policy(&avctx);if(runtime_vrr!=0 || runtime_mode!=1)return 0;
    avcodec_ohcodec_set_playback_speed(&avctx,0.5);oh_decode_update_playback_policy(&avctx);return runtime_mode==0 && !ctx.vrr_active;
  case 11: // UI interaction disables VRR; rejected OFF gets a retry.
    ctx.vrr_allowed=ctx.vrr_active=true;fail_vrr_off=1;avcodec_ohcodec_set_video_vrr_allowed(&avctx,0);
    oh_decode_update_playback_policy(&avctx);if(!ctx.playback_policy_pending)return 0;
    now+=250000;oh_decode_update_playback_policy(&avctx);return runtime_vrr==0 && !ctx.vrr_active;
  case 12: // Adaptive failure does not break video or repeatedly retry activation.
    failures=1;avcodec_ohcodec_set_playback_speed(&avctx,2);oh_decode_update_playback_policy(&avctx);
    ctx.playback_policy_pending=true;oh_decode_update_playback_policy(&avctx);return ctx.smart_fluency_failed && attempts==1;
  case 13: // Allocation failure gets a bounded retry.
    allocations_fail=1;avcodec_ohcodec_set_playback_speed(&avctx,2);oh_decode_update_playback_policy(&avctx);
    now+=250000;oh_decode_update_playback_policy(&avctx);return runtime_mode==1 && !ctx.smart_fluency_failed;
  case 14: // New user speed supersedes a pending delayed restoration.
    ctx.smart_fluency_active=true;fail_full=1;oh_decode_update_playback_policy(&avctx);
    avcodec_ohcodec_set_playback_speed(&avctx,2);oh_decode_update_playback_policy(&avctx);return runtime_mode==1 && ctx.policy_retry_after_us==0;
  case 15: // Valid unmatched timestamp is authoritative after dropped frames.
    oh_decode_queue_pts(&ctx,&avctx,100);return oh_decode_resolve_output_pts(&ctx,&avctx,200)==200 && !unlocked_errors;
  case 16: // Zero-timestamp vendor quirk still maps in presentation order.
    oh_decode_queue_pts(&ctx,&avctx,300);oh_decode_queue_pts(&ctx,&avctx,100);
    return oh_decode_resolve_output_pts(&ctx,&avctx,0)==100 && ctx.nb_pending_pts==1 && !unlocked_errors;
  case 17: // Long smart-drop runs retire stale PTS, retain reorder window.
    oh_decode_queue_pts(&ctx,&avctx,100);oh_decode_queue_pts(&ctx,&avctx,3500000);oh_decode_queue_pts(&ctx,&avctx,4000000);
    return oh_decode_resolve_output_pts(&ctx,&avctx,4000000)==4000000 && ctx.nb_pending_pts==1;
  case 18: // Full queue retires only oldest, not the whole timestamp map.
    for(int i=0;i<256;i++)oh_decode_queue_pts(&ctx,&avctx,i+1);
    oh_decode_queue_pts(&ctx,&avctx,257);
    return ctx.nb_pending_pts==256 && oh_decode_resolve_output_pts(&ctx,&avctx,256)==256;
  case 19: // No runtime keys for VRR, stay system-managed.
    ctx.keys.enable_vrr=NULL;ctx.vrr_allowed=true;oh_decode_update_playback_policy(&avctx);return !attempts;
  case 20: // Cadence becoming known late requests policy update.
    ctx.vrr_allowed=true;ctx.configured_frame_rate=0;
    avcodec_ohcodec_set_video_vrr_allowed(&avctx,1);oh_decode_update_playback_policy(&avctx);return runtime_vrr==1;
  case 21: // Broken vendor PTS cannot safely coexist with optional frame dropping.
    ctx.requested_playback_speed=2;ctx.smart_fluency_active=true;ctx.vrr_active=true;
    oh_decode_queue_pts(&ctx,&avctx,100);oh_decode_resolve_output_pts(&ctx,&avctx,0);
    oh_decode_update_playback_policy(&avctx);
    return ctx.output_pts_unreliable && runtime_mode==0 && runtime_vrr==0;
  }
  return 0;
}
int main(void) {for(int i=0;i<22;i++)if(!run(i))return i+1;return 0;}
`);
if (process.platform === 'win32') {
  const obj = path.resolve(temporary, 'policy.obj'), exe = path.resolve(temporary, 'policy.exe');
  cp.execFileSync(clang, ['--target=x86_64-pc-windows-msvc', '-O0', '-fno-builtin', '-fno-stack-protector', '-c', c, '-o', obj], {stdio: 'inherit'});
  cp.execFileSync(path.join(path.dirname(clang), 'lld-link.exe'), ['/entry:main', '/subsystem:console', '/nodefaultlib', obj, '/out:' + exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
} else {
  // CI runs the deterministic mock harness on its host; no device SDK or
  // optional WebAssembly linker is needed for this preflight test.
  const exe = path.resolve(temporary, 'policy-test');
  cp.execFileSync(clang, ['-O0', '-fno-builtin', c, '-o', exe], {stdio: 'inherit'});
  cp.execFileSync(exe, [], {stdio: 'inherit'});
}
console.log('PASS 22 native policy cases: MV bootstrap/fallback, speed restoration/retry, Surface VRR gating, hardware/legacy gating, valid/broken PTS and bounded drop cleanup.');
