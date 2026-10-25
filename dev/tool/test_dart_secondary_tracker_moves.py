"""Phase-6 real configurations, exact receiver chains and adapter projection."""
import copy

from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources, applied_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p6.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package, current=applied_sources(spec))
    assert len(earlier_sources(spec)) == 14
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 24
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) + 2 == 59
    adapter = next(r for r in spec['declarations'] if r['original'] == '_VpSkipSegmentHostAdapter')
    assert adapter['fate'] == 'patched' and len(adapter['patches']) == 2
    assert all(p['count'] == 1 for p in adapter['patches'])
    assert 'earlier_patches' not in spec
    assert '_s._trakt.traktScrobbleSeek(target);' in sources[spec['source']]
    destinations = list(spec['destinations'])
    simkl = next(p for p in destinations if 'simkl' in p)
    mdblist = next(p for p in destinations if 'mdblist' in p)
    for name in ['_simklScrobble', '_startSimklHeartbeat']:
        row = next(r for r in moves if r['original'].endswith('.' + name))
        assert [e for e in row['substitutions'] if e['before'] == ['_trakt', '.', 'traktProgress']] == [
            dict(before=['_trakt', '.', 'traktProgress'], after=['_host', '.', 'traktProgress'], count=1)]
    cases = [
        ('wrong Simkl skip receiver', spec['source'], '_s._simkl . simklScrobbleSeek', '_s._trakt.simklScrobbleSeek'),
        ('wrong MDBList skip receiver', spec['source'], '_s._mdblist . mdblistScrobbleSeek', '_s._simkl.mdblistScrobbleSeek'),
        ('lost P5 skip rewrite', spec['source'], '_s._trakt.traktScrobbleSeek', '_s._traktScrobbleSeek'),
        ('cached widget selector', spec['source'], 'bool get simklScrobble => _s . widget . simklScrobble ;', 'final bool simklScrobble = false;'),
        ('wrong MDBList live identity', spec['source'], 'bool get mdblistScrobble => _s . widget . mdblistScrobble ;', 'bool get mdblistScrobble => _s.widget.simklScrobble;'),
        ('cached Trakt progress', spec['source'], 'double traktProgress ( ) => _s . _trakt . traktProgress ( ) ;', 'double traktProgress() => 0;'),
        ('wrong Trakt adapter chain', spec['source'], 'double traktProgress ( ) => _s . _trakt . traktProgress ( ) ;', 'double traktProgress() => _s._simkl.traktProgress();'),
        ('unregistered sibling chain', simkl, '_host . traktProgress()', '_trakt.traktProgress()'),
        ('missing initialization wait', mdblist, 'await _host . playerInitializationFuture;', ''),
        ('late target capture', mdblist, 'target: target,', 'target: mdblistTarget()!,'),
        ('initial Simkl enabled', simkl, 'bool simklScrobbleEnabled = false;', 'bool simklScrobbleEnabled = true;'),
        ('dispose close removed', spec['source'], 'unawaited(_mdblist . mdblistSession?.close() ?? Future.value());', ''),
        ('Simkl eager assignment removed', spec['source'], '_simkl = VpSimklScrobbler ( _VpSimklScrobblerHostAdapter ( this ) ) ;', ''),
        ('MDBList eager assignment removed', spec['source'], '_mdblist = VpMdblistScrobbler ( _VpMdblistScrobblerHostAdapter ( this ) ) ;', ''),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-6 ' + label + ': rejected')
    disabled = copy.deepcopy(spec)
    del disabled['patched_class_projection']
    assert any('Occurrence alignment changed' in e for e in d.check(disabled, original, sources, package))
    print('Phase-6 whole skip-adapter projection requires explicit opt-in: rejected')

    # Guard-only witnesses: a token mismatch cannot satisfy these negatives.
    def binding(baseline, current, config):
        parsed = parse({'original': baseline, **current}, package,
                       ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers'])
        lookup = {}
        for path, unit in parsed.items():
            if path == 'original': continue
            splits = spec['split_containers'] if path == spec['source'] else spec['destinations'][path]['split_containers']
            _, _, nodes = partition(unit, splits)
            for key, node in nodes.items():
                if ':' not in key:
                    owner, _, name = key.rpartition('.')
                    lookup[path, owner, name or key] = node
        with configured(config):
            return failures(old, lookup, ownership_rows(spec), spec['source'], config,
                            members={r['original'] for r in moves}, package=package)
    config = d.guard_config(spec)
    assert not binding(original, sources, config)
    disabled = copy.deepcopy(config)
    disabled['registered_occurrence_substitutions'] = [s for s in disabled['registered_occurrence_substitutions'] if s['before'] != ['_trakt', '.', 'traktProgress']]
    assert binding(original, sources, disabled)
    print('Phase-6 binding-only full receiver-chain registration required: rejected')
    for parameter in ['dynamic _host', 'dynamic _trakt', 'VideoPlayerScreen widget']:
        baseline = original.replace('void _simklScrobble(String action)', 'void _simklScrobble(String action, ' + parameter + ')', 1)
        current = dict(sources, **{simkl: sources[simkl].replace('void simklScrobble(String action)', 'void simklScrobble(String action, ' + parameter + ')', 1)})
        assert binding(baseline, current, config), parameter
        print('Phase-6 binding-only lexical capture ' + parameter + ': rejected')
    wrong = dict(sources, **{simkl: sources[simkl].replace('_host . traktProgress()', '_host.duration()', 1)})
    assert binding(original, wrong, config)
    print('Phase-6 binding-only wrong chain leaf: rejected')
    print('Phase-6 complete real configurations: 24 moves, 59 references, 19/15 live Host readers, 14 earlier destinations PASS')
