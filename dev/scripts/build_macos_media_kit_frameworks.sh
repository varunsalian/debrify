#!/usr/bin/env bash
# Build MediaKit's exact macOS libmpv framework set with Debrify's subtitle
# decoders and passive auto-sync analysis filters. The upstream recipe stays
# pinned so unrelated player components do not move under this feature.

set -euo pipefail

OUTPUT_ARG="${1:?usage: $0 <Frameworks-output-directory>}"
case "$OUTPUT_ARG" in
  /*) OUTPUT="$OUTPUT_ARG" ;;
  *) OUTPUT="$(pwd)/$OUTPUT_ARG" ;;
esac

case "$(uname -s)" in
  Darwin) ;;
  *) echo "error: macOS frameworks must be built on macOS" >&2; exit 1 ;;
esac

for tool in git nix xcodebuild; do
  command -v "$tool" >/dev/null || {
    echo "error: missing build tool: $tool" >&2
    exit 1
  }
done

readonly UPSTREAM_REPO="https://github.com/media-kit/libmpv-darwin-build.git"
readonly UPSTREAM_COMMIT="b4e3ce98826cd4a28f6121b29f56ea203346e6e3"
readonly TARGET="mk-out-archive-xcframeworks-macos-universal-video-default"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH="$ROOT/dev/scripts/patches/libmpv-darwin-subtitle-decoders.patch"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debrify-libmpv-macos.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --filter=blob:none "$UPSTREAM_REPO" "$WORK/source"
git -C "$WORK/source" checkout --quiet "$UPSTREAM_COMMIT"
git -C "$WORK/source" apply --check "$PATCH"
git -C "$WORK/source" apply "$PATCH"

XCODE_PATH="$(dirname "$(dirname "$(xcode-select -p)")")"
(
  cd "$WORK/source"
  nix develop -c make \
    XCODE_PATH="$XCODE_PATH" \
    VERSION="debrify-subtitles-autosync-3" \
    TARGET="$TARGET"
)

ARCHIVE="$(find -L "$WORK/source/result" -maxdepth 1 -type f \
  -name 'libmpv-xcframeworks_*.tar.gz' -print -quit)"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "error: libmpv build did not produce the expected xcframework archive" >&2
  exit 1
fi

STAGE="$WORK/frameworks"
mkdir -p "$STAGE"
tar -xzf "$ARCHIVE" --strip-components 1 -C "$STAGE"

# Refuse a broad or unresolved destination before replacing generated binaries.
case "$OUTPUT" in
  "$ROOT"/packages/media_kit_libs_macos_video_patched/macos/Frameworks) ;;
  *) echo "error: refusing unexpected output directory: $OUTPUT" >&2; exit 1 ;;
esac
rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
mv "$STAGE" "$OUTPUT"

"$ROOT/dev/scripts/verify_macos_subtitle_decoders.sh" "$OUTPUT"
echo "==> Installed subtitle/auto-sync MediaKit frameworks at $OUTPUT"
