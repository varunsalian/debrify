#!/usr/bin/env bash
# Capture once against checkpoint-owned tests and format-only ORIGINAL code.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
format_subject='style(catalog): format the original catalog detail screen'
checkpoint_subject='test(catalog): step 0 original-code characterization checkpoint'
resolve_subject() {
  local expected="$1"
  local revision
  revision="$(git log -1 --format=%H --fixed-strings --grep="$expected" HEAD)"
  if [[ -z "$revision" || "$(git show -s --format=%s "$revision")" != "$expected" ]]; then
    printf 'Missing exact subject: %s\n' "$expected" >&2
    exit 1
  fi
  printf '%s\n' "$revision"
}
formatted="$(resolve_subject "$format_subject")"
checkpoint="$(resolve_subject "$checkpoint_subject")"
for input in lib pubspec.yaml pubspec.lock; do
  if [[ "$(git rev-parse "$checkpoint:$input")" != "$(git rev-parse "$formatted:$input")" ]]; then
    printf 'Checkpoint application input differs from format-only ORIGINAL: %s\n' "$input" >&2
    exit 1
  fi
done
if [[ "$(uname -s)" != Linux ]]; then
  printf '%s\n' 'Run in calibrated linux/amd64 Flutter 3.44.8 with libsqlite3-dev.' >&2
  exit 1
fi
version="$(flutter --version)"
if [[ "$version" != 'Flutter 3.44.8 '* ]]; then
  printf '%s\n' 'Expected Flutter 3.44.8.' >&2
  exit 1
fi
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/catalog_detail"
mkdir -p "$evidence" "$repo/.dart_tool"
capture_root="$(mktemp -d "$repo/.dart_tool/catalog_detail_linux_original.XXXXXX")"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$checkpoint"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
flutter pub get
git diff --exit-code -- pubspec.lock
for input in lib pubspec.yaml pubspec.lock; do
  [[ "$(git rev-parse "HEAD:$input")" == "$(git rev-parse "$formatted:$input")" ]]
done
flutter test --no-pub --update-goldens \
  test/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --no-pub \
  test/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/catalog_detail/linux"
cp test/goldens/catalog_detail/linux/*.png "$repo/test/goldens/catalog_detail/linux/"
sha256sum test/goldens/catalog_detail/linux/*.png | tee "$evidence/linux-original-sha256.txt"
printf '%s\n' "$checkpoint" | tee "$evidence/linux-original-revision.txt"
printf '%s\n' "$formatted" > "$evidence/linux-original-format-revision.txt"
printf '%s\n' 'Four ORIGINAL Linux goldens copied. Verify provenance and hashes, commit separately, then make the Linux test always strict. Never regenerate against moved code.'
