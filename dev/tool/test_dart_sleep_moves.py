"""Real Phase-2 configuration and opt-in owned-field binding negatives."""
import copy
from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import ownership_rows, partition
from dart_move_history import load_manifest, git_text
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p2.json')
    from check_vplayer_analyzer import declaration_mappings
    origins, _, reverse = declaration_mappings(spec)
    assert origins['lib/features/video_player/application/vp_format.dart', 'vpPad2'] == '_VideoPlayerScreenState._pad2'
    assert reverse['vpPad2'] == '_pad2'
    assert origins[next(iter(spec['destinations'])), 'VpSleepTimerController.fireSleepTimer'] == '_VideoPlayerScreenState._fireSleepTimer'
    print('Phase-2 analyzer mappings preserve historical P1 and current receivers PASS')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    print('Real Phase-2: complete split/fields/nullable chains/tear-offs/interpolation/frozen construction PASS')
    disabled = copy.deepcopy(spec)
    del disabled['guards']['occurrence_field_bindings']['owner_scoped_bare_fields']
    assert any('qualification' in e or 'Bare owner' in e for e in d.check(disabled, original, sources, package))
    print('Owned bare fields require explicit opt-in: rejected')
    rows = ownership_rows(spec)
    def guard(changed, config=None, foreign=False, baseline=None):
        if foreign:
            destination = next(iter(spec['destinations']))
            changed = dict(changed, **{destination: changed[destination] +
                '\nclass OtherController { void read() { sleepTimer?.cancel(); } }\n'})
        parsed = parse({'original': baseline or original, **changed}, package, ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers'])
        lookup = {}
        for path, unit in parsed.items():
            if path == 'original': continue
            splits = spec['split_containers'] if path == spec['source'] else spec['destinations'][path]['split_containers']
            if foreign and path != spec['source']: splits = [*splits, 'OtherController']
            _, _, nodes = partition(unit, splits)
            for key, node in nodes.items():
                if ':' not in key:
                    owner, _, name = key.rpartition('.')
                    lookup[path, owner, name or key] = node
        config = config or d.guard_config(spec)
        with configured(config):
            return failures(old, lookup, rows, spec['source'], config, package=package)
    assert not guard(sources)
    destination = next(iter(spec['destinations']))
    current = sources[destination]
    assert 'sleepTimer?.cancel()' in current
    # Only the raw binding guard is invoked: no token mismatch can masquerade
    # as a lexical/ownership rejection in these three required negatives.
    cases = [
        ('bare field from another owner', sources, True),
        ('owned field through Host', dict(sources, **{destination: current.replace(
            'sleepTimer?.cancel()', '_host.sleepTimer?.cancel()', 1)}), False),
    ]
    for label, changed, foreign in cases:
        errors = guard(changed, foreign=foreign)
        assert errors, label
        print('Phase-2 binding-only ' + label + ': rejected (' + errors[0] + ')')
    # Put the identical valid local in both sides. Occurrence counts remain
    # equal: only renaming the originally private field captures that local.
    baseline = original.replace('void _cancelSleepTimer() {',
        'void _cancelSleepTimer() { Timer? sleepTimer = null;', 1)
    capture = dict(sources, **{destination: current.replace('void cancelSleepTimer() {',
        'void cancelSleepTimer() { Timer? sleepTimer = null;', 1)})
    errors = guard(capture, baseline=baseline)
    assert any('field qualification lost' in e for e in errors), errors
    assert not any('alignment changed' in e for e in errors), errors
    print('Phase-2 binding-only same-named local capture, equal occurrence counts: rejected')
    config = copy.deepcopy(d.guard_config(spec))
    config['occurrence_field_bindings']['owner_scoped_bare_fields']['_VideoPlayerScreenState._sleepTimer'] = 'OtherController'
    assert any('Invalid owner-scoped' in e for e in guard(sources, config))
    print('Owner opt-in cannot name another class: rejected')
    config = copy.deepcopy(d.guard_config(spec))
    config['host_property_bindings']['_host.sleepTimer'] = '_VideoPlayerScreenState._sleepTimer'
    assert any('Owned field cannot' in e for e in guard(sources, config))
    print('Declared Host binding cannot legalize an owned field: rejected')
    for key, value in [('mandatory_qualification', False),
                       ('mandatory_qualification_classes', ['VpSleepTimerController'])]:
        config = copy.deepcopy(d.guard_config(spec))
        config['occurrence_field_bindings'][key] = value
        assert any('every other class' in e for e in guard(sources, config))
        print('Owner opt-in cannot relax ' + key + ': rejected')
