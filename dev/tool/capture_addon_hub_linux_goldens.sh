#!/usr/bin/env bash
# Original-code capture only, in Claude's reachable $HOME Linux clone.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
subject='test(addon_hub): step 0 original-code characterization checkpoint'
original_revision="$(git log -1 --format=%H --fixed-strings --grep="$subject" HEAD)"
if [[ -z "$original_revision" || "$(git show -s --format=%s "$original_revision")" != "$subject" ]]; then
  echo 'Missing exact addon-hub step-0 characterization checkpoint.' >&2
  exit 1
fi
format_subject='style(addon_hub): step 0a format-only original checkpoint'
format_revision="$(git log -1 --format=%H --fixed-strings --grep="$format_subject" "$original_revision")"
if [[ -z "$format_revision" || "$(git show -s --format=%s "$format_revision")" != "$format_subject" ]]; then
  echo 'Missing exact addon-hub format-only original.' >&2
  exit 1
fi
# Check every application file, not only the hub. The sole allowed delta is
# the byte-exact frozen test accessor appended to the unchanged original.
python3 - "$format_revision" "$original_revision" <<'PY'
import subprocess,sys
base,checkpoint=sys.argv[1:]
def git(*args):return subprocess.check_output(['git',*args])
def blobs(revision):
    result={}
    for line in git('ls-tree','-r',revision,'lib').decode().splitlines():
        meta,path=line.split('\t',1)
        result[path]=meta.split()[2]
    return result
before,after=blobs(base),blobs(checkpoint)
# Empty directory marker exists so original source guards scan unconditionally.
marker='lib/features/addon_hub/.gitkeep'
assert git('show',checkpoint+':'+marker)==b''
after.pop(marker)
assert before.keys()==after.keys()
source='lib/screens/addons/addon_hub_screen.dart'
for path,blob in before.items():
    if path==source:
        old=git('show',base+':'+path);new=git('show',checkpoint+':'+path)
        seam=git('show',checkpoint+':dev/tool/addon_hub_accessor.dart.txt')
        assert new==old+seam, 'Checkpoint application differs beyond the frozen accessor'
    else:
        assert blob==after[path], 'Checkpoint changed application file: '+path
print('All application files equal the format-only original after the exact frozen accessor is removed.')
PY
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run in calibrated debrify-flutter:3.44.8 linux/amd64 with libsqlite3.' >&2
  exit 1
fi
flutter --version | head -1 | grep -F 'Flutter 3.44.8' >/dev/null
capture_root="$(mktemp -d /tmp/addon-hub-original-linux.XXXXXX)"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$original_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
cd "$capture_root"
[[ "$(git rev-parse HEAD)" == "$original_revision" ]]
flutter pub get
common="$(git rev-parse --git-common-dir)"
evidence="$common/refactor-evidence/addon_hub"
mkdir -p "$evidence"
flutter test --no-pub --dart-define=ADDON_HUB_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  test/features/addon_hub/presentation/legacy_addon_hub/addon_hub_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --no-pub --dart-define=ADDON_HUB_REQUIRE_ORIGINAL_LINUX=true \
  test/features/addon_hub/presentation/legacy_addon_hub/addon_hub_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/addon_hub/linux"
cp test/goldens/addon_hub/linux/*.png "$repo/test/goldens/addon_hub/linux/"
sha256sum test/goldens/addon_hub/linux/*.png | tee "$evidence/linux-original-sha256.txt"
git rev-parse HEAD | tee "$evidence/linux-original-revision.txt"
echo 'Original Linux PNGs copied. Record image/calibration/runner provenance in linux-original-run-url.txt; review and commit assets separately.'
