#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

VLC_REPO=https://gitcode.com/OpenHarmony-ApplicationTPC/ohos_vlc.git
VLC_BRANCH=ohos-3.0.21
VLC_COMMIT=14a0483eb294e62305e596dc0d158c74e6a04cc9
VLC_PATCH=$ROOT_DIR/patches/0000-vlc-ffmpeg8-ohcodec-consolidated.patch
VLC_REALTIME_PATCH=$ROOT_DIR/patches/0010-vlc-ohos-realtime-audio-ring.patch
VLC_SYSTEM_REFRESH_PATCH=$ROOT_DIR/patches/0011-vlc-ohos-system-refresh-low-latency-audio.patch
FFMPEG_SYSTEM_REFRESH_PATCH=$ROOT_DIR/patches/0011-ffmpeg-ohcodec-system-refresh.patch

FFMPEG_REPO=https://github.com/FFmpeg/FFmpeg.git
FFMPEG_TAG=n8.1.2
FFMPEG_COMMIT=38b88335f99e76ed89ff3c93f877fdefce736c13
OHCODEC_PATCH_REPO=https://github.com/Yebingiscn/libmpv-ohos-ErBW_s-5en.git
OHCODEC_PATCH_COMMIT=54f298cddd162f459ed49e58974e3b8e763db177

bash -n "$ROOT_DIR/prebuild.sh"
bash -n "$ROOT_DIR/recipes/brotli-v1.0.9.HPKBUILD"
bash -n "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
bash -n "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q 'invalidate_restored_native_outputs' "$ROOT_DIR/prebuild.sh"
grep -q 'rm -rf -- "$cached_vlc_dir"' "$ROOT_DIR/prebuild.sh"
grep -q 'rm -rf -- "$cached_ffmpeg_dir"' "$ROOT_DIR/prebuild.sh"
grep -q "sed -i '/\^vlc,/d'" "$ROOT_DIR/prebuild.sh"
grep -q "sed -i '/\^FFmpeg,/d'" "$ROOT_DIR/prebuild.sh"
grep -q "source_commit=$VLC_COMMIT" "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '"openssl_3.4.3"' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
if grep -q 'openssl-3.4.0' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
then
    echo "ERROR: VLC recipe still references legacy OpenSSL 3.4.0"
    exit 1
fi

clone_with_retry() {
    local destination=$1
    shift
    local attempt
    for attempt in 1 2 3
    do
        rm -rf "$destination"
        if git clone --quiet "$@" "$destination"
        then
            return 0
        fi
        echo "Clone attempt $attempt failed: $destination" >&2
        sleep $((attempt * 5))
    done
    return 1
}

fetch_with_retry() {
    local repository=$1
    shift
    local attempt
    for attempt in 1 2 3
    do
        if git -C "$repository" fetch --quiet "$@"
        then
            return 0
        fi
        echo "Fetch attempt $attempt failed: $repository" >&2
        sleep $((attempt * 5))
    done
    return 1
}

clone_with_retry "$WORK_DIR/vlc" --depth=1 --branch "$VLC_BRANCH" "$VLC_REPO"
test "$(git -C "$WORK_DIR/vlc" rev-parse HEAD)" = "$VLC_COMMIT"

# The FFmpeg compatibility patch may use VLC public identifiers, but it must
# not assume APIs from a newer VLC branch. Catch that mismatch during the
# inexpensive preflight instead of after the full native dependency build.
grep '^+[^+]' "$VLC_PATCH" |
    grep -oE 'VLC_[A-Z][A-Z0-9_]*|vlc_[A-Za-z][A-Za-z0-9_]*' |
    sort -u > "$WORK_DIR/added-vlc-identifiers.txt" || true
while IFS= read -r identifier
do
    if ! git -C "$WORK_DIR/vlc" grep -q -F "$identifier" HEAD
    then
        echo "ERROR: consolidated VLC patch references an identifier absent from VLC 3.0.21: $identifier"
        exit 1
    fi
done < "$WORK_DIR/added-vlc-identifiers.txt"

git -C "$WORK_DIR/vlc" apply --check "$VLC_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_REALTIME_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_REALTIME_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_SYSTEM_REFRESH_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_SYSTEM_REFRESH_PATCH"

grep -q 'AUDIO_RING_CAPACITY' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'SetRendererWriteDataCallbackAdvanced' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'Audio low-latency queue configured' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'OHCodec surface presentation uses system refresh' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
if grep -qE '16666667|ohos_frame_period_ns' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
then
    echo "ERROR: VLC OHCodec presentation still contains a fixed 60 Hz cadence"
    exit 1
fi
if grep -q 'audio_buffer_t' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
then
    echo "ERROR: VLC OHAudio still uses the per-block linked-list queue"
    exit 1
fi
if grep -q '\[OHOS-DBG\] frame received:' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
then
    echo "ERROR: VLC still logs every decoded video frame"
    exit 1
fi

if git -C "$WORK_DIR/vlc" grep -E \
    'ohosavcodec|OHOSAVCodec|AV_PIX_FMT_OHOSCODEC|ohos_picture_context' -- \
    modules/codec/avcodec/avcodec.c modules/codec/avcodec/chroma.c \
    modules/codec/avcodec/video.c
then
    echo "ERROR: consolidated VLC patch leaves legacy OHOS FFmpeg APIs behind"
    exit 1
fi

clone_with_retry "$WORK_DIR/ffmpeg" --depth=1 --branch "$FFMPEG_TAG" "$FFMPEG_REPO"
test "$(git -C "$WORK_DIR/ffmpeg" rev-parse HEAD)" = "$FFMPEG_COMMIT"
clone_with_retry "$WORK_DIR/ohcodec-patches" --filter=blob:none --no-checkout \
    "$OHCODEC_PATCH_REPO"
fetch_with_retry "$WORK_DIR/ohcodec-patches" --depth=1 origin "$OHCODEC_PATCH_COMMIT"
git -C "$WORK_DIR/ohcodec-patches" checkout --quiet --detach "$OHCODEC_PATCH_COMMIT"
test "$(git -C "$WORK_DIR/ohcodec-patches" rev-parse HEAD)" = "$OHCODEC_PATCH_COMMIT"

for patch_name in \
    0002-ffmpeg-support-OHCodec-zero-copy-decode.patch \
    0003-ffmpeg-tune-OHCodec-decoder-frame-rate.patch \
    0006-avcodec-ohcodec-auto-vrr-smart-fluency.patch \
    0007-avcodec-ohcodec-fix-buffer-ownership-and-input-splitting.patch \
    0009-avcodec-ohcodec-preserve-dovi-metadata.patch \
    0010-avcodec-ohcodec-gate-dovi-metadata-parsing.patch
do
    patch_file="$WORK_DIR/ohcodec-patches/patches/ffmpeg/$patch_name"
    git -C "$WORK_DIR/ffmpeg" apply --check "$patch_file"
    git -C "$WORK_DIR/ffmpeg" apply "$patch_file"
done

git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_SYSTEM_REFRESH_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_SYSTEM_REFRESH_PATCH"

grep -q 'ohcodec_buffer.h' "$WORK_DIR/ffmpeg/libavcodec/Makefile"
grep -q 'av_ohcodec_release_buffer_at_time' "$WORK_DIR/ffmpeg/libavcodec/ohcodec_buffer.h"
grep -q 'avcodec_ohcodec_set_playback_speed' "$WORK_DIR/ffmpeg/libavcodec/avcodec.h"
grep -q 'direct_surface' "$WORK_DIR/ffmpeg/libavutil/hwcontext_oh.h"
grep -q 'refresh-rate=system-managed' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
if grep -qE 'OH_MD_KEY_FRAME_RATE|OUTPUT_ENABLE_VRR|source_frame_rate' \
    "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
then
    echo "ERROR: FFmpeg OHCodec still forces a decoder frame rate or VRR mode"
    exit 1
fi

echo "Native VLC/FFmpeg patch preflight passed."
