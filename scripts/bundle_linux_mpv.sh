#!/usr/bin/env bash
#
# Install Debrify's reproducible libmpv build into a Flutter Linux bundle.
#
# libmedia_kit_video_plugin.so has a hard DT_NEEDED edge to libmpv, while
# package:media_kit also dlopen()s the same library from Dart.  Keep that
# private dependency in bundle/lib/mpv and give only the plugin a RUNPATH to
# it.  In particular, do NOT put bundle/lib/mpv on LD_LIBRARY_PATH: doing so
# makes Ubuntu's multimedia, graphics and support libraries override the host
# GTK/Mesa stack for the entire Flutter process.
#
# Usage:
#   scripts/bundle_linux_mpv.sh <flutter-bundle> <private-libmpv-directory>

set -euo pipefail

BUNDLE="${1:?usage: $0 <flutter-bundle> <private-libmpv-directory>}"
SOURCE="${2:?usage: $0 <flutter-bundle> <private-libmpv-directory>}"
LIB="$BUNDLE/lib"
PRIVATE="$LIB/mpv"
PLUGIN="$LIB/libmedia_kit_video_plugin.so"

command -v patchelf >/dev/null || {
  echo "error: patchelf is required" >&2
  exit 1
}
command -v readelf >/dev/null || {
  echo "error: readelf is required" >&2
  exit 1
}

[ -d "$LIB" ] || { echo "error: Flutter bundle library directory not found: $LIB" >&2; exit 1; }
[ -f "$PLUGIN" ] || { echo "error: media_kit video plugin not found: $PLUGIN" >&2; exit 1; }

MPV_SOURCE="$SOURCE/libmpv.so.2"
[ -f "$MPV_SOURCE" ] || {
  echo "error: no libmpv.so.2 in $SOURCE" >&2
  exit 1
}

# Refuse the old accidental distro closure.  The private build intentionally
# contains libmpv (with FFmpeg/libass/libplacebo linked into it), not a copy of
# every library installed on the CI runner.
mapfile -t payload < <(find "$SOURCE" -maxdepth 1 -type f -name '*.so*' -printf '%f\n' | sort)
if [ "${#payload[@]}" -ne 1 ]; then
  printf 'error: private mpv payload must contain exactly one shared library; found:\n' >&2
  printf '  %s\n' "${payload[@]}" >&2
  exit 1
fi

rm -rf "$PRIVATE"
mkdir -p "$PRIVATE"
cp -L "$MPV_SOURCE" "$PRIVATE/libmpv.so.2"
chmod 0755 "$PRIVATE/libmpv.so.2"

# The plugin's direct dependency is resolved privately. libmpv itself uses
# host-facing graphics/audio ABI libraries and therefore needs no private
# search path of its own.
patchelf --set-rpath '$ORIGIN/mpv' "$PLUGIN"

# Dart receives the absolute AppImage-relative path from AppRun. Keep the
# canonical SONAME expected by media_kit and by the plugin.
if [ "$(patchelf --print-soname "$PRIVATE/libmpv.so.2")" != "libmpv.so.2" ]; then
  patchelf --set-soname libmpv.so.2 "$PRIVATE/libmpv.so.2"
fi

plugin_rpath="$(patchelf --print-rpath "$PLUGIN")"
[ "$plugin_rpath" = '$ORIGIN/mpv' ] || {
  echo "error: unexpected media_kit plugin RUNPATH: $plugin_rpath" >&2
  exit 1
}

readelf -d "$PLUGIN" | grep -q 'Shared library: \[libmpv.so.2\]' || {
  echo "error: media_kit video plugin does not require libmpv.so.2" >&2
  exit 1
}

# Exercise the loader exactly as the AppImage will: no global library path,
# plugin RUNPATH resolving mpv, and every remaining dependency from the host.
loader_report="$(LD_LIBRARY_PATH= ldd "$PLUGIN")"
if grep -q 'not found' <<<"$loader_report"; then
  echo "error: unresolved native dependency after private mpv installation:" >&2
  grep 'not found' <<<"$loader_report" >&2
  exit 1
fi
resolved_mpv="$(awk '/libmpv\.so\.2 =>/{print $3; exit}' <<<"$loader_report")"
[ "$resolved_mpv" = "$PRIVATE/libmpv.so.2" ] || {
  echo "error: plugin resolved libmpv outside its private directory: $resolved_mpv" >&2
  exit 1
}

echo "==> Installed private libmpv at $PRIVATE/libmpv.so.2"
echo "==> media_kit plugin RUNPATH: $plugin_rpath"
