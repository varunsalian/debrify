#!/usr/bin/env bash
#
# Copy libmpv and its transitive dependencies into a built Flutter Linux
# bundle, so the AppImage runs on hosts that have no libmpv installed.
#
# Why this exists: on Linux, package:media_kit bundles NOTHING. Both
# media_kit_libs_linux and media_kit_video set their *_bundled_libraries
# CMake variable to "", and media_kit_video links libmpv at build time via
# pkg-config while media_kit ALSO dlopen()s it at runtime (see
# packages/media_kit_patched/.../native_library.dart). So a stock
# `flutter build linux` produces a bundle that silently depends on the host
# having libmpv. Immutable distros (SteamOS on the Steam Deck) can't install
# it, which is what sent our first Deck user to distrobox.
#
# The bundle already has the plumbing to find libraries here: the runner's
# rpath is $ORIGIN/lib (linux/CMakeLists.txt) and linux/AppRun exports
# LD_LIBRARY_PATH pointing at the same directory. We only ever needed to put
# the file there.
#
# Usage: scripts/bundle_linux_mpv.sh <path-to-bundle>
#   e.g. scripts/bundle_linux_mpv.sh build/linux/x64/release/bundle
#
# Arch-agnostic — pkg-config resolves libmpv for whatever we're building.

set -euo pipefail

BUNDLE="${1:?usage: $0 <path-to-flutter-linux-bundle>}"
LIB="$BUNDLE/lib"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXCLUDELIST="$REPO_ROOT/linux/appimage-excludelist"

[ -d "$LIB" ] || { echo "error: $LIB does not exist — build the app first" >&2; exit 1; }
[ -f "$EXCLUDELIST" ] || { echo "error: missing $EXCLUDELIST" >&2; exit 1; }

EXCLUDED="$(mktemp)"
trap 'rm -f "$EXCLUDED"' EXIT

# Strip comments and blank lines; the file format is one soname per line.
# Note the upstream file deliberately comments OUT some entries (libglib,
# libgtk, ...) to mean "do bundle these" — stripping from # to end of line
# drops those, which is the intended reading.
sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$EXCLUDELIST" | grep -v '^[[:space:]]*$' > "$EXCLUDED"

# Libraries that must come from the HOST, on top of the upstream excludelist.
#
# The glib family is ours to add because upstream's list can't know our
# situation: it comments these out (i.e. "bundle them") for the general case,
# but a Flutter app hard-links GTK3 from the host, so the host's glib is
# already loaded in this process. Bundling a second copy and putting it first
# on LD_LIBRARY_PATH means host GTK3 gets our glib — fine when ours is newer,
# a missing-symbol crash when the host's GTK is newer than our glib. There can
# only be one glib in the process and it has to be the host's.
#
# Deliberately NOT excluded here: libva*, libvdpau and libvulkan. They are hard
# DT_NEEDED dependencies of Ubuntu's libmpv (verified against the libmpv2
# package metadata), so omitting them means libmpv fails to load outright on
# any host missing one. They are bundled and then redirected at the host's
# drivers by linux/AppRun — see the long comment there.
#
# The second group is glib's own support stack. Excluding glib but bundling
# the libraries that exist only to serve it just moves the skew one level
# down — the host's glib would end up using our pcre2. Anything that can run
# a GTK3 app necessarily has all of these, so leave the whole subtree host-
# side. Entries that never appear in libmpv's closure are harmless no-ops.
cat >> "$EXCLUDED" <<'EOF'
libglib-2.0.so.0
libgobject-2.0.so.0
libgio-2.0.so.0
libgmodule-2.0.so.0
libgthread-2.0.so.0
libpcre2-8.so.0
libselinux.so.1
libmount.so.1
libblkid.so.1
libffi.so.8
libffi.so.7
EOF

MPV_LIBDIR="$(pkg-config --variable=libdir mpv)"

# Don't hardcode the soname: Ubuntu 24.04 ships libmpv.so.2 (mpv 0.37+) but
# older bases ship libmpv.so.1, and media_kit accepts either.
MPV_SO=""
for _soname in libmpv.so.2 libmpv.so.1; do
  if [ -f "$MPV_LIBDIR/$_soname" ]; then
    MPV_SO="$MPV_LIBDIR/$_soname"
    MPV_SONAME="$_soname"
    break
  fi
done
[ -n "$MPV_SO" ] || { echo "error: no libmpv.so.{2,1} in $MPV_LIBDIR (is libmpv-dev installed?)" >&2; exit 1; }

echo "==> Bundling $MPV_SONAME from $MPV_SO into $LIB"

# ldd's output is already the full transitive closure, so one pass is enough.
# Copy each dependency under its SONAME (field 1), not the basename of the
# resolved path — those can differ (libfoo.so.1 -> libfoo.so.1.2.3) and the
# loader only ever searches for the soname.
copied=0
skipped=0
while read -r soname path; do
  if grep -qxF -- "$soname" "$EXCLUDED"; then
    echo "    skip (host)  $soname"
    skipped=$((skipped + 1))
    continue
  fi
  cp -L "$path" "$LIB/$soname"
  echo "    bundle       $soname"
  copied=$((copied + 1))
done < <(ldd "$MPV_SO" | awk '/=> \//{print $1, $3}' | sort -u)

cp -L "$MPV_SO" "$LIB/$MPV_SONAME"
copied=$((copied + 1))

echo "==> Bundled $copied libraries, left $skipped to the host"

# Guard: prove every dependency we claimed to bundle actually resolves from
# INSIDE the bundle. Checking only for ldd's "not found" would be close to
# vacuous — on a fully provisioned CI runner anything we forgot still resolves
# happily from /usr, and the check would pass on a bundle that dies on a user's
# machine. So assert the resolved path, not merely that one exists.
#
# This is still not proof the AppImage runs on SteamOS: excluded libraries are
# host-provided by design and unverifiable here, and nothing dlopen()ed at
# runtime (VA/VDPAU/Vulkan drivers, ALSA and PipeWire plugins) appears in ldd
# output at all. Only a Deck can answer that.
echo "==> Verifying the bundled closure resolves from inside the bundle"
LEAKS="$(mktemp)"
trap 'rm -f "$EXCLUDED" "$LEAKS"' EXIT

LD_LIBRARY_PATH="$LIB" ldd "$LIB/$MPV_SONAME" | awk '/=> \//{print $1, $3}' \
  | while read -r soname path; do
      grep -qxF -- "$soname" "$EXCLUDED" && continue
      case "$path" in
        "$LIB"/*) ;;
        *) echo "  $soname resolved to $path" >> "$LEAKS" ;;
      esac
    done

if [ -s "$LEAKS" ]; then
  echo "error: these libmpv dependencies came from the host instead of the bundle:" >&2
  cat "$LEAKS" >&2
  echo "       either bundle them or add them to the exclusion set with a reason." >&2
  exit 1
fi

# The media_kit plugin is checked only for hard failures: its own GTK linkage
# is host-provided by Flutter's design, so "resolved outside the bundle" is
# the expected state there, not an error.
PLUGIN="$LIB/libmedia_kit_video_plugin.so"
if [ -f "$PLUGIN" ] && LD_LIBRARY_PATH="$LIB" ldd "$PLUGIN" | grep -q 'not found'; then
  echo "error: unresolved dependencies in libmedia_kit_video_plugin.so:" >&2
  LD_LIBRARY_PATH="$LIB" ldd "$PLUGIN" | grep 'not found' >&2
  exit 1
fi

du -sh "$LIB" | awk '{print "==> bundle/lib is now " $1}'
echo "==> OK"
