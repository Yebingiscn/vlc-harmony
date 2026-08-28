#!/bin/bash

# Copyright (c) 2024 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# 执行该脚本时需进入到脚本所在目录
ROOT_DIR=$(pwd)
API_VERSION=26 # 使用 HarmonyOS 7.0 Beta1 API 26 NDK，与 OHCodec 补丁声明保持一致
SDK_DIR=$OHOS_SDK_HOME/$API_VERSION # SDK路径（流水线环境中SDK路径）
LYCIUM_TOOLS_URL=https://gitcode.com/openharmony-sig/tpc_c_cplusplus.git
LYCIUM_TOOLS_COMMIT=4de021fc105228135ba6f5ab74661fbbf857113f
LYCIUM_ROOT_DIR=$ROOT_DIR/tpc_c_cplusplus
LYCIUM_TOOLS_DIR=$LYCIUM_ROOT_DIR/lycium
LYCIUM_THIRDPARTY_DIR=$LYCIUM_ROOT_DIR/thirdparty
LYCIUM_COMMUNITY_DIR=$LYCIUM_ROOT_DIR/community
FFMPEG_OHCODEC_PATCH_REPO=https://github.com/Yebingiscn/libmpv-ohos-ErBW_s-5en.git
FFMPEG_OHCODEC_PATCH_COMMIT=54f298cddd162f459ed49e58974e3b8e763db177

function git_clone_with_retry()
{
    local destination=$1
    shift
    local attempt
    for attempt in 1 2 3
    do
        rm -rf "$destination"
        if git clone "$@" "$destination"
        then
            return 0
        fi
        echo "Clone attempt $attempt failed: $destination"
        sleep $((attempt * 5))
    done
    return 1
}

function git_fetch_with_retry()
{
    local repository=$1
    shift
    local attempt
    for attempt in 1 2 3
    do
        if git -C "$repository" fetch "$@"
        then
            return 0
        fi
        echo "Fetch attempt $attempt failed: $repository"
        sleep $((attempt * 5))
    done
    return 1
}

function prepare_lycium_tools()
{
    local commands=("gcc" "make" "cmake" "pkg-config" "autoconf" "autoreconf" "automake" "patch" "libtool" "autopoint" "gperf" \
    "tcl8.6-dev" "wget" "unzip" "gccgo-go" "flex " "bison" "premake4" "python3" "python3-pip" \
    "ninja-build" "meson" "sox" "gfortran" "subversion" "build-essential" "module-assistant" " gcc-multilib" \
    "g++-multilib" "libltdl7-dev" "cabextract" "libboost-all-dev" "libxml2-utils" "gettext" "libxml-libxml-perl" \
    "libxml2" "libxml2-dev" "libxml-parser-perl" "texinfo" "libtool-bin" "xmlto" "po4a" "yasm" "nasm" "xutils-dev" \
    "libx11-dev" "xtrans-dev" "gfortran-arm-linux-gnueabi" "gfortran-aarch64-linux-gnu")

    apt update >> /dev/null

    for cmd in ${commands[@]}
    do
        which $cmd >> /dev/null
        if [ $? -ne 0 ]
        then
            echo "install $cmd"
            apt install $cmd -y >> /dev/null
        fi
    done
}

function prepare_lycium()
{
    local restored_usr_dir=
    if [ -d "$LYCIUM_TOOLS_DIR/usr" ]
    then
        restored_usr_dir=$(mktemp -d)/usr
        mv "$LYCIUM_TOOLS_DIR/usr" "$restored_usr_dir"
    fi

    if [ -d $LYCIUM_ROOT_DIR ]
    then
        rm -rf $LYCIUM_ROOT_DIR
    fi

    git_clone_with_retry $LYCIUM_ROOT_DIR --filter=blob:none --no-checkout $LYCIUM_TOOLS_URL
    if [ $? -ne 0 ]
    then
        return 1
    fi
    git_fetch_with_retry $LYCIUM_ROOT_DIR --depth=1 origin $LYCIUM_TOOLS_COMMIT || return 1
    git -C $LYCIUM_ROOT_DIR checkout --detach $LYCIUM_TOOLS_COMMIT || return 1
    if [ "$(git -C $LYCIUM_ROOT_DIR rev-parse HEAD)" != "$LYCIUM_TOOLS_COMMIT" ]
    then
        echo "ERROR: Lycium resolved to an unexpected commit"
        return 1
    fi

    if [ -n "$restored_usr_dir" ]
    then
        rm -rf "$LYCIUM_TOOLS_DIR/usr"
        mv "$restored_usr_dir" "$LYCIUM_TOOLS_DIR/usr"
        rmdir "$(dirname "$restored_usr_dir")"
    fi

    cd $LYCIUM_TOOLS_DIR/Buildtools
    tar -zxvf toolchain.tar.gz
    if [ $? -ne 0 ]
    then
        echo "unpack sdk toolchain failed!!"
        cd $OLDPWD
        return 1
    fi

    cp toolchain/* $SDK_DIR/native/llvm/bin/

    prepare_lycium_tools
    ret=$?
    cd $OLDPWD

    return $ret
}

function configure_lycium_build()
{
    local a52_recipe="$LYCIUM_COMMUNITY_DIR/a52dec/HPKBUILD"
    local fribidi_recipe="$LYCIUM_THIRDPARTY_DIR/fribidi/HPKBUILD"
    local openssl_recipe="$LYCIUM_COMMUNITY_DIR/openssl_3.4.3/HPKBUILD"
    local zlib_recipe="$LYCIUM_THIRDPARTY_DIR/zlib/HPKBUILD"
    local zlib_checksum="$LYCIUM_THIRDPARTY_DIR/zlib/SHA512SUM"
    local recipe

    # The application only ships arm64-v8a libraries. Avoid building unused
    # arm32/x86_64 variants of every transitive dependency.
    while IFS= read -r -d '' recipe
    do
        if grep -Eq '^[[:space:]]*archs=.*"arm64-v8a"' "$recipe"
        then
            sed -i -E 's/^[[:space:]]*archs=.*/archs=("arm64-v8a")/' "$recipe"
        fi
    done < <(find "$LYCIUM_THIRDPARTY_DIR" "$LYCIUM_COMMUNITY_DIR" -type f -name HPKBUILD -print0)

    # The original Adelie mirror is unavailable and GStreamer's mirror can
    # intermittently return 503. MIT's MacPorts mirror contains the exact same
    # archive and still matches Lycium's committed SHA-512.
    sed -i \
        's#https://distfiles.adelielinux.org/source/$pkgname/#https://mirrors.mit.edu/macports/distfiles/a52dec/#' \
        "$a52_recipe"
    if ! grep -Fq \
        'source="https://mirrors.mit.edu/macports/distfiles/a52dec/$pkgname-$pkgver.tar.gz"' \
        "$a52_recipe"
    then
        echo "ERROR: patch a52dec download source failed!!!"
        return 1
    fi

    # Keep one zlib provider in the dependency graph.
    sed -i 's/depends=(zlib_1_3_1)/depends=(zlib)/' "$openssl_recipe"
    if ! grep -Fq 'depends=(zlib)' "$openssl_recipe"
    then
        echo "ERROR: upgrade OpenSSL dependency failed!!!"
        return 1
    fi

    # FriBidi 1.0.12 generates a shared version header from several recursive
    # targets. Parallel generators can truncate that header while host tools
    # are compiling, so serialize both its host helper and target build.
    sed -i \
        -e 's/\$MAKE VERBOSE=1 >> \$buildlog 2>\&1/env -u MAKE make -j1 VERBOSE=1 >> \$buildlog 2>\&1/g' \
        -e 's/\$MAKE VERBOSE=1 >> "\$buildlog" 2>\&1/env -u MAKE make -j1 VERBOSE=1 >> "\$buildlog" 2>\&1/g' \
        "$fribidi_recipe"
    if [ "$(grep -Fc 'env -u MAKE make -j1 VERBOSE=1' "$fribidi_recipe")" -ne 2 ] ||
        grep -Fq '$MAKE VERBOSE=1 >>' "$fribidi_recipe"
    then
        echo "ERROR: disable parallel FriBidi build failed!!!"
        return 1
    fi

    # zlib.net currently serves an HTML error page for its 1.3.2 fossils URL.
    # Use the upstream project's GitHub release asset and pin its SHA-512.
    if ! grep -Fq 'pkgver=1.3.2' "$zlib_recipe"
    then
        echo "ERROR: unsupported zlib recipe version!!!"
        return 1
    fi
    sed -i \
        's#https://$pkgname.net/fossils/$pkgname-$pkgver.tar.gz#https://github.com/madler/zlib/releases/download/v$pkgver/$pkgname-$pkgver.tar.gz#' \
        "$zlib_recipe"
    printf '%s  %s\n' \
        '70963771ea5d763614278a69b474f09b7d237ef8f53b675a10fe31d9923aeef601504b35d7ebd1b1e7f347e9ebb048e6b3b47fffdf137e7bdc7e8d5eb4ec4692' \
        'zlib-1.3.2.tar.gz' > "$zlib_checksum"
    if ! grep -Fq \
        'source="https://github.com/madler/zlib/releases/download/v$pkgver/$pkgname-$pkgver.tar.gz"' \
        "$zlib_recipe"
    then
        echo "ERROR: patch zlib download source failed!!!"
        return 1
    fi

    return 0
}

function copy_depends()
{
    local dir="$1"
    local name="$2"

    if [ -d "$LYCIUM_THIRDPARTY_DIR/$name" ]
    then
        rm -rf "$LYCIUM_THIRDPARTY_DIR/$name"
    fi
    cp -arf "$dir/$name" "$LYCIUM_THIRDPARTY_DIR/"
}

function check_sdk()
{
    if [ ! -d $SDK_DIR ]
    then
        return 1
    fi

    export OHOS_SDK=$SDK_DIR
    return 0
}

function check_copy_shasum()
{
    local libpath=$1
    local pack_name=$2
    local libname=$3

    cd $LYCIUM_THIRDPARTY_DIR/$libpath
    if [ ! -f ./SHA512SUM ]
    then
        sha512sum $pack_name > ./SHA512SUM
    fi
    cp ./SHA512SUM $LYCIUM_TOOLS_DIR/usr/$libname/

    cd $OLDPWD
}

function install_shasum()
{
    return 0
}

function start_build()
{
    local result=0
    cd $LYCIUM_TOOLS_DIR
    if [ $? -ne 0 ]
    then
        return 1
    fi

    bash build.sh vlc
    result=$?
    cd $OLDPWD
    return $result
}

function install_vlc_patches()
{
    local vlc_recipe_dir=$LYCIUM_THIRDPARTY_DIR/vlc

    cp -f "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD" "$vlc_recipe_dir/HPKBUILD" || return 1
    cp -f "$ROOT_DIR/patches/0000-vlc-ffmpeg8-ohcodec-consolidated.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0010-vlc-ohos-realtime-audio-ring.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0011-vlc-ohos-system-refresh-low-latency-audio.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0012-vlc-ohcodec-surface-backpressure.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0013-vlc-ohcodec-use-frame-pts.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0014-vlc-ohcodec-vsync-present.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0015-vlc-ohcodec-deadline-gated-present.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0016-vlc-ohcodec-respect-direct-rendering.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0017-vlc-ohos-live-window-resize.patch" "$vlc_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0018-vlc-ffmpeg8-opus-audio-init.patch" "$vlc_recipe_dir/" || return 1
    return 0
}

function invalidate_restored_native_outputs()
{
    local cached_vlc_dir=$LYCIUM_TOOLS_DIR/usr/vlc
    local cached_ffmpeg_dir=$LYCIUM_TOOLS_DIR/usr/FFmpeg
    local build_record=$LYCIUM_TOOLS_DIR/usr/hpk_build.csv

    # The dependency checkpoint is intentionally shared between native-build
    # runs, but older checkpoints also contain the final FFmpeg/VLC installs.
    # Lycium uses hpk_build.csv, rather than the installation directory, as
    # the authoritative completed-package list. Invalidate each patched leaf
    # so the current local sources are compiled while preserving other deps.
    if [ -f "$build_record" ]
    then
        sed -i '/^vlc,/d' "$build_record"
        sed -i '/^FFmpeg,/d' "$build_record"
    fi
    if [ -d "$cached_vlc_dir" ]
    then
        echo "Removing restored VLC output so the current patch set is rebuilt"
        rm -rf -- "$cached_vlc_dir"
    fi
    if [ -d "$cached_ffmpeg_dir" ]
    then
        echo "Removing restored FFmpeg output so the current patch set is rebuilt"
        rm -rf -- "$cached_ffmpeg_dir"
    fi
}

function install_ffmpeg_patches()
{
    local ffmpeg_recipe_dir=$LYCIUM_COMMUNITY_DIR/FFmpeg-surface-dev
    local patch_source_dir=$LYCIUM_ROOT_DIR/libmpv-ohos-patches

    cp -f "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD" "$ffmpeg_recipe_dir/HPKBUILD"
    cp -f "$ROOT_DIR/recipes/brotli-v1.0.9.HPKBUILD" "$LYCIUM_COMMUNITY_DIR/brotli/HPKBUILD"
    git_clone_with_retry "$patch_source_dir" --filter=blob:none --depth=1 --no-checkout \
        "$FFMPEG_OHCODEC_PATCH_REPO"
    if [ $? -ne 0 ]; then
        return 1
    fi
    git_fetch_with_retry "$patch_source_dir" --depth=1 origin "$FFMPEG_OHCODEC_PATCH_COMMIT"
    git -C "$patch_source_dir" checkout --detach "$FFMPEG_OHCODEC_PATCH_COMMIT"
    if [ "$(git -C "$patch_source_dir" rev-parse HEAD)" != "$FFMPEG_OHCODEC_PATCH_COMMIT" ]; then
        echo "ERROR: OHCodec patch source commit verification failed!!!"
        return 1
    fi

    local patch_name
    for patch_name in \
        0002-ffmpeg-support-OHCodec-zero-copy-decode.patch \
        0003-ffmpeg-tune-OHCodec-decoder-frame-rate.patch \
        0006-avcodec-ohcodec-auto-vrr-smart-fluency.patch \
        0007-avcodec-ohcodec-fix-buffer-ownership-and-input-splitting.patch \
        0009-avcodec-ohcodec-preserve-dovi-metadata.patch \
        0010-avcodec-ohcodec-gate-dovi-metadata-parsing.patch
    do
        cp -f "$patch_source_dir/patches/ffmpeg/$patch_name" "$ffmpeg_recipe_dir/" || return 1
    done
    cp -f "$ROOT_DIR/patches/0011-ffmpeg-ohcodec-system-refresh.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0012-ffmpeg-ohcodec-stall-diagnostics.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0013-ffmpeg-ohcodec-propagate-frame-pts.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0014-ffmpeg-ohcodec-pts-fallback.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0015-ffmpeg-ohcodec-bounded-output-queue.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0016-ffmpeg-ohcodec-respect-output-offset.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0017-ffmpeg-ohcodec-handle-p010-buffer-output.patch" "$ffmpeg_recipe_dir/" || return 1
    cp -f "$ROOT_DIR/patches/0018-ffmpeg-ohcodec-synthesize-missing-timestamps.patch" "$ffmpeg_recipe_dir/" || return 1
    return 0
}

function install_depends()
{
    mkdir -p $ROOT_DIR/library/libs/arm64-v8a/
    local install_dir=$ROOT_DIR/library/libs/arm64-v8a/
    cp -arf $LYCIUM_TOOLS_DIR/usr/vlc/arm64-v8a/lib/vlc "$install_dir"
    cp -fL $LYCIUM_TOOLS_DIR/usr/vlc/arm64-v8a/lib/libvlc.so.5 "$install_dir/libvlc.so.5"
    cp -fL $LYCIUM_TOOLS_DIR/usr/vlc/arm64-v8a/lib/libvlccore.so.9 "$install_dir/libvlccore.so.9"
    cp -f $LYCIUM_TOOLS_DIR/usr/a52dec/arm64-v8a/lib/liba52.so.0 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/aribb24/arm64-v8a/lib/libaribb24.so.0 "$install_dir"
    cp -fL $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavcodec.so.62 "$install_dir/libavcodec.so.62"
    cp -fL $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavformat.so.62 "$install_dir/libavformat.so.62"
    cp -fL $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavutil.so.60 "$install_dir/libavutil.so.60"
    cp -f $LYCIUM_TOOLS_DIR/usr/libdca/arm64-v8a/lib/libdca.so.0 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libkate/arm64-v8a/lib/libkate.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libpng/arm64-v8a/lib/libpng16.so.16 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/speex/arm64-v8a/lib/libspeex.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/speexdsp/arm64-v8a/lib/libspeexdsp.so.1 "$install_dir"
    cp -fL $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libswresample.so.6 "$install_dir/libswresample.so.6"
    cp -fL $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libswscale.so.9 "$install_dir/libswscale.so.9"
    cp -f $LYCIUM_TOOLS_DIR/usr/libtheora/arm64-v8a/lib/libtheoradec.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libtheora/arm64-v8a/lib/libtheoraenc.so.1 "$install_dir"
    # Transitive deps of libavcodec.so (required for h264/aac decode)
    cp -f $LYCIUM_TOOLS_DIR/usr/dav1d/arm64-v8a/lib/libdav1d.so.7 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/lame/arm64-v8a/lib/libmp3lame.so.0 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/openh264/arm64-v8a/lib/libopenh264.so.8 "$install_dir"
    # Opus, Ogg and Vorbis recipes produce static archives for HarmonyOS.
    # They are linked into their consumers and therefore have no runtime .so
    # files to copy into the HAP.
    cp -f $LYCIUM_TOOLS_DIR/usr/libxml2/arm64-v8a/lib/libxml2.so.2 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/xz/arm64-v8a/lib/liblzma.so.5 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/openssl_3.4.3/arm64-v8a/lib/libssl.so.3 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/openssl_3.4.3/arm64-v8a/lib/libcrypto.so.3 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/zlib/arm64-v8a/lib/libz.so.1 "$install_dir"

    local runtime_lib
    while IFS= read -r runtime_lib
    do
        if [ -n "$runtime_lib" ] && [ ! -s "$install_dir/$runtime_lib" ]
        then
            echo "ERROR: required runtime library was not installed: $runtime_lib"
            return 1
        fi
    done < "$ROOT_DIR/runtime-libs-arm64.txt"

    mkdir -p $ROOT_DIR/library/src/main/cpp/thirdpart/include/
    cp -arf $LYCIUM_TOOLS_DIR/usr/vlc/arm64-v8a/include/* $ROOT_DIR/library/src/main/cpp/thirdpart/include/
    return 0
}

function prebuild()
{
    check_sdk
    if [ $? -ne 0 ]
    then
        echo "ERROR: check_sdk failed!!!"
        return 1
    fi
    prepare_lycium
    if [ $? -ne 0 ]
    then
        echo "ERROR: prepare_lycium failed!!!"
        return 1
    fi

    configure_lycium_build
    if [ $? -ne 0 ]
    then
        echo "ERROR: configure Lycium build failed!!!"
        return 1
    fi

    install_ffmpeg_patches
    if [ $? -ne 0 ]
    then
        echo "ERROR: install ffmpeg patches failed!!!"
        return 1
    fi

    install_vlc_patches
    if [ $? -ne 0 ]
    then
        echo "ERROR: install vlc patches failed!!!"
        return 1
    fi

    invalidate_restored_native_outputs

    start_build
    if [ $? -ne 0 ]
    then
        echo "ERROR: start_build failed!!!"
        return 1
    fi

    install_depends
    if [ $? -ne 0 ]
    then
        echo "ERROR: install depends failed!!!"
        return 1
    fi

    if [ -f "$ROOT_DIR/../sync_native_libs.sh" ]
    then
        bash "$ROOT_DIR/../sync_native_libs.sh"
        if [ $? -ne 0 ]
        then
            echo "ERROR: sync native libs failed!!!"
            return 1
        fi
    fi
    echo "prebuild success!!"
    return 0
}

prebuild $*
ret=$?
echo "ret = $ret"
exit $ret

#EOF
