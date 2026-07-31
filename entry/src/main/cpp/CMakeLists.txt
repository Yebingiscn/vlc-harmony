# HarmonyOS NAPI 模块:libVLC → ArkTS 桥(+ XComponent NativeWindow)。
cmake_minimum_required(VERSION 3.5.0)
project(libvlcnapi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(VLC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvlc/arm64-v8a)

include_directories(
  ${NATIVERENDER_ROOT_PATH}
  ${VLC_ROOT}/include
)

# 预编译 libVLC(链接用 so 放在 third_party;运行时 so/插件放在 entry/libs/arm64-v8a)。
add_library(vlc SHARED IMPORTED)
set_target_properties(vlc PROPERTIES IMPORTED_LOCATION ${VLC_ROOT}/libvlc.so)
add_library(vlccore SHARED IMPORTED)
set_target_properties(vlccore PROPERTIES IMPORTED_LOCATION ${VLC_ROOT}/libvlccore.so)

add_library(vlcnapi SHARED
  vlc_napi.cpp
  xcomponent_manager.cpp
)

find_library(ace_napi ace_napi.z)
find_library(ace_ndk ace_ndk.z)
find_library(native_window native_window)
find_library(hilog_lib hilog_ndk.z)

target_link_libraries(vlcnapi PUBLIC
  ${ace_napi}
  ${ace_ndk}
  ${native_window}
  ${hilog_lib}
  vlc
  vlccore
)
