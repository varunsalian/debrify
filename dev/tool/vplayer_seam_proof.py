#!/usr/bin/env python3
"""Validate frozen S, installation guards and the three once-only default paths."""
import argparse
import copy
import json
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import check
from dart_move_history import git_text, load_manifest
from dart_move_partition import partition
from check_settings_moves import tokens

SOURCE = 'lib/screens/video_player_screen.dart'
MANIFEST = 'dev/tool/dart_moves/vplayer_p1_seam.json'


def installation_errors(sources):
    errors = []
    for path, text in sources.items():
        if path != SOURCE and 'VideoPlayerScreenTestHooks' in text:
            errors.append('test hook reference outside its facade: ' + path)
    # All facade hook code is frozen by the exhaustive token check. This
    # separately forbids references in all other application files.
    return errors


def prove(package, self_test=False):
    manifest = load_manifest(MANIFEST)
    original = git_text(manifest['base'], SOURCE)
    current = (ROOT / SOURCE).read_text()
    sources = {p.relative_to(ROOT).as_posix(): p.read_text()
               for p in (ROOT / 'lib').rglob('*.dart')}
    errors = check(manifest, original, {SOURCE: current}, package)
    errors += installation_errors(sources)
    patched = [r for r in manifest['declarations'] if r['fate'] == 'patched']
    assert {r['original'] for r in patched} == {
        '_VideoPlayerScreenState.initState', '_VideoPlayerScreenState._createPlayerInstance'}
    assert sum(len(r['patches']) for r in patched) == 3
    unit = parse({'current': current}, package, ownership=True)['current']
    hook = next(n for n in unit['declarations'] if n['name'] == 'VideoPlayerScreenTestHooks')
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
            'ready removed': current.replace('ready: () => _onPlayerInstanceReady(instanceGeneration),', ''),
            'assignment order': current.replace('_player = player;\n    _playerCreated = true;', '_playerCreated = true;\n    _player = player;'),
        }.items():
            assert check(manifest, original, {SOURCE: text}, package), 'accepted ' + name
        assert installation_errors({SOURCE: current, 'lib/other.dart': 'VideoPlayerScreenTestHooks.install(null);'})
    return errors, dict(patched_declarations=2, interception_patches=3,
                        original_spans=len(manifest['declarations']),
                        frozen_scaffolding=list(manifest['scaffolding'][SOURCE]),
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
