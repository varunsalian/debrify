#!/usr/bin/env bash
# Run from a clone under $HOME in calibrated debrify-flutter:3.44.8 linux/amd64.
# Only the Step 0b ORIGINAL review checkpoint may produce these PNGs.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
reference_revision=c7a3d156d260e08421043a5430c6242124ba8e1b
checkpoint_subject='test(stremio-tv): step 0b review closure checkpoint'
revision_log="$(git log --format='%H %s' HEAD)"
checkpoint_revision="$(python3 -c 'import sys; subject=sys.argv[1]; rows=sys.stdin.read().splitlines(); matches=[r[:40] for r in rows if r[41:]==subject]; assert len(matches)==1, (subject,matches); print(matches[0])' "$checkpoint_subject" <<< "$revision_log")"
for input in lib pubspec.yaml pubspec.lock; do
  if [[ "$(git rev-parse "$checkpoint_revision:$input")" != "$(git rev-parse "$reference_revision:$input")" ]]; then
    echo "ORIGINAL application mismatch at $input" >&2
    exit 1
  fi
done
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'Run in calibrated debrify-flutter:3.44.8 linux/amd64 with libsqlite3.' >&2
  exit 1
fi
sdk_json="$(flutter --version --machine)"
python3 -c 'import json,sys; s=json.loads(sys.stdin.read()); assert s["frameworkVersion"]=="3.44.8"; assert s["dartSdkVersion"]=="3.12.2"' <<< "$sdk_json"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/stremio_tv"
mkdir -p "$evidence" "$repo/.dart_tool"
capture_root="$(mktemp -d "$repo/.dart_tool/stremio_tv_linux_original.XXXXXX")"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$checkpoint_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
flutter pub get
test_path=test/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_goldens_test.dart
flutter test --no-pub --concurrency=1 --dart-define=STREMIO_TV_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture-first.txt"
sha256sum test/goldens/stremio_tv/linux/*.png > "$evidence/linux-original-sha256-first.txt"
[[ "$(find test/goldens/stremio_tv/linux -name '*.png' | wc -l | tr -d ' ')" == 6 ]]
rm test/goldens/stremio_tv/linux/*.png
flutter test --no-pub --concurrency=1 --dart-define=STREMIO_TV_CAPTURE_ORIGINAL_LINUX=true \
  --dart-define=STREMIO_TV_REVERSE_GOLDENS=true --update-goldens "$test_path" \
  2>&1 | tee "$evidence/linux-original-capture-reverse.txt"
[[ "$(find test/goldens/stremio_tv/linux -name '*.png' | wc -l | tr -d ' ')" == 6 ]]
sha256sum test/goldens/stremio_tv/linux/*.png > "$evidence/linux-original-sha256-reverse.txt"
cmp "$evidence/linux-original-sha256-first.txt" "$evidence/linux-original-sha256-reverse.txt"
flutter test --no-pub --concurrency=1 --dart-define=STREMIO_TV_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/stremio_tv/linux"
cp test/goldens/stremio_tv/linux/*.png "$repo/test/goldens/stremio_tv/linux/"
printf 'checkpoint %s\nreference %s\nlib %s\npubspec.yaml %s\npubspec.lock %s\nUTC %s\n' \
  "$checkpoint_revision" "$reference_revision" "$(git rev-parse "$checkpoint_revision:lib")" \
  "$(git rev-parse "$checkpoint_revision:pubspec.yaml")" "$(git rev-parse "$checkpoint_revision:pubspec.lock")" \
  "$(date -u +%FT%TZ)" > "$evidence/linux-original-revision.txt"
printf '%s\n' "$sdk_json" >> "$evidence/linux-original-revision.txt"
echo 'Six repeatable ORIGINAL Linux PNGs and strict evidence copied. Review and commit separately.'
