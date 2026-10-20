"""Validate seam checkpoints (S2e on accepted P15, S2f on accepted P18) and all historical destinations.

The exhaustive seam ledger proves the facade delta. The accepted applied
ownership ledger, extended by just those patches, still proves its complete
facade/destinations and unmodified historical destination protections. This is
not a phase-16 production move/history proof.
"""
import copy

from check_verbatim_moves import ROOT
from check_dart_moves import check, run_manifest
from dart_move_history import load_manifest, git_text, earlier_sources, check_earlier



CHECKPOINTS = {
    # checkpoint: (phase, base, accepted owner ledger, owner phase, patched keys)
    'S2e': (16, 'ed7c6717a', 'dev/tool/dart_moves/vplayer_p15.json', 15, {
        '_VideoPlayerScreenState._openStartupDebridDirect',
        '_VideoPlayerScreenState._tryOpenStartupVod'}),
    'S2f': (19, '46bc00ce7', 'dev/tool/dart_moves/vplayer_p18.json', 18, {
        '_VideoPlayerScreenState._installDecoderObservers',
        '_VideoPlayerScreenState._scheduleRendererStartupValidation',
        'VpS2Hooks'}),
}


def run_current_manifest(path, package):
    seam = load_manifest(path)
    if seam.get('checkpoint') not in CHECKPOINTS:
        return run_manifest(path, package)
    phase, base, owner_path, owner_phase, keys = CHECKPOINTS[seam['checkpoint']]
    # The accepted owner boundary is fixed; ordinary production manifests use
    # run_manifest without an overlay or history exemption.
    assert seam['phase'] == phase and seam['base'] == base
    assert seam['destinations'] == seam['scaffolding'] == {}
    source = seam['source']
    current = (ROOT / source).read_text()
    errors = check(seam, git_text(seam['base'], source), {source: current}, package)
    owner = load_manifest(owner_path)
    assert owner == load_manifest(owner_path, seam['base'])
    assert owner['status'] == 'applied' and owner['phase'] == owner_phase
    errors += run_manifest(owner_path, package, at=seam['base'])
    overlay = copy.deepcopy(owner)
    patches = {r['original']: r for r in seam['declarations'] if r['fate'] == 'patched'}
    assert set(patches) == keys
    for row in overlay['declarations']:
        if row['original'] in patches:
            assert row['fate'] == 'retained' and not row.get('substitutions') and not row.get('patches')
            row.update(patches[row['original']])
    overlay['patched_class_projection'] = sorted(
        {*overlay.get('patched_class_projection', []), *seam.get('patched_class_projection', [])})
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
