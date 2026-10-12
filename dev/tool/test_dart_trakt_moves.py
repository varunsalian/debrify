"""Phase-5 real configuration: Trakt only, adapter patch and live selectors."""
import copy

import check_dart_moves as d
from dart_move_fixture import materialize
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p5.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 13
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 12
    assert not any('simkl' in r['original'].lower() or 'mdblist' in r['original'].lower() for r in moves)
    adapter = next(r for r in spec['declarations'] if r['original'] == '_VpSkipSegmentHostAdapter')
    assert adapter['fate'] == 'patched' and len(adapter['patches']) == 1 and adapter['patches'][0]['count'] == 1
    assert 'earlier_patches' not in spec
    for name in ['_simklScrobble', '_startSimklHeartbeat']:
        row = next(r for r in spec['declarations'] if r['original'].endswith('.' + name))
        assert row['fate'] == 'retained'
        assert row['substitutions'] == [dict(before=['_traktProgress'], after=['_trakt', '.', 'traktProgress'], count=1)]
    destination = next(iter(spec['destinations']))
    cases = [
        ('wrong skip forwarding receiver', spec['source'], '_s._trakt . traktScrobbleSeek', '_s._skip.traktScrobbleSeek'),
        ('skip adapter extra edit', spec['source'], 'bool get mounted => _s.mounted;', 'bool get mounted => false;'),
        ('cached widget boolean', spec['source'], 'bool get traktScrobble => _s . widget . traktScrobble ;', 'final bool traktScrobble = false;'),
        ('wrong live widget identity', spec['source'], 'contentImdbId => _s . widget . contentImdbId', 'contentImdbId => _s.widget.contentType'),
        ('cached current episode index', spec['source'], 'int get currentIndex => _s . _currentIndex ;', 'late final int currentIndex = _s._currentIndex;'),
        ('seek handover order', destination, '_host . stremioTvStartupSeek.cancel();\n    _host . resumeWriteGuard.noteUserSeek();', '_host.resumeWriteGuard.noteUserSeek();\n    _host.stremioTvStartupSeek.cancel();'),
        ('seek handover dropped', destination, '_host . resumeWriteGuard.noteUserSeek();', ''),
        ('captured show becomes late live read', destination, '_host . episodeTrackerProgressImdbId != imdbId', '_host.episodeTrackerProgressImdbId != _host.currentSeriesImdbId'),
        ('initial enablement changed', destination, 'bool traktScrobbleEnabled = false;', 'bool traktScrobbleEnabled = true;'),
        ('Trakt eager assignment removed', spec['source'], '_trakt = VpTraktScrobbler ( _VpTraktScrobblerHostAdapter ( this ) ) ;', ''),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        start = (sources[path].index('class _VpSkipSegmentHostAdapter')
                 if label == 'skip adapter extra edit' else 0)
        at = sources[path].index(before, start)
        changed = dict(sources, **{path: sources[path][:at] + after + sources[path][at + len(before):]})
        assert d.check(spec, original, changed, package), label
        print('Phase-5 ' + label + ': rejected')
    disabled = copy.deepcopy(spec)
    del disabled['patched_class_projection']
    assert any('Occurrence alignment changed' in e for e in d.check(disabled, original, sources, package))
    print('Phase-5 adapter projection requires exact opt-in: rejected')
    for identity in ['_VideoPlayerScreenState._traktProgress', 'doesNotExist']:
        wrong = copy.deepcopy(spec)
        wrong['patched_class_projection'] = [identity]
        assert any('class patch projection requires' in e for e in d.check(wrong, original, sources, package))
    wrong = copy.deepcopy(spec)
    next(r for r in wrong['declarations'] if r['original'] == '_VpSkipSegmentHostAdapter')['patches'][0]['count'] = 2
    assert d.check(wrong, original, sources, package)
    print('Phase-5 class kind/fate/missing declaration and patch count negatives: rejected')
    disabled = copy.deepcopy(spec)
    del disabled['guards']['registered_occurrence_substitutions']
    assert d.check(disabled, original, sources, package)
    print('Phase-5 live widget registrations required: rejected')
    print('Phase-5 complete real configuration: 12 moves, 21 live Host readers, 13 earlier destinations PASS')
