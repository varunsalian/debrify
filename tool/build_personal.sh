#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
platform=${1:-}
configuration=${2:-Release}
display_name="Debrify Personal"
suffix=.personal

usage() {
  echo "Usage: tool/build_personal.sh android|ios|tvos|macos [Debug|Release]" >&2
  exit 64
}

case "$platform" in
  android)
    case "$configuration" in
      Debug|debug) task=assembleDebug ;;
      Release|release) task=assembleRelease ;;
      *) usage ;;
    esac
    cd "$repo_dir/android"
    if [ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]; then
      JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
      export JAVA_HOME
    fi
    ./gradlew "$task" -PdebrifyPersonalBuild=true
    ;;
  ios)
    exec xcodebuild \
      -workspace "$repo_dir/ios/Runner.xcworkspace" \
      -scheme Runner \
      -configuration "$configuration" \
      -destination 'generic/platform=iOS' \
      -allowProvisioningUpdates \
      -derivedDataPath "$repo_dir/build/personal/ios" \
      DEBRIFY_BUNDLE_SUFFIX="$suffix" \
      DEBRIFY_APP_DISPLAY_NAME="$display_name"
    ;;
  tvos)
    # The personal build deliberately omits App Group entitlements. Its main
    # app data stays isolated; Top Shelf is allowed to be unavailable.
    exec xcodebuild \
      -workspace "$repo_dir/tvos/Runner.xcworkspace" \
      -scheme Runner \
      -configuration "$configuration" \
      -destination 'generic/platform=tvOS' \
      -allowProvisioningUpdates \
      -derivedDataPath "$repo_dir/build/personal/tvos" \
      DEBRIFY_BUNDLE_SUFFIX="$suffix" \
      DEBRIFY_APP_DISPLAY_NAME="$display_name" \
      DEBRIFY_APP_GROUP=group.com.varunsalian.debrifytv.personal \
      CODE_SIGN_ENTITLEMENTS=
    ;;
  macos)
    exec xcodebuild \
      -workspace "$repo_dir/macos/Runner.xcworkspace" \
      -scheme Runner \
      -configuration "$configuration" \
      -destination 'platform=macOS' \
      -derivedDataPath "$repo_dir/build/personal/macos" \
      DEBRIFY_BUNDLE_SUFFIX="$suffix" \
      DEBRIFY_APP_DISPLAY_NAME="$display_name" \
      DEBRIFY_PRODUCT_NAME="$display_name"
    ;;
  *) usage ;;
esac
