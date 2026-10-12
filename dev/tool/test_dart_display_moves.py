"""Phase-4 real configuration: live widget selectors and frozen construction."""
import copy

from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
from check_vplayer_analyzer import declaration_mappings
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p4.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 12
    assert sum(r['fate'] == 'moved' for r in spec['declarations']) == 16
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 33
    destination = next(iter(spec['destinations']))
    origins, _, _ = declaration_mappings(spec)
    for path, target, origin in [
        (destination, 'VpDisplayModeController.toggleOrientation', '_toggleOrientation'),
        ('lib/features/video_player/presentation/legacy_video_player/vp_sleep_timer_controller.dart',
         'VpSleepTimerController.fireSleepTimer', '_fireSleepTimer'),
        ('lib/features/video_player/presentation/legacy_video_player/vp_skip_segment_controller.dart',
         'VpSkipSegmentController.skipActiveSegment', '_skipActiveSegment'),
    ]:
        assert origins[path, target] == '_VideoPlayerScreenState.' + origin
    print('Phase-4 complete real configuration: 16 moves, 33 references, 12 earlier destinations PASS')
    cases = [
        ('cached widget value', spec['source'],
         'bool get hideBackButton => _s . widget . hideBackButton ;',
         'final bool hideBackButton = false;'),
        ('lazy cached widget value', spec['source'],
         'bool get hideOptions => _s . widget . hideOptions ;',
         'late final bool hideOptions = _s.widget.hideOptions;'),
        ('wrong widget forwarder', spec['source'],
         'hideBackButton => _s . widget . hideBackButton',
         'hideBackButton => _s.widget.hideOptions'),
        ('display eager assignment removed', spec['source'],
         '_display = VpDisplayModeController ( _VpDisplayModeHostAdapter ( this ) ) ;', ''),
        ('previous skip assignment removed', spec['source'],
         '_skip = VpSkipSegmentController(_VpSkipSegmentHostAdapter(this));', ''),
        ('HUD allocation moved/changed', spec['source'],
         '_speedHoldHud = ValueNotifier<bool>(false);', '_speedHoldHud = ValueNotifier<bool>(true);'),
        ('resume direct field write becomes effectful action', spec['source'],
         '_display . playbackSpeed = speed;', '_display.setPlaybackSpeed(speed);'),
        ('destination widget reference', destination,
         '_host . hideOptions', 'widget.hideOptions'),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-4 ' + label + ': rejected')

    # Invoke only the binding guard: token/scaffold mismatches cannot count as
    # the lexical rejection. Both sides share the identical added parameter.
    def binding(baseline, current, config):
        parsed = parse({'original': baseline, **current}, package,
                       ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers'])
        lookup = {}
        for path, unit in parsed.items():
            if path == 'original':
                continue
            splits = spec['split_containers'] if path == spec['source'] else [
                'VpDisplayModeController']
            _, _, nodes = partition(unit, splits)
            for key, node in nodes.items():
                if ':' not in key:
                    owner, _, name = key.rpartition('.')
                    lookup[path, owner, name or key] = node
        with configured(config):
            moved = {r['original'] for r in spec['declarations'] if r['fate'] == 'moved'}
            return failures(old, lookup, ownership_rows(spec), spec['source'], config,
                            members=moved, package=package)

    config = d.guard_config(spec)
    assert not binding(original, sources, config)
    disabled = copy.deepcopy(config)
    del disabled['registered_occurrence_substitutions']
    assert binding(original, sources, disabled)
    print('Phase-4 binding-only widget selector registration required: rejected')
    for parameter in ['VideoPlayerScreen widget', 'VpDisplayModeHost _host']:
        baseline = original.replace('void _onLongPressStart(LongPressStartDetails details)',
            'void _onLongPressStart(LongPressStartDetails details, ' + parameter + ')', 1)
        current = dict(sources, **{destination: sources[destination].replace(
            'void onLongPressStart(LongPressStartDetails details)',
            'void onLongPressStart(LongPressStartDetails details, ' + parameter + ')', 1)})
        errors = binding(baseline, current, config)
        assert errors, parameter
        print('Phase-4 binding-only lexical capture ' + parameter + ': rejected (' + errors[0] + ')')
