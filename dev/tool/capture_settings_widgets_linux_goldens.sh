#!/usr/bin/env bash
# Capture ONLY the characterized original; never regenerate against moved code.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
checkpoint_subject='test(settings-widgets): step 0b close review gaps on original'
format_subject='style(settings-widgets): format the original settings widgets'
# Consume all git-log output: an early awk exit causes SIGPIPE under pipefail.
checkpoint="$(git log --format='%H %s' HEAD | awk -v subject="$checkpoint_subject" 'substr($0,42)==subject {print substr($0,1,40)}')"
reference="$(git log --format='%H %s' HEAD | awk -v subject="$format_subject" 'substr($0,42)==subject {print substr($0,1,40)}')"
for revision in "$checkpoint" "$reference"; do
  if [[ -z "$revision" || "$revision" == *$'\n'* ]]; then
    echo 'Expected exactly one checkpoint and one format-only reference, by exact subject.' >&2
    exit 1
  fi
done
if [[ -n "$(git ls-tree -r --name-only "$checkpoint" -- test/goldens/settings_widgets/linux)" ]]; then
  echo 'Original capture checkpoint must not already contain Linux PNGs.' >&2
  exit 1
fi
for input in lib pubspec.yaml pubspec.lock; do
  if [[ "$(git rev-parse "$checkpoint:$input")" != "$(git rev-parse "$reference:$input")" ]]; then
    echo "Checkpoint application differs from format-only original: $input" >&2
    exit 1
  fi
done
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'Run in the calibrated linux/amd64 debrify-flutter:3.44.8 image with libsqlite3.' >&2
  exit 1
fi
image_id="${SETTINGS_WIDGETS_LINUX_IMAGE_ID:?Set SETTINGS_WIDGETS_LINUX_IMAGE_ID to the calibrated Docker image ID}"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/settings_widgets"
mkdir -p "$evidence" "$repo/.dart_tool"
flutter --version > "$evidence/linux-original-sdk.txt"
grep -E '^Flutter 3\.44\.8 ' "$evidence/linux-original-sdk.txt" >/dev/null
capture_root="$(mktemp -d "$repo/.dart_tool/settings_widgets_linux_original.XXXXXX")"
rmdir "$capture_root"
reproduction_root="$(mktemp -d "$repo/.dart_tool/settings_widgets_linux_reproduction.XXXXXX")"
rmdir "$reproduction_root"
cleanup() {
  git -C "$repo" worktree remove --force "$capture_root" 2>/dev/null || true
  git -C "$repo" worktree remove --force "$reproduction_root" 2>/dev/null || true
}
trap cleanup EXIT
git worktree add --detach "$capture_root" "$checkpoint"
cd "$capture_root"
[[ "$(git rev-parse HEAD)" == "$checkpoint" ]]
flutter pub get
[[ "$(git hash-object pubspec.lock)" == "$(git rev-parse "$checkpoint:pubspec.lock")" ]]
test_path='test/features/settings_widgets/presentation/settings_widgets_goldens_test.dart'
flutter test --no-pub --dart-define=SETTINGS_WIDGETS_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --no-pub --dart-define=SETTINGS_WIDGETS_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
sha256sum test/goldens/settings_widgets/linux/*.png | tee "$evidence/linux-original-sha256.txt"
# A second clean checkout starts with no Linux PNGs or first-run build/cache.
# Capture independently, then compare bytes; a replay of fresh PNGs alone is
# not evidence that two original renders reproduce one another.
git -C "$repo" worktree add --detach "$reproduction_root" "$checkpoint"
cd "$reproduction_root"
[[ "$(git rev-parse HEAD)" == "$checkpoint" ]]
[[ ! -d test/goldens/settings_widgets/linux ]]
flutter pub get
[[ "$(git hash-object pubspec.lock)" == "$(git rev-parse "$checkpoint:pubspec.lock")" ]]
flutter test --no-pub --dart-define=SETTINGS_WIDGETS_CAPTURE_ORIGINAL_LINUX=true \
  --dart-define=SETTINGS_WIDGETS_GOLDEN_ORDER=reverse \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-reproduction-capture.txt"
sha256sum test/goldens/settings_widgets/linux/*.png | tee "$evidence/linux-original-reproduction-sha256.txt"
cmp "$evidence/linux-original-sha256.txt" "$evidence/linux-original-reproduction-sha256.txt"
for scene in tv_legacy_gallery tv_spotlight_gallery wide_connections phone_connections phone_skeleton; do
  cmp "$capture_root/test/goldens/settings_widgets/linux/$scene.png" \
    "test/goldens/settings_widgets/linux/$scene.png"
done
flutter test --no-pub --dart-define=SETTINGS_WIDGETS_REQUIRE_ORIGINAL_LINUX=true \
  --dart-define=SETTINGS_WIDGETS_GOLDEN_ORDER=reverse \
  "$test_path" 2>&1 | tee "$evidence/linux-original-reproduction-strict.txt"
mkdir -p "$repo/test/goldens/settings_widgets/linux"
for scene in tv_legacy_gallery tv_spotlight_gallery wide_connections phone_connections phone_skeleton; do
  cp "test/goldens/settings_widgets/linux/$scene.png" "$repo/test/goldens/settings_widgets/linux/$scene.png"
done
{
  printf 'checkpoint=%s\nreference=%s\nimage_id=%s\nplatform=linux/amd64\n' "$checkpoint" "$reference" "$image_id"
  printf 'reproduction=independent-second-worktree-byte-identical\n'
  for input in lib test pubspec.yaml pubspec.lock; do
    printf '%s=%s\n' "$input" "$(git rev-parse "$checkpoint:$input")"
  done
  cat "$evidence/linux-original-sdk.txt"
} | tee "$evidence/linux-original-revision.txt"
printf '%s\n' "${SETTINGS_WIDGETS_LINUX_RUN_URL:-Local calibrated linux/amd64 Docker capture}" > "$evidence/linux-original-run-url.txt"
echo 'Five ORIGINAL Linux goldens copied. Verify provenance/hashes, commit separately as step L, then enable strict Linux tests.'
