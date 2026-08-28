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
VLC_SURFACE_BACKPRESSURE_PATCH=$ROOT_DIR/patches/0012-vlc-ohcodec-surface-backpressure.patch
VLC_SURFACE_PTS_PATCH=$ROOT_DIR/patches/0013-vlc-ohcodec-use-frame-pts.patch
VLC_VSYNC_PRESENT_PATCH=$ROOT_DIR/patches/0014-vlc-ohcodec-vsync-present.patch
VLC_DEADLINE_PRESENT_PATCH=$ROOT_DIR/patches/0015-vlc-ohcodec-deadline-gated-present.patch
VLC_BUFFER_OUTPUT_PATCH=$ROOT_DIR/patches/0016-vlc-ohcodec-respect-direct-rendering.patch
VLC_LIVE_RESIZE_PATCH=$ROOT_DIR/patches/0017-vlc-ohos-live-window-resize.patch
VLC_OPUS_AUDIO_PATCH=$ROOT_DIR/patches/0018-vlc-ffmpeg8-opus-audio-init.patch
VLC_LIBOPUS_PATCH=$ROOT_DIR/patches/0019-vlc-ohos-prefer-libopus-decoder.patch
FFMPEG_SYSTEM_REFRESH_PATCH=$ROOT_DIR/patches/0011-ffmpeg-ohcodec-system-refresh.patch
FFMPEG_STALL_DIAGNOSTICS_PATCH=$ROOT_DIR/patches/0012-ffmpeg-ohcodec-stall-diagnostics.patch
FFMPEG_FRAME_PTS_PATCH=$ROOT_DIR/patches/0013-ffmpeg-ohcodec-propagate-frame-pts.patch
FFMPEG_PTS_FALLBACK_PATCH=$ROOT_DIR/patches/0014-ffmpeg-ohcodec-pts-fallback.patch
FFMPEG_BOUNDED_OUTPUT_PATCH=$ROOT_DIR/patches/0015-ffmpeg-ohcodec-bounded-output-queue.patch
FFMPEG_OUTPUT_OFFSET_PATCH=$ROOT_DIR/patches/0016-ffmpeg-ohcodec-respect-output-offset.patch
FFMPEG_P010_BUFFER_PATCH=$ROOT_DIR/patches/0017-ffmpeg-ohcodec-handle-p010-buffer-output.patch
FFMPEG_SYNTHETIC_PTS_PATCH=$ROOT_DIR/patches/0018-ffmpeg-ohcodec-synthesize-missing-timestamps.patch

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
grep -q 'patches/0013-vlc-ohcodec-use-frame-pts.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0013-ffmpeg-ohcodec-propagate-frame-pts.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0014-vlc-ohcodec-vsync-present.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0015-vlc-ohcodec-deadline-gated-present.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0016-vlc-ohcodec-respect-direct-rendering.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0017-vlc-ohos-live-window-resize.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0018-vlc-ffmpeg8-opus-audio-init.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0019-vlc-ohos-prefer-libopus-decoder.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0014-ffmpeg-ohcodec-pts-fallback.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0015-ffmpeg-ohcodec-bounded-output-queue.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0016-ffmpeg-ohcodec-respect-output-offset.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0017-ffmpeg-ohcodec-handle-p010-buffer-output.patch' "$ROOT_DIR/prebuild.sh"
grep -q 'patches/0018-ffmpeg-ohcodec-synthesize-missing-timestamps.patch' "$ROOT_DIR/prebuild.sh"
grep -q '0014-vlc-ohcodec-vsync-present.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0015-vlc-ohcodec-deadline-gated-present.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0016-vlc-ohcodec-respect-direct-rendering.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0017-vlc-ohos-live-window-resize.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0018-vlc-ffmpeg8-opus-audio-init.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0019-vlc-ohos-prefer-libopus-decoder.patch' "$ROOT_DIR/recipes/vlc-ffmpeg8.HPKBUILD"
grep -q '0014-ffmpeg-ohcodec-pts-fallback.patch' "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
grep -q '0015-ffmpeg-ohcodec-bounded-output-queue.patch' "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
grep -q '0016-ffmpeg-ohcodec-respect-output-offset.patch' "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
grep -q '0017-ffmpeg-ohcodec-handle-p010-buffer-output.patch' "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
grep -q '0018-ffmpeg-ohcodec-synthesize-missing-timestamps.patch' "$ROOT_DIR/recipes/ffmpeg-8.1.2.HPKBUILD"
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
git -C "$WORK_DIR/vlc" apply --check "$VLC_SURFACE_BACKPRESSURE_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_SURFACE_BACKPRESSURE_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_SURFACE_PTS_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_SURFACE_PTS_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_VSYNC_PRESENT_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_VSYNC_PRESENT_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_DEADLINE_PRESENT_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_DEADLINE_PRESENT_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_BUFFER_OUTPUT_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_BUFFER_OUTPUT_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_LIVE_RESIZE_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_LIVE_RESIZE_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_OPUS_AUDIO_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_OPUS_AUDIO_PATCH"
git -C "$WORK_DIR/vlc" apply --check "$VLC_LIBOPUS_PATCH"
git -C "$WORK_DIR/vlc" apply "$VLC_LIBOPUS_PATCH"

grep -q 'AUDIO_RING_CAPACITY' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'SetRendererWriteDataCallbackAdvanced' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'Audio low-latency queue configured' \
    "$WORK_DIR/vlc/modules/audio_output/audiounit_ohos.c"
grep -q 'OHCodec Surface uses deadline-gated immediate release' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'OHCodec Buffer output enabled for VLC subtitle composition' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'var_InheritBool(p_dec, "avcodec-dr")' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'codec->id == AV_CODEC_ID_OPUS && ctx->sample_rate <= 0' \
    "$WORK_DIR/vlc/modules/codec/avcodec/audio.c"
grep -q 'p_dec->fmt_in.audio.i_channels > 0' \
    "$WORK_DIR/vlc/modules/codec/avcodec/audio.c"
grep -q 'cannot start codec (%s): %s (%d)' \
    "$WORK_DIR/vlc/modules/codec/avcodec/avcodec.c"
grep -q 'avcodec_find_decoder_by_name( "libopus" )' \
    "$WORK_DIR/vlc/modules/codec/avcodec/avcodec.c"
if grep -q 'VLC_TICK_FROM_MS' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
then
    echo "VLC 3.0.21 compatibility error: VLC_TICK_FROM_MS is unavailable" >&2
    exit 1
fi
grep -q 'OHCodec output stalled' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'av_ohcodec_release_buffer(buffer, 0)' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'const int ret = av_ohcodec_release_buffer(buffer, 1)' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'i_pts = frame->pts' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
grep -q 'p_context->pkt_timebase = AV_TIME_BASE_Q' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
if grep -qE '16666667|ohos_frame_period_ns' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
then
    echo "ERROR: VLC OHCodec presentation still contains a fixed 60 Hz cadence"
    exit 1
fi
if grep -q 'av_ohcodec_release_buffer_at_time(buffer' \
    "$WORK_DIR/vlc/modules/codec/avcodec/video.c"
then
    echo "ERROR: VLC OHCodec still queues future-dated Surface buffers"
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
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_STALL_DIAGNOSTICS_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_STALL_DIAGNOSTICS_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_FRAME_PTS_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_FRAME_PTS_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_PTS_FALLBACK_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_PTS_FALLBACK_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_BOUNDED_OUTPUT_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_BOUNDED_OUTPUT_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_OUTPUT_OFFSET_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_OUTPUT_OFFSET_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_P010_BUFFER_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_P010_BUFFER_PATCH"
git -C "$WORK_DIR/ffmpeg" apply --check "$FFMPEG_SYNTHETIC_PTS_PATCH"
git -C "$WORK_DIR/ffmpeg" apply "$FFMPEG_SYNTHETIC_PTS_PATCH"

grep -q 'ohcodec_buffer.h' "$WORK_DIR/ffmpeg/libavcodec/Makefile"
grep -q 'av_ohcodec_release_buffer_at_time' "$WORK_DIR/ffmpeg/libavcodec/ohcodec_buffer.h"
grep -q 'avcodec_ohcodec_set_playback_speed' "$WORK_DIR/ffmpeg/libavcodec/avcodec.h"
grep -q 'direct_surface' "$WORK_DIR/ffmpeg/libavutil/hwcontext_oh.h"
grep -q 'refresh-rate=system-managed' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q '\[OHCodecStall\] callback=output' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'best_effort_timestamp = frame->pts' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q '\[OHCodecPTS\] output timestamp fallback' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q '\[OHCodecQueue\] bounded backlog' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'OH_SURFACE_MAX_QUEUED_OUTPUTS 3' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q '\[OHCodecWatchdog\] consumer idle=' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'OH_SURFACE_MAX_PENDING_INPUTS 6' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'p += attr->offset' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'Invalid OHCodec output layout' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 's->bit_depth > 8 ? AV_PIX_FMT_P010' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'layout_width /= 2' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q 'pkt->pts != AV_NOPTS_VALUE ? pkt->pts : pkt->dts' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
grep -q '\[OHCodecPTS\] synthesized missing packet timestamp' "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
if grep -qE 'OH_MD_KEY_FRAME_RATE|OUTPUT_ENABLE_VRR|source_frame_rate' \
    "$WORK_DIR/ffmpeg/libavcodec/ohdec.c"
then
    echo "ERROR: FFmpeg OHCodec still forces a decoder frame rate or VRR mode"
    exit 1
fi

echo "Native VLC/FFmpeg patch preflight passed."
