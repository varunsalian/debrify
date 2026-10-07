#!/usr/bin/env bash
# Claude-owned Step L: two ORIGINAL-code captures in opposite orders, then strict replay.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
original_revision="$(git -c grep.patternType=basic log -1 --format=%H --grep='^test(alldebrid-files): step 0 original-code characterization checkpoint$' HEAD)"
if [[ -z "$original_revision" ]]; then
  echo 'Missing reviewed AllDebrid Step 0 checkpoint.' >&2
  exit 1
fi
common="$(git rev-parse --path-format=absolute --git-common-dir)"
evidence="$common/refactor-evidence/alldebrid_files"
mkdir -p "$evidence"
image_id="$(docker image inspect debrify-flutter:3.44.8 --format '{{.Id}}')"
printf '%s\n' "$image_id" > "$evidence/linux-original-image.txt"
printf '%s\n' "$original_revision" > "$evidence/linux-original-revision.txt"
# Mount the git directory rather than the worktree's .git pointer. The normal
# clone lives below the container HOME, has its own .git directory and resolves
# its application packages with flutter pub get inside the container.
docker run -i --rm --platform linux/amd64 \
  -v "$common:/source.git:ro" -v "$evidence:/evidence" \
  -e ORIGINAL_REVISION="$original_revision" \
  debrify-flutter:3.44.8 bash -s <<'CONTAINER'
set -euo pipefail
capture_root="$(mktemp -d "$HOME/alldebrid-original.XXXXXX")"
git -c safe.directory=/source.git clone --no-hardlinks /source.git "$capture_root"
cd "$capture_root"
git checkout --detach "$ORIGINAL_REVISION"
test -d .git
flutter --version --machine > /evidence/linux-original-sdk.json
python3 - <<'PY'
import json
assert json.load(open('/evidence/linux-original-sdk.json'))['frameworkVersion'] == '3.44.8'
PY
flutter pub get
views=test/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_views_test.dart
flutter test --dart-define=ALLDEBRID_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  "$views" --plain-name 'reachable pixel golden' 2>&1 | tee /evidence/linux-original-capture.txt
sha256sum test/goldens/alldebrid_files/linux/*.png > /evidence/linux-original-first-sha256.txt
flutter test --dart-define=ALLDEBRID_CAPTURE_ORIGINAL_LINUX=true \
  --dart-define=ALLDEBRID_GOLDEN_REVERSE=true --update-goldens \
  "$views" --plain-name 'reachable pixel golden' 2>&1 | tee /evidence/linux-original-capture-reversed.txt
sha256sum test/goldens/alldebrid_files/linux/*.png > /evidence/linux-original-sha256.txt
cmp /evidence/linux-original-first-sha256.txt /evidence/linux-original-sha256.txt
flutter test --dart-define=ALLDEBRID_REQUIRE_ORIGINAL_LINUX=true \
  "$views" --plain-name 'reachable pixel golden' 2>&1 | tee /evidence/linux-original-strict.txt
mkdir -p /evidence/linux-original-pngs
cp test/goldens/alldebrid_files/linux/*.png /evidence/linux-original-pngs/
git rev-parse 'HEAD^{tree}' > /evidence/linux-original-tree.txt
CONTAINER
mkdir -p "$repo/test/goldens/alldebrid_files/linux"
cp "$evidence/linux-original-pngs/"*.png "$repo/test/goldens/alldebrid_files/linux/"
echo 'Six original Linux PNGs copied; review provenance and commit separately at Step L.'
