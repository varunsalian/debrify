#!/usr/bin/env bash
# Build MediaKit's exact Android v1.1.11 native bundle with Debrify's subtitle
# decoders and passive auto-sync analysis filters. This intentionally keeps
# mpv, FFmpeg, helper code and every unrelated option at the pinned versions.

set -euo pipefail

OUTPUT_ARG="${1:?usage: $0 <jar-output-directory>}"
case "$OUTPUT_ARG" in
  /*) OUTPUT="$OUTPUT_ARG" ;;
  *) OUTPUT="$(pwd)/$OUTPUT_ARG" ;;
esac

case "$(uname -s)" in
  Linux) ;;
  *) echo "error: Android MediaKit libraries must be built on Linux" >&2; exit 1 ;;
esac

for tool in git java javac flutter wget unzip zip meson ninja pkg-config; do
  command -v "$tool" >/dev/null || {
    echo "error: missing build tool: $tool" >&2
    exit 1
  }
done
if [[ -z "${ANDROID_HOME:-}" || ! -d "$ANDROID_HOME" ]]; then
  echo "error: ANDROID_HOME must point to an installed Android SDK" >&2
  exit 1
fi

readonly UPSTREAM_REPO="https://github.com/media-kit/libmpv-android-video-build.git"
readonly UPSTREAM_COMMIT="1ecf5100ec0f75e1d0630f48851b85769c92eed2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$ROOT/dev/scripts/patches/libmpv-android-subtitle-decoders.patch"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debrify-libmpv-android.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --filter=blob:none "$UPSTREAM_REPO" "$WORK/source"
git -C "$WORK/source" checkout --quiet "$UPSTREAM_COMMIT"
# This patch intentionally uses zero-context insertions against the exact
# pinned upstream commit. Without --unidiff-zero, Git may relocate both hunks
# to EOF, turning FFmpeg flags into shell commands after the build completes.
git -C "$WORK/source" apply --unidiff-zero --check "$PATCH"
git -C "$WORK/source" apply --unidiff-zero "$PATCH"

# Avoid the upstream script's package-manager branch. GitHub's Android runner
# already has Java 17, Flutter and the SDK; the recipe installs only its pinned
# NDK/build-tools into that SDK. v1.1.11's cleanup predicates expect these
# directories to exist before their first invocation.
mkdir -p "$WORK/source/buildscripts/deps" "$WORK/source/buildscripts/prefix"
mkdir -p "$WORK/source/buildscripts/sdk"
ln -s "$ANDROID_HOME" "$WORK/source/buildscripts/sdk/android-sdk-linux"
(
  cd "$WORK/source/buildscripts"
  TRAVIS=1 ./bundle_default.sh
)

STAGE="$WORK/jars"
mkdir -p "$STAGE"
find "$WORK/source/buildscripts/artifacts/default" -maxdepth 1 -type f \
  -name 'default-*.jar' \
  -exec cp {} "$STAGE"/ \;

if [[ "$(find "$STAGE" -maxdepth 1 -type f -name 'default-*.jar' | wc -l | tr -d ' ')" != 4 ]]; then
  echo "error: Android libmpv build did not produce four ABI jars" >&2
  exit 1
fi

"$ROOT/scripts/verify_android_subtitle_decoders.sh" "$STAGE"

case "$OUTPUT" in
  "$ROOT"/packages/media_kit_libs_android_video_patched/android/libs) ;;
  *) echo "error: refusing unexpected output directory: $OUTPUT" >&2; exit 1 ;;
esac
mkdir -p "$OUTPUT"
find "$OUTPUT" -maxdepth 1 -type f -name 'default-*.jar' -delete
find "$OUTPUT" -maxdepth 1 -type f -name '.debrify-subtitle-build' -delete
cp "$STAGE"/default-*.jar "$OUTPUT"/
"$ROOT/scripts/verify_android_subtitle_decoders.sh" "$OUTPUT"
printf '%s\n' "$UPSTREAM_COMMIT" > "$OUTPUT/.debrify-subtitle-build"

echo "==> Installed subtitle/auto-sync MediaKit Android libraries at $OUTPUT"
