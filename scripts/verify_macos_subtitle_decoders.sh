#!/usr/bin/env bash
# Fail release builds if the packaged FFmpeg silently drops required subtitle
# decoders. FFmpeg embeds its configure command in Avcodec.framework.

set -euo pipefail

FRAMEWORKS="${1:?usage: $0 <Frameworks-directory>}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debrify-verify-macos-subs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

binaries=()
if [[ -d "$FRAMEWORKS/Avcodec.xcframework" ]]; then
  while IFS= read -r binary; do
    binaries+=("$binary")
  done < <(find "$FRAMEWORKS/Avcodec.xcframework" -type f -name Avcodec -print | sort)
elif [[ -f "$FRAMEWORKS/Avcodec.framework/Versions/A/Avcodec" ]]; then
  binaries+=("$FRAMEWORKS/Avcodec.framework/Versions/A/Avcodec")
fi
if [[ "${#binaries[@]}" -eq 0 ]]; then
  echo "error: Avcodec binary not found below $FRAMEWORKS" >&2
  exit 1
fi

required=(
  ass ssa dvbsub dvdsub pgssub xsub ccaption jacosub microdvd movtext mpl2
  pjs realtext sami srt stl subrip subviewer subviewer1 text vplayer webvtt
)
required_filters=(astats aspectralstats)
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

echo "verified ${#required[@]} subtitle decoders and ${#required_filters[@]} auto-sync filters across $verified macOS architecture slices"
