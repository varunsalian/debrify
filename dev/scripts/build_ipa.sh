#!/usr/bin/env bash
#
# Build Debrify for iOS, ad-hoc sign it for sideloading, and drop the .ipa in
# ~/Downloads/ios so AltServer can pick it up (menu bar -> Sideload .ipa -> iPad).
#
# Usage:
#   scripts/build_ipa.sh              # clean-ish build, sign, package
#   scripts/build_ipa.sh --no-build   # re-package the existing Runner.app
#   scripts/build_ipa.sh --out DIR    # write the .ipa somewhere else
#
# Requires the Xcode iOS platform component. If xcodebuild complains that
# "iOS <ver> is not installed", run once:  xcodebuild -downloadPlatform iOS

set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
BUILD_DIR="$REPO/build/ios/iphoneos"
APP="$BUILD_DIR/Runner.app"
OUT_DIR="$HOME/Downloads/ios"
DO_BUILD=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --out)      OUT_DIR="${2:?--out needs a directory}"; shift 2 ;;
    -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Name the artifact after pubspec's "version: 0.6.4-alpha.1+21".
VERSION="$(awk -F': ' '/^version:/{print $2; exit}' pubspec.yaml | tr -d '[:space:]')"
VERSION="${VERSION/+/-}"
IPA="$OUT_DIR/debrify-${VERSION:-local}.ipa"

if [ "$DO_BUILD" -eq 1 ]; then
  say "flutter build ios --release --no-codesign"
  flutter build ios --release --no-codesign
fi

[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

# --no-codesign emits Mach-Os with no LC_CODE_SIGNATURE, so __LINKEDIT reserves no
# room for a signature and AltStore's ldid aborts with
# "ldid.cpp: _assert(): end >= size - 0x10". Ad-hoc signing reserves that space;
# AltServer then replaces the signature with your own cert. Order matters:
# dylibs -> frameworks -> app bundle.
# Mirrors the "Ad-hoc sign for sideloading" step in .github/workflows/build.yml.
say "ad-hoc signing"
for d in "$APP"/Frameworks/*.dylib; do
  [ -f "$d" ] && codesign -f -s - --timestamp=none "$d"
done
for f in "$APP"/Frameworks/*.framework; do
  [ -d "$f" ] && codesign -f -s - --timestamp=none "$f"
done
codesign -f -s - --timestamp=none "$APP"

# Refuse to ship an IPA that would fail to install.
missing=0
check() {
  if [ -f "$1" ] && [ "$(otool -l "$1" | grep -c LC_CODE_SIGNATURE)" -eq 0 ]; then
    echo "error: no LC_CODE_SIGNATURE in $1" >&2
    missing=$((missing + 1))
  fi
}
check "$APP/Runner"
for d in "$APP"/Frameworks/*.dylib; do check "$d"; done
for f in "$APP"/Frameworks/*.framework; do check "$f/$(basename "$f" .framework)"; done
if [ "$missing" -ne 0 ]; then
  echo "error: $missing binary(ies) left unsigned; the IPA would not sideload" >&2
  exit 1
fi
echo "all binaries carry LC_CODE_SIGNATURE"

say "packaging"
mkdir -p "$OUT_DIR"
rm -f "$IPA"
(
  cd "$BUILD_DIR"
  rm -rf Payload
  mkdir Payload
  cp -R Runner.app Payload/
  zip -qry "$IPA" Payload
  rm -rf Payload
)

say "done"
ls -lh "$IPA"
cat <<EOF

Install it:  AltServer menu bar icon -> Sideload .ipa -> Varun Salian's iPad
             then pick $IPA
EOF
