#!/usr/bin/env bash
# Capture once against checkpoint-owned tests and format-only ORIGINAL code.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
format_subject='style(catalog): format the original catalog detail screen'
checkpoint_subject='test(catalog): step 0b original-code review checkpoint'
resolve_subject() {
  local expected="$1"
  local history revision subject
  history="$(git log --format=%H%x09%s HEAD)"
  while IFS=$'\t' read -r revision subject; do
    if [[ "$subject" == "$expected" ]]; then
      printf '%s\n' "$revision"
      return 0
    fi
  done <<< "$history"
  printf 'Missing exact subject: %s\n' "$expected" >&2
  exit 1
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
git ls-files -z 'test/goldens/catalog_detail/linux/*.png' | xargs -0 sha256sum > "$capture_root/.dart_tool/existing-linux.sha256"
flutter test --no-pub --update-goldens \
  test/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_views_test.dart \
  --plain-name 'reachable pixel golden tv_movie_rich' 2>&1 | tee "$evidence/linux-rich-original-capture.txt"
flutter test --no-pub \
  test/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-rich-original-strict.txt"
sha256sum --check "$capture_root/.dart_tool/existing-linux.sha256"
mkdir -p "$repo/test/goldens/catalog_detail/linux"
cp test/goldens/catalog_detail/linux/tv_movie_rich.png "$repo/test/goldens/catalog_detail/linux/"
sha256sum test/goldens/catalog_detail/linux/tv_movie_rich.png | tee "$evidence/linux-rich-original-sha256.txt"
printf '%s\n' "$checkpoint" | tee "$evidence/linux-rich-original-revision.txt"
printf '%s\n' "$formatted" > "$evidence/linux-rich-original-format-revision.txt"
printf '%s\n' 'Rich ORIGINAL Linux golden copied; five strict originals passed. Verify provenance and hashes and commit this asset separately. Never regenerate against moved code.'
