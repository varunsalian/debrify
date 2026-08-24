#!/usr/bin/env bash
#
# Build the private Linux libmpv used by Debrify's AppImage.
#
# mpv-build statically links FFmpeg, libass and libplacebo into libmpv.  The
# result deliberately keeps the host boundary at Linux desktop ABIs (OpenGL,
# VA-API, X11/Wayland, Pulse/ALSA, fonts and libc) instead of copying a distro's
# entire ldd closure into the AppImage.
#
# Run this on Linux. Both x86_64 and aarch64 are built natively by their GitHub
# Actions runners.
#
# Usage: scripts/build_linux_libmpv.sh <output-directory>

set -euo pipefail

OUTPUT_ARG="${1:?usage: $0 <output-directory>}"
case "$OUTPUT_ARG" in
  /*) OUTPUT="$OUTPUT_ARG" ;;
  *) OUTPUT="$(pwd)/$OUTPUT_ARG" ;;
esac

case "$(uname -s)" in
  Linux) ;;
  *) echo "error: private libmpv must be built on Linux" >&2; exit 1 ;;
esac

for tool in git meson ninja pkg-config readelf strip strings; do
  command -v "$tool" >/dev/null || {
    echo "error: missing build tool: $tool" >&2
    exit 1
  }
done

# Pin every source, including the build wrapper. Moving these is an explicit
# dependency update and produces a reviewable release change.
readonly MPV_BUILD_COMMIT=9443097290e82008f26f1597590926c63e7ae053
readonly MPV_COMMIT=e48ac7ce08462f5e33af6ef9deeac6fa87eef01e
readonly FFMPEG_COMMIT=f893221c8d89cb798b829bebe71d55e1a3f242fd
readonly LIBASS_COMMIT=bbb3c7f1570a4a021e52683f3fbdf74fe492ae84
readonly LIBPLACEBO_COMMIT=3188549fba13bbdf3a5a98de2a38c2e71f04e21e

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/mpv-player/mpv-build.git "$WORK/mpv-build"
git -C "$WORK/mpv-build" checkout --quiet "$MPV_BUILD_COMMIT"
cd "$WORK/mpv-build"

./use-mpv-custom "$MPV_COMMIT"
./use-ffmpeg-custom "$FFMPEG_COMMIT"
./use-libass-custom "$LIBASS_COMMIT"
./use-libplacebo-custom "$LIBPLACEBO_COMMIT"

# The Flutter plugin uses libmpv's OpenGL render API. It does not need the mpv
# command-line executable, Lua/JS scripting, optical media, SDL, Vulkan, or
# encoding support. Disabling those features reduces both dependencies and the
# ABI surface exposed to the host.
cat > mpv_options <<'EOF'
-Dlibmpv=true
-Dcplayer=false
-Dtests=false
-Dlua=disabled
-Djavascript=disabled
-Dsdl2=disabled
-Dvulkan=disabled
-Ddvdnav=disabled
-Dcdda=disabled
-Dlibbluray=disabled
-Duchardet=disabled
-Drubberband=disabled
-Dopenal=disabled
EOF

# HTTPS is required for debrid and IPTV URLs. mpv-build makes FFmpeg static;
# OpenSSL remains a host ABI on Linux. Keep FFmpeg's encoders because mpv uses
# a small subset for features such as AC-3 audio conversion and recording.
cat > ffmpeg_options <<'EOF'
--disable-programs
--disable-doc
--disable-debug
--enable-openssl
--enable-nonfree
EOF

./rebuild -j"$(getconf _NPROCESSORS_ONLN)"

MPV_LIBRARY="mpv/build/libmpv.so.2"
[ -f "$MPV_LIBRARY" ] || {
  echo "error: mpv build completed without a shared libmpv" >&2
  find mpv/build -maxdepth 2 -type f -name '*mpv*' -print >&2 || true
  exit 1
}

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/include/mpv" "$OUTPUT/pkgconfig"
cp -L "$MPV_LIBRARY" "$OUTPUT/libmpv.so.2"
chmod 0755 "$OUTPUT/libmpv.so.2"
strip --strip-unneeded "$OUTPUT/libmpv.so.2"

# Subtitle auto-sync depends on these passive FFmpeg analysis filters. This
# build compiles full FFmpeg so they are present by default, but a future
# trim of ffmpeg_options must not silently drop them — fail the build instead.
# strings runs ONCE into a file: piping it straight into `grep -q` would let
# grep's early exit kill strings with SIGPIPE, which pipefail (set above)
# turns into a false "missing filter" failure on every successful build.
STRINGS_DUMP="$(mktemp)"
strings "$OUTPUT/libmpv.so.2" > "$STRINGS_DUMP"
for autosync_filter in astats aspectralstats ametadata; do
  if ! grep -qx "$autosync_filter" "$STRINGS_DUMP"; then
    rm -f "$STRINGS_DUMP"
    echo "error: private libmpv is missing auto-sync filter: $autosync_filter" >&2
    exit 1
  fi
done
rm -f "$STRINGS_DUMP"

# media_kit_video is a C++ plugin and hard-links libmpv. Give the subsequent
# Flutter build the headers and pkg-config metadata from this exact source
# revision so its DT_NEEDED entry is libmpv.so.2, not the CI image's system
# libmpv.so.1. The unversioned symlink is link-time only; AppImage packaging
# copies only the real SONAME file.
cp mpv/include/mpv/*.h "$OUTPUT/include/mpv/"
ln -s libmpv.so.2 "$OUTPUT/libmpv.so"
cat > "$OUTPUT/pkgconfig/mpv.pc" <<'EOF'
prefix=${pcfiledir}/..
libdir=${prefix}
includedir=${prefix}/include

Name: mpv
Description: Debrify private libmpv
Version: 0.40.0
Libs: -L${libdir} -lmpv
Cflags: -I${includedir}
EOF

PKG_CONFIG_PATH="$OUTPUT/pkgconfig" pkg-config --exact-version=0.40.0 mpv
resolved_link="$(PKG_CONFIG_PATH="$OUTPUT/pkgconfig" pkg-config --variable=libdir mpv)/libmpv.so"
[ "$(readlink "$resolved_link")" = "libmpv.so.2" ] || {
  echo "error: private mpv link-time symlink is invalid: $resolved_link" >&2
  exit 1
}

# These are process-global implementation libraries and must never leak back
# into the private artifact. Their host copies own the GPU, display, desktop
# and device ABI boundary.
for forbidden in \
  libavcodec libavformat libavutil libswscale libswresample libavfilter \
  libplacebo libass libgtk libglib libgobject libgio libsystemd libudev \
  libvulkan; do
  if readelf -d "$OUTPUT/libmpv.so.2" | grep -q "Shared library: \[$forbidden"; then
    echo "error: private libmpv unexpectedly depends on $forbidden" >&2
    exit 1
  fi
done

echo "==> Private libmpv dynamic dependencies"
readelf -d "$OUTPUT/libmpv.so.2" | sed -n 's/.*Shared library: \[\(.*\)\]/    \1/p'
echo "==> Wrote $OUTPUT/libmpv.so.2"
