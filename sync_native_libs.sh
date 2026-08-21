#!/usr/bin/env bash
# 将 ohos_vlc / dist 中的预编译 so 同步到 vlc-harmony。
# 优先从 ohos_vlc/library/libs(已解引用的真实 ELF)复制;缺失时回退 dist。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OHOS_LIBS="${ROOT_DIR}/ohos_vlc/library/libs/arm64-v8a"
DIST_USR="${ROOT_DIR}/dist/usr"
DEST_LIBS="${ROOT_DIR}/entry/libs/arm64-v8a"
DEST_LINK="${ROOT_DIR}/entry/src/main/cpp/third_party/libvlc/arm64-v8a"

mkdir -p "$DEST_LIBS" "$DEST_LINK"

if [[ -d "$OHOS_LIBS" && -f "$OHOS_LIBS/libvlc.so.5" && -f "$OHOS_LIBS/libvlccore.so.9" ]]; then
  echo "Sync runtime libs from ohos_vlc: $OHOS_LIBS"
  rm -rf "$DEST_LIBS"
  mkdir -p "$DEST_LIBS"
  cp -a "$OHOS_LIBS"/. "$DEST_LIBS"/
  cp -fL "$OHOS_LIBS/libvlc.so.5" "$DEST_LINK/libvlc.so"
  cp -fL "$OHOS_LIBS/libvlccore.so.9" "$DEST_LINK/libvlccore.so"
  cp -fL "$OHOS_LIBS/libvlc.so.5" "$DEST_LINK/libvlc.so.5"
  cp -fL "$OHOS_LIBS/libvlccore.so.9" "$DEST_LINK/libvlccore.so.9"
else
  echo "ohos_vlc libs missing, fallback to dist (dereference versioned ELF)"
  mkdir -p "$DEST_LIBS"
  # shellcheck disable=SC2043
  for pair in \
    "vlc/arm64-v8a/lib/libvlc.so.5.6.1:libvlc.so.5" \
    "vlc/arm64-v8a/lib/libvlccore.so.9.0.1:libvlccore.so.9" \
    "a52dec/arm64-v8a/lib/liba52.so.0:liba52.so.0" \
    "aribb24/arm64-v8a/lib/libaribb24.so.0:libaribb24.so.0" \
    "FFmpeg/arm64-v8a/lib/libavcodec.so.60:libavcodec.so.60" \
    "FFmpeg/arm64-v8a/lib/libavformat.so.60:libavformat.so.60" \
    "FFmpeg/arm64-v8a/lib/libavutil.so.58:libavutil.so.58" \
    "libdca/arm64-v8a/lib/libdca.so.0:libdca.so.0" \
    "libkate/arm64-v8a/lib/libkate.so.1:libkate.so.1" \
    "libpng/arm64-v8a/lib/libpng16.so.16:libpng16.so.16" \
    "speex/arm64-v8a/lib/libspeex.so.1:libspeex.so.1" \
    "speexdsp/arm64-v8a/lib/libspeexdsp.so.1:libspeexdsp.so.1" \
    "FFmpeg/arm64-v8a/lib/libswresample.so.4:libswresample.so.4" \
    "FFmpeg/arm64-v8a/lib/libswscale.so.7:libswscale.so.7" \
    "libtheora/arm64-v8a/lib/libtheoradec.so.1:libtheoradec.so.1" \
    "libtheora/arm64-v8a/lib/libtheoraenc.so.1:libtheoraenc.so.1" \
    "dav1d/arm64-v8a/lib/libdav1d.so.7:libdav1d.so.7" \
    "lame/arm64-v8a/lib/libmp3lame.so.0:libmp3lame.so.0" \
    "openh264/arm64-v8a/lib/libopenh264.so.8:libopenh264.so.8" \
    "zlib/arm64-v8a/lib/libz.so.1:libz.so.1"
  do
    src="${DIST_USR}/${pair%%:*}"
    dst_name="${pair##*:}"
    # Prefer fully-versioned real ELF if symlink-sized
    if [[ -f "$src" ]]; then
      cp -fL "$src" "$DEST_LIBS/$dst_name" 2>/dev/null || cp -f "$src" "$DEST_LIBS/$dst_name"
    else
      echo "WARN missing $src"
    fi
  done
  cp -a "${DIST_USR}/vlc/arm64-v8a/lib/vlc" "$DEST_LIBS/"
  cp -fL "${DIST_USR}/vlc/arm64-v8a/lib/libvlc.so.5.6.1" "$DEST_LINK/libvlc.so"
  cp -fL "${DIST_USR}/vlc/arm64-v8a/lib/libvlccore.so.9.0.1" "$DEST_LINK/libvlccore.so"
  cp -f "$DEST_LINK/libvlc.so" "$DEST_LINK/libvlc.so.5"
  cp -f "$DEST_LINK/libvlccore.so" "$DEST_LINK/libvlccore.so.9"
fi

echo "Done."
echo "  runtime: $DEST_LIBS"
echo "  link:    $DEST_LINK"
ls -la "$DEST_LINK"
ls "$DEST_LIBS/vlc/plugins/video_output" | grep ohos || true
