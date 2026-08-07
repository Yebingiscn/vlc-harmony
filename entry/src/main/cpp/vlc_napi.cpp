// vlc_napi.cpp 鈥斺€?libVLC C API 鈫?ArkTS NAPI(鍙ユ焺寮?瀵归綈 libvlcjni 瀵硅薄鐢熷懡鍛ㄦ湡)銆?
#include "napi/native_api.h"
#include "xcomponent_manager.h"

#include <vlc/vlc.h>
#include <vlc/deprecated.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>

#include <dlfcn.h>
#include <unistd.h>
#include <chrono>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x6C63
#define LOG_TAG "VlcNapi"

void OnLibvlcLog(void *data, int level, const libvlc_log_t *ctx, const char *fmt, va_list args)
{
    (void)data;
    (void)ctx;
    char msg[2048] = {0};
    vsnprintf(msg, sizeof(msg), fmt, args);
    if (level >= LIBVLC_ERROR) {
        OH_LOG_ERROR(LOG_APP, "libvlc: %{public}s", msg);
    } else if (level == LIBVLC_WARNING) {
        OH_LOG_WARN(LOG_APP, "libvlc: %{public}s", msg);
    } else if (level == LIBVLC_DEBUG) {
        OH_LOG_DEBUG(LOG_APP, "libvlc: %{public}s", msg);
    } else {
        OH_LOG_INFO(LOG_APP, "libvlc: %{public}s", msg);
    }
}

namespace {

std::mutex g_mtx;
uint32_t g_nextHandle = 1;

struct LibEntry {
    libvlc_instance_t *inst = nullptr;
};

struct MediaEntry {
    libvlc_media_t *media = nullptr;
    int ownedFd = -1;
    uint32_t libHandle = 0;
};

struct PlayerEntry {
    libvlc_media_player_t *mp = nullptr;
    uint32_t libHandle = 0;
    uint32_t mediaHandle = 0;
    std::string videoOutId;
    bool windowBound = false;
    napi_threadsafe_function tsfn = nullptr;
    napi_ref jsCallbackRef = nullptr;
};

struct EqEntry {
    libvlc_equalizer_t *eq = nullptr;
};

struct MediaListEntry {
    libvlc_media_list_t *list = nullptr;
};

struct MediaDiscovererEntry {
    libvlc_media_discoverer_t *md = nullptr;
    uint32_t listHandle = 0;
};

struct RendererItemEntry {
    libvlc_renderer_item_t *item = nullptr;
    uint32_t rdHandle = 0;
};

struct RendererDiscovererEntry {
    libvlc_renderer_discoverer_t *rd = nullptr;
    uint32_t libHandle = 0;
    std::vector<uint32_t> itemHandles;
    napi_threadsafe_function tsfn = nullptr;
    napi_ref jsCallbackRef = nullptr;
};

std::unordered_map<uint32_t, LibEntry> g_libs;
std::unordered_map<uint32_t, MediaEntry> g_medias;
std::unordered_map<uint32_t, PlayerEntry> g_players;
std::unordered_map<uint32_t, EqEntry> g_eqs;
std::unordered_map<uint32_t, MediaListEntry> g_lists;
std::unordered_map<uint32_t, MediaDiscovererEntry> g_mds;
std::unordered_map<uint32_t, RendererItemEntry> g_renderers;
std::unordered_map<uint32_t, RendererDiscovererEntry> g_rds;

uint32_t AllocHandleLocked()
{
    return g_nextHandle++;
}

std::string ResolvePluginPath()
{
    std::string nativeLibDir;
    Dl_info dli;
    if (dladdr(reinterpret_cast<void *>(&ResolvePluginPath), &dli) && dli.dli_fname != nullptr) {
        std::string self(dli.dli_fname);
        size_t slash = self.find_last_of('/');
        if (slash != std::string::npos) {
            nativeLibDir = self.substr(0, slash);
        }
    }
    return nativeLibDir.empty() ? std::string("vlc") : (nativeLibDir + "/vlc");
}

void CloseOwnedFd(int &fd)
{
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
}

void SetOhosNativeWindow(libvlc_media_player_t *mp, OHNativeWindow *win, const std::string &id)
{
    if (mp == nullptr) {
        return;
    }
    OH_LOG_INFO(LOG_APP, "set_ohos_nativewindow_ptr mp=%{public}p win=%{public}p id=%{public}s",
                mp, win, id.c_str());
    // Must NOT hold g_mtx: may interact with VLC threads / vout events.
    libvlc_media_player_set_ohos_nativewindow_ptr(mp, win);
}

void MarkWindowBoundLocked(const std::string &id, bool bound)
{
    for (auto &kv : g_players) {
        PlayerEntry &pe = kv.second;
        if (pe.videoOutId == id && pe.mp != nullptr) {
            pe.windowBound = bound;
        }
    }
}

void OnSurfaceReady(const std::string &id, OHNativeWindow *win)
{
    std::vector<libvlc_media_player_t *> mps;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        OH_LOG_INFO(LOG_APP, "OnSurfaceReady id=%{public}s win=%{public}p", id.c_str(), win);
        for (auto &kv : g_players) {
            if (!kv.second.videoOutId.empty() && kv.second.videoOutId == id && kv.second.mp != nullptr) {
                mps.push_back(kv.second.mp);
            }
        }
    }
    for (libvlc_media_player_t *mp : mps) {
        SetOhosNativeWindow(mp, win, id);
    }
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        MarkWindowBoundLocked(id, true);
    }
}

/** Detach OHOS native window from matching players (Android detachViews / cleanUI). */
void DetachNativeWindowById(const std::string &id)
{
    std::vector<libvlc_media_player_t *> mps;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        OH_LOG_INFO(LOG_APP, "DetachNativeWindowById id=%{public}s", id.c_str());
        for (auto &kv : g_players) {
            PlayerEntry &pe = kv.second;
            if (pe.videoOutId == id && pe.mp != nullptr) {
                mps.push_back(pe.mp);
                pe.windowBound = false;
                pe.videoOutId.clear();
            }
        }
    }
    for (libvlc_media_player_t *mp : mps) {
        libvlc_media_player_set_ohos_nativewindow_ptr(mp, nullptr);
    }
}

void OnSurfaceDestroyed(const std::string &id)
{
    DetachNativeWindowById(id);
}

struct EventPayload {
    uint32_t playerHandle = 0;
    std::string name;
    double value = 0.0;
};

void call_js(napi_env env, napi_value /*cb*/, void * /*context*/, void *data)
{
    if (env == nullptr || data == nullptr) {
        return;
    }
    auto *payload = static_cast<EventPayload *>(data);
    napi_ref ref = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_players.find(payload->playerHandle);
        if (it != g_players.end()) {
            ref = it->second.jsCallbackRef;
        }
    }
    if (ref == nullptr) {
        delete payload;
        return;
    }
    // ref looked up under lock; invoke outside lock to avoid deadlock with VLC callbacks.
    napi_value global;
    napi_get_global(env, &global);
    napi_value callback;
    if (napi_get_reference_value(env, ref, &callback) != napi_ok || callback == nullptr) {
        delete payload;
        return;
    }
    napi_value h;
    napi_create_uint32(env, payload->playerHandle, &h);
    napi_value eventName;
    napi_create_string_utf8(env, payload->name.c_str(), payload->name.length(), &eventName);
    napi_value val;
    napi_create_double(env, payload->value, &val);
    napi_value args[3] = {h, eventName, val};
    napi_value result;
    napi_call_function(env, global, callback, 3, args, &result);
    delete payload;
}

void tsfn_finalize(napi_env /*env*/, void * /*data*/, void * /*hint*/) {}

void EmitPlayerEventTsfn(napi_threadsafe_function tsfn, uint32_t playerHandle, const char *name, double value)
{
    if (tsfn == nullptr) {
        return;
    }
    auto *payload = new EventPayload{playerHandle, std::string(name), value};
    napi_acquire_threadsafe_function(tsfn);
    // nonblocking: avoid deadlock when UI thread is inside libvlc_media_player_stop
    // while a VLC thread waits for the JS event callback.
    napi_status st = napi_call_threadsafe_function(tsfn, payload, napi_tsfn_nonblocking);
    if (st != napi_ok) {
        delete payload;
    }
    napi_release_threadsafe_function(tsfn, napi_tsfn_release);
}

void on_player_event(const struct libvlc_event_t *event, void *user)
{
    if (user == nullptr) {
        return;
    }
    uint32_t handle = *static_cast<uint32_t *>(user);
    const char *name = nullptr;
    double dval = 0.0;
    switch (event->type) {
        case libvlc_MediaPlayerPlaying:
            name = "playing";
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
            break;
        case libvlc_MediaPlayerBuffering:
            name = "buffering";
            dval = event->u.media_player_buffering.new_cache;
            break;
        case libvlc_MediaPlayerESAdded:
            name = "esAdded";
            dval = static_cast<double>(event->u.media_player_es_changed.i_type);
            break;
        case libvlc_MediaPlayerESDeleted:
            name = "esDeleted";
            dval = static_cast<double>(event->u.media_player_es_changed.i_type);
            break;
        case libvlc_MediaPlayerESSelected:
            name = "esSelected";
            dval = static_cast<double>(event->u.media_player_es_changed.i_type);
            break;
        default:
            return;
    }
    napi_threadsafe_function tsfn = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_players.find(handle);
        if (it != g_players.end()) {
            tsfn = it->second.tsfn;
        }
    }
    EmitPlayerEventTsfn(tsfn, handle, name, dval);
}

// event user data retained per player (stable heap uint32 handle)
std::unordered_map<uint32_t, uint32_t *> g_eventUsers;

bool GetU32(napi_env env, napi_value v, uint32_t *out)
{
    return napi_get_value_uint32(env, v, out) == napi_ok;
}

bool GetI32(napi_env env, napi_value v, int32_t *out)
{
    return napi_get_value_int32(env, v, out) == napi_ok;
}

bool GetI64(napi_env env, napi_value v, int64_t *out)
{
    return napi_get_value_int64(env, v, out) == napi_ok;
}

bool GetF64(napi_env env, napi_value v, double *out)
{
    return napi_get_value_double(env, v, out) == napi_ok;
}

std::string GetString(napi_env env, napi_value v)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string s(len, '\0');
    napi_get_value_string_utf8(env, v, &s[0], len + 1, &len);
    return s;
}

napi_value Bool(napi_env env, bool b)
{
    napi_value r;
    napi_get_boolean(env, b, &r);
    return r;
}

napi_value U32(napi_env env, uint32_t v)
{
    napi_value r;
    napi_create_uint32(env, v, &r);
    return r;
}

napi_value I32(napi_env env, int32_t v)
{
    napi_value r;
    napi_create_int32(env, v, &r);
    return r;
}

napi_value I64(napi_env env, int64_t v)
{
    napi_value r;
    napi_create_int64(env, v, &r);
    return r;
}

napi_value F64(napi_env env, double v)
{
    napi_value r;
    napi_create_double(env, v, &r);
    return r;
}

napi_value TracksToArray(napi_env env, libvlc_track_description_t *desc)
{
    napi_value arr;
    napi_create_array(env, &arr);
    uint32_t idx = 0;
    for (libvlc_track_description_t *p = desc; p != nullptr; p = p->p_next) {
        napi_value obj;
        napi_create_object(env, &obj);
        napi_set_named_property(env, obj, "id", I32(env, p->i_id));
        napi_value name;
        napi_create_string_utf8(env, p->psz_name ? p->psz_name : "", NAPI_AUTO_LENGTH, &name);
        napi_set_named_property(env, obj, "name", name);
        napi_set_element(env, arr, idx++, obj);
    }
    if (desc != nullptr) {
        libvlc_track_description_list_release(desc);
    }
    return arr;
}

PlayerEntry *FindPlayerLocked(uint32_t h)
{
    auto it = g_players.find(h);
    return it == g_players.end() ? nullptr : &it->second;
}

MediaEntry *FindMediaLocked(uint32_t h)
{
    auto it = g_medias.find(h);
    return it == g_medias.end() ? nullptr : &it->second;
}

LibEntry *FindLibLocked(uint32_t h)
{
    auto it = g_libs.find(h);
    return it == g_libs.end() ? nullptr : &it->second;
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ LibVLC 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

napi_value LibvlcCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string pluginPath = ResolvePluginPath();
    std::string pp = "--plugin-path=" + pluginPath;
    std::vector<std::string> optStorage;
    std::vector<const char *> argvVlc;
    argvVlc.push_back(pp.c_str());
    argvVlc.push_back("--verbose=2");
    argvVlc.push_back("--no-media-library");
    argvVlc.push_back("--ignore-config");
    argvVlc.push_back("--stats");

    if (argc >= 1) {
        bool isArray = false;
        napi_is_array(env, argv[0], &isArray);
        if (isArray) {
            uint32_t len = 0;
            napi_get_array_length(env, argv[0], &len);
            for (uint32_t i = 0; i < len; ++i) {
                napi_value item;
                napi_get_element(env, argv[0], i, &item);
                optStorage.push_back(GetString(env, item));
            }
            for (const auto &s : optStorage) {
                argvVlc.push_back(s.c_str());
            }
        }
    }

    libvlc_instance_t *inst = libvlc_new(static_cast<int>(argvVlc.size()), argvVlc.data());
    if (inst == nullptr) {
        OH_LOG_ERROR(LOG_APP, "libvlc_new FAILED");
        return U32(env, 0);
    }
    libvlc_log_set(inst, OnLibvlcLog, nullptr);
    std::lock_guard<std::mutex> lk(g_mtx);
    uint32_t h = AllocHandleLocked();
    g_libs[h] = LibEntry{inst};
    xMgr.SetSurfaceReadyCallback(OnSurfaceReady);
    xMgr.SetSurfaceDestroyedCallback(OnSurfaceDestroyed);
    OH_LOG_INFO(LOG_APP, "libvlcCreate h=%{public}u inst=%{public}p", h, inst);
    return U32(env, h);
}

napi_value LibvlcRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_libs.find(h);
    if (it != g_libs.end()) {
        if (it->second.inst) {
            libvlc_release(it->second.inst);
        }
        g_libs.erase(it);
    }
    return nullptr;
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ Media 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

napi_value MediaCreateLocation(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 2 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::string mrl = GetString(env, argv[1]);
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_t *m = libvlc_media_new_location(lib->inst, mrl.c_str());
    if (m == nullptr) {
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    g_medias[h] = MediaEntry{m, -1, libH};
    return U32(env, h);
}

napi_value MediaCreatePath(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 2 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::string path = GetString(env, argv[1]);
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_t *m = libvlc_media_new_path(lib->inst, path.c_str());
    if (m == nullptr) {
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    g_medias[h] = MediaEntry{m, -1, libH};
    return U32(env, h);
}

napi_value MediaCreateFd(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    int32_t fd = -1;
    if (argc < 2 || !GetU32(env, argv[0], &libH) || !GetI32(env, argv[1], &fd) || fd < 0) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    int dupFd = dup(fd);
    if (dupFd < 0) {
        return U32(env, 0);
    }
    lseek(dupFd, 0, SEEK_SET);
    libvlc_media_t *m = libvlc_media_new_fd(lib->inst, dupFd);
    if (m == nullptr) {
        close(dupFd);
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    g_medias[h] = MediaEntry{m, dupFd, libH};
    return U32(env, h);
}

napi_value MediaRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_medias.find(h);
    if (it != g_medias.end()) {
        if (it->second.media) {
            libvlc_media_release(it->second.media);
        }
        CloseOwnedFd(it->second.ownedFd);
        g_medias.erase(it);
    }
    return nullptr;
}

napi_value MediaParse(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t timeoutMs = 5000;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return Bool(env, false);
    }
    if (argc >= 2) {
        GetI32(env, argv[1], &timeoutMs);
    }
    libvlc_media_t *media = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        MediaEntry *me = FindMediaLocked(h);
        if (me == nullptr || me->media == nullptr) {
            return Bool(env, false);
        }
        media = me->media;
        libvlc_media_retain(media);
    }
    int rc = libvlc_media_parse_with_options(media, libvlc_media_parse_local, timeoutMs);
    bool ok = false;
    if (rc == 0) {
        auto start = std::chrono::steady_clock::now();
        while (true) {
            libvlc_media_parsed_status_t st = libvlc_media_get_parsed_status(media);
            if (st == libvlc_media_parsed_status_done || st == libvlc_media_parsed_status_failed ||
                st == libvlc_media_parsed_status_timeout || st == libvlc_media_parsed_status_skipped) {
                ok = (st == libvlc_media_parsed_status_done);
                break;
            }
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - start).count();
            if (elapsed > timeoutMs + 500) {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
    }
    libvlc_media_release(media);
    return Bool(env, ok);
}

napi_value MediaGetTracksInfo(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_t *media = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        MediaEntry *me = FindMediaLocked(h);
        if (me == nullptr || me->media == nullptr) {
            return nullptr;
        }
        media = me->media;
    }
    libvlc_media_track_t **tracks = nullptr;
    unsigned count = libvlc_media_tracks_get(media, &tracks);
    napi_value arr;
    napi_create_array(env, &arr);
    if (tracks == nullptr) {
        return arr;
    }
    for (unsigned i = 0; i < count; i++) {
        libvlc_media_track_t *t = tracks[i];
        if (t == nullptr) {
            continue;
        }
        napi_value obj;
        napi_create_object(env, &obj);
        // id
        napi_set_named_property(env, obj, "id", I32(env, t->i_id));
        // type: libvlc_track_type_t { 0=audio, 1=video, 2=text/spu }
        napi_set_named_property(env, obj, "type", I32(env, (int32_t)t->i_type));
        // codecFourcc
        napi_set_named_property(env, obj, "codecFourcc", U32(env, t->i_codec));
        napi_value descStr;
        napi_create_string_utf8(env, t->psz_description ? t->psz_description : "", NAPI_AUTO_LENGTH, &descStr);
        napi_set_named_property(env, obj, "codecDesc", descStr);
        napi_value langStr;
        napi_create_string_utf8(env, t->psz_language ? t->psz_language : "", NAPI_AUTO_LENGTH, &langStr);
        napi_set_named_property(env, obj, "language", langStr);
        napi_set_named_property(env, obj, "bitrate", U32(env, t->i_bitrate));
        if (t->i_type == libvlc_track_audio && t->audio != nullptr) {
            napi_set_named_property(env, obj, "channels", U32(env, t->audio->i_channels));
            napi_set_named_property(env, obj, "sampleRate", U32(env, t->audio->i_rate));
        }
        if (t->i_type == libvlc_track_video && t->video != nullptr) {
            napi_set_named_property(env, obj, "videoWidth", U32(env, t->video->i_width));
            napi_set_named_property(env, obj, "videoHeight", U32(env, t->video->i_height));
            napi_set_named_property(env, obj, "frameRateNum", U32(env, t->video->i_frame_rate_num));
            napi_set_named_property(env, obj, "frameRateDen", U32(env, t->video->i_frame_rate_den));
        }
        napi_set_element(env, arr, i, obj);
    }
    libvlc_media_tracks_release(tracks, count);
    return arr;
}

napi_value MediaGetMeta(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    MediaEntry *me = FindMediaLocked(h);
    if (me == nullptr || me->media == nullptr) {
        return nullptr;
    }
    char *title = libvlc_media_get_meta(me->media, libvlc_meta_Title);
    char *artist = libvlc_media_get_meta(me->media, libvlc_meta_Artist);
    char *album = libvlc_media_get_meta(me->media, libvlc_meta_Album);
    libvlc_time_t dur = libvlc_media_get_duration(me->media);
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value t, a, al, d;
    napi_create_string_utf8(env, title ? title : "", NAPI_AUTO_LENGTH, &t);
    napi_create_string_utf8(env, artist ? artist : "", NAPI_AUTO_LENGTH, &a);
    napi_create_string_utf8(env, album ? album : "", NAPI_AUTO_LENGTH, &al);
    napi_create_int64(env, static_cast<int64_t>(dur), &d);
    napi_set_named_property(env, obj, "title", t);
    napi_set_named_property(env, obj, "artist", a);
    napi_set_named_property(env, obj, "album", al);
    napi_set_named_property(env, obj, "duration", d);
    libvlc_free(title);
    libvlc_free(artist);
    libvlc_free(album);
    return obj;
}

napi_value MediaGetStats(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    MediaEntry *me = FindMediaLocked(h);
    if (me == nullptr || me->media == nullptr) {
        return nullptr;
    }
    libvlc_media_stats_t st = {0};
    int rc = libvlc_media_get_stats(me->media, &st);
    if (rc == 0) {
        OH_LOG_WARN(LOG_APP, "mediaGetStats failed rc=%{public}d handle=%{public}u", rc, h);
        return nullptr;
    }
    napi_value obj;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "readBytes", I64(env, st.i_read_bytes));
    napi_set_named_property(env, obj, "inputBitrate", F64(env, st.f_input_bitrate));
    napi_set_named_property(env, obj, "demuxReadBytes", I64(env, st.i_demux_read_bytes));
    napi_set_named_property(env, obj, "demuxBitrate", F64(env, st.f_demux_bitrate));
    napi_set_named_property(env, obj, "demuxCorrupted", I64(env, st.i_demux_corrupted));
    napi_set_named_property(env, obj, "demuxDiscontinuity", I64(env, st.i_demux_discontinuity));
    napi_set_named_property(env, obj, "decodedVideo", I64(env, st.i_decoded_video));
    napi_set_named_property(env, obj, "decodedAudio", I64(env, st.i_decoded_audio));
    napi_set_named_property(env, obj, "displayedPictures", I64(env, st.i_displayed_pictures));
    napi_set_named_property(env, obj, "lostPictures", I64(env, st.i_lost_pictures));
    napi_set_named_property(env, obj, "playedAbuffers", I64(env, st.i_played_abuffers));
    napi_set_named_property(env, obj, "lostAbuffers", I64(env, st.i_lost_abuffers));
    napi_set_named_property(env, obj, "sentPackets", I64(env, st.i_sent_packets));
    napi_set_named_property(env, obj, "sentBytes", I64(env, st.i_sent_bytes));
    napi_set_named_property(env, obj, "sendBitrate", F64(env, st.f_send_bitrate));
    return obj;
}

napi_value GetProcessUsage(napi_env env, napi_callback_info info)
{
    (void)info;
    long long cpuTicks = 0;
    long long rssKb = 0;
    FILE *f = fopen("/proc/self/stat", "r");
    if (f != nullptr) {
        char line[1024] = {0};
        if (fgets(line, sizeof(line), f) != nullptr) {
            const char *p = strchr(line, ')');
            if (p != nullptr) {
                unsigned long long utime = 0;
                unsigned long long stime = 0;
                int n = sscanf(p + 2,
                    "%*c %*d %*d %*d %*d %*d %*d %*u %*u %*u %*u %llu %llu",
                    &utime, &stime);
                if (n == 2) {
                    cpuTicks = static_cast<long long>(utime + stime);
                }
            }
        }
        fclose(f);
    }
    FILE *f2 = fopen("/proc/self/status", "r");
    if (f2 != nullptr) {
        char line[512] = {0};
        while (fgets(line, sizeof(line), f2) != nullptr) {
            if (strncmp(line, "VmRSS:", 6) == 0) {
                sscanf(line + 6, "%lld", &rssKb);
                break;
            }
        }
        fclose(f2);
    }
    long clkTck = sysconf(_SC_CLK_TCK);
    if (clkTck <= 0) {
        clkTck = 100;
    }
    napi_value obj;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "cpuTicks", I64(env, cpuTicks));
    napi_set_named_property(env, obj, "rssKb", I64(env, rssKb));
    napi_set_named_property(env, obj, "clkTck", I32(env, static_cast<int32_t>(clkTck)));
    return obj;
}

napi_value MediaAddOption(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h)) {
        return Bool(env, false);
    }
    std::string option = GetString(env, argv[1]);
    std::lock_guard<std::mutex> lk(g_mtx);
    MediaEntry *me = FindMediaLocked(h);
    if (me == nullptr || me->media == nullptr || option.empty()) {
        return Bool(env, false);
    }
    libvlc_media_add_option(me->media, option.c_str());
    return Bool(env, true);
}

napi_value MediaAddSlave(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t type = 0;
    int32_t priority = 4;
    if (argc < 3 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &type)) {
        return Bool(env, false);
    }
    std::string uri = GetString(env, argv[2]);
    if (argc >= 4) {
        GetI32(env, argv[3], &priority);
    }
    libvlc_media_t *media = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        MediaEntry *me = FindMediaLocked(h);
        if (me == nullptr || me->media == nullptr) {
            return Bool(env, false);
        }
        media = me->media;
    }
    int rc = libvlc_media_slaves_add(media, static_cast<libvlc_media_slave_type_t>(type),
                                     static_cast<unsigned>(priority), uri.c_str());
    return Bool(env, rc == 0);
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ MediaPlayer 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

void AttachPlayerEventsLocked(uint32_t handle, PlayerEntry &pe)
{
    libvlc_event_manager_t *em = libvlc_media_player_event_manager(pe.mp);
    if (em == nullptr) {
        return;
    }
    auto *user = new uint32_t(handle);
    g_eventUsers[handle] = user;
    const libvlc_event_type_t types[] = {
        libvlc_MediaPlayerPlaying, libvlc_MediaPlayerPaused, libvlc_MediaPlayerStopped,
        libvlc_MediaPlayerEndReached, libvlc_MediaPlayerEncounteredError,
        libvlc_MediaPlayerLengthChanged, libvlc_MediaPlayerTimeChanged,
        libvlc_MediaPlayerPositionChanged, libvlc_MediaPlayerVout,
        libvlc_MediaPlayerBuffering, libvlc_MediaPlayerESAdded,
        libvlc_MediaPlayerESDeleted, libvlc_MediaPlayerESSelected,
    };
    for (auto t : types) {
        libvlc_event_attach(em, t, on_player_event, user);
    }
}

void DetachPlayerEventsLocked(uint32_t handle, PlayerEntry &pe)
{
    if (pe.mp != nullptr) {
        libvlc_event_manager_t *em = libvlc_media_player_event_manager(pe.mp);
        auto it = g_eventUsers.find(handle);
        if (em != nullptr && it != g_eventUsers.end()) {
            const libvlc_event_type_t types[] = {
                libvlc_MediaPlayerPlaying, libvlc_MediaPlayerPaused, libvlc_MediaPlayerStopped,
                libvlc_MediaPlayerEndReached, libvlc_MediaPlayerEncounteredError,
                libvlc_MediaPlayerLengthChanged, libvlc_MediaPlayerTimeChanged,
                libvlc_MediaPlayerPositionChanged, libvlc_MediaPlayerVout,
                libvlc_MediaPlayerBuffering, libvlc_MediaPlayerESAdded,
                libvlc_MediaPlayerESDeleted, libvlc_MediaPlayerESSelected,
            };
            for (auto t : types) {
                libvlc_event_detach(em, t, on_player_event, it->second);
            }
        }
    }
    auto it = g_eventUsers.find(handle);
    if (it != g_eventUsers.end()) {
        delete it->second;
        g_eventUsers.erase(it);
    }
}

napi_value MediaPlayerCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 1 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_player_t *mp = libvlc_media_player_new(lib->inst);
    if (mp == nullptr) {
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    PlayerEntry pe;
    pe.mp = mp;
    pe.libHandle = libH;
    g_players[h] = pe;
    AttachPlayerEventsLocked(h, g_players[h]);
    OH_LOG_INFO(LOG_APP, "mediaPlayerCreate h=%{public}u mp=%{public}p", h, mp);
    return U32(env, h);
}

napi_value MediaPlayerRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_players.find(h);
        if (it == g_players.end()) {
            return nullptr;
        }
        DetachPlayerEventsLocked(h, it->second);
        if (it->second.tsfn) {
            napi_release_threadsafe_function(it->second.tsfn, napi_tsfn_release);
            it->second.tsfn = nullptr;
        }
        if (it->second.jsCallbackRef) {
            napi_delete_reference(env, it->second.jsCallbackRef);
            it->second.jsCallbackRef = nullptr;
        }
        mp = it->second.mp;
        it->second.mp = nullptr;
        g_players.erase(it);
    }
    // release outside lock: may join/stop internally and fire late events
    if (mp != nullptr) {
        libvlc_media_player_release(mp);
    }
    return nullptr;
}

napi_value MediaPlayerReleaseAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_players.find(h);
        if (it == g_players.end()) {
            return nullptr;
        }
        // Do NOT call libvlc_event_detach here: it waits for VLC threads that may be
        // blocked inside event callbacks, freezing the main thread. The event user
        // pointer is intentionally leaked for the async test path.
        if (it->second.tsfn) {
            napi_release_threadsafe_function(it->second.tsfn, napi_tsfn_release);
            it->second.tsfn = nullptr;
        }
        if (it->second.jsCallbackRef) {
            napi_delete_reference(env, it->second.jsCallbackRef);
            it->second.jsCallbackRef = nullptr;
        }
        mp = it->second.mp;
        it->second.mp = nullptr;
        g_players.erase(it);
    }
    if (mp != nullptr) {
        std::thread([mp]() {
            libvlc_media_player_stop(mp);
            libvlc_media_player_release(mp);
        }).detach();
    }
    return nullptr;
}

napi_value MediaPlayerSetEventListener(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h)) {
        return Bool(env, false);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    PlayerEntry *pe = FindPlayerLocked(h);
    if (pe == nullptr) {
        return Bool(env, false);
    }
    if (pe->jsCallbackRef != nullptr) {
        napi_delete_reference(env, pe->jsCallbackRef);
        pe->jsCallbackRef = nullptr;
    }
    if (pe->tsfn != nullptr) {
        napi_release_threadsafe_function(pe->tsfn, napi_tsfn_release);
        pe->tsfn = nullptr;
    }
    napi_valuetype vt;
    napi_typeof(env, argv[1], &vt);
    if (vt != napi_function) {
        return Bool(env, false);
    }
    napi_create_reference(env, argv[1], 1, &pe->jsCallbackRef);
    napi_value resName;
    napi_create_string_utf8(env, "VlcPlayerEvent", NAPI_AUTO_LENGTH, &resName);
    // context = PlayerEntry* so call_js can find callback ref
    napi_create_threadsafe_function(env, argv[1], nullptr, resName, 0, 1, nullptr, tsfn_finalize, pe, call_js,
                                    &pe->tsfn);
    return Bool(env, true);
}

napi_value MediaPlayerSetMedia(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    uint32_t mh = 0;
    if (argc < 2 || !GetU32(env, argv[0], &ph) || !GetU32(env, argv[1], &mh)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    libvlc_media_t *media = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        MediaEntry *me = FindMediaLocked(mh);
        if (pe == nullptr || pe->mp == nullptr || me == nullptr || me->media == nullptr) {
            return Bool(env, false);
        }
        mp = pe->mp;
        media = me->media;
        pe->mediaHandle = mh;
    }
    // Outside g_mtx: set_media can emit media/player events.
    libvlc_media_player_set_media(mp, media);
    return Bool(env, true);
}

napi_value MediaPlayerSetVideoOut(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    if (argc < 2 || !GetU32(env, argv[0], &ph)) {
        return Bool(env, false);
    }
    std::string id = GetString(env, argv[1]);
    libvlc_media_player_t *mp = nullptr;
    OHNativeWindow *win = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        if (pe == nullptr) {
            return Bool(env, false);
        }
        pe->videoOutId = id;
        pe->windowBound = false;
        mp = pe->mp;
        win = xMgr.GetNativeWindow(id);
    }
    if (win == nullptr || mp == nullptr) {
        return Bool(env, false);
    }
    SetOhosNativeWindow(mp, win, id);
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        if (pe != nullptr && pe->videoOutId == id) {
            pe->windowBound = true;
        }
    }
    return Bool(env, true);
}

/** Clear video out for a player handle (Android MediaPlayer.detachViews). */
napi_value MediaPlayerDetachViews(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe == nullptr || pe->mp == nullptr) {
            return nullptr;
        }
        mp = pe->mp;
        pe->windowBound = false;
        pe->videoOutId.clear();
    }
    libvlc_media_player_set_ohos_nativewindow_ptr(mp, nullptr);
    return nullptr;
}

napi_value HasNativeWindow(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool has = false;
    if (argc >= 1) {
        has = xMgr.HasNativeWindow(GetString(env, argv[0]));
    }
    return Bool(env, has);
}

napi_value MediaPlayerPlay(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    OHNativeWindow *pendingWin = nullptr;
    std::string pendingId;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe == nullptr || pe->mp == nullptr) {
            return nullptr;
        }
        mp = pe->mp;
        if (!pe->windowBound && !pe->videoOutId.empty()) {
            pendingId = pe->videoOutId;
            pendingWin = xMgr.GetNativeWindow(pe->videoOutId);
        }
    }
    if (pendingWin != nullptr) {
        SetOhosNativeWindow(mp, pendingWin, pendingId);
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe != nullptr && pe->videoOutId == pendingId) {
            pe->windowBound = true;
        }
    }
    // Call outside g_mtx: play may emit events that re-enter on_player_event → g_mtx.
    libvlc_media_player_play(mp);
    return nullptr;
}

napi_value MediaPlayerPause(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    if (mp != nullptr) {
        libvlc_media_player_set_pause(mp, 1);
    }
    return nullptr;
}

napi_value MediaPlayerStop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    // Must NOT hold g_mtx: stop waits for VLC threads that fire events needing g_mtx.
    if (mp != nullptr) {
        libvlc_media_player_stop(mp);
    }
    return nullptr;
}

napi_value MediaPlayerGetTime(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int64_t t = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            t = libvlc_media_player_get_time(pe->mp);
        }
    }
    return I64(env, t);
}

napi_value MediaPlayerSetTime(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int64_t t = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI64(env, argv[1], &t)) {
        return nullptr;
    }
    // Off UI + outside g_mtx: set_time can block (ISO/DVD) and emits events that need g_mtx
    // (same deadlock class as stop/play: THREAD_BLOCK while Slider → setTime).
    std::thread([h, t]() {
        libvlc_media_player_t *mp = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            PlayerEntry *pe = FindPlayerLocked(h);
            if (pe && pe->mp) {
                mp = pe->mp;
            }
        }
        if (mp != nullptr) {
            libvlc_media_player_set_time(mp, t);
        }
    }).detach();
    return nullptr;
}

napi_value MediaPlayerSetPosition(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double pos = 0.0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetF64(env, argv[1], &pos)) {
        return nullptr;
    }
    // Same async pattern as set_time: position seek on ISO/DVD can block and
    // emits events that require g_mtx.
    std::thread([h, pos]() {
        libvlc_media_player_t *mp = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            PlayerEntry *pe = FindPlayerLocked(h);
            if (pe && pe->mp) {
                mp = pe->mp;
            }
        }
        if (mp != nullptr) {
            libvlc_media_player_set_position(mp, static_cast<float>(pos));
        }
    }).detach();
    return nullptr;
}

napi_value MediaPlayerGetLength(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int64_t t = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            t = libvlc_media_player_get_length(pe->mp);
        }
    }
    return I64(env, t);
}

napi_value MediaPlayerSetRate(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double r = 1.0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetF64(env, argv[1], &r)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    if (mp != nullptr) {
        libvlc_media_player_set_rate(mp, static_cast<float>(r));
    }
    return nullptr;
}

napi_value MediaPlayerGetRate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double r = 1.0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            r = libvlc_media_player_get_rate(pe->mp);
        }
    }
    return F64(env, r);
}

napi_value MediaPlayerSetVolume(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t v = 100;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &v)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    if (mp != nullptr) {
        libvlc_audio_set_volume(mp, v);
    }
    return nullptr;
}

napi_value MediaPlayerGetVolume(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int v = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            v = libvlc_audio_get_volume(pe->mp);
        }
    }
    return I32(env, v);
}

napi_value MediaPlayerGetState(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int s = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            s = static_cast<int>(libvlc_media_player_get_state(pe->mp));
        }
    }
    return I32(env, s);
}

napi_value MediaPlayerGetPosition(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double p = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            p = libvlc_media_player_get_position(pe->mp);
        }
    }
    return F64(env, p);
}

napi_value MediaPlayerGetVideoSize(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    unsigned px = 0;
    unsigned py = 0;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe == nullptr || pe->mp == nullptr) {
            return nullptr;
        }
        if (libvlc_video_get_size(pe->mp, 0, &px, &py) != 0 || px == 0 || py == 0) {
            return nullptr;
        }
    }
    napi_value res;
    napi_create_object(env, &res);
    napi_set_named_property(env, res, "width", U32(env, px));
    napi_set_named_property(env, res, "height", U32(env, py));
    return res;
}

napi_value MediaPlayerGetFps(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return F64(env, 0.0);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe != nullptr) {
            mp = pe->mp;
        }
    }
    return F64(env, mp != nullptr ? libvlc_media_player_get_fps(mp) : 0.0f);
}

napi_value MediaPlayerSetScale(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double f = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetF64(env, argv[1], &f)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    if (mp != nullptr) {
        libvlc_video_set_scale(mp, static_cast<float>(f));
    }
    return nullptr;
}

napi_value MediaPlayerAddSlave(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t type = 0;
    bool select = true;
    if (argc < 3 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &type)) {
        return Bool(env, false);
    }
    std::string uri = GetString(env, argv[2]);
    if (argc >= 4) {
        bool b = true;
        napi_get_value_bool(env, argv[3], &b);
        select = b;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe != nullptr && pe->mp != nullptr) {
            mp = pe->mp;
        }
    }
    if (mp == nullptr) {
        return Bool(env, false);
    }
    int rc = libvlc_media_player_add_slave(mp, static_cast<libvlc_media_slave_type_t>(type),
                                           uri.c_str(), select);
    return Bool(env, rc == 0);
}

napi_value MediaPlayerGetAudioTracks(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    libvlc_track_description_t *desc = nullptr;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            desc = libvlc_audio_get_track_description(pe->mp);
        }
    }
    return TracksToArray(env, desc);
}

napi_value MediaPlayerGetSpuTracks(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    libvlc_track_description_t *desc = nullptr;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            desc = libvlc_video_get_spu_description(pe->mp);
        }
    }
    return TracksToArray(env, desc);
}

napi_value MediaPlayerGetVideoTracks(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    libvlc_track_description_t *desc = nullptr;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            desc = libvlc_video_get_track_description(pe->mp);
        }
    }
    return TracksToArray(env, desc);
}

napi_value MediaPlayerGetAudioTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int id = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            id = libvlc_audio_get_track(pe->mp);
        }
    }
    return I32(env, id);
}

napi_value MediaPlayerGetSpuTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int id = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            id = libvlc_video_get_spu(pe->mp);
        }
    }
    return I32(env, id);
}

napi_value MediaPlayerGetVideoTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int id = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            id = libvlc_video_get_track(pe->mp);
        }
    }
    return I32(env, id);
}

napi_value MediaPlayerSetAudioTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t id = -1;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &id)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_audio_set_track(mp, id) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerSetSpuTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t id = -1;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &id)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_video_set_spu(mp, id) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerSetVideoTrack(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t id = -1;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &id)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_video_set_track(mp, id) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerSetSpuDelay(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int64_t us = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI64(env, argv[1], &us)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_video_set_spu_delay(mp, us) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerGetSpuDelay(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t delay = -1;
    if (argc >= 1) {
        uint32_t h = 0;
        if (GetU32(env, argv[0], &h)) {
            std::lock_guard<std::mutex> lk(g_mtx);
            PlayerEntry *pe = FindPlayerLocked(h);
            if (pe && pe->mp) {
                delay = libvlc_video_get_spu_delay(pe->mp);
            }
        }
    }
    return I64(env, delay);
}

napi_value MediaPlayerSetAudioDelay(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int64_t us = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI64(env, argv[1], &us)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_audio_set_delay(mp, us) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerGetAudioDelay(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t delay = -1;
    if (argc >= 1) {
        uint32_t h = 0;
        if (GetU32(env, argv[0], &h)) {
            std::lock_guard<std::mutex> lk(g_mtx);
            PlayerEntry *pe = FindPlayerLocked(h);
            if (pe && pe->mp) {
                delay = libvlc_audio_get_delay(pe->mp);
            }
        }
    }
    return I64(env, delay);
}

napi_value MediaPlayerGetChapters(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t title = -1;
    napi_value arr;
    napi_create_array(env, &arr);
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return arr;
    }
    if (argc >= 2) {
        GetI32(env, argv[1], &title);
    }
    libvlc_chapter_description_t **chapters = nullptr;
    int count = -1;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            count = libvlc_media_player_get_full_chapter_descriptions(pe->mp, title, &chapters);
        }
    }
    if (count > 0 && chapters != nullptr) {
        for (int i = 0; i < count; ++i) {
            napi_value obj;
            napi_create_object(env, &obj);
            const char *n = chapters[i]->psz_name ? chapters[i]->psz_name : "";
            napi_value name;
            napi_create_string_utf8(env, n, NAPI_AUTO_LENGTH, &name);
            napi_set_named_property(env, obj, "name", name);
            napi_set_named_property(env, obj, "timeOffset", I64(env, chapters[i]->i_time_offset));
            napi_set_named_property(env, obj, "duration", I64(env, chapters[i]->i_duration));
            napi_set_element(env, arr, static_cast<uint32_t>(i), obj);
        }
        libvlc_chapter_descriptions_release(chapters, static_cast<unsigned>(count));
    }
    return arr;
}

napi_value MediaPlayerGetChapter(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int ch = -1;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            ch = libvlc_media_player_get_chapter(pe->mp);
        }
    }
    return I32(env, ch);
}

napi_value MediaPlayerSetChapter(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int32_t ch = 0;
    if (argc < 2 || !GetU32(env, argv[0], &h) || !GetI32(env, argv[1], &ch)) {
        return nullptr;
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(h);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    // Outside g_mtx: chapter change emits player events.
    if (mp != nullptr) {
        libvlc_media_player_set_chapter(mp, ch);
    }
    return nullptr;
}

napi_value MediaPlayerSetRenderer(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    uint32_t rh = 0;
    if (argc < 2 || !GetU32(env, argv[0], &ph) || !GetU32(env, argv[1], &rh)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    libvlc_renderer_item_t *item = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        auto rit = g_renderers.find(rh);
        if (pe && pe->mp && rit != g_renderers.end() && rit->second.item) {
            mp = pe->mp;
            item = rit->second.item;
        }
    }
    bool ok = false;
    if (mp != nullptr && item != nullptr) {
        ok = libvlc_media_player_set_renderer(mp, item) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerClearRenderer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    if (argc < 1 || !GetU32(env, argv[0], &ph)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_media_player_set_renderer(mp, nullptr) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerSetEqualizer(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    uint32_t eh = 0;
    if (argc < 2 || !GetU32(env, argv[0], &ph) || !GetU32(env, argv[1], &eh)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    libvlc_equalizer_t *eq = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        auto eit = g_eqs.find(eh);
        if (pe && pe->mp && eit != g_eqs.end()) {
            mp = pe->mp;
            eq = eit->second.eq;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_media_player_set_equalizer(mp, eq) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaPlayerClearEqualizer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t ph = 0;
    if (argc < 1 || !GetU32(env, argv[0], &ph)) {
        return Bool(env, false);
    }
    libvlc_media_player_t *mp = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        PlayerEntry *pe = FindPlayerLocked(ph);
        if (pe && pe->mp) {
            mp = pe->mp;
        }
    }
    bool ok = false;
    if (mp != nullptr) {
        ok = libvlc_media_player_set_equalizer(mp, nullptr) == 0;
    }
    return Bool(env, ok);
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ Equalizer 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

napi_value EqualizerGetPresetCount(napi_env env, napi_callback_info /*info*/)
{
    return U32(env, libvlc_audio_equalizer_get_preset_count());
}

napi_value EqualizerGetPresetName(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t idx = 0;
    if (argc >= 1) {
        GetU32(env, argv[0], &idx);
    }
    const char *n = libvlc_audio_equalizer_get_preset_name(idx);
    napi_value r;
    napi_create_string_utf8(env, n ? n : "", NAPI_AUTO_LENGTH, &r);
    return r;
}

napi_value EqualizerGetBandCount(napi_env env, napi_callback_info /*info*/)
{
    return U32(env, libvlc_audio_equalizer_get_band_count());
}

napi_value EqualizerGetBandFrequency(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t idx = 0;
    if (argc >= 1) {
        GetU32(env, argv[0], &idx);
    }
    return F64(env, libvlc_audio_equalizer_get_band_frequency(idx));
}

napi_value EqualizerCreate(napi_env env, napi_callback_info /*info*/)
{
    libvlc_equalizer_t *eq = libvlc_audio_equalizer_new();
    if (eq == nullptr) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    uint32_t h = AllocHandleLocked();
    g_eqs[h] = EqEntry{eq};
    return U32(env, h);
}

napi_value EqualizerCreateFromPreset(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t idx = 0;
    if (argc >= 1) {
        GetU32(env, argv[0], &idx);
    }
    libvlc_equalizer_t *eq = libvlc_audio_equalizer_new_from_preset(idx);
    if (eq == nullptr) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    uint32_t h = AllocHandleLocked();
    g_eqs[h] = EqEntry{eq};
    return U32(env, h);
}

napi_value EqualizerRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_eqs.find(h);
        if (it != g_eqs.end()) {
            if (it->second.eq) {
                libvlc_audio_equalizer_release(it->second.eq);
            }
            g_eqs.erase(it);
        }
    }
    return nullptr;
}

napi_value EqualizerSetPreAmp(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double pre = 0;
    bool ok = false;
    if (argc >= 2 && GetU32(env, argv[0], &h) && GetF64(env, argv[1], &pre)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_eqs.find(h);
        if (it != g_eqs.end() && it->second.eq) {
            ok = libvlc_audio_equalizer_set_preamp(it->second.eq, static_cast<float>(pre)) == 0;
        }
    }
    return Bool(env, ok);
}

napi_value EqualizerGetPreAmp(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    double pre = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_eqs.find(h);
        if (it != g_eqs.end() && it->second.eq) {
            pre = libvlc_audio_equalizer_get_preamp(it->second.eq);
        }
    }
    return F64(env, pre);
}

napi_value EqualizerSetAmp(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    uint32_t band = 0;
    double amp = 0;
    bool ok = false;
    if (argc >= 3 && GetU32(env, argv[0], &h) && GetU32(env, argv[1], &band) && GetF64(env, argv[2], &amp)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_eqs.find(h);
        if (it != g_eqs.end() && it->second.eq) {
            ok = libvlc_audio_equalizer_set_amp_at_index(it->second.eq, static_cast<float>(amp), band) == 0;
        }
    }
    return Bool(env, ok);
}

napi_value EqualizerGetAmp(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    uint32_t band = 0;
    double amp = 0;
    if (argc >= 2 && GetU32(env, argv[0], &h) && GetU32(env, argv[1], &band)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_eqs.find(h);
        if (it != g_eqs.end() && it->second.eq) {
            amp = libvlc_audio_equalizer_get_amp_at_index(it->second.eq, band);
        }
    }
    return F64(env, amp);
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ MediaList 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

napi_value MediaListCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 1 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_list_t *list = libvlc_media_list_new(lib->inst);
    if (list == nullptr) {
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    g_lists[h] = MediaListEntry{list};
    return U32(env, h);
}

napi_value MediaListRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_lists.find(h);
        if (it != g_lists.end()) {
            if (it->second.list) {
                libvlc_media_list_release(it->second.list);
            }
            g_lists.erase(it);
        }
    }
    return nullptr;
}

napi_value MediaListCount(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    int c = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_lists.find(h);
        if (it != g_lists.end() && it->second.list) {
            libvlc_media_list_lock(it->second.list);
            c = libvlc_media_list_count(it->second.list);
            libvlc_media_list_unlock(it->second.list);
        }
    }
    return I32(env, c);
}

napi_value MediaListAddMedia(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t lh = 0;
    uint32_t mh = 0;
    bool ok = false;
    if (argc >= 2 && GetU32(env, argv[0], &lh) && GetU32(env, argv[1], &mh)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto lit = g_lists.find(lh);
        MediaEntry *me = FindMediaLocked(mh);
        if (lit != g_lists.end() && lit->second.list && me && me->media) {
            libvlc_media_list_lock(lit->second.list);
            ok = libvlc_media_list_add_media(lit->second.list, me->media) == 0;
            libvlc_media_list_unlock(lit->second.list);
        }
    }
    return Bool(env, ok);
}

napi_value MediaListRemoveIndex(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t lh = 0;
    int32_t idx = 0;
    bool ok = false;
    if (argc >= 2 && GetU32(env, argv[0], &lh) && GetI32(env, argv[1], &idx)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto lit = g_lists.find(lh);
        if (lit != g_lists.end() && lit->second.list) {
            libvlc_media_list_lock(lit->second.list);
            ok = libvlc_media_list_remove_index(lit->second.list, idx) == 0;
            libvlc_media_list_unlock(lit->second.list);
        }
    }
    return Bool(env, ok);
}

napi_value MediaListItemAt(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t lh = 0;
    int32_t idx = 0;
    if (argc < 2 || !GetU32(env, argv[0], &lh) || !GetI32(env, argv[1], &idx)) {
        return U32(env, 0);
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    auto lit = g_lists.find(lh);
    if (lit == g_lists.end() || lit->second.list == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_list_lock(lit->second.list);
    libvlc_media_t *m = libvlc_media_list_item_at_index(lit->second.list, idx);
    libvlc_media_list_unlock(lit->second.list);
    if (m == nullptr) {
        return U32(env, 0);
    }
    // retain already done by item_at_index
    uint32_t h = AllocHandleLocked();
    g_medias[h] = MediaEntry{m, -1, 0};
    return U32(env, h);
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ MediaDiscoverer 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

napi_value MediaDiscovererCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 2 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::string name = GetString(env, argv[1]);
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_discoverer_t *md = libvlc_media_discoverer_new(lib->inst, name.c_str());
    if (md == nullptr) {
        return U32(env, 0);
    }
    libvlc_media_list_t *list = libvlc_media_discoverer_media_list(md);
    uint32_t listH = 0;
    if (list != nullptr) {
        libvlc_media_list_retain(list);
        listH = AllocHandleLocked();
        g_lists[listH] = MediaListEntry{list};
    }
    uint32_t h = AllocHandleLocked();
    g_mds[h] = MediaDiscovererEntry{md, listH};
    return U32(env, h);
}

napi_value MediaDiscovererRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_mds.find(h);
        if (it != g_mds.end()) {
            if (it->second.listHandle != 0) {
                auto lit = g_lists.find(it->second.listHandle);
                if (lit != g_lists.end()) {
                    if (lit->second.list) {
                        libvlc_media_list_release(lit->second.list);
                    }
                    g_lists.erase(lit);
                }
            }
            if (it->second.md) {
                libvlc_media_discoverer_release(it->second.md);
            }
            g_mds.erase(it);
        }
    }
    return nullptr;
}

napi_value MediaDiscovererStart(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return Bool(env, false);
    }
    libvlc_media_discoverer_t *md = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_mds.find(h);
        if (it != g_mds.end() && it->second.md) {
            md = it->second.md;
        }
    }
    bool ok = false;
    if (md != nullptr) {
        ok = libvlc_media_discoverer_start(md) == 0;
    }
    return Bool(env, ok);
}

napi_value MediaDiscovererStop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_media_discoverer_t *md = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_mds.find(h);
        if (it != g_mds.end() && it->second.md) {
            md = it->second.md;
        }
    }
    if (md != nullptr) {
        libvlc_media_discoverer_stop(md);
    }
    return nullptr;
}

napi_value MediaDiscovererMediaList(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    uint32_t listH = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_mds.find(h);
        if (it != g_mds.end()) {
            listH = it->second.listHandle;
        }
    }
    return U32(env, listH);
}

// 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ RendererDiscoverer 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

void on_renderer_event(const struct libvlc_event_t *event, void *user)
{
    auto *box = static_cast<std::pair<uint32_t, RendererDiscovererEntry *> *>(user);
    if (box == nullptr || box->second == nullptr) {
        return;
    }
    uint32_t rdH = box->first;
    RendererDiscovererEntry *rd = box->second;
    if (event->type == libvlc_RendererDiscovererItemAdded) {
        libvlc_renderer_item_t *item = event->u.renderer_discoverer_item_added.item;
        if (item == nullptr) {
            return;
        }
        libvlc_renderer_item_hold(item);
        napi_threadsafe_function tsfn = nullptr;
        uint32_t ih = 0;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            ih = AllocHandleLocked();
            g_renderers[ih] = RendererItemEntry{item, rdH};
            rd->itemHandles.push_back(ih);
            tsfn = rd->tsfn;
        }
        // Outside g_mtx + nonblocking: avoid deadlock with UI thread holding g_mtx.
        if (tsfn) {
            auto *payload = new EventPayload{ih, "rendererItemAdded", static_cast<double>(ih)};
            napi_acquire_threadsafe_function(tsfn);
            napi_status st = napi_call_threadsafe_function(tsfn, payload, napi_tsfn_nonblocking);
            if (st != napi_ok) {
                delete payload;
            }
            napi_release_threadsafe_function(tsfn, napi_tsfn_release);
        }
    } else if (event->type == libvlc_RendererDiscovererItemDeleted) {
        napi_threadsafe_function tsfn = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            tsfn = rd->tsfn;
        }
        if (tsfn) {
            auto *payload = new EventPayload{0, "rendererItemDeleted", 0};
            napi_acquire_threadsafe_function(tsfn);
            napi_status st = napi_call_threadsafe_function(tsfn, payload, napi_tsfn_nonblocking);
            if (st != napi_ok) {
                delete payload;
            }
            napi_release_threadsafe_function(tsfn, napi_tsfn_release);
        }
    }
}

std::unordered_map<uint32_t, std::pair<uint32_t, RendererDiscovererEntry *> *> g_rdEventUsers;

napi_value RendererDiscovererList(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    napi_value arr;
    napi_create_array(env, &arr);
    if (argc < 1 || !GetU32(env, argv[0], &libH)) {
        return arr;
    }
    libvlc_instance_t *inst = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        LibEntry *lib = FindLibLocked(libH);
        if (lib) {
            inst = lib->inst;
        }
    }
    if (inst == nullptr) {
        return arr;
    }
    libvlc_rd_description_t **list = nullptr;
    size_t count = libvlc_renderer_discoverer_list_get(inst, &list);
    for (size_t i = 0; i < count; ++i) {
        napi_value name;
        napi_create_string_utf8(env, list[i]->psz_name ? list[i]->psz_name : "", NAPI_AUTO_LENGTH, &name);
        napi_set_element(env, arr, static_cast<uint32_t>(i), name);
    }
    if (list != nullptr) {
        libvlc_renderer_discoverer_list_release(list, count);
    }
    return arr;
}

napi_value RendererDiscovererCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t libH = 0;
    if (argc < 2 || !GetU32(env, argv[0], &libH)) {
        return U32(env, 0);
    }
    std::string name = GetString(env, argv[1]);
    std::lock_guard<std::mutex> lk(g_mtx);
    LibEntry *lib = FindLibLocked(libH);
    if (lib == nullptr || lib->inst == nullptr) {
        return U32(env, 0);
    }
    libvlc_renderer_discoverer_t *rd = libvlc_renderer_discoverer_new(lib->inst, name.c_str());
    if (rd == nullptr) {
        return U32(env, 0);
    }
    uint32_t h = AllocHandleLocked();
    RendererDiscovererEntry entry;
    entry.rd = rd;
    entry.libHandle = libH;
    g_rds[h] = entry;
    auto *user = new std::pair<uint32_t, RendererDiscovererEntry *>(h, &g_rds[h]);
    g_rdEventUsers[h] = user;
    libvlc_event_manager_t *em = libvlc_renderer_discoverer_event_manager(rd);
    if (em != nullptr) {
        libvlc_event_attach(em, libvlc_RendererDiscovererItemAdded, on_renderer_event, user);
        libvlc_event_attach(em, libvlc_RendererDiscovererItemDeleted, on_renderer_event, user);
    }
    return U32(env, h);
}

napi_value RendererDiscovererRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_rds.find(h);
    if (it == g_rds.end()) {
        return nullptr;
    }
    auto eit = g_rdEventUsers.find(h);
    if (eit != g_rdEventUsers.end() && it->second.rd) {
        libvlc_event_manager_t *em = libvlc_renderer_discoverer_event_manager(it->second.rd);
        if (em) {
            libvlc_event_detach(em, libvlc_RendererDiscovererItemAdded, on_renderer_event, eit->second);
            libvlc_event_detach(em, libvlc_RendererDiscovererItemDeleted, on_renderer_event, eit->second);
        }
        delete eit->second;
        g_rdEventUsers.erase(eit);
    }
    for (uint32_t ih : it->second.itemHandles) {
        auto rit = g_renderers.find(ih);
        if (rit != g_renderers.end()) {
            if (rit->second.item) {
                libvlc_renderer_item_release(rit->second.item);
            }
            g_renderers.erase(rit);
        }
    }
    if (it->second.tsfn) {
        napi_release_threadsafe_function(it->second.tsfn, napi_tsfn_release);
    }
    if (it->second.jsCallbackRef) {
        napi_delete_reference(env, it->second.jsCallbackRef);
    }
    if (it->second.rd) {
        libvlc_renderer_discoverer_release(it->second.rd);
    }
    g_rds.erase(it);
    return nullptr;
}

napi_value RendererDiscovererStart(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return Bool(env, false);
    }
    libvlc_renderer_discoverer_t *rd = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_rds.find(h);
        if (it != g_rds.end() && it->second.rd) {
            rd = it->second.rd;
        }
    }
    bool ok = false;
    // Outside g_mtx: start may synchronously fire ItemAdded → on_renderer_event → g_mtx.
    if (rd != nullptr) {
        ok = libvlc_renderer_discoverer_start(rd) == 0;
    }
    return Bool(env, ok);
}

napi_value RendererDiscovererStop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return nullptr;
    }
    libvlc_renderer_discoverer_t *rd = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_rds.find(h);
        if (it != g_rds.end() && it->second.rd) {
            rd = it->second.rd;
        }
    }
    if (rd != nullptr) {
        libvlc_renderer_discoverer_stop(rd);
    }
    return nullptr;
}

napi_value RendererDiscovererGetItems(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value arr;
    napi_create_array(env, &arr);
    uint32_t h = 0;
    if (argc < 1 || !GetU32(env, argv[0], &h)) {
        return arr;
    }
    std::lock_guard<std::mutex> lk(g_mtx);
    auto it = g_rds.find(h);
    if (it == g_rds.end()) {
        return arr;
    }
    uint32_t idx = 0;
    for (uint32_t ih : it->second.itemHandles) {
        auto rit = g_renderers.find(ih);
        if (rit == g_renderers.end() || rit->second.item == nullptr) {
            continue;
        }
        napi_value obj;
        napi_create_object(env, &obj);
        napi_set_named_property(env, obj, "handle", U32(env, ih));
        const char *n = libvlc_renderer_item_name(rit->second.item);
        const char *t = libvlc_renderer_item_type(rit->second.item);
        napi_value nm;
        napi_value tp;
        napi_create_string_utf8(env, n ? n : "", NAPI_AUTO_LENGTH, &nm);
        napi_create_string_utf8(env, t ? t : "", NAPI_AUTO_LENGTH, &tp);
        napi_set_named_property(env, obj, "name", nm);
        napi_set_named_property(env, obj, "type", tp);
        napi_set_element(env, arr, idx++, obj);
    }
    return arr;
}

napi_value RendererItemRelease(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint32_t h = 0;
    if (argc >= 1 && GetU32(env, argv[0], &h)) {
        std::lock_guard<std::mutex> lk(g_mtx);
        auto it = g_renderers.find(h);
        if (it != g_renderers.end()) {
            if (it->second.item) {
                libvlc_renderer_item_release(it->second.item);
            }
            g_renderers.erase(it);
        }
    }
    return nullptr;
}

void RegisterXComponentIfPresent(napi_env env, napi_value exports)
{
    napi_value xComponentInstance = nullptr;
    napi_status status = napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &xComponentInstance);
    if (status != napi_ok || xComponentInstance == nullptr) {
        return;
    }
    OH_NativeXComponent *nativeXComponent = nullptr;
    status = napi_unwrap(env, xComponentInstance, reinterpret_cast<void **>(&nativeXComponent));
    if (status != napi_ok || nativeXComponent == nullptr) {
        return;
    }
    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return;
    }
    std::string strId(idStr);
    xMgr.AddNativeXcomponent(strId, nativeXComponent);
    xMgr.RegisterCallback(strId);
    xMgr.SetSurfaceReadyCallback(OnSurfaceReady);
    xMgr.SetSurfaceDestroyedCallback(OnSurfaceDestroyed);
}

}  // namespace

napi_value VlcNapiInit(napi_env env, napi_value exports)
{
    OH_LOG_INFO(LOG_APP, "VlcNapiInit enter (handle API)");
    napi_property_descriptor desc[] = {
        {"libvlcCreate", nullptr, LibvlcCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"libvlcRelease", nullptr, LibvlcRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaCreateLocation", nullptr, MediaCreateLocation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaCreatePath", nullptr, MediaCreatePath, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaCreateFd", nullptr, MediaCreateFd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaRelease", nullptr, MediaRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaParse", nullptr, MediaParse, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaGetMeta", nullptr, MediaGetMeta, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaGetStats", nullptr, MediaGetStats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaAddOption", nullptr, MediaAddOption, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaGetTracksInfo", nullptr, MediaGetTracksInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaAddSlave", nullptr, MediaAddSlave, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getProcessUsage", nullptr, GetProcessUsage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerCreate", nullptr, MediaPlayerCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerRelease", nullptr, MediaPlayerRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerReleaseAsync", nullptr, MediaPlayerReleaseAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetEventListener", nullptr, MediaPlayerSetEventListener, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetMedia", nullptr, MediaPlayerSetMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetVideoOut", nullptr, MediaPlayerSetVideoOut, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerDetachViews", nullptr, MediaPlayerDetachViews, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hasNativeWindow", nullptr, HasNativeWindow, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerPlay", nullptr, MediaPlayerPlay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerPause", nullptr, MediaPlayerPause, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerStop", nullptr, MediaPlayerStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetTime", nullptr, MediaPlayerGetTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetTime", nullptr, MediaPlayerSetTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetPosition", nullptr, MediaPlayerSetPosition, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetLength", nullptr, MediaPlayerGetLength, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetRate", nullptr, MediaPlayerSetRate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetRate", nullptr, MediaPlayerGetRate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetVolume", nullptr, MediaPlayerSetVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetVolume", nullptr, MediaPlayerGetVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetState", nullptr, MediaPlayerGetState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetPosition", nullptr, MediaPlayerGetPosition, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetVideoSize", nullptr, MediaPlayerGetVideoSize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetFps", nullptr, MediaPlayerGetFps, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetScale", nullptr, MediaPlayerSetScale, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerAddSlave", nullptr, MediaPlayerAddSlave, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetAudioTracks", nullptr, MediaPlayerGetAudioTracks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetSpuTracks", nullptr, MediaPlayerGetSpuTracks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetVideoTracks", nullptr, MediaPlayerGetVideoTracks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetAudioTrack", nullptr, MediaPlayerGetAudioTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetSpuTrack", nullptr, MediaPlayerGetSpuTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetVideoTrack", nullptr, MediaPlayerGetVideoTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetAudioTrack", nullptr, MediaPlayerSetAudioTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetSpuTrack", nullptr, MediaPlayerSetSpuTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetVideoTrack", nullptr, MediaPlayerSetVideoTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetSpuDelay", nullptr, MediaPlayerSetSpuDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetSpuDelay", nullptr, MediaPlayerGetSpuDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetAudioDelay", nullptr, MediaPlayerSetAudioDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetAudioDelay", nullptr, MediaPlayerGetAudioDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetChapters", nullptr, MediaPlayerGetChapters, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerGetChapter", nullptr, MediaPlayerGetChapter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetChapter", nullptr, MediaPlayerSetChapter, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetRenderer", nullptr, MediaPlayerSetRenderer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerClearRenderer", nullptr, MediaPlayerClearRenderer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerSetEqualizer", nullptr, MediaPlayerSetEqualizer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaPlayerClearEqualizer", nullptr, MediaPlayerClearEqualizer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetPresetCount", nullptr, EqualizerGetPresetCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetPresetName", nullptr, EqualizerGetPresetName, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetBandCount", nullptr, EqualizerGetBandCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetBandFrequency", nullptr, EqualizerGetBandFrequency, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerCreate", nullptr, EqualizerCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerCreateFromPreset", nullptr, EqualizerCreateFromPreset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerRelease", nullptr, EqualizerRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerSetPreAmp", nullptr, EqualizerSetPreAmp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetPreAmp", nullptr, EqualizerGetPreAmp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerSetAmp", nullptr, EqualizerSetAmp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"equalizerGetAmp", nullptr, EqualizerGetAmp, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListCreate", nullptr, MediaListCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListRelease", nullptr, MediaListRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListCount", nullptr, MediaListCount, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListAddMedia", nullptr, MediaListAddMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListRemoveIndex", nullptr, MediaListRemoveIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaListItemAt", nullptr, MediaListItemAt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaDiscovererCreate", nullptr, MediaDiscovererCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaDiscovererRelease", nullptr, MediaDiscovererRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaDiscovererStart", nullptr, MediaDiscovererStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaDiscovererStop", nullptr, MediaDiscovererStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"mediaDiscovererMediaList", nullptr, MediaDiscovererMediaList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererList", nullptr, RendererDiscovererList, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererCreate", nullptr, RendererDiscovererCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererRelease", nullptr, RendererDiscovererRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererStart", nullptr, RendererDiscovererStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererStop", nullptr, RendererDiscovererStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererDiscovererGetItems", nullptr, RendererDiscovererGetItems, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"rendererItemRelease", nullptr, RendererItemRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
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
