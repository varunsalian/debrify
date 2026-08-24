#!/usr/bin/env bash
# Fail release builds if the packaged MediaKit frameworks are not genuinely
# universal or if FFmpeg silently drops required subtitle decoders. XCFramework
# metadata is not sufficient: a locally replaced binary can claim x86_64 while
# containing only arm64, which then fails late in the release linker.

set -euo pipefail

FRAMEWORKS="${1:?usage: $0 <Frameworks-directory> [--architectures-only]}"
MODE="${2:-full}"
if [[ "$MODE" != "full" && "$MODE" != "--architectures-only" ]]; then
  echo "error: unsupported verification mode: $MODE" >&2
  exit 1
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debrify-verify-macos-subs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

required_frameworks=(
  Ass Avcodec Avfilter Avformat Avutil Dav1d Freetype Fribidi Harfbuzz
  Mbedcrypto Mbedtls Mbedx509 Mpv Png16 Swresample Swscale Uchardet Xml2
)

framework_binaries() {
  local name="$1"
  if [[ -d "$FRAMEWORKS/$name.xcframework" ]]; then
    find "$FRAMEWORKS/$name.xcframework" -type f -name "$name" -print | sort
  elif [[ -f "$FRAMEWORKS/$name.framework/Versions/A/$name" ]]; then
    printf '%s\n' "$FRAMEWORKS/$name.framework/Versions/A/$name"
  elif [[ -f "$FRAMEWORKS/$name.framework/$name" ]]; then
    printf '%s\n' "$FRAMEWORKS/$name.framework/$name"
  fi
}

for framework in "${required_frameworks[@]}"; do
  candidates=()
  while IFS= read -r binary; do
    candidates+=("$binary")
  done < <(framework_binaries "$framework")
  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "error: $framework binary not found below $FRAMEWORKS" >&2
    exit 1
  fi
  for binary in "${candidates[@]}"; do
    architectures="$(lipo -archs "$binary")"
    for required_architecture in x86_64 arm64; do
      if [[ " $architectures " != *" $required_architecture "* ]]; then
        echo "error: $framework is missing macOS architecture: $required_architecture (found: $architectures)" >&2
        exit 1
      fi
    done

    while IFS= read -r minimum; do
      if ! awk -v version="$minimum" 'BEGIN { exit !(version + 0 <= 11.0) }'; then
        echo "error: $framework requires macOS $minimum; expected 11.0 or older" >&2
        exit 1
      fi
    done < <(
      vtool -show-build "$binary" | awk '
        $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { legacy = 1; next }
        legacy && $1 == "version" { print $2; legacy = 0; next }
        $1 == "minos" { print $2 }
      '
    )
  done
done

if [[ "$MODE" == "--architectures-only" ]]; then
  echo "verified universal macOS framework architectures and deployment targets"
  exit 0
fi

binaries=()
while IFS= read -r binary; do
  binaries+=("$binary")
done < <(framework_binaries Avcodec)
if [[ "${#binaries[@]}" -eq 0 ]]; then
  echo "error: Avcodec binary not found below $FRAMEWORKS" >&2
  exit 1
fi

required=(
  ass ssa dvbsub dvdsub pgssub xsub ccaption jacosub microdvd movtext mpl2
  pjs realtext sami srt stl subrip subviewer subviewer1 text vplayer webvtt
)
required_filters=(astats aspectralstats ametadata)
verified=0
verify_binary() {
  local binary="$1"
  local label="$2"
  local config
  config="$(strings "$binary" | grep -- '--disable-autodetect' | head -1 || true)"
  if [[ -z "$config" ]]; then
    echo "error: FFmpeg configure manifest not found in $label" >&2
    return 1
  fi

  local missing=0
  local decoder
  for decoder in "${required[@]}"; do
    if [[ "$config" != *"--enable-decoder=$decoder"* ]]; then
      echo "error: $label is missing FFmpeg subtitle decoder: $decoder" >&2
      missing=$((missing + 1))
    fi
  done
  local filter
  for filter in "${required_filters[@]}"; do
    if [[ "$config" != *"--enable-filter=$filter"* ]]; then
      echo "error: $label is missing FFmpeg auto-sync filter: $filter" >&2
      missing=$((missing + 1))
    fi
  done
  [[ "$missing" -eq 0 ]]
}

binary_index=0
for binary in "${binaries[@]}"; do
  architectures="$(lipo -archs "$binary")"
  for architecture in $architectures; do
    thin="$WORK/avcodec-$binary_index-$architecture"
    lipo "$binary" -thin "$architecture" -output "$thin"
    verify_binary "$thin" "$(basename "$binary")[$architecture]"
    verified=$((verified + 1))
  done
  binary_index=$((binary_index + 1))
done

echo "verified universal macOS frameworks, ${#required[@]} subtitle decoders, and ${#required_filters[@]} auto-sync filters across $verified architecture slices"
