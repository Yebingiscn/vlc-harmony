// vlc_napi.cpp —— libVLC C API → ArkTS NAPI 桥(单实例播放器)。
// 链接预编译 libvlc.so / libvlccore.so(ohos arm64-v8a)。事件经 threadsafe function 回调 JS。
#include "napi/native_api.h"
#include <vlc/vlc.h>

#include <dlfcn.h>
#include <mutex>
#include <string>
#include <vector>
#include <cstring>

namespace {
libvlc_instance_t* g_vlc = nullptr;
libvlc_media_player_t* g_mp = nullptr;
libvlc_media_t* g_media = nullptr;
std::mutex g_mtx;
napi_threadsafe_function g_tsfn = nullptr;
napi_ref g_js_callback_ref = nullptr;

// VLC 事件回调(运行在 VLC 线程)→ 投递到 threadsafe function,由 JS 线程接收。
void on_vlc_event(const struct libvlc_event_t* event, void* /*user*/) {
  if (g_tsfn == nullptr) {
    return;
  }
  const char* name = nullptr;
  double dval = 0.0;
  switch (event->type) {
    case libvlc_MediaPlayerPlaying: name = "playing"; break;
    case libvlc_MediaPlayerPaused: name = "paused"; break;
    case libvlc_MediaPlayerStopped: name = "stopped"; break;
    case libvlc_MediaPlayerEndReached: name = "ended"; break;
    case libvlc_MediaPlayerEncounteredError: name = "error"; break;
    case libvlc_MediaPlayerLengthChanged:
      name = "lengthChanged";
      dval = (double) event->u.media_player_length_changed.new_length;
      break;
    case libvlc_MediaPlayerTimeChanged:
      name = "timeChanged";
      dval = (double) event->u.media_player_time_changed.new_time;
      break;
    case libvlc_MediaPlayerPositionChanged:
      name = "positionChanged";
      dval = event->u.media_player_position_changed.new_position;
      break;
    default: return;
  }
  // 分配事件载荷(name + 数值),通过 threadsafe fn 传给 JS。
  auto* payload = new std::pair<std::string, double>(std::string(name), dval);
  napi_acquire_threadsafe_function(g_tsfn);
  napi_call_threadsafe_function(g_tsfn, payload, napi_tsfn_blocking);
  napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
}

// threadsafe 的 JS 调用:取出载荷,调用 JS callback(eventName, value)。
void call_js(napi_env env, napi_value /*cb*/, void* context, void* data) {
  if (env == nullptr || data == nullptr) {
    return;
  }
  auto* payload = static_cast<std::pair<std::string, double>*>(data);
  napi_value global;
  napi_get_global(env, &global);
  napi_value callback;
  if (napi_get_reference_value(env, g_js_callback_ref, &callback) != napi_ok || callback == nullptr) {
    delete payload;
    return;
  }
  napi_value eventName;
  napi_create_string_utf8(env, payload->first.c_str(), payload->first.length(), &eventName);
  napi_value val;
  napi_create_double(env, payload->second, &val);
  napi_value args[2] = { eventName, val };
  napi_value result;
  napi_call_function(env, global, callback, 2, args, &result);
  delete payload;
}

void tsfn_finalize(napi_env /*env*/, void* /*data*/, void* /*hint*/) {
  // 占位:资源清理在 release() 里做。
}

// ---- NAPI 方法实现 ----

napi_value InitVlc(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lk(g_mtx);
  if (g_vlc == nullptr) {
    // 用 dladdr 取 libvlcnapi.so 自身路径 → 推出原生库目录(= 插件解包目录,与 libvlc/libvlccore/插件 .so 同目录)。
    std::string pluginPath;
    Dl_info dli;
    if (dladdr(reinterpret_cast<void*>(&InitVlc), &dli) && dli.dli_fname != nullptr) {
      std::string self(dli.dli_fname);
      size_t slash = self.find_last_of('/');
      if (slash != std::string::npos) {
        pluginPath = self.substr(0, slash);
      }
    }
    std::vector<const char*> argv;
    std::string pp = "--plugin-path=" + pluginPath;
    argv.push_back(pp.c_str());
    argv.push_back("--no-media-library");
    argv.push_back("--ignore-config");
    argv.push_back("--no-stats");
    g_vlc = libvlc_new(static_cast<int>(argv.size()), argv.data());
  }
  if (g_mp == nullptr && g_vlc != nullptr) {
    g_mp = libvlc_media_player_new(g_vlc);
    libvlc_event_manager_t* em = libvlc_media_player_event_manager(g_mp);
    if (em != nullptr) {
      libvlc_event_attach(em, libvlc_MediaPlayerPlaying, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerPaused, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerStopped, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerEndReached, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerEncounteredError, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerLengthChanged, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerTimeChanged, on_vlc_event, nullptr);
      libvlc_event_attach(em, libvlc_MediaPlayerPositionChanged, on_vlc_event, nullptr);
    }
  }
  napi_value result;
  napi_get_boolean(env, g_vlc != nullptr && g_mp != nullptr, &result);
  return result;
}

napi_value SetEventListener(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 1) {
    napi_get_undefined(env, &argv[0]);
  }
  if (g_js_callback_ref != nullptr) {
    napi_delete_reference(env, g_js_callback_ref);
    g_js_callback_ref = nullptr;
  }
  if (g_tsfn != nullptr) {
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
    g_tsfn = nullptr;
  }
  napi_valuetype vt;
  napi_typeof(env, argv[0], &vt);
  if (vt != napi_function) {
    napi_value r;
    napi_get_boolean(env, false, &r);
    return r;
  }
  napi_create_reference(env, argv[0], 1, &g_js_callback_ref);
  napi_value resName;
  napi_create_string_utf8(env, "VlcEvent", NAPI_AUTO_LENGTH, &resName);
  napi_create_threadsafe_function(env, argv[0], nullptr, resName, 0, 1, nullptr,
                                  tsfn_finalize, nullptr, call_js, &g_tsfn);
  napi_value r;
  napi_get_boolean(env, true, &r);
  return r;
}

napi_value SetMedia(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 1 || g_vlc == nullptr) {
    napi_value r; napi_get_boolean(env, false, &r); return r;
  }
  size_t len = 0;
  napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
  std::string mrl(len, '\0');
  napi_get_value_string_utf8(env, argv[0], &mrl[0], len + 1, &len);
  std::lock_guard<std::mutex> lk(g_mtx);
  if (g_media != nullptr) {
    libvlc_media_release(g_media);
    g_media = nullptr;
  }
  // 含 "://" 视为 location(MRL),否则本地路径。
  if (mrl.find("://") != std::string::npos) {
    g_media = libvlc_media_new_location(g_vlc, mrl.c_str());
  } else {
    g_media = libvlc_media_new_path(g_vlc, mrl.c_str());
  }
  if (g_media != nullptr && g_mp != nullptr) {
    libvlc_media_player_set_media(g_mp, g_media);
  }
  napi_value r;
  napi_get_boolean(env, g_media != nullptr, &r);
  return r;
}

napi_value Play(napi_env env, napi_callback_info /*info*/) {
  if (g_mp) { libvlc_media_player_play(g_mp); }
  return nullptr;
}
napi_value Pause(napi_env env, napi_callback_info /*info*/) {
  if (g_mp) { libvlc_media_player_set_pause(g_mp, 1); }
  return nullptr;
}
napi_value Resume(napi_env env, napi_callback_info /*info*/) {
  if (g_mp) { libvlc_media_player_set_pause(g_mp, 0); }
  return nullptr;
}
napi_value Stop(napi_env env, napi_callback_info /*info*/) {
  if (g_mp) { libvlc_media_player_stop(g_mp); }
  return nullptr;
}

napi_value GetTime(napi_env env, napi_callback_info /*info*/) {
  int64_t t = g_mp ? libvlc_media_player_get_time(g_mp) : -1;
  napi_value r; napi_create_int64(env, t, &r); return r;
}
napi_value SetTime(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int64_t t = 0;
  if (argc >= 1) { napi_get_value_int64(env, argv[0], &t); }
  if (g_mp) { libvlc_media_player_set_time(g_mp, t); }
  return nullptr;
}
napi_value GetLength(napi_env env, napi_callback_info /*info*/) {
  int64_t t = g_mp ? libvlc_media_player_get_length(g_mp) : -1;
  napi_value r; napi_create_int64(env, t, &r); return r;
}
napi_value SetRate(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  double r = 1.0;
  if (argc >= 1) { napi_get_value_double(env, argv[0], &r); }
  if (g_mp) { libvlc_media_player_set_rate(g_mp, r); }
  return nullptr;
}
napi_value GetRate(napi_env env, napi_callback_info /*info*/) {
  double r = g_mp ? libvlc_media_player_get_rate(g_mp) : 1.0;
  napi_value v; napi_create_double(env, r, &v); return v;
}
napi_value SetVolume(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  int v = 100;
  if (argc >= 1) { napi_get_value_int32(env, argv[0], &v); }
  if (g_mp) { libvlc_audio_set_volume(g_mp, v); }
  return nullptr;
}
napi_value GetVolume(napi_env env, napi_callback_info /*info*/) {
  int v = g_mp ? libvlc_audio_get_volume(g_mp) : -1;
  napi_value r; napi_create_int32(env, v, &r); return r;
}
napi_value GetState(napi_env env, napi_callback_info /*info*/) {
  int s = g_mp ? (int) libvlc_media_player_get_state(g_mp) : 0;
  napi_value r; napi_create_int32(env, s, &r); return r;
}
napi_value GetPosition(napi_env env, napi_callback_info /*info*/) {
  float p = g_mp ? libvlc_media_player_get_position(g_mp) : 0.0f;
  napi_value r; napi_create_double(env, (double) p, &r); return r;
}
napi_value Release(napi_env env, napi_callback_info /*info*/) {
  std::lock_guard<std::mutex> lk(g_mtx);
  if (g_media) { libvlc_media_release(g_media); g_media = nullptr; }
  if (g_mp) { libvlc_media_player_release(g_mp); g_mp = nullptr; }
  if (g_vlc) { libvlc_release(g_vlc); g_vlc = nullptr; }
  if (g_tsfn) { napi_release_threadsafe_function(g_tsfn, napi_tsfn_release); g_tsfn = nullptr; }
  if (g_js_callback_ref) { napi_delete_reference(env, g_js_callback_ref); g_js_callback_ref = nullptr; }
  return nullptr;
}
}  // namespace

napi_value VlcNapiInit(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"init", nullptr, InitVlc, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setEventListener", nullptr, SetEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setMedia", nullptr, SetMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"play", nullptr, Play, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"pause", nullptr, Pause, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"resume", nullptr, Resume, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getTime", nullptr, GetTime, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setTime", nullptr, SetTime, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getLength", nullptr, GetLength, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setRate", nullptr, SetRate, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getRate", nullptr, GetRate, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setVolume", nullptr, SetVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getVolume", nullptr, GetVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getState", nullptr, GetState, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getPosition", nullptr, GetPosition, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

static napi_module vlcModule = {
  .nm_version = 1,
  .nm_flags = 0,
  .nm_filename = nullptr,
  .nm_register_func = VlcNapiInit,
  .nm_modname = "libvlcnapi",
  .nm_priv = nullptr,
  .reserved = 0,
};

extern "C" __attribute__((constructor)) void RegisterVlcModule(void) {
  napi_module_register(&vlcModule);
}
