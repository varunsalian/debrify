#!/usr/bin/env bash
# Capture ONLY the exact original characterization checkpoint, inside this clone.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
checkpoint="$(git log --format='%H%x09%s' HEAD | awk -F '\t' '$2 == "test(spotlight-board): step 0 original-code characterization checkpoint" { print $1; exit }')"
reference="$(git log --format='%H%x09%s' HEAD | awk -F '\t' '$2 == "style(spotlight): format the original spotlight board" { print $1; exit }')"
if [[ -z "$checkpoint" || -z "$reference" ]]; then
  echo 'Missing exact Spotlight step-0 checkpoint or approved reference R.' >&2
  exit 1
fi
for path in lib pubspec.yaml pubspec.lock; do
  original_hash="$(git rev-parse "$checkpoint:$path")"
  reference_hash="$(git rev-parse "$reference:$path")"
  if [[ "$original_hash" != "$reference_hash" ]]; then
    echo "Original application differs from approved R: $path" >&2
    exit 1
  fi
  echo "$path $original_hash = $reference_hash"
done
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run in the calibrated debrify-flutter:3.44.8 linux/amd64 image.' >&2
  exit 1
fi
flutter --version | head -1 | grep -F 'Flutter 3.44.8' >/dev/null
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/spotlight_board"
mkdir -p "$evidence" "$repo/.dart_tool/spotlight_board"
capture_root="$(mktemp -d "$repo/.dart_tool/spotlight_board/linux-original.XXXXXX")"
trap 'rm -rf "$capture_root"' EXIT
git archive "$checkpoint" | tar -xf - -C "$capture_root"
cd "$capture_root"
flutter pub get
test_path='test/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_goldens_test.dart'
flutter test --no-pub --dart-define=SPOTLIGHT_BOARD_CAPTURE_ORIGINAL_LINUX=true \
  --update-goldens "$test_path" 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --no-pub --dart-define=SPOTLIGHT_BOARD_REQUIRE_ORIGINAL_LINUX=true \
  "$test_path" 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/spotlight_board/linux"
cp test/goldens/spotlight_board/linux/*.png "$repo/test/goldens/spotlight_board/linux/"
sha256sum test/goldens/spotlight_board/linux/*.png | tee "$evidence/linux-original-sha256.txt"
echo "$checkpoint" | tee "$evidence/linux-original-revision.txt"
echo "${SPOTLIGHT_BOARD_LINUX_RUN_URL:-local calibrated linux/amd64 debrify-flutter:3.44.8 capture $(date -u +%FT%TZ)}" > "$evidence/linux-original-run-url.txt"
echo "Approved R: $reference; characterization checkpoint: $checkpoint"
echo 'Six ORIGINAL Linux goldens copied. Verify provenance and commit separately.'
