#!/usr/bin/env bash
# Original-code capture only. No SDK installation, branch change, or push.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
original_revision=c4f5375a
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run this script on Ubuntu with Flutter 3.44.8 already installed.' >&2
  exit 1
fi
flutter --version | head -1 | grep -F 'Flutter 3.44.8' >/dev/null
capture_root="$(mktemp -d /tmp/torbox-original-linux.XXXXXX)"
# git worktree requires its destination not to exist.
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$original_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
# Use the reviewed characterization tests with the original screen/accessor.
cp -R "$repo/test/features/torbox_downloads" "$capture_root/test/features/"
cp "$repo/test/support/torbox_downloads_fixture.dart" "$capture_root/test/support/"
# Original source guards resolve against the original move manifest/config.
cd "$capture_root"
flutter pub get
common="$(git rev-parse --git-common-dir)"
evidence="$common/refactor-evidence/torbox"
mkdir -p "$evidence"
flutter test --dart-define=TORBOX_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  test/features/torbox_downloads/presentation/legacy_torbox/torbox_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test test/features/torbox_downloads/presentation/legacy_torbox/torbox_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/torbox_downloads/linux"
cp test/goldens/torbox_downloads/linux/*.png "$repo/test/goldens/torbox_downloads/linux/"
sha256sum test/goldens/torbox_downloads/linux/*.png | tee "$evidence/linux-original-sha256.txt"
git rev-parse HEAD | tee "$evidence/linux-original-revision.txt"
echo 'Original Linux goldens copied to your checkout. Review and commit the four PNGs; do not regenerate them against extracted code.'
