#include "xcomponent_manager.h"

#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x6C63  // 'lc'
#define LOG_TAG "VlcXComp"

XcomponentManager &XcomponentManager::GetInstance()
{
    static XcomponentManager instance;
    return instance;
}

void XcomponentManager::SetSurfaceReadyCallback(SurfaceReadyFn cb)
{
    std::unique_lock<std::mutex> lock(mtx_);
    surfaceReadyCb_ = cb;
}

XcomponentManager::SurfaceReadyFn XcomponentManager::GetSurfaceReadyCallback()
{
    std::unique_lock<std::mutex> lock(mtx_);
    return surfaceReadyCb_;
}

void XcomponentManager::SetSurfaceDestroyedCallback(SurfaceDestroyedFn cb)
{
    std::unique_lock<std::mutex> lock(mtx_);
    surfaceDestroyedCb_ = cb;
}

XcomponentManager::SurfaceDestroyedFn XcomponentManager::GetSurfaceDestroyedCallback()
{
    std::unique_lock<std::mutex> lock(mtx_);
    return surfaceDestroyedCb_;
}

int32_t XcomponentManager::RegisterCallback(OH_NativeXComponent *nativeXComponent)
{
    callback_.OnSurfaceCreated = Callbacks::OnSurfaceCreatedCB;
    callback_.OnSurfaceChanged = Callbacks::OnSurfaceChangedCB;
    callback_.OnSurfaceDestroyed = Callbacks::OnSurfaceDestroyedCB;
    callback_.DispatchTouchEvent = Callbacks::OnDispatchTouchEventCB;
    int32_t ret = OH_NativeXComponent_RegisterCallback(nativeXComponent, &callback_);
    OH_LOG_INFO(LOG_APP, "RegisterCallback component=%{public}p ret=%{public}d", nativeXComponent, ret);
    // Do not force a fixed refresh range. HarmonyOS can select the display
    // cadence from the decoded stream, playback speed and device VRR policy.
    return ret;
}

int32_t XcomponentManager::RegisterCallback(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    auto it = nativeXcomponentMap_.find(id);
    if (it == nativeXcomponentMap_.end()) {
        OH_LOG_ERROR(LOG_APP, "RegisterCallback: id=%{public}s not found", id.c_str());
        return -1;
    }
    OH_NativeXComponent *nativeXComponent = it->second;
    lock.unlock();
    return RegisterCallback(nativeXComponent);
}

void XcomponentManager::Callbacks::OnDispatchTouchEventCB(OH_NativeXComponent * /*component*/, void * /*window*/) {}

void XcomponentManager::Callbacks::OnSurfaceChangedCB(OH_NativeXComponent *component, void *window)
{
    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
    uint64_t len = OH_XCOMPONENT_ID_LEN_MAX;
    int32_t ret = OH_NativeXComponent_GetXComponentId(component, id, &len);
    OH_LOG_INFO(LOG_APP, "OnSurfaceChanged id=%{public}s ret=%{public}d win=%{public}p",
                ret == OH_NATIVEXCOMPONENT_RESULT_SUCCESS ? id : "?", ret, window);
    if (ret == OH_NATIVEXCOMPONENT_RESULT_SUCCESS && window != nullptr) {
        // 尺寸变化时刷新 window 登记(缩放适配会改 XComponent 宽高)
        uint64_t generation = xMgr.AddNativeWindow(id, reinterpret_cast<OHNativeWindow *>(window), false);
        XcomponentManager::SurfaceReadyFn cb = xMgr.GetSurfaceReadyCallback();
        if (cb != nullptr) {
            cb(std::string(id), reinterpret_cast<OHNativeWindow *>(window), generation);
        }
    }
}

void XcomponentManager::Callbacks::OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window)
{
    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
    uint64_t len = OH_XCOMPONENT_ID_LEN_MAX;
    int32_t ret = OH_NativeXComponent_GetXComponentId(component, id, &len);
    if (ret != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "OnSurfaceCreated GetXComponentId failed ret=%{public}d", ret);
        return;
    }
    OH_LOG_INFO(LOG_APP, "OnSurfaceCreated id=%{public}s win=%{public}p", id, window);
    uint64_t generation = xMgr.AddNativeWindow(id, reinterpret_cast<OHNativeWindow *>(window), true);

    XcomponentManager::SurfaceReadyFn cb = xMgr.GetSurfaceReadyCallback();
    if (cb != nullptr) {
        cb(std::string(id), reinterpret_cast<OHNativeWindow *>(window), generation);
    }
}

void XcomponentManager::Callbacks::OnSurfaceDestroyedCB(OH_NativeXComponent *component, void * /*window*/)
{
    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
    uint64_t len = OH_XCOMPONENT_ID_LEN_MAX;
    int32_t ret = OH_NativeXComponent_GetXComponentId(component, id, &len);
    if (ret != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "OnSurfaceDestroyed GetXComponentId failed ret=%{public}d", ret);
        return;
    }
    OH_LOG_INFO(LOG_APP, "OnSurfaceDestroyed id=%{public}s", id);
    XcomponentManager::SurfaceDestroyedFn cb = xMgr.GetSurfaceDestroyedCallback();
    if (cb != nullptr) {
        cb(std::string(id));
    }
    // XComponent 本身仍然有效，后续可能用同一个 id 创建新的 Surface。
    // 只移除失效的 NativeWindow，保留组件和 generation 以识别重建。
    xMgr.ReleaseWindow(id);
}

int32_t XcomponentManager::AddNativeXcomponent(const std::string &id, OH_NativeXComponent *nativeXComponent)
{
    std::unique_lock<std::mutex> lock(mtx_);
    OH_LOG_INFO(LOG_APP, "AddNativeXcomponent id=%{public}s xc=%{public}p", id.c_str(), nativeXComponent);
    nativeXcomponentMap_[id] = nativeXComponent;
    return 0;
}

uint64_t XcomponentManager::AddNativeWindow(const std::string &id, OHNativeWindow *win, bool newSurface)
{
    std::unique_lock<std::mutex> lock(mtx_);
    uint64_t &generation = surfaceGenerationMap_[id];
    if (newSurface || generation == 0) {
        ++generation;
    }
    OH_LOG_INFO(LOG_APP, "AddNativeWindow id=%{public}s win=%{public}p generation=%{public}llu",
                id.c_str(), win, static_cast<unsigned long long>(generation));
    OHNativeWindowMap_[id] = win;
    return generation;
}

OH_NativeXComponent *XcomponentManager::GetNativeXcomponent(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    auto item = nativeXcomponentMap_.find(id);
    if (item == nativeXcomponentMap_.end()) {
        OH_LOG_WARN(LOG_APP, "GetNativeXcomponent miss id=%{public}s", id.c_str());
        return nullptr;
    }
    return item->second;
}

OHNativeWindow *XcomponentManager::GetNativeWindow(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    auto item = OHNativeWindowMap_.find(id);
    if (item == OHNativeWindowMap_.end()) {
        OH_LOG_WARN(LOG_APP, "GetNativeWindow miss id=%{public}s (surface not ready?)", id.c_str());
        return nullptr;
    }
    return item->second;
}

uint64_t XcomponentManager::GetSurfaceGeneration(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    auto item = surfaceGenerationMap_.find(id);
    return item == surfaceGenerationMap_.end() ? 0 : item->second;
}

bool XcomponentManager::HasNativeWindow(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    return OHNativeWindowMap_.find(id) != OHNativeWindowMap_.end();
}

void XcomponentManager::ReleaseWindow(const std::string &id)
{
    std::unique_lock<std::mutex> lock(mtx_);
    OH_LOG_INFO(LOG_APP, "ReleaseWindow id=%{public}s", id.c_str());
    OHNativeWindowMap_.erase(id);
}
