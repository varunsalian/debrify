"""Validate the pipelined S2e seam without inventing phase-15 history.

The exhaustive seam ledger proves the facade delta. The accepted applied
ownership ledger, extended by just those patches, still proves its complete
facade/destinations and unmodified historical destination protections. This is
not a phase-16 move/history proof; that remains blocked until phase 15 merges.
"""
import copy

from check_verbatim_moves import ROOT
from check_dart_moves import check, run_manifest
from dart_move_history import load_manifest, git_text, earlier_sources, check_earlier

S2E = 'dev/tool/dart_moves/vplayer_p16_seam.json'


def run_current_manifest(path, package):
    seam = load_manifest(path)
    if seam.get('checkpoint') != 'S2e':
        return run_manifest(path, package)
    # These constants are the accepted pre-P15 boundary, not a configurable
    # history exemption. All ordinary production manifests use run_manifest.
    assert seam['phase'] == 16 and seam['base'] == 'be4cd78aa'
    assert seam['destinations'] == seam['scaffolding'] == {}
    source = seam['source']
    current = (ROOT / source).read_text()
    errors = check(seam, git_text(seam['base'], source), {source: current}, package)
    owner_path = 'dev/tool/dart_moves/vplayer_p14.json'
    owner = load_manifest(owner_path)
    assert owner == load_manifest(owner_path, seam['base'])
    assert owner['status'] == 'applied' and owner['phase'] == 14
    errors += run_manifest(owner_path, package, at=seam['base'])
    overlay = copy.deepcopy(owner)
    patches = {r['original']: r for r in seam['declarations'] if r['fate'] == 'patched'}
    assert set(patches) == {
        '_VideoPlayerScreenState._openStartupDebridDirect',
        '_VideoPlayerScreenState._tryOpenStartupVod'}
    for row in overlay['declarations']:
        if row['original'] in patches:
            assert row['fate'] == 'retained' and not row.get('substitutions')
            row.update(patches[row['original']])
    paths = {source, *owner['destinations']}
    sources = {p: (ROOT / p).read_text() for p in paths}
    errors += check(overlay, git_text(owner['base'], source), sources, package)
    earlier = earlier_sources(owner)
    actual = {p.relative_to(ROOT).as_posix()
              for p in (ROOT / owner['feature']).rglob('*.dart')}
    if actual != set(earlier) | set(owner['destinations']):
        errors.append('unexpected/missing feature source files')
    errors += check_earlier(owner, package)
    return errors
