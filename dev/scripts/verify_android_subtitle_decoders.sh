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
required_filters=(astats aspectralstats ametadata)

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
  local filter
  for filter in "${required_filters[@]}"; do
    if [[ "$config" != *"--enable-filter=$filter"* ]]; then
      echo "error: $label is missing FFmpeg auto-sync filter: $filter" >&2
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
  # Flutter release APKs target its three supported Android architectures.
  # The native package also builds x86 for downstream consumers, but Flutter
  # does not package that legacy emulator ABI.
  packaged_abis=(armeabi-v7a arm64-v8a x86_64)
  for abi in "${packaged_abis[@]}"; do
    if [[ ! -f "$WORK/apk/lib/$abi/libmpv.so" ]]; then
      echo "error: expected lib/$abi/libmpv.so in $INPUT" >&2
      exit 1
    fi
  done
  # The native TV player's neural VAD (ten-vad + its JNI shim) ships for the
  # ARM ABIs only; the app falls back to energy features where it is absent,
  # but a release that silently lost it on ARM would be a regression.
  unzip -q "$INPUT" 'lib/*/libten_vad.so' 'lib/*/libdebrify_tenvad.so' -d "$WORK/apk" || true
  readelf_bin="$(command -v readelf || command -v llvm-readelf || true)"
  for abi in armeabi-v7a arm64-v8a; do
    for vad_lib in libten_vad.so libdebrify_tenvad.so; do
      if [[ ! -f "$WORK/apk/lib/$abi/$vad_lib" ]]; then
        echo "error: expected lib/$abi/$vad_lib (subtitle auto-sync VAD) in $INPUT" >&2
        exit 1
      fi
      # Every 64-bit LOAD segment must be 16 KB-aligned or Android 16 drops
      # the whole app into page-size compatibility mode (16 KB pages exist
      # only on 64-bit devices; 32-bit ARM is exempt).
      if [[ "$abi" == "arm64-v8a" && -n "$readelf_bin" ]]; then
        if "$readelf_bin" -lW "$WORK/apk/lib/$abi/$vad_lib" | awk '$1 == "LOAD" { a = $NF; if (a != "0x4000" && a != "0x10000") bad = 1 } END { exit bad }'; then
          :
        else
          echo "error: lib/$abi/$vad_lib has a LOAD segment not 16 KB-aligned" >&2
          exit 1
        fi
      elif [[ "$abi" == "arm64-v8a" ]]; then
        echo "warning: readelf not found; skipping 16 KB alignment check for lib/$abi/$vad_lib" >&2
      fi
    done
  done
  while IFS= read -r binary; do
    verify_binary "$binary" "${binary#"$WORK/apk/"}"
    verified=$((verified + 1))
  done < <(find "$WORK/apk" -type f -name libmpv.so -print | sort)
  if [[ "$verified" -ne "${#packaged_abis[@]}" ]]; then
    echo "error: expected ${#packaged_abis[@]} libmpv ABIs in $INPUT, found $verified" >&2
    exit 1
  fi
else
  echo "error: expected a jar directory or APK: $INPUT" >&2
  exit 1
fi

echo "verified ${#required[@]} subtitle decoders and ${#required_filters[@]} auto-sync filters across $verified Android ABIs"
