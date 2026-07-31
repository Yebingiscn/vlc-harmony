// vlc_napi.cpp —— libVLC C API → ArkTS NAPI 桥(单实例播放器)。
// 对齐 ohos_vlc: XComponent → OHNativeWindow → libvlc_media_player_set_ohos_nativewindow_ptr。
#include "napi/native_api.h"
#include "xcomponent_manager.h"

#include <vlc/vlc.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>

#include <dlfcn.h>
#include <unistd.h>
#include <mutex>
#include <string>
#include <vector>
#include <cstring>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x6C63
#define LOG_TAG "VlcNapi"

namespace {
libvlc_instance_t *g_vlc = nullptr;
libvlc_media_player_t *g_mp = nullptr;
libvlc_media_t *g_media = nullptr;
std::mutex g_mtx;
napi_threadsafe_function g_tsfn = nullptr;
napi_ref g_js_callback_ref = nullptr;
/** 当前请求绑定的 XComponent id(Surface 晚到时自动重绑)。 */
std::string g_video_out_id;
bool g_window_bound = false;
/** setMediaFd 时 dup 出的 fd(VLC 不关闭,由本模块在换媒体/release 时关闭)。 */
int g_media_fd = -1;

void CloseOwnedMediaFdLocked()
{
    if (g_media_fd >= 0) {
        OH_LOG_INFO(LOG_APP, "close owned media fd=%{public}d", g_media_fd);
        close(g_media_fd);
        g_media_fd = -1;
    }
}

void BindNativeWindowLocked(const std::string &id, OHNativeWindow *win)
{
    if (g_mp == nullptr) {
        OH_LOG_WARN(LOG_APP, "BindNativeWindow: media_player null, defer id=%{public}s", id.c_str());
        return;
    }
    if (win == nullptr) {
        OH_LOG_ERROR(LOG_APP, "BindNativeWindow: win null id=%{public}s", id.c_str());
        return;
    }
    OH_LOG_INFO(LOG_APP, "set_ohos_nativewindow_ptr mp=%{public}p win=%{public}p id=%{public}s",
                g_mp, win, id.c_str());
    libvlc_media_player_set_ohos_nativewindow_ptr(g_mp, win);
    g_window_bound = true;
}

void OnSurfaceReady(const std::string &id, OHNativeWindow *win)
{
    std::lock_guard<std::mutex> lk(g_mtx);
    OH_LOG_INFO(LOG_APP, "OnSurfaceReady id=%{public}s win=%{public}p want=%{public}s",
                id.c_str(), win, g_video_out_id.c_str());
    if (!g_video_out_id.empty() && g_video_out_id == id) {
        BindNativeWindowLocked(id, win);
    }
}

void on_vlc_event(const struct libvlc_event_t *event, void * /*user*/)
{
    if (g_tsfn == nullptr) {
        return;
    }
    const char *name = nullptr;
    double dval = 0.0;
    switch (event->type) {
        case libvlc_MediaPlayerPlaying:
            name = "playing";
            OH_LOG_INFO(LOG_APP, "event playing (window_bound=%{public}d)", g_window_bound ? 1 : 0);
            break;
        case libvlc_MediaPlayerPaused:
            name = "paused";
            break;
        case libvlc_MediaPlayerStopped:
            name = "stopped";
            break;
        case libvlc_MediaPlayerEndReached:
            name = "ended";
            break;
        case libvlc_MediaPlayerEncounteredError:
            name = "error";
            OH_LOG_ERROR(LOG_APP, "event MediaPlayerEncounteredError");
            break;
        case libvlc_MediaPlayerLengthChanged:
            name = "lengthChanged";
            dval = static_cast<double>(event->u.media_player_length_changed.new_length);
            break;
        case libvlc_MediaPlayerTimeChanged:
            name = "timeChanged";
            dval = static_cast<double>(event->u.media_player_time_changed.new_time);
            break;
        case libvlc_MediaPlayerPositionChanged:
            name = "positionChanged";
            dval = event->u.media_player_position_changed.new_position;
            break;
        case libvlc_MediaPlayerVout:
            name = "vout";
            dval = static_cast<double>(event->u.media_player_vout.new_count);
            OH_LOG_INFO(LOG_APP, "event MediaPlayerVout count=%{public}d bound=%{public}d",
                        event->u.media_player_vout.new_count, g_window_bound ? 1 : 0);
            break;
        default:
            return;
    }
    auto *payload = new std::pair<std::string, double>(std::string(name), dval);
    napi_acquire_threadsafe_function(g_tsfn);
    napi_call_threadsafe_function(g_tsfn, payload, napi_tsfn_blocking);
    napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
}

void call_js(napi_env env, napi_value /*cb*/, void * /*context*/, void *data)
{
    if (env == nullptr || data == nullptr) {
        return;
    }
    auto *payload = static_cast<std::pair<std::string, double> *>(data);
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
    napi_value args[2] = {eventName, val};
    napi_value result;
    napi_call_function(env, global, callback, 2, args, &result);
    delete payload;
}

void tsfn_finalize(napi_env /*env*/, void * /*data*/, void * /*hint*/) {}

bool EnsurePlayerLocked()
{
    if (g_vlc == nullptr) {
        // libvlcnapi.so 所在目录(= HAP 解包后的 libs/arm64-v8a),插件在其子目录 vlc/plugins。
        std::string nativeLibDir;
        Dl_info dli;
        if (dladdr(reinterpret_cast<void *>(&EnsurePlayerLocked), &dli) && dli.dli_fname != nullptr) {
            std::string self(dli.dli_fname);
            size_t slash = self.find_last_of('/');
            if (slash != std::string::npos) {
                nativeLibDir = self.substr(0, slash);
            }
        }
        std::string pluginPath = nativeLibDir.empty() ? std::string("vlc") : (nativeLibDir + "/vlc");
        std::vector<const char *> argv;
        std::string pp = "--plugin-path=" + pluginPath;
        // verbose 便于 hilog / 控制台定位解码与 vout 问题
        argv.push_back(pp.c_str());
        argv.push_back("--verbose=2");
        argv.push_back("--no-media-library");
        argv.push_back("--ignore-config");
        argv.push_back("--no-stats");
        OH_LOG_INFO(LOG_APP, "libvlc_new nativeLibDir=%{public}s plugin-path=%{public}s",
                    nativeLibDir.c_str(), pluginPath.c_str());
        g_vlc = libvlc_new(static_cast<int>(argv.size()), argv.data());
        if (g_vlc == nullptr) {
            OH_LOG_ERROR(LOG_APP, "libvlc_new FAILED");
            return false;
        }
        OH_LOG_INFO(LOG_APP, "libvlc_new ok instance=%{public}p", g_vlc);
    }
    if (g_mp == nullptr) {
        g_mp = libvlc_media_player_new(g_vlc);
        if (g_mp == nullptr) {
            OH_LOG_ERROR(LOG_APP, "libvlc_media_player_new FAILED");
            return false;
        }
        libvlc_event_manager_t *em = libvlc_media_player_event_manager(g_mp);
        if (em != nullptr) {
            libvlc_event_attach(em, libvlc_MediaPlayerPlaying, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerPaused, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerStopped, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerEndReached, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerEncounteredError, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerLengthChanged, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerTimeChanged, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerPositionChanged, on_vlc_event, nullptr);
            libvlc_event_attach(em, libvlc_MediaPlayerVout, on_vlc_event, nullptr);
        }
        OH_LOG_INFO(LOG_APP, "media_player created mp=%{public}p", g_mp);
        // 若 Surface 已先到,补绑
        if (!g_video_out_id.empty()) {
            OHNativeWindow *win = xMgr.GetNativeWindow(g_video_out_id);
            if (win != nullptr) {
                BindNativeWindowLocked(g_video_out_id, win);
            }
        }
    }
    return g_vlc != nullptr && g_mp != nullptr;
}

napi_value InitVlc(napi_env env, napi_callback_info /*info*/)
{
    std::lock_guard<std::mutex> lk(g_mtx);
    xMgr.SetSurfaceReadyCallback(OnSurfaceReady);
    bool ok = EnsurePlayerLocked();
    OH_LOG_INFO(LOG_APP, "init => %{public}s", ok ? "ok" : "fail");
    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

napi_value SetVideoOut(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value r;
    if (argc < 1) {
        OH_LOG_ERROR(LOG_APP, "setVideoOut: missing xcomponent id");
        napi_get_boolean(env, false, &r);
        return r;
    }
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
    std::string id(len, '\0');
    napi_get_value_string_utf8(env, argv[0], &id[0], len + 1, &len);

    std::lock_guard<std::mutex> lk(g_mtx);
    g_video_out_id = id;
    g_window_bound = false;
    EnsurePlayerLocked();

    OH_NativeXComponent *xc = xMgr.GetNativeXcomponent(id);
    OHNativeWindow *win = xMgr.GetNativeWindow(id);
    OH_LOG_INFO(LOG_APP, "setVideoOut id=%{public}s xc=%{public}p win=%{public}p mp=%{public}p",
                id.c_str(), xc, win, g_mp);

    if (win == nullptr) {
        OH_LOG_WARN(LOG_APP, "setVideoOut: NativeWindow not ready yet, will bind on OnSurfaceCreated");
        napi_get_boolean(env, false, &r);
        return r;
    }
    BindNativeWindowLocked(id, win);
    napi_get_boolean(env, true, &r);
    return r;
}

napi_value HasNativeWindow(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool has = false;
    if (argc >= 1) {
        size_t len = 0;
        napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
        std::string id(len, '\0');
        napi_get_value_string_utf8(env, argv[0], &id[0], len + 1, &len);
        has = xMgr.HasNativeWindow(id);
    }
    napi_value r;
    napi_get_boolean(env, has, &r);
    return r;
}

napi_value SetEventListener(napi_env env, napi_callback_info info)
{
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
    napi_create_threadsafe_function(env, argv[0], nullptr, resName, 0, 1, nullptr, tsfn_finalize, nullptr, call_js,
                                    &g_tsfn);
    napi_value r;
    napi_get_boolean(env, true, &r);
    return r;
}

napi_value SetMedia(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_value r;
        napi_get_boolean(env, false, &r);
        return r;
    }
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &len);
    std::string mrl(len, '\0');
    napi_get_value_string_utf8(env, argv[0], &mrl[0], len + 1, &len);

    std::lock_guard<std::mutex> lk(g_mtx);
    if (!EnsurePlayerLocked()) {
        napi_value r;
        napi_get_boolean(env, false, &r);
        return r;
    }
    if (g_media != nullptr) {
        libvlc_media_release(g_media);
        g_media = nullptr;
    }
    CloseOwnedMediaFdLocked();
    if (mrl.find("://") != std::string::npos) {
        OH_LOG_INFO(LOG_APP, "setMedia location=%{public}s", mrl.c_str());
        g_media = libvlc_media_new_location(g_vlc, mrl.c_str());
    } else {
        OH_LOG_INFO(LOG_APP, "setMedia path=%{public}s", mrl.c_str());
        g_media = libvlc_media_new_path(g_vlc, mrl.c_str());
    }
    if (g_media != nullptr && g_mp != nullptr) {
        libvlc_media_player_set_media(g_mp, g_media);
    } else {
        OH_LOG_ERROR(LOG_APP, "setMedia FAILED media=%{public}p", g_media);
    }
    napi_value r;
    napi_get_boolean(env, g_media != nullptr, &r);
    return r;
}

/**
 * 用已打开的 fd 创建媒体(鸿蒙相册 file://media/Photo/... 需 fs.openSync 后走此路径)。
 * Native 会 dup(fd),调用方可立即 close 自己的 File。
 */
napi_value SetMediaFd(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value r;
    if (argc < 1) {
        OH_LOG_ERROR(LOG_APP, "setMediaFd: missing fd");
        napi_get_boolean(env, false, &r);
        return r;
    }
    int32_t fd = -1;
    napi_get_value_int32(env, argv[0], &fd);
    if (fd < 0) {
        OH_LOG_ERROR(LOG_APP, "setMediaFd: invalid fd=%{public}d", fd);
        napi_get_boolean(env, false, &r);
        return r;
    }

    std::lock_guard<std::mutex> lk(g_mtx);
    if (!EnsurePlayerLocked()) {
        napi_get_boolean(env, false, &r);
        return r;
    }
    if (g_media != nullptr) {
        libvlc_media_release(g_media);
        g_media = nullptr;
    }
    CloseOwnedMediaFdLocked();

    int dupFd = dup(fd);
    if (dupFd < 0) {
        OH_LOG_ERROR(LOG_APP, "setMediaFd: dup(%{public}d) failed", fd);
        napi_get_boolean(env, false, &r);
        return r;
    }
    // 每次从文件头播放
    lseek(dupFd, 0, SEEK_SET);
    OH_LOG_INFO(LOG_APP, "setMediaFd srcFd=%{public}d dupFd=%{public}d", fd, dupFd);
    g_media = libvlc_media_new_fd(g_vlc, dupFd);
    if (g_media == nullptr) {
        OH_LOG_ERROR(LOG_APP, "libvlc_media_new_fd FAILED fd=%{public}d", dupFd);
        close(dupFd);
        napi_get_boolean(env, false, &r);
        return r;
    }
    g_media_fd = dupFd;
    if (g_mp != nullptr) {
        libvlc_media_player_set_media(g_mp, g_media);
    }
    napi_get_boolean(env, true, &r);
    return r;
}

napi_value Play(napi_env env, napi_callback_info /*info*/)
{
    std::lock_guard<std::mutex> lk(g_mtx);
    OH_LOG_INFO(LOG_APP, "play mp=%{public}p bound=%{public}d videoOut=%{public}s", g_mp, g_window_bound ? 1 : 0,
                g_video_out_id.c_str());
    if (g_mp) {
        // 播放前再尝试绑一次,避免 race
        if (!g_window_bound && !g_video_out_id.empty()) {
            OHNativeWindow *win = xMgr.GetNativeWindow(g_video_out_id);
            if (win != nullptr) {
                BindNativeWindowLocked(g_video_out_id, win);
            } else {
                OH_LOG_WARN(LOG_APP, "play without NativeWindow — expect black screen");
            }
        }
        int ret = libvlc_media_player_play(g_mp);
        OH_LOG_INFO(LOG_APP, "libvlc_media_player_play ret=%{public}d", ret);
    }
    return nullptr;
}

napi_value Pause(napi_env env, napi_callback_info /*info*/)
{
    if (g_mp) {
        libvlc_media_player_set_pause(g_mp, 1);
    }
    return nullptr;
}

napi_value Resume(napi_env env, napi_callback_info /*info*/)
{
    if (g_mp) {
        libvlc_media_player_set_pause(g_mp, 0);
    }
    return nullptr;
}

napi_value Stop(napi_env env, napi_callback_info /*info*/)
{
    OH_LOG_INFO(LOG_APP, "stop");
    if (g_mp) {
        libvlc_media_player_stop(g_mp);
    }
    return nullptr;
}

napi_value GetTime(napi_env env, napi_callback_info /*info*/)
{
    int64_t t = g_mp ? libvlc_media_player_get_time(g_mp) : -1;
    napi_value r;
    napi_create_int64(env, t, &r);
    return r;
}

napi_value SetTime(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t t = 0;
    if (argc >= 1) {
        napi_get_value_int64(env, argv[0], &t);
    }
    if (g_mp) {
        libvlc_media_player_set_time(g_mp, t);
    }
    return nullptr;
}

napi_value GetLength(napi_env env, napi_callback_info /*info*/)
{
    int64_t t = g_mp ? libvlc_media_player_get_length(g_mp) : -1;
    napi_value r;
    napi_create_int64(env, t, &r);
    return r;
}

napi_value SetRate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double r = 1.0;
    if (argc >= 1) {
        napi_get_value_double(env, argv[0], &r);
    }
    if (g_mp) {
        libvlc_media_player_set_rate(g_mp, r);
    }
    return nullptr;
}

napi_value GetRate(napi_env env, napi_callback_info /*info*/)
{
    double r = g_mp ? libvlc_media_player_get_rate(g_mp) : 1.0;
    napi_value v;
    napi_create_double(env, r, &v);
    return v;
}

napi_value SetVolume(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int v = 100;
    if (argc >= 1) {
        napi_get_value_int32(env, argv[0], &v);
    }
    if (g_mp) {
        libvlc_audio_set_volume(g_mp, v);
    }
    return nullptr;
}

napi_value GetVolume(napi_env env, napi_callback_info /*info*/)
{
    int v = g_mp ? libvlc_audio_get_volume(g_mp) : -1;
    napi_value r;
    napi_create_int32(env, v, &r);
    return r;
}

napi_value GetState(napi_env env, napi_callback_info /*info*/)
{
    int s = g_mp ? static_cast<int>(libvlc_media_player_get_state(g_mp)) : 0;
    napi_value r;
    napi_create_int32(env, s, &r);
    return r;
}

napi_value GetPosition(napi_env env, napi_callback_info /*info*/)
{
    float p = g_mp ? libvlc_media_player_get_position(g_mp) : 0.0f;
    napi_value r;
    napi_create_double(env, static_cast<double>(p), &r);
    return r;
}

/** 获取视频原始像素尺寸 {width,height};失败返回 null。 */
napi_value GetVideoSize(napi_env env, napi_callback_info /*info*/)
{
    if (g_mp == nullptr) {
        return nullptr;
    }
    unsigned px = 0;
    unsigned py = 0;
    int ret = libvlc_video_get_size(g_mp, 0, &px, &py);
    if (ret != 0 || px == 0 || py == 0) {
        OH_LOG_WARN(LOG_APP, "getVideoSize fail ret=%{public}d %ux%u", ret, px, py);
        return nullptr;
    }
    OH_LOG_INFO(LOG_APP, "getVideoSize %ux%u", px, py);
    napi_value res = nullptr;
    napi_create_object(env, &res);
    napi_value w = nullptr;
    napi_value h = nullptr;
    napi_create_uint32(env, px, &w);
    napi_create_uint32(env, py, &h);
    napi_set_named_property(env, res, "width", w);
    napi_set_named_property(env, res, "height", h);
    return res;
}

/** scale=0 表示按输出窗口自适应(保持比例);>0 为缩放因子。 */
napi_value SetScale(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double factor = 0.0;
    if (argc >= 1) {
        napi_get_value_double(env, argv[0], &factor);
    }
    if (g_mp) {
        OH_LOG_INFO(LOG_APP, "setScale factor=%{public}f", factor);
        libvlc_video_set_scale(g_mp, static_cast<float>(factor));
    }
    return nullptr;
}

napi_value Release(napi_env env, napi_callback_info /*info*/)
{
    std::lock_guard<std::mutex> lk(g_mtx);
    OH_LOG_INFO(LOG_APP, "release");
    if (g_media) {
        libvlc_media_release(g_media);
        g_media = nullptr;
    }
    CloseOwnedMediaFdLocked();
    if (g_mp) {
        libvlc_media_player_release(g_mp);
        g_mp = nullptr;
    }
    if (g_vlc) {
        libvlc_release(g_vlc);
        g_vlc = nullptr;
    }
    g_video_out_id.clear();
    g_window_bound = false;
    if (g_tsfn) {
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
    }
    if (g_js_callback_ref) {
        napi_delete_reference(env, g_js_callback_ref);
        g_js_callback_ref = nullptr;
    }
    return nullptr;
}

/** 从 exports 取出 XComponent 并注册 surface 回调(libraryname 加载时触发)。 */
void RegisterXComponentIfPresent(napi_env env, napi_value exports)
{
    napi_value xComponentInstance = nullptr;
    napi_status status = napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &xComponentInstance);
    if (status != napi_ok || xComponentInstance == nullptr) {
        OH_LOG_INFO(LOG_APP, "RegisterXComponent: no OH_NATIVE_XCOMPONENT_OBJ (normal so import)");
        return;
    }
    OH_NativeXComponent *nativeXComponent = nullptr;
    status = napi_unwrap(env, xComponentInstance, reinterpret_cast<void **>(&nativeXComponent));
    if (status != napi_ok || nativeXComponent == nullptr) {
        OH_LOG_ERROR(LOG_APP, "RegisterXComponent: napi_unwrap failed");
        return;
    }
    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    int32_t ret = OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize);
    if (ret != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "RegisterXComponent: GetXComponentId failed ret=%{public}d", ret);
        return;
    }
    std::string strId(idStr);
    OH_LOG_INFO(LOG_APP, "RegisterXComponent id=%{public}s xc=%{public}p", strId.c_str(), nativeXComponent);
    xMgr.AddNativeXcomponent(strId, nativeXComponent);
    xMgr.RegisterCallback(strId);
    xMgr.SetSurfaceReadyCallback(OnSurfaceReady);
}
}  // namespace

napi_value VlcNapiInit(napi_env env, napi_value exports)
{
    OH_LOG_INFO(LOG_APP, "VlcNapiInit enter");
    napi_property_descriptor desc[] = {
        {"init", nullptr, InitVlc, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVideoOut", nullptr, SetVideoOut, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hasNativeWindow", nullptr, HasNativeWindow, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setEventListener", nullptr, SetEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setMedia", nullptr, SetMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setMediaFd", nullptr, SetMediaFd, nullptr, nullptr, nullptr, napi_default, nullptr},
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
        {"getVideoSize", nullptr, GetVideoSize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setScale", nullptr, SetScale, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    RegisterXComponentIfPresent(env, exports);
    OH_LOG_INFO(LOG_APP, "VlcNapiInit done");
    return exports;
}

static napi_module vlcModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = VlcNapiInit,
    .nm_modname = "libvlcnapi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVlcModule(void)
{
    napi_module_register(&vlcModule);
}
