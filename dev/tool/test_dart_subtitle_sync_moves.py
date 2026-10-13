"""Phase-9 real configuration: shared State, one engine owner, two teardowns."""
from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p9.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 18
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 21
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained'
               for e in r.get('substitutions', [])) == 33
    destination = next(iter(spec['destinations']))
    cases = [
        ('constructor assignment removed', spec['source'],
         '_subtitleSync = VpSubtitleAutoSync ( _VpSubtitleAutoSyncHostAdapter ( this ) ) ;', ''),
        ('cached player adapter', spec['source'], 'mk . Player get player => _s . _player ;',
         'late final mk.Player player = _s._player;'),
        ('settings write mis-targeted', destination, '_host . subtitleSettings = settings;',
         '_host.otherSettings = settings;'),
        ('path snapshot becomes live read', destination, 'subtitleFilePath: externalPath,',
         'subtitleFilePath: _host.activeExternalSubtitlePath!,'),
        ('position callback becomes snapshot', destination,
         'getCurrentPositionMs: () => _host . player.state.position.inMilliseconds,',
         'getCurrentPositionMs: () => 0,'),
        ('engine callback captured by a local', destination, 'final controller = subtitleAutoSync;',
         'final subtitleAutoSync = null; final controller = subtitleAutoSync;'),
        ('State notifier allocated in controller', destination, 'final VpSubtitleAutoSyncHost _host ;',
         'final VpSubtitleAutoSyncHost _host; final autoSyncPill = ValueNotifier(null);'),
        ('State disposal routed through hide helper', spec['source'],
         'final subtitleAutoSync = _subtitleSync . subtitleAutoSync;',
         '_subtitleSync.disposeSubtitleAutoSync(); final subtitleAutoSync = _subtitleSync.subtitleAutoSync;'),
        ('replacement engine disposal removed', spec['source'],
         'await _subtitleSync . disposeSubtitleAutoSync();', ''),
        ('native delay scaling changed', destination, '(ms / 1000.0)', '(ms / 100.0)'),
        ('announce duration changed', destination, 'Duration(seconds: 5)', 'Duration(seconds: 6)'),
        ('manual effect moved past mounted guard', destination, '_host . player.platform',
         '(_host.mounted ? _host.player : throw StateError("disposed")).platform'),
        ('Host reads in constructor', destination, 'VpSubtitleAutoSync ( this . _host ) ;',
         'VpSubtitleAutoSync(this._host) { _host.player; }'),
        ('initializer changed', destination, 'bool subtitleAutoSyncEnabled = false;',
         'bool subtitleAutoSyncEnabled = true;'),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-9 ' + label + ': rejected')

    # Binding-only checks establish scope independently of token comparison.
    def binding(current):
        parsed = parse({'original': original, **current}, package,
                       ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers'])
        lookup = {}
        for path, unit in parsed.items():
            if path == 'original':
                continue
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
    for before, after in [('_host . subtitleSettings', 'subtitleSettings'),
                          ('_host . player', 'player'),
                          ('_host . setState', 'setState')]:
        changed = dict(sources, **{destination: sources[destination].replace(before, after)})
        assert binding(changed), before
        print('Phase-9 binding-only ' + before + ': rejected')
    print('Phase-9: 21 moves, 33 retained occurrences, 18 earlier destinations PASS')
