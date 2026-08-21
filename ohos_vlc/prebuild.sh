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
API_VERSION=18 # 三方库对应API版本，用于记录SDK路径,必须和"compileSdkVersion"字段表示的API版本保持一致
SDK_DIR=$OHOS_SDK_HOME/$API_VERSION # SDK路径（流水线环境中SDK路径）
LYCIUM_TOOLS_URL=https://gitcode.com/openharmony-sig/tpc_c_cplusplus.git
LYCIUM_ROOT_DIR=$ROOT_DIR/tpc_c_cplusplus
LYCIUM_TOOLS_DIR=$LYCIUM_ROOT_DIR/lycium
LYCIUM_THIRDPARTY_DIR=$LYCIUM_ROOT_DIR/thirdparty
LYCIUM_COMMUNITY_DIR=$LYCIUM_ROOT_DIR/community

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
    cp -f "$ROOT_DIR/patches/0001-avcodec-respect-disabled-hardware-decoding.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0002-avcodec-fallback-to-software-on-hw-start-failure.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0003-vcd-mode1-2048-iso.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0004-bluray-seek-fix.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0005-vcd-iso9660-no-cue.patch" "$vlc_recipe_dir/"
    cp -f "$ROOT_DIR/patches/0007-vlc-ohos-surface-clocked-present.patch" "$vlc_recipe_dir/"
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
    cp -f "$ROOT_DIR/patches/0006-ohosavcodec-seek-safety-and-input-pacing.patch" "$ffmpeg_recipe_dir/"
    patch -d "$ffmpeg_recipe_dir" -p1 < "$ROOT_DIR/patches/ffmpeg-hpkbuild-apply-local-patches.patch"
    return $?
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
    cp -f $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavcodec.so.60 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavformat.so.60 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libavutil.so.58 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libdca/arm64-v8a/lib/libdca.so.0 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libkate/arm64-v8a/lib/libkate.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/libpng/arm64-v8a/lib/libpng16.so.16 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/speex/arm64-v8a/lib/libspeex.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/speexdsp/arm64-v8a/lib/libspeexdsp.so.1 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libswresample.so.4 "$install_dir"
    cp -f $LYCIUM_TOOLS_DIR/usr/FFmpeg/arm64-v8a/lib/libswscale.so.7 "$install_dir"
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
