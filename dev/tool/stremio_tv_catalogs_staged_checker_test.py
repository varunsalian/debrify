"""Keep frozen ORIGINAL negatives and verify the current staged production split."""
import copy
import csv
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def self_test(package=None):
    import check_settings_moves
    from check_verbatim_moves import ROOT
    from stremio_tv_catalogs_checker_test import self_test as original_self_test
    from stremio_tv_catalogs_probe import SOURCE, GROUPS

    assert package is not None, 'An isolated --parser-package is required'
    config_path = 'dev/tool/stremio_tv_catalogs_checker_config.json'
    manifest_path = 'dev/tool/stremio_tv_catalogs_manifest.tsv'
    config = json.loads((ROOT / config_path).read_text())
    # The frozen test starts with ORIGINAL, whose aliases have no owner files.
    # Use its creation-stage registrations for that fixture; all its positives
    # and negatives run unchanged. Actual production uses the staged config below.
    original_config = copy.deepcopy(config)
    original_config.update(type_aliases=[], file_aliases=[], additional_owners=[], completed_step=0)
    with tempfile.TemporaryDirectory(prefix='stremio_tv_catalogs_checker_fixture_', dir=ROOT / '.dart_tool') as directory:
        fixture = Path(directory)
        (fixture / 'dev/tool').mkdir(parents=True)
        (fixture / config_path).write_text(json.dumps(original_config, indent=2) + '\n')
        shutil.copyfile(ROOT / manifest_path, fixture / manifest_path)
        # Read-only git show resolves the same original revision through a
        # gitfile to this checkout's git directory (a worktree or a main clone).
        git_dir = subprocess.check_output(['git', 'rev-parse', '--absolute-git-dir'], cwd=ROOT, text=True).strip()
        (fixture / '.git').write_text('gitdir: ' + git_dir + '\n')
        with check_settings_moves.configured(original_config):
            previous = check_settings_moves.ROOT
            try:
                check_settings_moves.ROOT = fixture
                original_self_test(package)
            finally:
                check_settings_moves.ROOT = previous

    original = subprocess.check_output(['git', 'show', config['baseline'] + ':' + SOURCE], cwd=ROOT, text=True)
    with (ROOT / manifest_path).open() as handle:
        rows = list(csv.DictReader(handle, delimiter='\t'))
    sources = {path: (ROOT / path).read_text() for path in [SOURCE, *GROUPS] if (ROOT / path).exists()}
    errors = check_settings_moves.check(original, sources, rows, SOURCE, package, config=config)
    assert not errors, errors
    print('Stremio catalogs current staged production positive: PASS')
