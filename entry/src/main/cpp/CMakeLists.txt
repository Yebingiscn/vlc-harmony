# HarmonyOS NAPI 模块:libVLC → ArkTS 桥。
cmake_minimum_required(VERSION 3.5.0)
project(libvlcnapi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(VLC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvlc/arm64-v8a)

include_directories(
  ${NATIVERENDER_ROOT_PATH}
  ${VLC_ROOT}/include
)

# 预编译 libVLC 共享库(IMPORTED,仅链接,不重新编译)。
add_library(vlc SHARED IMPORTED)
set_target_properties(vlc PROPERTIES IMPORTED_LOCATION ${VLC_ROOT}/libvlc.so)
add_library(vlccore SHARED IMPORTED)
set_target_properties(vlccore PROPERTIES IMPORTED_LOCATION ${VLC_ROOT}/libvlccore.so)

add_library(vlcnapi SHARED vlc_napi.cpp)

find_library(ace_napi ace_napi.z)

target_link_libraries(vlcnapi PUBLIC
  ${ace_napi}
  vlc
  vlccore
)
