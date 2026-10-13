"""Phase-10 real configuration: shared attempts, live predicates, PiP projection."""
import copy
from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p10.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 19
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 5
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 22
    patched = next(r for r in spec['declarations'] if r['original'] == '_VpPipLifecycleHostAdapter')
    assert sum(e['count'] for e in patched['patches']) == 1
    assert len(spec['guards']['registered_occurrence_substitutions']) == 4
    destination = next(iter(spec['destinations']))
    cases = [
        ('constructor assignment removed', spec['source'],
         '_subtitleApply = VpSubtitleApply ( _VpSubtitleApplyHostAdapter ( this ) ) ;', ''),
        ('constructor Host read', destination, 'VpSubtitleApply ( this . _host ) ;',
         'VpSubtitleApply(this._host) { _host.player; }'),
        ('cached player adapter', spec['source'], 'mk . Player get player => _s . _player ;',
         'late final mk.Player player = _s._player;'),
        ('cached Android predicate', spec['source'], 'bool get isAndroid => VpS2Hooks . isAndroid ;',
         'late final bool isAndroid = VpS2Hooks.isAndroid;'),
        ('raw Android predicate', destination, '_host . isAndroid', 'Platform.isAndroid'),
        ('wrong Android projection', destination, '_host . isAndroid', '_host.isIOS'),
        ('raw iOS predicate', destination, '_host . isIOS', 'Platform.isIOS'),
        ('wrong PiP projection', destination, '_host . iosPipStarting', '_host.isPipActive'),
        ('wrong sibling chain', destination, '_host . setActiveExternalSubtitlePath', '_host.persistTrackChoice'),
        ('generation initializer added to controller', destination, 'final VpSubtitleApplyHost _host ;',
         'final VpSubtitleApplyHost _host; int subtitleDiagnosticGeneration = 0;'),
        ('wrong diagnostic setter', destination, '_host . activeSubtitleApplyAttempt = attempt;',
         '_host.otherAttempt = attempt;'),
        ('wrong generation increment', destination, '++_host . subtitleDiagnosticGeneration',
         '++_host.addonSubtitleFetchToken'),
        ('captured previous track changed', destination, 'previous: _host . player.state.track.subtitle,',
         'previous: track,'),
        ('delay changed', destination, 'Duration(milliseconds: 50)', 'Duration(milliseconds: 51)'),
        ('snapshot becomes live read', destination, 'attempt.previousStremioId', '_host.selectedStremioSubtitleId'),
        ('wrong PiP adapter target', spec['source'], '_s._subtitleApply . setNativeSubtitleVisibilityForTrack',
         '_s._subtitleSync.setNativeSubtitleVisibilityForTrack'),
        ('unrelated PiP adapter edit', spec['source'], 'Object get pipOwner => _s;',
         'Object get pipOwner => Object();'),
        ('disposal attempt clear removed', spec['source'], '_activeSubtitleApplyAttempt = null;', ''),
        ('frozen notifier identity', spec['source'],
         'ValueNotifier < String ? > get subtitleSelectionCorrection => _s . _subtitleSelectionCorrection ;',
         'ValueNotifier<String?> get subtitleSelectionCorrection => ValueNotifier(null);'),
        ('facade back import', destination, "import 'package:flutter/material.dart'",
         "import 'package:debrify/screens/video_player_screen.dart'"),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-10 ' + label + ': rejected')
    for chain in spec['guards']['registered_occurrence_substitutions']:
        changed = copy.deepcopy(spec)
        changed['guards']['registered_occurrence_substitutions'].remove(chain)
        assert d.check(changed, original, sources, package), chain
        print('Phase-10 unregistered ' + '.'.join(chain['before']) + ': rejected')

    def binding(current):
        parsed = parse({'original': original, **current}, package,
                       ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers'])
        lookup = {}
        for path, unit in parsed.items():
            if path == 'original': continue
            splits = (spec['split_containers'] if path == spec['source']
                      else spec['destinations'][path]['split_containers'])
            _, _, nodes = partition(unit, splits)
            for key, node in nodes.items():
                if ':' not in key:
                    owner, _, name = key.rpartition('.')
                    lookup[path, owner, name or key] = node
        config = d.guard_config(spec)
        with configured(config):
            return failures(old, lookup, ownership_rows(spec), spec['source'], config,
                            members={r['original'] for r in moves}, package=package)
    assert not binding(sources)
    for before, after in [('_host . player', 'player'),
                          ('_host . activeSubtitleApplyAttempt', 'activeSubtitleApplyAttempt'),
                          ('_host . subtitleDiagnosticGeneration', 'subtitleDiagnosticGeneration'),
                          ('_host . context', 'context')]:
        changed = dict(sources, **{destination: sources[destination].replace(before, after)})
        assert binding(changed), before
        print('Phase-10 binding-only ' + before + ': rejected')
    print('Phase-10: five moves, 23 retained references including patched PiP adapter, 19 earlier destinations PASS')
