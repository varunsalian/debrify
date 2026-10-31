#!/usr/bin/env bash
# Recapture Linux goldens for the given test files, as CI renders them.
#
#   dev/tool/capture_linux_goldens.sh test/path/a_test.dart [test/path/b_test.dart ...]
#
# Runs in the calibrated debrify-flutter:3.44.8 linux/amd64 image under Colima
# (`colima start` first). Clones the committed HEAD into the container (so
# commit the UI change before capturing), captures twice and requires
# byte-identical results, then replays strictly and copies every changed
# Linux golden back into this checkout. About 4 minutes for two golden files.
# GOLDEN_GLOB selects the Linux goldens to collect (default
# test/goldens/**/linux/*.png), e.g. GOLDEN_GLOB='test/theme/goldens/linux/*.png'.
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo "usage: $0 <golden test file>..." >&2
  exit 2
fi
repo="$(git rev-parse --show-toplevel)"
# Colima shares only the home directory with its VM.
out="$HOME/.cache/debrify-linux-goldens"
rm -rf "$out"
mkdir -p "$out"
common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"
docker run -i --rm --platform linux/amd64 \
  -v "$common:/source.git:ro" -v "$out:/out" \
  -e REVISION="$(git -C "$repo" rev-parse HEAD)" \
  -e TESTS="$*" \
  -e GOLDEN_GLOB="${GOLDEN_GLOB:-test/goldens/**/linux/*.png}" \
  debrify-flutter:3.44.8 bash -s <<'CONTAINER'
set -euo pipefail
root="$(mktemp -d "$HOME/goldens.XXXXXX")"
git -c safe.directory=/source.git clone -q --no-hardlinks /source.git "$root"
cd "$root"
git checkout -q --detach "$REVISION"
read -r -a tests <<< "$TESTS"
flutter pub get > /out/pub-get.txt 2>&1
snapshot() { git ls-files -m -o --exclude-standard "$GOLDEN_GLOB" | sort | xargs -r sha256sum; }
flutter test --update-goldens "${tests[@]}" > /out/capture-1.txt 2>&1 || true
snapshot > /out/sha-1.txt
flutter test --update-goldens "${tests[@]}" > /out/capture-2.txt 2>&1 || true
snapshot > /out/sha-2.txt
cmp -s /out/sha-1.txt /out/sha-2.txt || { echo "captures differ" >&2; exit 1; }
flutter test "${tests[@]}" > /out/replay.txt 2>&1 || { tail -20 /out/replay.txt >&2; exit 1; }
git ls-files -m -o --exclude-standard "$GOLDEN_GLOB" > /out/changed.txt
while read -r f; do mkdir -p "/out/files/$(dirname "$f")"; cp "$f" "/out/files/$f"; done < /out/changed.txt
CONTAINER
while read -r f; do
  mkdir -p "$repo/$(dirname "$f")"
  cp "$out/files/$f" "$repo/$f"
done < "$out/changed.txt"
echo "Linux goldens updated: $(wc -l < "$out/changed.txt" | tr -d ' ') file(s)"
cat "$out/changed.txt"
