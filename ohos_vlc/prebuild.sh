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
LYCIUM_ROOT_DIR=$ROOT_DIR/tpc_c_cplusplus
LYCIUM_TOOLS_DIR=$LYCIUM_ROOT_DIR/lycium
LYCIUM_THIRDPARTY_DIR=$LYCIUM_ROOT_DIR/thirdparty
LYCIUM_COMMUNITY_DIR=$LYCIUM_ROOT_DIR/community
FFMPEG_OHCODEC_PATCH_REPO=https://github.com/Yebingiscn/libmpv-ohos-ErBW_s-5en.git
FFMPEG_OHCODEC_PATCH_COMMIT=54f298cddd162f459ed49e58974e3b8e763db177
VLC_UPSTREAM_REPO=https://github.com/videolan/vlc.git
VLC_UPSTREAM_BASE_TAG=3.0.21
VLC_UPSTREAM_COMPAT_COMMIT=1089af38fc26293d0b93a9456adf7ae4a5b0b930

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
    if [ -d $LYCIUM_ROOT_DIR ]
    then
        rm -rf $LYCIUM_ROOT_DIR
    fi

    git clone $LYCIUM_TOOLS_URL --depth=1
    if [ $? -ne 0 ]
    then
        return 1
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
    local vlc_recipe="$LYCIUM_THIRDPARTY_DIR/vlc/HPKBUILD"
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

    # Use the maintained OpenSSL 3.4.3 recipe for both FFmpeg and VLC, and keep
    # one zlib provider in the dependency graph.
    sed -i 's/depends=(zlib_1_3_1)/depends=(zlib)/' "$openssl_recipe"
    sed -i \
        -e 's/"openssl-3.4.0"/"openssl_3.4.3"/' \
        -e 's#usr/openssl-3.4.0/#usr/openssl_3.4.3/#g' \
        "$vlc_recipe"
    if ! grep -Fq '"openssl_3.4.3"' "$vlc_recipe" ||
        grep -Fq 'openssl-3.4.0' "$vlc_recipe" ||
        ! grep -Fq 'depends=(zlib)' "$openssl_recipe"
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
    local upstream_source_dir=$LYCIUM_ROOT_DIR/vlc-upstream-compat

    git clone --filter=blob:none --depth=1 --no-checkout "$VLC_UPSTREAM_REPO" "$upstream_source_dir"
    if [ $? -ne 0 ]; then
        return 1
    fi
    git -C "$upstream_source_dir" fetch --depth=1 origin \
        "refs/tags/$VLC_UPSTREAM_BASE_TAG:refs/tags/$VLC_UPSTREAM_BASE_TAG" || return 1
    git -C "$upstream_source_dir" fetch --depth=1 origin \
        "$VLC_UPSTREAM_COMPAT_COMMIT" || return 1
    if [ "$(git -C "$upstream_source_dir" rev-parse FETCH_HEAD)" != "$VLC_UPSTREAM_COMPAT_COMMIT" ]; then
        echo "ERROR: VLC compatibility source commit verification failed!!!"
        return 1
    fi
    git -C "$upstream_source_dir" diff --binary \
        --output="$vlc_recipe_dir/0000-vlc-upstream-ffmpeg8-compat.patch" \
        "$VLC_UPSTREAM_BASE_TAG" "$VLC_UPSTREAM_COMPAT_COMMIT" -- \
        modules/codec/avcodec modules/demux/avformat || return 1

    cp -f "$ROOT_DIR/patches/0000-vlc-remove-legacy-ohos-chroma.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0006-vlc-add-ffmpeg8-ohcodec-chroma.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0001-avcodec-respect-disabled-hardware-decoding.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0002-avcodec-fallback-to-software-on-hw-start-failure.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0003-vcd-mode1-2048-iso.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0004-bluray-seek-fix.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0005-vcd-iso9660-no-cue.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0007-vlc-ohos-surface-clocked-present.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0008-vlc-ffmpeg8-ohcodec-device-context.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0009-vlc-forward-playback-speed-to-ohcodec.patch" "$vlc_recipe_dir/"
    patch -d "$vlc_recipe_dir" -p1 < "$ROOT_DIR/patches/vlc-hpkbuild-apply-local-patches.patch"
    if [ $? -ne 0 ]; then
        return 1
    fi
    patch -d "$vlc_recipe_dir" -p0 < "$ROOT_DIR/patches/vlc-hpkbuild-build-dvbpsi.patch"
    return $?
}

function install_ffmpeg_patches()
{
    local ffmpeg_recipe_dir=$LYCIUM_COMMUNITY_DIR/FFmpeg-surface-dev
    local patch_source_dir=$LYCIUM_ROOT_DIR/libmpv-ohos-patches

    cp -f "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD" "$ffmpeg_recipe_dir/HPKBUILD"
    cp -f "$ROOT_DIR/recipes/brotli-v1.0.9.HPKBUILD" "$LYCIUM_COMMUNITY_DIR/brotli/HPKBUILD"
    git clone --filter=blob:none --depth=1 --no-checkout "$FFMPEG_OHCODEC_PATCH_REPO" "$patch_source_dir"
    if [ $? -ne 0 ]; then
        return 1
    fi
    git -C "$patch_source_dir" fetch --depth=1 origin "$FFMPEG_OHCODEC_PATCH_COMMIT"
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
    cp -f $LYCIUM_TOOLS_DIR/usr/zlib/arm64-v8a/lib/libz.so.1 "$install_dir"

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
