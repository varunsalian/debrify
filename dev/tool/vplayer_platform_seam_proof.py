#!/usr/bin/env python3
"""S2/S2b ownership, native default/order and installation/reference guards."""
import argparse
import json
import re
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import run_manifest
from check_settings_moves import tokens
from dart_move_history import git_text, load_manifest

SOURCE = 'lib/screens/video_player_screen.dart'
MANIFEST = 'dev/tool/dart_moves/vplayer_p8_seam.json'
HOOK = 'VpS2Hooks'
S2_SITES = {
    'initState': {'isIOS': 1, 'isAndroid': 1},
    '_bindPlayerInstanceSubscriptions': {'isIOS': 1},
    '_openMedia': {'isIOS': 1},
    '_setNativeSubtitleVisibilityForTrack': {'isIOS': 1},
    '_buildSubtitleViewConfig': {'isIOS': 1},
    '_enterPip': {'isIOS': 4},
    '_armPipAutoEnter': {'isIOS': 1},
    '_onPipModeChanged': {'isIOS': 1},
    '_pauseForBackground': {'isIOS': 2, 'isAndroid': 1},
}
S2B_SITES = {
    '_initializePlayer': {'isAndroid': 1},
    '_canFallbackExplicitRenderer': {'isAndroid': 1},
}
SITES = {**S2_SITES, **S2B_SITES}
S2B_CONTEXTS = {
    '_initializePlayer': ['if', '(', HOOK, '.', 'isAndroid', '&&', '!',
                          'PlatformUtil', '.', 'isAndroidTvCached', ')'],
    '_canFallbackExplicitRenderer': [
        'AndroidRendererStartupFallback', '.', 'shouldArm', '(', 'isAndroid',
        ':', HOOK, '.', 'isAndroid', ',', 'isAndroidTv', ':', 'PlatformUtil',
        '.', 'isAndroidTvCached', ','],
}
S2B_PATCHES = {
    '_initializePlayer': dict(
        before=['if', '(', 'Platform', '.', 'isAndroid', '&&', '!',
                'PlatformUtil', '.', 'isAndroidTvCached', ')'],
        after=S2B_CONTEXTS['_initializePlayer'], count=1),
    '_canFallbackExplicitRenderer': dict(
        before=['isAndroid', ':', 'Platform', '.', 'isAndroid'],
        after=['isAndroid', ':', HOOK, '.', 'isAndroid'], count=1),
}


def includes(body, seq):
    return [i for i in range(len(body)) if body[i:i + len(seq)] == seq]


def default_errors(members):
    errors = []
    for name, callback in [('isIOS', 'ios'), ('isAndroid', 'android')]:
        expected = ['static', 'bool', 'get', name, '=>', '_installed', '?.', callback,
                    '?.', 'call', '(', ')', '??', 'Platform', '.', name, ';']
        if members[name] != expected:
            errors.append('default/override path changed: ' + name)
    return errors


def installation_errors(members):
    body = members['install']
    guards = [
        ['if', '(', 'kReleaseMode', '||', 'kProfileMode', ')'],
        ['if', '(', '!', 'const', 'bool', '.', 'fromEnvironment', '(', "'DEBRIFY_VP_TEST_HOOKS'", ')', ')'],
        ['assert', '(', '(', ')', '{', '_installed', '=', 'hooks', ';', 'return', 'true', ';', '}', '(', ')', ')', ';'],
    ]
    locations = [includes(body, seq) for seq in guards]
    assignments = includes(body, ['_installed', '='])
    errors = []
    if any(len(p) != 1 for p in locations) or [p[0] for p in locations if p] != sorted(p[0] for p in locations if p):
        errors.append('installation gates/assert order changed')
    if len(assignments) != 1 or body.count('throw') != 2:
        errors.append('installation assignment/throws changed')
    for key, member in members.items():
        if key != 'install' and includes(member, ['_installed', '=']):
            errors.append('installation outside installer: ' + key)
    return errors


def renderer_site_errors(members):
    """Independent of manifest substitutions: once-only reads in original order."""
    errors = []
    for name, context in S2B_CONTEXTS.items():
        body = members.get(name, [])
        if len(includes(body, context)) != 1 or body.count(HOOK) != 1:
            errors.append('renderer predicate default/count/order changed: ' + name)
    return errors


def source_errors(sources):
    errors = ['platform hook reference outside facade: ' + path for path, source in sources.items()
              if path != SOURCE and HOOK in source]
    if re.search(r'\b' + HOOK + r'\s*\.\s*(install|_installed)\b', sources.get(SOURCE, '')):
        errors.append('qualified installer/storage reference in facade')
    return errors


def prove(package, self_test=False):
    checkpoint = load_manifest(MANIFEST)
    patched = [r for r in checkpoint['declarations'] if r['fate'] == 'patched']
    expected = { '_VideoPlayerScreenState.' + name: counts for name, counts in SITES.items() }
    assert set(r['original'] for r in patched) == set(expected)
    for row in patched:
        name = row['original'].split('.')[-1]
        declared = ([S2B_PATCHES[name]] if name in S2B_PATCHES else
                    [dict(before=['Platform', '.', predicate], after=[HOOK, '.', predicate], count=count)
                     for predicate, count in expected[row['original']].items()])
        assert row['patches'] == declared
    # Preserve the accepted S2 declaration patches and hook/installer verbatim.
    accepted_s2 = json.loads(git_text('21b19c944', MANIFEST))
    accepted_patches = {r['original']: r['patches'] for r in accepted_s2['declarations']
                        if r['fate'] == 'patched'}
    assert set(accepted_patches) == {'_VideoPlayerScreenState.' + name for name in S2_SITES}
    current_patches = {r['original']: r['patches'] for r in patched}
    assert all(current_patches[name] == patches for name, patches in accepted_patches.items())
    assert checkpoint['scaffolding'] == accepted_s2['scaffolding']
    applied = []
    for path in (ROOT / 'dev/tool/dart_moves').glob('*.json'):
        candidate = json.loads(path.read_text())
        if isinstance(candidate, dict) and candidate.get('series') == 'vplayer' and candidate.get('status') in {'applied', 'checkpoint'}:
            applied.append((path, candidate))
    active_path, active = max(applied, key=lambda item: (item[1]['phase'], item[1]['status'] == 'applied'))
    errors = run_manifest(active_path, package)
    sources = {p.relative_to(ROOT).as_posix(): p.read_text() for p in (ROOT / 'lib').rglob('*.dart')}
    errors += source_errors(sources)
    unit = parse({SOURCE: sources[SOURCE]}, package, ownership=True)[SOURCE]
    hook = next(n for n in unit['declarations'] if n['name'] == HOOK)
    assert tokens(hook) == checkpoint['scaffolding'][SOURCE][HOOK]
    members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']] for n in hook['members']}
    errors += default_errors(members) + installation_errors(members)
    state = next(n for n in unit['declarations'] if n['name'] == '_VideoPlayerScreenState')
    renderer_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                        for n in state['members'] if n['name'] in S2B_SITES}
    errors += renderer_site_errors(renderer_members)
    negatives = []
    if self_test:
        import copy
        for name, getter, old, new in [
            ('wrong iOS default', 'isIOS', 'isIOS', 'isAndroid'),
            ('wrong Android default', 'isAndroid', 'isAndroid', 'isIOS'),
            ('override ignored', 'isIOS', '_installed', 'null'),
            ('default eager', 'isIOS', '??', '|'),
            ('callback twice', 'isIOS', 'call', 'callTwice'),
        ]:
            mutated = copy.deepcopy(members);target = mutated[getter];index = len(target)-2 if name.startswith('wrong') else target.index(old);target[index] = new
            assert default_errors(mutated), 'independent default guard accepted ' + name
            negatives.append(name)
        for name, old, new in [
            ('release missing', ['kReleaseMode', '||'], []),
            ('profile missing', ['||', 'kProfileMode'], []),
            ('flag missing', ["'DEBRIFY_VP_TEST_HOOKS'"], ["'OTHER_FLAG'"]),
            ('assignment outside assert', ['assert'], ['call']),
            ('second assignment', ['return', 'true'], ['_installed', '=', 'hooks', ';', 'return', 'true']),
        ]:
            mutated = copy.deepcopy(members);body = mutated['install'];hit = includes(body, old);assert len(hit)==1;index=hit[0];body[index:index+len(old)]=new
            assert installation_errors(mutated), 'independent install guard accepted ' + name
            negatives.append(name)
        mutated = copy.deepcopy(members);mutated['other'] = ['_installed', '=', 'hooks', ';'];assert installation_errors(mutated);negatives.append('assignment in other member')
        assert source_errors({SOURCE:sources[SOURCE], 'lib/other.dart':HOOK + '.install(null);'});negatives.append('other lib reference')
        assert source_errors({SOURCE:sources[SOURCE] + '\n' + HOOK + '.install(null);'});negatives.append('facade installer reference')
        for site, context in S2B_CONTEXTS.items():
            for name in ['wrong predicate', 'override bypassed', 'predicate twice',
                         'operand order', 'TV predicate changed']:
                mutated = copy.deepcopy(renderer_members)
                body = mutated[site]
                start = includes(body, context)[0]
                hook_at = start + context.index(HOOK)
                if name == 'wrong predicate':
                    body[hook_at + 2] = 'isIOS'
                elif name == 'override bypassed':
                    body[hook_at] = 'Platform'
                elif name == 'predicate twice':
                    body[hook_at:hook_at] = [HOOK, '.', 'isAndroid', '&&']
                elif name == 'operand order':
                    end = start + len(context)
                    reordered = (['if', '(', '!', 'PlatformUtil', '.', 'isAndroidTvCached',
                                  '&&', HOOK, '.', 'isAndroid', ')']
                                 if site == '_initializePlayer' else
                                 ['AndroidRendererStartupFallback', '.', 'shouldArm', '(',
                                  'isAndroidTv', ':', 'PlatformUtil', '.', 'isAndroidTvCached', ',',
                                  'isAndroid', ':', HOOK, '.', 'isAndroid', ','])
                    body[start:end] = reordered
                else:
                    body[body.index('isAndroidTvCached', start)] = 'isTelevision'
                assert renderer_site_errors(mutated), 'independent site guard accepted ' + site + ': ' + name
                negatives.append('S2b ' + site + ': ' + name)
    return errors, dict(patched_declarations=len(patched), counted_patches=sum(len(r['patches']) for r in patched), predicate_occurrences=sum(sum(c.values()) for c in SITES.values()),
                        classified_spans=len(checkpoint['declarations']), active_phase=active['phase'], independent_negatives=negatives,
                        s2_declarations_preserved=len(accepted_patches), s2b_sites=len(S2B_SITES))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parser-package', type=Path, required=True)
    p.add_argument('--self-test', action='store_true')
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    errors, result = prove(args.parser_package, args.self_test)
    if args.output:args.output.write_text(json.dumps(dict(errors=errors, **result), indent=2)+'\n')
    for error in errors:print(error)
    print('FAIL' if errors else 'PASS', json.dumps(result))
    return bool(errors)

if __name__ == '__main__':raise SystemExit(main())
