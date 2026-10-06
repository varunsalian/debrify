#!/usr/bin/env bash
# ORIGINAL captures only, in calibrated debrify-flutter:3.44.8 linux/amd64.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
revision_log="$(git log --format='%H %s' HEAD)"
resolve_subject() {
  python3 -c 'import sys; subject=sys.argv[1]; matches=[r[:40] for r in sys.stdin.read().splitlines() if r[41:]==subject]; assert len(matches)==1,(subject,matches); print(matches[0])' "$1" <<< "$revision_log"
}
reference_revision="$(git rev-parse 49c53e2e)"
checkpoint_revision="$(resolve_subject 'test(recordings): step 0 original-code characterization checkpoint')"
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
evidence="$common/refactor-evidence/recordings"
mkdir -p "$evidence" "$repo/.dart_tool"
capture_root="$(mktemp -d "$HOME/recordings_linux_original.XXXXXX")"
rmdir "$capture_root"
git clone --no-hardlinks "$repo" "$capture_root"
git -C "$capture_root" checkout --detach "$checkpoint_revision"
[[ -d "$capture_root/.git" ]]
trap 'rm -rf "$capture_root"' EXIT
cd "$capture_root"
flutter pub get
git diff --exit-code -- pubspec.yaml pubspec.lock
test_path=test/features/recordings/presentation/recordings_goldens_test.dart
flutter test --no-pub --concurrency=1 --dart-define=RECORDINGS_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture-first.txt"
sha256sum test/goldens/recordings/linux/*.png > "$evidence/linux-original-sha256-first.txt"
[[ "$(find test/goldens/recordings/linux -name '*.png' | wc -l | tr -d ' ')" == 3 ]]
rm test/goldens/recordings/linux/*.png
flutter test --no-pub --concurrency=1 --dart-define=RECORDINGS_CAPTURE_ORIGINAL_LINUX=true \
  --dart-define=RECORDINGS_REVERSE_GOLDENS=true --update-goldens "$test_path" \
  2>&1 | tee "$evidence/linux-original-capture-reverse.txt"
[[ "$(find test/goldens/recordings/linux -name '*.png' | wc -l | tr -d ' ')" == 3 ]]
sha256sum test/goldens/recordings/linux/*.png > "$evidence/linux-original-sha256-reverse.txt"
cmp "$evidence/linux-original-sha256-first.txt" "$evidence/linux-original-sha256-reverse.txt"
flutter test --no-pub --concurrency=1 --dart-define=RECORDINGS_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/recordings/linux"
cp test/goldens/recordings/linux/*.png "$repo/test/goldens/recordings/linux/"
printf 'checkpoint %s\nreference %s\nlib %s\npubspec.yaml %s\npubspec.lock %s\nUTC %s\n' \
  "$checkpoint_revision" "$reference_revision" "$(git rev-parse "$checkpoint_revision:lib")" \
  "$(git rev-parse "$checkpoint_revision:pubspec.yaml")" "$(git rev-parse "$checkpoint_revision:pubspec.lock")" \
  "$(date -u +%FT%TZ)" > "$evidence/linux-original-revision.txt"
printf '%s\n' "$sdk_json" >> "$evidence/linux-original-revision.txt"
echo 'Three repeatable ORIGINAL Linux PNGs and strict evidence copied. Review and commit separately.'
