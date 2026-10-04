#!/usr/bin/env bash
# Capture ONLY the characterized original; never regenerate against moved code.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
checkpoint_subject='test(detail-showcase): step 0 original-code characterization checkpoint'
format_subject='style(showcase): format the original showcase parts'
# Consume all git-log output: an early awk exit causes SIGPIPE under pipefail.
checkpoint="$(git log --format='%H %s' HEAD | awk -v subject="$checkpoint_subject" 'substr($0,42)==subject {print substr($0,1,40)}')"
reference="$(git log --format='%H %s' HEAD | awk -v subject="$format_subject" 'substr($0,42)==subject {print substr($0,1,40)}')"
for revision in "$checkpoint" "$reference"; do
  if [[ -z "$revision" || "$revision" == *$'\n'* ]]; then
    echo 'Expected exactly one checkpoint and one format-only reference, by exact subject.' >&2
    exit 1
  fi
done
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
image_id="${DETAIL_SHOWCASE_LINUX_IMAGE_ID:?Set DETAIL_SHOWCASE_LINUX_IMAGE_ID to the calibrated Docker image ID}"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/detail_showcase"
mkdir -p "$evidence" "$repo/.dart_tool"
flutter --version > "$evidence/linux-original-sdk.txt"
grep -E '^Flutter 3\.44\.8 ' "$evidence/linux-original-sdk.txt" >/dev/null
capture_root="$(mktemp -d "$repo/.dart_tool/detail_showcase_linux_original.XXXXXX")"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$checkpoint"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
[[ "$(git rev-parse HEAD)" == "$checkpoint" ]]
flutter pub get
[[ "$(git hash-object pubspec.lock)" == "$(git rev-parse "$checkpoint:pubspec.lock")" ]]
test_path='test/features/detail_showcase/presentation/detail_showcase_goldens_test.dart'
flutter test --no-pub --dart-define=DETAIL_SHOWCASE_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --no-pub --dart-define=DETAIL_SHOWCASE_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/detail_showcase/linux"
for scene in tv_movie compact_series wide_series_bands compact_guide; do
  cp "test/goldens/detail_showcase/linux/$scene.png" "$repo/test/goldens/detail_showcase/linux/$scene.png"
done
sha256sum test/goldens/detail_showcase/linux/*.png | tee "$evidence/linux-original-sha256.txt"
{
  printf 'checkpoint=%s\nreference=%s\nimage_id=%s\nplatform=linux/amd64\n' "$checkpoint" "$reference" "$image_id"
  for input in lib test pubspec.yaml pubspec.lock; do
    printf '%s=%s\n' "$input" "$(git rev-parse "$checkpoint:$input")"
  done
  cat "$evidence/linux-original-sdk.txt"
} | tee "$evidence/linux-original-revision.txt"
printf '%s\n' "${DETAIL_SHOWCASE_LINUX_RUN_URL:-Local calibrated linux/amd64 Docker capture}" > "$evidence/linux-original-run-url.txt"
echo 'Four ORIGINAL Linux goldens copied. Verify provenance/hashes, commit separately as step L, then enable strict Linux tests.'
