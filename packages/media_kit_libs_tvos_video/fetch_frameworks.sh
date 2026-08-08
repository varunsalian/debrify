#!/usr/bin/env bash
# Fetch the prebuilt libmpv + ffmpeg xcframeworks that package:media_kit needs
# on tvOS, into this package's tvos/Frameworks/ directory.
#
# ~2.7 GB extracted, so the binaries are gitignored (see the repo .gitignore)
# and pulled on demand instead: locally on a fresh clone, and in CI by the
# `tvos` job in .github/workflows/build.yml.
#
# media_kit's own source (media-kit/libmpv-darwin-build) targets ios/macos
# only. karelrooted/libmpv publishes the same library set built WITH Apple TV
# slices, which is what this pulls.
#
# Safe to re-run: frameworks already present are left alone, so an interrupted
# fetch resumes where it stopped.
set -euo pipefail

REPO="karelrooted/libmpv"
TAG="v0.0.1-beta"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$PKG_DIR/tvos/Frameworks"
WORK="${TMPDIR:-/tmp}/libmpv-tvos-$TAG"

# Exactly the set the podspec's OTHER_LDFLAGS links: 9 framework-wrapped
# ffmpeg/TLS slices plus 19 bare archives. The release ships five more
# (Libdovi, Libeffcee, Libnfs, Libreadline, Libsmbclient) that nothing on the
# link line references — pulling them would cost ~55 MB for nothing. Keep this
# list and OTHER_LDFLAGS in sync.
FRAMEWORKS=(
  Libass Libavcodec Libavdevice Libavfilter Libavformat Libavutil
  Libbluray Libcrypto Libdav1d Libfreetype Libfribidi Libglslang
  Libgmp Libgnutls Libharfbuzz Libhogweed Liblcms2 Libluajit-5.1
  Libmpv Libnettle Libplacebo Libpng Libshaderc_combined Libssl
  Libswresample Libswscale Libuchardet MoltenVK
)

fetch_one() {
  local name="$1"
  local url="https://github.com/$REPO/releases/download/$TAG/$name.xcframework.zip"
  local zip="$WORK/$name.xcframework.zip"
  local stage="$WORK/stage-$name"

  if [[ -d "$DEST/$name.xcframework" ]]; then
    echo "  have  $name"
    return 0
  fi

  # Always start clean rather than `curl -C -`: a leftover zip here means a
  # previous run failed, and resuming onto a *complete* file makes the CDN
  # answer 416 and curl exit non-zero for what is actually a finished download.
  rm -f "$zip"
  echo "  get   $name"
  # --no-progress-meter because four parallel workers writing CR-driven progress
  # bars to one non-tty log collapse into a single unreadable line.
  curl -fSL --no-progress-meter --retry 5 --retry-delay 2 --retry-all-errors \
    -o "$zip" "$url"

  # Extract to a staging dir, not straight into $DEST — an interrupted extract
  # there would leave a partial .xcframework that the `have` check above then
  # skips forever.
  rm -rf "$stage"
  mkdir -p "$stage"
  unzip -q "$zip" -d "$stage"

  local fw
  fw="$(find "$stage" -maxdepth 2 -type d -name '*.xcframework' | head -1)"
  if [[ -z "$fw" ]]; then
    echo "error: $name — no .xcframework inside the archive" >&2
    return 1
  fi

  # A framework carrying only ios/macos slices links fine for iOS and then
  # fails the tvOS build with the misleading "building for tvOS but linking
  # iOS". Catch that here, where the message can say what actually happened.
  if ! plutil -p "$fw/Info.plist" | grep -q '"SupportedPlatform" => "tvos"'; then
    echo "error: $name — no tvOS slice in $TAG" >&2
    return 1
  fi

  rm -rf "$DEST/$name.xcframework"
  mv "$fw" "$DEST/$name.xcframework"
  rm -rf "$stage" "$zip"
}

# Re-entry point for the xargs workers below. Kept as a self-invocation rather
# than `export -f`, which needs a bash newer than the 3.2 macOS ships as
# /bin/bash.
if [[ "${1:-}" == "--one" ]]; then
  mkdir -p "$DEST" "$WORK"
  fetch_one "$2"
  exit $?
fi

mkdir -p "$DEST" "$WORK"

echo "=== fetching ${#FRAMEWORKS[@]} xcframeworks from $REPO@$TAG ==="
# ~830 MB total. Four at a time: enough to saturate a typical link without
# tripping the release CDN's rate limiting.
if ! printf '%s\n' "${FRAMEWORKS[@]}" \
  | xargs -P "${FETCH_JOBS:-4}" -I{} "${BASH_SOURCE[0]}" --one {}; then
  echo "error: one or more frameworks failed to fetch (see above)" >&2
  exit 1
fi

# Guard against a partial success that xargs somehow let through — the build
# failure this would otherwise cause is a link error a thousand lines deep.
missing=0
for name in "${FRAMEWORKS[@]}"; do
  if [[ ! -d "$DEST/$name.xcframework" ]]; then
    echo "error: missing $name.xcframework" >&2
    missing=$((missing + 1))
  fi
done
if [[ "$missing" -ne 0 ]]; then
  echo "error: $missing framework(s) missing after fetch" >&2
  exit 1
fi

rmdir "$WORK" 2>/dev/null || true

echo "=== done ==="
echo "$(ls "$DEST" | wc -l | tr -d ' ') xcframeworks in $DEST"
du -sh "$DEST"
