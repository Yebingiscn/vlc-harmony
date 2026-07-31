#pragma once

#include <mutex>
#include <string>
#include <unordered_map>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_window/external_window.h>

class XcomponentManager {
public:
    static XcomponentManager &GetInstance();

    int32_t RegisterCallback(const std::string &id);
    int32_t AddNativeXcomponent(const std::string &id, OH_NativeXComponent *nativeXComponent);
    int32_t AddNativeWindow(const std::string &id, OHNativeWindow *win);
    OH_NativeXComponent *GetNativeXcomponent(const std::string &id);
    OHNativeWindow *GetNativeWindow(const std::string &id);
    bool HasNativeWindow(const std::string &id);
    void Release(const std::string &id);

    /** Surface 创建后回调(用于窗口就绪后自动绑到 libVLC)。 */
    using SurfaceReadyFn = void (*)(const std::string &id, OHNativeWindow *win);
    void SetSurfaceReadyCallback(SurfaceReadyFn cb);
    SurfaceReadyFn GetSurfaceReadyCallback();

private:
    class Callbacks {
    public:
        static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window);
        static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window);
        static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window);
        static void OnDispatchTouchEventCB(OH_NativeXComponent *component, void *window);
    };
    int32_t RegisterCallback(OH_NativeXComponent *nativeXComponent);

    OH_NativeXComponent_Callback callback_ {};
    std::mutex mtx_;
    std::unordered_map<std::string, OH_NativeXComponent *> nativeXcomponentMap_;
    std::unordered_map<std::string, OHNativeWindow *> OHNativeWindowMap_;
    SurfaceReadyFn surfaceReadyCb_ {nullptr};
};

#define xMgr XcomponentManager::GetInstance()
