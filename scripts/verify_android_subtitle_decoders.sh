#!/usr/bin/env bash
# Verify the FFmpeg configure manifest embedded in MediaKit's Android libmpv.
# Accepts either a directory containing ABI jars, or a built APK.

set -euo pipefail

INPUT="${1:?usage: $0 <jar-directory-or-apk>}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/debrify-verify-android-subs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

required=(
  ass ssa dvbsub dvdsub pgssub xsub ccaption jacosub microdvd movtext mpl2
  pjs realtext sami srt stl subrip subviewer subviewer1 text vplayer webvtt
)

verify_binary() {
  local binary="$1"
  local label="$2"
  local config
  config="$(strings "$binary" | grep -- '--target-os=android' | head -1 || true)"
  if [[ -z "$config" ]]; then
    echo "error: FFmpeg configure manifest not found in $label" >&2
    return 1
  fi

  local missing=0
  local decoder
  for decoder in "${required[@]}"; do
    if [[ "$config" != *"--enable-decoder=$decoder"* && \
          "$config" != *"--enable-decoder='$decoder'"* ]]; then
      echo "error: $label is missing FFmpeg subtitle decoder: $decoder" >&2
      missing=$((missing + 1))
    fi
  done
  [[ "$missing" -eq 0 ]]
}

verified=0
if [[ -d "$INPUT" ]]; then
  shopt -s nullglob
  jars=("$INPUT"/default-*.jar)
  if [[ "${#jars[@]}" -ne 4 ]]; then
    echo "error: expected four MediaKit ABI jars below $INPUT" >&2
    exit 1
  fi
  for jar in "${jars[@]}"; do
    jar_stage="$WORK/$(basename "$jar" .jar)"
    mkdir -p "$jar_stage"
    unzip -q "$jar" 'lib/*/libmpv.so' -d "$jar_stage"
    binary="$(find "$jar_stage" -type f -name libmpv.so -print -quit)"
    verify_binary "$binary" "$(basename "$jar")"
    verified=$((verified + 1))
  done
elif [[ -f "$INPUT" && "$INPUT" == *.apk ]]; then
  unzip -q "$INPUT" 'lib/*/libmpv.so' -d "$WORK/apk"
  while IFS= read -r binary; do
    verify_binary "$binary" "${binary#"$WORK/apk/"}"
    verified=$((verified + 1))
  done < <(find "$WORK/apk" -type f -name libmpv.so -print | sort)
  if [[ "$verified" -ne 4 ]]; then
    echo "error: expected four libmpv ABIs in $INPUT, found $verified" >&2
    exit 1
  fi
else
  echo "error: expected a jar directory or APK: $INPUT" >&2
  exit 1
fi

echo "verified ${#required[@]} subtitle decoders across $verified Android ABIs"
