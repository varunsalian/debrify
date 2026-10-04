#!/usr/bin/env bash
# Original-code capture only; checkpoint owns all tests and fixture inputs.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
subject='test(merged): step 0 original-code characterization checkpoint'
original_revision="$(git log --format='%H %s' HEAD | awk -v subject="$subject" 'substr($0,42)==subject {print substr($0,1,40)}')"
if [[ -z "$original_revision" || "$original_revision" == *$'\n'* ]]; then
  echo 'Expected one exact merged-detail step-0 characterization checkpoint.' >&2
  exit 1
fi
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run in the calibrated linux/amd64 image with Flutter 3.44.8 and libsqlite3-dev.' >&2
  exit 1
fi
flutter --version | head -1 | grep -F 'Flutter 3.44.8' >/dev/null
capture_root="$(mktemp -d /tmp/merged-detail-original-linux.XXXXXX)"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$original_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
flutter pub get
common="$(git rev-parse --git-common-dir)"
evidence="$common/refactor-evidence/merged_detail"
mkdir -p "$evidence"
flutter test --dart-define=MERGED_DETAIL_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  test/features/merged_detail/presentation/legacy_merged_detail/merged_detail_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --dart-define=MERGED_DETAIL_REQUIRE_ORIGINAL_LINUX=true \
  test/features/merged_detail/presentation/legacy_merged_detail/merged_detail_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/merged_detail/linux"
cp test/goldens/merged_detail/linux/*.png "$repo/test/goldens/merged_detail/linux/"
sha256sum test/goldens/merged_detail/linux/*.png | tee "$evidence/linux-original-sha256.txt"
git rev-parse HEAD | tee "$evidence/linux-original-revision.txt"
echo 'Five original Linux goldens copied. Verify hashes/provenance and commit separately; never regenerate against moved code.'
