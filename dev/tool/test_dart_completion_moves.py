"""Phase-7 real configuration: exact membership, live selectors and EOF order."""
import copy

from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p7.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 16
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 14
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 11
    assert [r['original'] for r in spec['declarations'] if r['fate'] == 'patched'] == [
        '_VideoPlayerScreenState._VideoPlayerScreenState']
    assert 'patched_class_projection' not in spec and 'earlier_patches' not in spec
    destination = next(iter(spec['destinations']))
    cases = [
        ('cached widget selector', spec['source'], 'bool get traktScrobble => _s . widget . traktScrobble ;', 'final bool traktScrobble = false;'),
        ('wrong live movie selector', spec['source'], 'String ? get contentImdbId => _s . widget . contentImdbId ;', 'String? get contentImdbId => _s._effectiveContentImdbId;'),
        ('constructor assignment removed', spec['source'], '_completion = VpLocalCompletion ( _VpLocalCompletionHostAdapter ( this ) ) ;', ''),
        ('episode flag initially spent', destination, 'bool currentEpisodeMarkedAsFinished = false;', 'bool currentEpisodeMarkedAsFinished = true;'),
        ('threshold literal rewritten', destination, 'LocalCompletionStorage.defaultLocalCompletionThreshold;', '90;'),
        ('local playlist capture becomes live', destination, 'final seriesPlaylist = _host . seriesPlaylist;', 'final seriesPlaylist = null;'),
        ('one extra catch edit', destination, 'catch (e) {}', 'catch (e) { rethrow; }'),
        ('EOF await removed', spec['source'], 'await _completion . markCurrentEpisodeAsFinished();', '_completion.markCurrentEpisodeAsFinished();'),
        ('position dispatch removed', spec['source'], '_completion . checkAndApplyLocalCompletion();', ''),
        ('movie save suppression removed', spec['source'], '_completion . currentMovieMarkedAsFinished &&', 'false &&'),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-7 ' + label + ': rejected')

    # Scope-only witnesses cannot earn a pass from the token comparator.
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
    disabled['registered_occurrence_substitutions'] = []
    assert binding(original, sources, disabled)
    for parameter in ['dynamic _host', 'VideoPlayerScreen widget']:
        baseline = original.replace('Future<void> _markCurrentEpisodeAsFinished()', 'Future<void> _markCurrentEpisodeAsFinished(' + parameter + ')', 1)
        current = dict(sources, **{destination: sources[destination].replace('Future<void> markCurrentEpisodeAsFinished()', 'Future<void> markCurrentEpisodeAsFinished(' + parameter + ')', 1)})
        assert binding(baseline, current, config), parameter
        print('Phase-7 binding-only lexical capture ' + parameter + ': rejected')
    print('Phase-7 complete real configuration: 14 moves, 11 references, 21 live Host getters, 16 earlier destinations PASS')
