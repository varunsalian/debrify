#!/usr/bin/env bash
# Original-code capture only. No SDK installation, branch change, or push.
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
# Resolve the unique step-0 checkpoint itself, including when this script is
# executed from that commit. A commit cannot contain its own literal hash.
original_revision="$(git log -1 --format=%H --grep='^test(premiumize): step 0 original-code characterization checkpoint$' HEAD)"
if [[ -z "$original_revision" ]]; then
  echo 'Missing reviewed Premiumize step-0 original-code checkpoint.' >&2
  exit 1
fi
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run this script on Ubuntu with Flutter 3.44.8 already installed.' >&2
  exit 1
fi
flutter --version | grep -F 'Flutter 3.44.8' >/dev/null
capture_root="$(mktemp -d /tmp/premiumize-original-linux.XXXXXX)"
rmdir "$capture_root"
git worktree add --detach "$capture_root" "$original_revision"
trap 'git -C "$repo" worktree remove --force "$capture_root"' EXIT
# The checkpoint owns its tests, fixture, and unchanged original screen/accessor.
cd "$capture_root"
flutter pub get
# Refuse an extraction or a different original. The only permitted production
# addition at this checkpoint is the registered testing accessor.
python3 - <<'PYTHON'
import subprocess
from pathlib import Path
source = 'lib/screens/premiumize/premiumize_files_screen.dart'
original = subprocess.check_output(['git', 'show', '49c53e2e:' + source])
assert Path(source).read_bytes().startswith(original)
assert not list(Path('lib/features/premiumize_files').rglob('*.dart'))
PYTHON
common="$(git rev-parse --git-common-dir)"
evidence="$common/refactor-evidence/premiumize"
mkdir -p "$evidence"
flutter test --dart-define=PREMIUMIZE_CAPTURE_ORIGINAL_LINUX=true --update-goldens \
  test/features/premiumize_files/presentation/legacy_premiumize/premiumize_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-capture.txt"
flutter test --dart-define=PREMIUMIZE_REQUIRE_ORIGINAL_LINUX=true \
  test/features/premiumize_files/presentation/legacy_premiumize/premiumize_views_test.dart \
  --plain-name 'reachable pixel golden' 2>&1 | tee "$evidence/linux-original-strict.txt"
mkdir -p "$repo/test/goldens/premiumize_files/linux"
cp test/goldens/premiumize_files/linux/*.png "$repo/test/goldens/premiumize_files/linux/"
sha256sum test/goldens/premiumize_files/linux/*.png | tee "$evidence/linux-original-sha256.txt"
git rev-parse HEAD | tee "$evidence/linux-original-revision.txt"
python3 - "$evidence" <<'PYTHON'
import hashlib, json, subprocess, sys
from pathlib import Path
inputs = [Path('lib/screens/premiumize/premiumize_files_screen.dart'),
          *Path('test/features/premiumize_files').rglob('*'),
          *Path('test/support').glob('premiumize_*.dart')]
metadata = {
    'checkpoint': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'sdk': json.loads(subprocess.check_output(['flutter', '--version', '--machine'], text=True)),
    'capture_flag': 'PREMIUMIZE_CAPTURE_ORIGINAL_LINUX=true',
    'strict_flag': 'PREMIUMIZE_REQUIRE_ORIGINAL_LINUX=true',
    'input_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in inputs if p.is_file()},
    'golden_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in Path('test/goldens/premiumize_files/linux').glob('*.png')},
}
assert len(metadata['golden_sha256']) == 7
Path(sys.argv[1], 'linux-original-env.json').write_text(json.dumps(metadata, indent=2) + '\n')
PYTHON
echo 'Seven original Linux goldens copied. Review and commit the PNGs; do not regenerate them against extracted code.'
