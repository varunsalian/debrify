#!/usr/bin/env python3
"""Validate frozen S, installation guards and the three once-only default paths."""
import argparse
import copy
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import check, run_manifest
from vplayer_checkpoint_proof import run_current_manifest
from dart_move_history import git_text, load_manifest
from dart_move_partition import partition
from check_settings_moves import tokens

SOURCE = 'lib/screens/video_player_screen.dart'
MANIFEST = 'dev/tool/dart_moves/vplayer_p1_seam.json'
# P20 relocates `_createPlayerInstance` (resolution P1-2/R6). The private
# hooks stay facade-only; the instance reaches them through two plain Host
# forwarders, each used exactly once, in the original creation order.
INSTANCE = 'lib/features/video_player/presentation/legacy_video_player/vp_player_instance.dart'
INSTANCE_ADAPTER = '_VpPlayerInstanceHostAdapter'
FACTORY_FORWARDERS = {
    'createPlayer': ['@', 'override', 'mk', '.', 'Player', 'createPlayer', '(', '{', 'required',
                     'mk', '.', 'PlayerConfiguration', 'configuration', '}', ')', '=>',
                     'VideoPlayerScreenTestHooks', '.', '_createPlayer', '(', 'configuration', ':',
                     'configuration', ')', ';'],
    'createVideoController': ['@', 'override', 'mkv', '.', 'VideoController', 'createVideoController',
                              '(', 'mk', '.', 'Player', 'player', ',', '{', 'required', 'mkv', '.',
                              'VideoControllerConfiguration', 'configuration', '}', ')', '=>',
                              'VideoPlayerScreenTestHooks', '.', '_createVideoController', '(', 'player',
                              ',', 'configuration', ':', 'configuration', ')', ';'],
}
# Ordered once-only sites in the relocated `createPlayerInstance` body
# (parser tokens drop trailing commas).
INSTANCE_ORDER = [
    ['_host', '.', 'createPlayer', '('],
    ['ready', ':', '(', ')', '=>', 'onPlayerInstanceReady', '(', 'instanceGeneration', ')'],
    ['_host', '.', 'player', '=', 'player', ';'],
    ['_host', '.', 'playerCreated', '=', 'true', ';'],
    ['_host', '.', 'videoController', '=', '_host', '.', 'createVideoController', '('],
]


def installation_errors(sources):
    errors = []
    for path, text in sources.items():
        if path != SOURCE and 'VideoPlayerScreenTestHooks' in text:
            errors.append('test hook reference outside its facade: ' + path)
    # All facade hook code is frozen by the exhaustive token check. This
    # separately forbids references in all other application files.
    return errors


def _hits(body, seq):
    return [i for i in range(len(body)) if body[i:i + len(seq)] == seq]


def relocation_errors(sources, package):
    """P20: once-only ordered factory/ready sites and exact facade forwarders."""
    if INSTANCE not in sources:
        return []
    errors = []
    unit = parse({'i': sources[INSTANCE]}, package, ownership=True)['i']
    owner = next((n for n in unit['declarations'] if n['name'] == 'VpPlayerInstance'), None)
    member = next((m for m in (owner or {}).get('members', []) if m['name'] == 'createPlayerInstance'), None)
    body = tokens(member) if member else []
    starts = []
    for seq in INSTANCE_ORDER:
        hits = _hits(body, seq)
        if len(hits) != 1:
            errors.append('P20 relocated instance site missing/duplicated: ' + ' '.join(seq))
        else:
            starts.append(hits[0])
    if len(starts) == len(INSTANCE_ORDER) and starts != sorted(starts):
        errors.append('P20 relocated instance creation order changed')
    for name in FACTORY_FORWARDERS:
        if len(_hits(body, ['_host', '.', name, '('])) != 1 or sources[INSTANCE].count(name + '(') != 2:
            errors.append('P20 factory forwarder use count changed: ' + name)
    facade = parse({'f': sources[SOURCE]}, package, ownership=True)['f']
    adapter = next((n for n in facade['declarations'] if n['name'] == INSTANCE_ADAPTER), None)
    members = {m['name']: tokens(m) for m in (adapter or {}).get('members', [])}
    for name, expected in FACTORY_FORWARDERS.items():
        if members.get(name) != expected:
            errors.append('P20 factory forwarder changed: ' + INSTANCE_ADAPTER + '.' + name)
    return errors


def prove(package, self_test=False):
    seam = load_manifest(MANIFEST)
    phase_path = 'dev/tool/dart_moves/vplayer_p1.json'
    phase = load_manifest(phase_path)
    seam_ledger = phase if phase['status'] == 'applied' else seam
    applied = []
    for path in (ROOT / 'dev/tool/dart_moves').glob('*.json'):
        candidate = load_manifest(path)
        if (candidate.get('schema') == 1 and candidate.get('series') == 'vplayer'
                and candidate.get('status') in {'applied', 'checkpoint'}):
            applied.append((path, candidate))
    active_path, manifest = max(applied, key=lambda item: (
        item[1]['phase'], item[1].get('status') == 'applied'))
    original = git_text(manifest['base'], SOURCE)
    current = (ROOT / SOURCE).read_text()
    sources = {p.relative_to(ROOT).as_posix(): p.read_text()
               for p in (ROOT / 'lib').rglob('*.dart')}
    owned = {path: sources[path] for path in [SOURCE, *manifest['destinations']]}
    errors = run_current_manifest(active_path, package)
    errors += installation_errors(sources)
    errors += relocation_errors(sources, package)
    relocated = INSTANCE in sources
    patched = [r for r in seam_ledger['declarations'] if r['fate'] == 'patched']
    assert {r['original'] for r in patched} == {
        '_VideoPlayerScreenState.initState', '_VideoPlayerScreenState._createPlayerInstance'}
    assert sum(len(r['patches']) for r in patched) == 3
    # A later ownership ledger must keep the accepted S interception edits
    # and installer scaffold exactly, rather than replace the S proof.
    seam_patches = {r['original']: r['patches'] for r in seam['declarations']
                    if r['fate'] == 'patched'}
    assert {r['original']: r['patches'] for r in patched} == seam_patches
    assert (seam_ledger['scaffolding'][SOURCE]['VideoPlayerScreenTestHooks']
            == seam['scaffolding'][SOURCE]['VideoPlayerScreenTestHooks'])
    unit = parse({'current': current}, package, ownership=True)['current']
    hook = next(n for n in unit['declarations'] if n['name'] == 'VideoPlayerScreenTestHooks')
    assert tokens(hook) == seam['scaffolding'][SOURCE]['VideoPlayerScreenTestHooks']
    members = {n['name']: tokens(n) for n in hook['members']}
    installed = members['install']
    required = [
        ['if', '(', 'kReleaseMode', '||', 'kProfileMode', ')'],
        ['if', '(', '!', 'const', 'bool', '.', 'fromEnvironment', '(', "'DEBRIFY_VP_TEST_HOOKS'", ')', ')'],
        ['assert', '(', '(', ')', '{', '_installed', '=', 'hooks', ';', 'return', 'true', ';', '}', '(', ')', ')', ';'],
    ]
    starts = []
    for seq in required:
        hits = [i for i in range(len(installed)) if installed[i:i + len(seq)] == seq]
        assert len(hits) == 1, ('installation guard missing/duplicated', seq)
        starts.append(hits[0])
    assert starts == sorted(starts)
    assert installed.count('throw') == 2
    assignments = [i for i, v in enumerate(tokens(hook))
                   if v == '_installed' and tokens(hook)[i + 1:i + 2] == ['=']]
    assert len(assignments) == 1
    defaults = {'_ensureInitialized': ['MediaKitInit', '.', 'ensureInitialized'],
                '_createPlayer': ['mk', '.', 'Player', '('],
                '_createVideoController': ['mkv', '.', 'VideoController', '(']}
    for name, sequence in defaults.items():
        body = members[name]
        assert sum(body[i:i + len(sequence)] == sequence for i in range(len(body))) == 1
        assert body.count('hooks') == 3  # snapshot, null test, alternative call
    if self_test:
        for name, text in {
            'second assignment': current.replace('_installed = hooks;', '_installed = hooks; _installed = hooks;'),
            'missing release guard': current.replace('kReleaseMode || kProfileMode', 'kReleaseMode'),
            'missing flag': current.replace("'DEBRIFY_VP_TEST_HOOKS'", "'OTHER_FLAG'"),
            'twice default': current.replace('MediaKitInit.ensureInitialized();', 'MediaKitInit.ensureInitialized(); MediaKitInit.ensureInitialized();'),
            'configuration twice': current.replace('mk.Player(configuration: configuration)', 'mk.Player(configuration: mk.PlayerConfiguration())'),
        }.items():
            assert check(manifest, original, dict(owned, **{SOURCE: text}), package), 'accepted ' + name
        if not relocated:
            for name, text in {
                'ready removed': current.replace('ready: () => _onPlayerInstanceReady(instanceGeneration),', ''),
                'assignment order': current.replace('_player = player;\n    _playerCreated = true;', '_playerCreated = true;\n    _player = player;'),
            }.items():
                assert text != current, 'negative did not apply: ' + name
                assert check(manifest, original, dict(owned, **{SOURCE: text}), package), 'accepted ' + name
        else:
            instance = sources[INSTANCE]
            for name, path, text in [
                ('ready removed', INSTANCE, instance.replace('ready: () => onPlayerInstanceReady(instanceGeneration),', '')),
                ('ready rerouted', INSTANCE, instance.replace('ready: () => onPlayerInstanceReady(instanceGeneration),', 'ready: () => _host.setState(() {}),')),
                ('assignment order', INSTANCE, instance.replace('_host.player = player;\n    _host.playerCreated = true;', '_host.playerCreated = true;\n    _host.player = player;')),
                ('factory twice', INSTANCE, instance.replace('    _host.player = player;\n', '    _host.player = player;\n    _host.createPlayer(configuration: mk.PlayerConfiguration());\n')),
                ('forwarder bypassed', SOURCE, current.replace('VideoPlayerScreenTestHooks._createPlayer(configuration: configuration);', 'mk.Player(configuration: configuration);')),
                ('controller forwarder bypassed', SOURCE, current.replace('}) => VideoPlayerScreenTestHooks._createVideoController(', '}) => VideoPlayerScreenTestHooks._createVideoController(\n    mk.Player(),\n    configuration: configuration,\n  );\n  mkv.VideoController unused(\n    mk.Player player, {\n    required mkv.VideoControllerConfiguration configuration,\n  }) => VideoPlayerScreenTestHooks._createVideoController(', 1)),
            ]:
                assert text != sources[path], 'negative did not apply: ' + name
                mutated = dict(sources, **{path: text})
                assert relocation_errors(mutated, package), 'relocation accepted ' + name
                assert check(manifest, original, dict(owned, **{path: text}), package), 'accepted ' + name
        assert installation_errors({SOURCE: current, 'lib/other.dart': 'VideoPlayerScreenTestHooks.install(null);'})
        if relocated:
            assert installation_errors(dict(sources, **{INSTANCE: sources[INSTANCE] + '\n// VideoPlayerScreenTestHooks\n'}))
    return errors, dict(p20_relocated_instance=relocated, patched_declarations=2, interception_patches=3,
                        original_spans=len(manifest['declarations']), ownership_phase=manifest['phase'],
                        frozen_scaffolding=list(seam_ledger['scaffolding'][SOURCE]),
                        default_operations_once=True, original_configuration_once=True,
                        installation='explicit release/profile throw, compile-time flag, assert-only assignment',
                        negatives=self_test)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    ensure_parser_package(args.parser_package.parents[1], args.parser_package)
    errors, result = prove(args.parser_package, args.self_test)
    if args.output:
        args.output.write_text(json.dumps(dict(errors=errors, **result), indent=2) + '\n')
    for error in errors:
        print(error)
    print('FAIL' if errors else 'PASS', json.dumps(result))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
