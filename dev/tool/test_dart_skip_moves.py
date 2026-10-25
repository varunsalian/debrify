"""Complete Phase-3 fixture: records, caches, live writes and construction."""
import copy

from check_vplayer_analyzer import declaration_mappings
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources, applied_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p3.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package, current=applied_sources(spec))
    assert len(earlier_sources(spec)) == 11
    origins, _, reverse = declaration_mappings(spec)
    destination = next(iter(spec['destinations']))
    assert origins[destination, 'VpSkipSegmentController.skipActiveSegment'] == '_VideoPlayerScreenState._skipActiveSegment'
    assert reverse['vpPad2'] == '_pad2'
    assert origins['lib/features/video_player/presentation/legacy_video_player/vp_sleep_timer_controller.dart',
                   'VpSleepTimerController.fireSleepTimer'] == '_VideoPlayerScreenState._fireSleepTimer'
    print('Phase-3 complete real configuration; historical P1/P2 mapping and 11 destinations PASS')
    cases = [
        ('map key drift', destination, 'skipSegmentsCache[request.key]', 'skipSegmentsCache["wrong"]'),
        ('nullable selector drift', destination, 'currentSkipSegmentRequest()?.key', 'currentSkipSegmentRequest()?.imdbId'),
        ('generation increment deletion', destination, '++skipSegmentsFetchGeneration', 'skipSegmentsFetchGeneration'),
        ('position write no longer live', destination, '_host . position = target', 'position = target'),
        ('eager assignment deletion', spec['source'], '_skip = VpSkipSegmentController ( _VpSkipSegmentHostAdapter ( this ) ) ;', ''),
        ('prior constructor assignment deletion', spec['source'], '_sleep = VpSleepTimerController(_VpSleepTimerHostAdapter(this));', ''),
        ('frozen notifier changed', spec['source'], 'SkipSegmentUiController();', 'SkipSegmentUiController()..clear();'),
        ('cached host value', spec['source'], 'Duration get position => _s . _position ;', 'final Duration position = Duration.zero;'),
        ('frozen host signature', destination, 'set position ( Duration v ) ;', 'set position ( int v ) ;'),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-3 ' + label + ': rejected')
    modified = copy.deepcopy(spec)
    row = next(r for r in modified['declarations'] if r['fate'] == 'patched')
    assert row['original'] == '_VideoPlayerScreenState._VideoPlayerScreenState'
    row['patches'][0]['after'] = [';', '_skip', '=', 'null', ';', '}']
    assert d.check(modified, original, sources, package)
    print('Phase-3 undeclared constructor patch: rejected')
