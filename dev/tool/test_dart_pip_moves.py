"""Phase-8 real configuration: owner identity, exact chains and captured time."""
import copy
from check_verbatim_moves import parse
from check_settings_moves import configured
from occurrence_field_bindings import failures
from dart_move_partition import partition, ownership_rows
from dart_move_history import load_manifest, git_text, check_earlier, earlier_sources
from dart_move_fixture import materialize
import check_dart_moves as d


def run(package):
    spec = load_manifest('dev/tool/dart_moves/vplayer_p8.json')
    original = git_text(spec['base'], spec['source'])
    sources = materialize(spec, original, package)
    assert not d.check(spec, original, sources, package)
    assert not check_earlier(spec, package)
    assert len(earlier_sources(spec)) == 17
    moves = [r for r in spec['declarations'] if r['fate'] == 'moved']
    assert len(moves) == 14
    assert sum(e['count'] for r in spec['declarations'] if r['fate'] == 'retained' for e in r.get('substitutions', [])) == 22
    assert sum(e['count'] for r in moves for e in r.get('substitutions', []) if e['before'] == ['this']) == 7
    destination = next(iter(spec['destinations']))
    cases = [
        ('owner is collaborator', destination, 'PipService.isOwner(_host . pipOwner)', 'PipService.isOwner(this)'),
        ('new owner object', spec['source'], 'Object get pipOwner => _s ;', 'Object get pipOwner => Object();'),
        ('cached predicate', spec['source'], 'bool get isIOS => VpS2Hooks . isIOS ;', 'final bool isIOS = VpS2Hooks.isIOS;'),
        ('wrong platform predicate', spec['source'], 'bool get isAndroid => VpS2Hooks . isAndroid ;', 'bool get isAndroid => VpS2Hooks.isIOS;'),
        ('constructor assignment removed', spec['source'], '_pip = VpPipLifecycle ( _VpPipLifecycleHostAdapter ( this ) ) ;', ''),
        ('captured player becomes live', destination, 'identical(player, _host . player)', 'identical(_host.player, _host.player)'),
        ('captured time becomes live', destination, 'DateTime.now().difference(backgroundedAt)', 'DateTime.now().difference(this.backgroundedAt!)'),
        ('owned field captured by local', destination, 'final backgroundedAt = this . backgroundedAt;', 'final backgroundedAt = backgroundedAt;'),
        ('landscape wrong controller', spec['source'], '_s . _display . landscapeLocked', '_s._display.showSpeedIndicator'),
        ('tracker fanout reorder', destination, '_host . traktScrobbleSeek(position);\n      _host . simklScrobbleSeek(position);', '_host.simklScrobbleSeek(position);\n      _host.traktScrobbleSeek(position);'),
        ('recording teardown removed', spec['source'], 'unawaited(_stopRecording(userInitiated: false));', ''),
        ('onPause closure replaced', spec['source'], 'onPause: () {\n        unawaited(_stopRecording(userInitiated: false));\n        _pip . pauseForBackground();\n      },', 'onPause: _pip.pauseForBackground,'),
        ('dispose session close removed', spec['source'], '_pip . iosPipSession?.close();', ''),
        ('field literal changed', destination, 'int lastIosPipPositionSecond = -1;', 'int lastIosPipPositionSecond = 0;'),
    ]
    for label, path, before, after in cases:
        assert before in sources[path], (label, before)
        changed = dict(sources, **{path: sources[path].replace(before, after, 1)})
        assert d.check(spec, original, changed, package), label
        print('Phase-8 ' + label + ': rejected')
    row = next(r for r in spec['declarations'] if r['original'].endswith('._resumeFromBackground'))
    for label, mutate in [
        ('missing owned qualifier opt-in', lambda r: r.pop('owned_this_fields')),
        ('wrong owned qualifier field', lambda r: r.update(owned_this_fields={'_player': 2})),
        ('wrong owned qualifier count', lambda r: r.update(owned_this_fields={'_backgroundedAt': 3})),
    ]:
        changed = copy.deepcopy(spec);target = next(r for r in changed['declarations'] if r['original']==row['original']);mutate(target)
        assert d.check(changed, original, sources, package), label
        print('Phase-8 ' + label + ': rejected')
    # Binding-only negatives cannot spend a token mismatch as scope evidence.
    def binding(current, config):
        parsed = parse({'original': original, **current}, package, ownership=True, occurrence_bindings=True)
        _, _, old = partition(parsed['original'], spec['split_containers']);lookup={}
        for path, unit in parsed.items():
            if path=='original':continue
            splits=spec['split_containers'] if path==spec['source'] else spec['destinations'][path]['split_containers']
            _, _, nodes=partition(unit,splits)
            for key,node in nodes.items():
                if ':' not in key:
                    owner,_,name=key.rpartition('.');lookup[path,owner,name or key]=node
        with configured(config):return failures(old,lookup,ownership_rows(spec),spec['source'],config,members={r['original'] for r in moves},package=package)
    config=d.guard_config(spec);assert not binding(sources,config)
    disabled=copy.deepcopy(config);disabled['registered_occurrence_substitutions']=[];assert binding(sources,disabled)
    for before, after in [('this . backgroundedAt','backgroundedAt'),('_host . isIOS','VpS2Hooks.isIOS'),('_host . traktScrobbleSeek','_trakt.traktScrobbleSeek')]:
        changed=dict(sources,**{destination:sources[destination].replace(before,after)})
        assert binding(changed,config),before
        print('Phase-8 binding-only '+before+': rejected')
    print('Phase-8 real configuration: 14 moves, 22 retained occurrences, 7 State owners, live predicates/chains and captured time PASS')
