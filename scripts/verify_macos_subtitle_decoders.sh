#!/usr/bin/env bash
# Fail release builds if the packaged FFmpeg silently drops required subtitle
# decoders. FFmpeg embeds its configure command in Avcodec.framework.

set -euo pipefail

FRAMEWORKS="${1:?usage: $0 <Frameworks-directory>}"
if [[ -d "$FRAMEWORKS/Avcodec.xcframework" ]]; then
  AVCODEC="$(find "$FRAMEWORKS/Avcodec.xcframework" -type f -name Avcodec -print -quit)"
elif [[ -f "$FRAMEWORKS/Avcodec.framework/Versions/A/Avcodec" ]]; then
  AVCODEC="$FRAMEWORKS/Avcodec.framework/Versions/A/Avcodec"
else
  AVCODEC=""
fi
if [[ -z "$AVCODEC" || ! -f "$AVCODEC" ]]; then
  echo "error: Avcodec binary not found below $FRAMEWORKS" >&2
  exit 1
fi

CONFIG="$(strings "$AVCODEC" | grep -- '--disable-autodetect' | head -1 || true)"
if [[ -z "$CONFIG" ]]; then
  echo "error: FFmpeg configure manifest not found in $AVCODEC" >&2
  exit 1
fi

required=(
  ass ssa dvbsub dvdsub pgssub xsub ccaption jacosub microdvd movtext mpl2
  pjs realtext sami srt stl subrip subviewer subviewer1 text vplayer webvtt
)
missing=0
for decoder in "${required[@]}"; do
  if [[ "$CONFIG" != *"--enable-decoder=$decoder"* ]]; then
    echo "error: FFmpeg subtitle decoder missing: $decoder" >&2
    missing=$((missing + 1))
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "verified ${#required[@]} subtitle decoders in $(basename "$AVCODEC")"
