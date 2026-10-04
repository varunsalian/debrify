#!/usr/bin/env bash
# Original-code capture only. No SDK installation, branch change, or push.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
# Resolve the unique step-0 checkpoint itself, including when this script is
# executed from that commit. A commit cannot contain its own literal hash.
original_revision="$(git log -1 --format=%H --grep='^test(iptv_settings): step 0 original-code characterization checkpoint$' HEAD)"
if [[ -z "$original_revision" ]]; then
  echo 'Missing reviewed IPTV settings step-0 original-code checkpoint.' >&2
  exit 1
fi
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run this script on Ubuntu with Flutter 3.44.8 already installed.' >&2
  exit 1
fi
flutter --version | head -1 | grep -F 'Flutter 3.44.8' >/dev/null
capture_root="$(mktemp -d /tmp/iptv_settings-original-linux.XXXXXX)"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$original_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
# The checkpoint owns its tests, fixture, and unchanged original screen/accessor.
cd "$capture_root"
flutter pub get
common="$(git rev-parse --git-common-dir)"
evidence="$common/refactor-evidence/iptv_settings"
mkdir -p "$evidence"
flutter test --dart-define=IPTV_SETTINGS_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  test/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --dart-define=IPTV_SETTINGS_REQUIRE_ORIGINAL_LINUX=true \
  test/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/iptv_settings/linux"
cp test/goldens/iptv_settings/linux/*.png "$repo/test/goldens/iptv_settings/linux/"
sha256sum test/goldens/iptv_settings/linux/*.png | tee "$evidence/linux-original-sha256.txt"
git rev-parse HEAD | tee "$evidence/linux-original-revision.txt"
echo 'Four original Linux goldens copied. Review and commit the PNGs; do not regenerate them against extracted code.'
