#!/usr/bin/env bash
# Capture only checkpoint-owned tests on hash-verified ORIGINAL application code.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
checkpoint_subject='test(episodes-panel): step 0 original-code characterization checkpoint'
reference_subject='style(episodes-panel): format the original episodes panel'
# Consume the entire log before matching: no early reader may SIGPIPE git log.
revision_log="$(git log --format='%H %s' HEAD)"
resolve_subject() {
  local subject="$1"
  local matches
  matches="$(python3 -c 'import sys; subject=sys.argv[1]; rows=sys.stdin.read().splitlines(); matches=[row[:40] for row in rows if row[41:]==subject]; assert len(matches)==1, (subject,matches); print(matches[0])' "$subject" <<< "$revision_log")"
  printf '%s\n' "$matches"
}
checkpoint_revision="$(resolve_subject "$checkpoint_subject")"
reference_revision="$(resolve_subject "$reference_subject")"
for input in lib pubspec.yaml pubspec.lock; do
  if [[ "$(git rev-parse "$checkpoint_revision:$input")" != "$(git rev-parse "$reference_revision:$input")" ]]; then
    echo "ORIGINAL application mismatch at $input" >&2
    exit 1
  fi
done
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run in calibrated debrify-flutter:3.44.8 linux/amd64 with libsqlite3.' >&2
  exit 1
fi
sdk_json="$(flutter --version --machine)"
python3 -c 'import json,sys; s=json.loads(sys.stdin.read()); assert s["frameworkVersion"]=="3.44.8"; assert s["dartSdkVersion"]=="3.12.2"' <<< "$sdk_json"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/episodes_panel"
mkdir -p "$evidence" "$repo/.dart_tool"
capture_root="$(mktemp -d "$repo/.dart_tool/episodes_panel_linux_original.XXXXXX")"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$checkpoint_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
flutter pub get
test_path='test/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_goldens_test.dart'
flutter test --no-pub --dart-define=EPISODES_PANEL_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture.txt"
sha256sum test/goldens/episodes_panel/linux/*.png > "$evidence/linux-original-first-sha256.txt"
flutter test --no-pub --dart-define=EPISODES_PANEL_CAPTURE_ORIGINAL_LINUX=true \
  --dart-define=EPISODES_PANEL_REVERSE_GOLDENS=true --update-goldens "$test_path" \
  2>&1 | tee "$evidence/linux-original-reverse-capture.txt"
sha256sum test/goldens/episodes_panel/linux/*.png > "$evidence/linux-original-second-sha256.txt"
cmp "$evidence/linux-original-first-sha256.txt" "$evidence/linux-original-second-sha256.txt"
flutter test --no-pub --dart-define=EPISODES_PANEL_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/episodes_panel/linux"
cp test/goldens/episodes_panel/linux/*.png "$repo/test/goldens/episodes_panel/linux/"
sha256sum test/goldens/episodes_panel/linux/*.png | tee "$evidence/linux-original-sha256.txt"
printf '%s\n' "$checkpoint_revision" | tee "$evidence/linux-original-revision.txt"
printf 'local calibrated Docker capture; checkpoint %s; reference %s; captured %s\n' \
  "$checkpoint_revision" "$reference_revision" "$(date -u +%FT%TZ)" > "$evidence/linux-original-run-url.txt"
echo 'Five repeatable Linux originals copied. Verify provenance and commit separately.'
