#!/usr/bin/env python3
"""S2/S2b/S2c/S2d ownership, default/order and installation/reference guards."""
import argparse
import json
import re
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import run_manifest
from check_settings_moves import tokens
from dart_move_history import git_text, load_manifest
from vplayer_source_reader import read

SOURCE = 'lib/screens/video_player_screen.dart'
MANIFEST = 'dev/tool/dart_moves/vplayer_p8_seam.json'
S2C_MANIFEST = 'dev/tool/dart_moves/vplayer_p10_seam.json'
S2D_MANIFEST = 'dev/tool/dart_moves/vplayer_p13_seam.json'
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
S2C_SITE = '_setSubtitleTrackWithDiagnostics'
S2C_PATCH = dict(
    before=['if', '(', 'Platform', '.', 'isAndroid', '&&', '!',
            'PlatformUtil', '.', 'isAndroidTvCached', '&&'],
    after=['if', '(', HOOK, '.', 'isAndroid', '&&', '!',
           'PlatformUtil', '.', 'isAndroidTvCached', '&&'], count=1)
S2C_CONTEXT = [
    'if', '(', 'isCurrent', '!=', 'null', '&&', '!', 'isCurrent', '(', ')',
    ')', 'return', 'false', ';',
    *S2C_PATCH['after'],
    'requiresNativeSubtitleRendering', '(', 'track', ')', '&&',
    '_androidVideoRendererMode', '!=', 'AndroidVideoRendererMode', '.',
    'directMediaCodec', ')',
]
S2D_SUPPORT = ['DesktopRecordingService', '.', 'instance', '.', 'isSupported']
S2D_PATCHES = {
    'initState': dict(
        before=['if', '(', *S2D_SUPPORT, ')'],
        after=['if', '(', *S2D_SUPPORT, '&&', '!', HOOK, '.', 'isIOS', ')'],
        count=1),
    '_toggleRecording': dict(
        before=['if', '(', *S2D_SUPPORT, '&&', '_recordingSupported', ')'],
        after=['if', '(', *S2D_SUPPORT, '&&', '!', HOOK, '.', 'isIOS',
               '&&', '_recordingSupported', ')'], count=1),
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
    body = members.get(S2C_SITE, [])
    if len(includes(body, S2C_CONTEXT)) != 1 or body.count(HOOK) != 1:
        errors.append('S2c renderer predicate default/count/order changed: ' + S2C_SITE)
    return errors


def subtitle_projection_errors(members):
    """Check the live default path independently of ownership normalization."""
    expected = {
        'isAndroid': ['@', 'override', 'bool', 'get', 'isAndroid', '=>', HOOK, '.', 'isAndroid', ';'],
        'androidVideoRendererMode': [
            '@', 'override', 'AndroidVideoRendererMode', 'get', 'androidVideoRendererMode', '=>',
            '_s', '.', '_androidVideoRendererMode', ';'],
    }
    return ['S2c live Host projection changed: ' + name
            for name, body in expected.items() if members.get(name) != body]


def recording_projection_errors(members):
    """Check relocated S2d defaults independently of ownership normalization."""
    expected = {
        'isIOS': ['@', 'override', 'bool', 'get', 'isIOS', '=>', HOOK, '.', 'isIOS', ';'],
        'recordingSupported': ['@', 'override', 'bool', 'get', 'recordingSupported',
                               '=>', '_s', '.', '_recordingSupported', ';'],
    }
    return ['S2d live Host projection changed: ' + name
            for name, body in expected.items() if members.get(name) != body]


def recording_site_errors(members):
    """Independent exact sites: original support read precedes the live override."""
    errors = []
    for name, patch in S2D_PATCHES.items():
        body = members.get(name, [])
        if (len(includes(body, patch['after'])) != 1
                or len(includes(body, S2D_SUPPORT)) != 1):
            errors.append('S2d desktop predicate default/count/order changed: ' + name)
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
    # S2c belongs to the current phase, rather than rewriting the P8 ledger.
    # The accepted S2b checkpoint remains exactly frozen, including its patches.
    assert checkpoint == load_manifest(MANIFEST, '866cbaf03')
    extension = load_manifest(S2C_MANIFEST)
    extension_patches = [r for r in extension['declarations'] if r['fate'] == 'patched']
    assert extension['base'] == '5c7b704bd' and extension['checkpoint'] == 'S2c'
    assert len(extension_patches) == 1
    assert extension_patches[0]['original'] == '_VideoPlayerScreenState.' + S2C_SITE
    assert extension_patches[0]['patches'] == [S2C_PATCH]
    assert all(r['fate'] in {'retained', 'patched'} for r in extension['declarations'])
    assert extension['destinations'] == extension['scaffolding'] == {}
    # The accepted S2c ledger also stays frozen. S2d owns just the two
    # desktop gates; it adds no hook, installer or production destination.
    assert extension == load_manifest(S2C_MANIFEST, 'a2e034cb3')
    recording = load_manifest(S2D_MANIFEST)
    recording_patches = {r['original']: r['patches'] for r in recording['declarations']
                         if r['fate'] == 'patched'}
    assert recording['base'] == 'e4a9ab581' and recording['checkpoint'] == 'S2d'
    assert recording_patches == {'_VideoPlayerScreenState.' + name: [patch]
                                  for name, patch in S2D_PATCHES.items()}
    assert all(r['fate'] in {'retained', 'patched'} for r in recording['declarations'])
    assert recording['destinations'] == recording['scaffolding'] == {}
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
                        for n in state['members'] if n['name'] in {*S2B_SITES, S2C_SITE}}
    projection_members = None
    if S2C_SITE not in renderer_members:
        # Resolve and validate the LIVE owner before examining the relocated
        # predicate. This never returns git-show text or bypasses the move proof.
        resolved = read('_VideoPlayerScreenState.' + S2C_SITE, package)
        assert resolved['path'] == 'lib/features/video_player/presentation/legacy_video_player/vp_subtitle_apply.dart'
        moved = parse({'live': resolved['source']}, package, ownership=True)['live']['declarations'][0]
        body = [t['text'] for t in moved['tokens'] if not t['comment']]
        for before, after in [
            (['_host', '.', 'isAndroid'], [HOOK, '.', 'isAndroid']),
            (['_host', '.', 'androidVideoRendererMode'], ['_androidVideoRendererMode']),
        ]:
            hits = includes(body, before)
            assert len(hits) == 1, (before, hits)
            at = hits[0]
            body[at:at + len(before)] = after
        renderer_members[S2C_SITE] = body
        adapter = next(n for n in unit['declarations'] if n['name'] == '_VpSubtitleApplyHostAdapter')
        projection_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                              for n in adapter['members']}
        errors += subtitle_projection_errors(projection_members)
    errors += renderer_site_errors(renderer_members)
    recording_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                         for n in state['members'] if n['name'] in S2D_PATCHES}
    recording_projection_members = None
    if '_toggleRecording' not in recording_members:
        # Resolve the LIVE owner through the current exhaustive move ledger.
        # Restore only its two typed Host projections for the independent
        # original-condition proof; never substitute historical source text.
        resolved = read('_VideoPlayerScreenState._toggleRecording', package)
        assert resolved['path'] == 'lib/features/video_player/presentation/legacy_video_player/vp_iptv_recording.dart'
        moved = parse({'live': resolved['source']}, package, ownership=True)['live']['declarations'][0]
        body = [t['text'] for t in moved['tokens'] if not t['comment']]
        for before, after in [
            (['_host', '.', 'isIOS'], [HOOK, '.', 'isIOS']),
            (['_host', '.', 'recordingSupported'], ['_recordingSupported']),
        ]:
            hits = includes(body, before)
            assert hits, (before, hits)
            for at in reversed(hits):
                body[at:at + len(before)] = after
        recording_members['_toggleRecording'] = body
        adapter = next(n for n in unit['declarations'] if n['name'] == '_VpIptvRecordingHostAdapter')
        recording_projection_members = {
            n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
            for n in adapter['members'] if not n.get('isSetter')}
        errors += recording_projection_errors(recording_projection_members)
    errors += recording_site_errors(recording_members)
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
        if projection_members is not None:
            for name, member, before, after in [
                ('wrong predicate', 'isAndroid', ['isAndroid', ';'], ['isIOS', ';']),
                ('override bypassed', 'isAndroid', [HOOK], ['Platform']),
                ('cached predicate', 'isAndroid', [HOOK, '.', 'isAndroid'], ['_cachedAndroid']),
                ('predicate twice', 'isAndroid', [HOOK, '.', 'isAndroid'],
                 [HOOK, '.', 'isAndroid', '&&', HOOK, '.', 'isAndroid']),
                ('cached renderer', 'androidVideoRendererMode', ['_s', '.', '_androidVideoRendererMode'], ['_cachedRenderer']),
            ]:
                mutated = copy.deepcopy(projection_members)
                body = mutated[member]
                hits = includes(body, before)
                assert len(hits) == 1
                at = hits[0]
                body[at:at + len(before)] = after
                assert subtitle_projection_errors(mutated), 'independent S2c projection accepted ' + name
                negatives.append('S2c Host projection: ' + name)
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
        for name, before, after in [
            ('wrong predicate', [HOOK, '.', 'isAndroid'], [HOOK, '.', 'isIOS']),
            ('override bypassed', [HOOK], ['Platform']),
            ('predicate twice', [HOOK, '.', 'isAndroid'],
             [HOOK, '.', 'isAndroid', '&&', HOOK, '.', 'isAndroid']),
            ('operand order', S2C_PATCH['after'],
             ['if', '(', '!', 'PlatformUtil', '.', 'isAndroidTvCached', '&&',
              HOOK, '.', 'isAndroid', '&&']),
            ('TV predicate changed', ['isAndroidTvCached'], ['isTelevision']),
            ('current guard order', S2C_CONTEXT, S2C_CONTEXT[14:]),
            ('native rendering predicate changed', ['requiresNativeSubtitleRendering'], ['isText']),
            ('renderer mode changed', ['directMediaCodec'], ['auto']),
        ]:
            mutated = copy.deepcopy(renderer_members)
            body = mutated[S2C_SITE]
            hits = includes(body, before)
            assert len(hits) == 1, (name, hits)
            start = hits[0]
            body[start:start + len(before)] = after
            assert renderer_site_errors(mutated), 'independent S2c site guard accepted ' + name
            negatives.append('S2c ' + S2C_SITE + ': ' + name)
        if recording_projection_members is not None:
            for name, before, after in [
                ('bypassed override', [HOOK], ['Platform']),
                ('wrong default', [HOOK, '.', 'isIOS'], [HOOK, '.', 'isAndroid']),
                ('duplicate predicate', [HOOK, '.', 'isIOS'],
                 [HOOK, '.', 'isIOS', '||', HOOK, '.', 'isIOS']),
                ('wrong support field', ['_s', '.', '_recordingSupported'],
                 ['_s', '.', '_isRecording']),
            ]:
                mutated = copy.deepcopy(recording_projection_members)
                body = mutated['recordingSupported' if name == 'wrong support field' else 'isIOS']
                hits = includes(body, before)
                assert len(hits) == 1
                at = hits[0]
                body[at:at + len(before)] = after
                assert recording_projection_errors(mutated), name
                negatives.append('S2d Host projection: ' + name)
        for site, patch in S2D_PATCHES.items():
            changes = [
                ('wrong predicate', [HOOK, '.', 'isIOS'], [HOOK, '.', 'isAndroid']),
                ('override bypassed', [HOOK], ['Platform']),
                ('predicate twice', [HOOK, '.', 'isIOS'],
                 [HOOK, '.', 'isIOS', '||', HOOK, '.', 'isIOS']),
                ('support twice', S2D_SUPPORT, [*S2D_SUPPORT, '&&', *S2D_SUPPORT]),
                ('operand order', [*S2D_SUPPORT, '&&', '!', HOOK, '.', 'isIOS'],
                 ['!', HOOK, '.', 'isIOS', '&&', *S2D_SUPPORT]),
                ('override polarity', ['&&', '!', HOOK], ['&&', HOOK]),
                ('support changed', ['isSupported'], ['isAvailable']),
            ]
            if site == '_toggleRecording':
                changes.append(('recording support order', patch['after'],
                                ['if', '(', '_recordingSupported', '&&', *S2D_SUPPORT,
                                 '&&', '!', HOOK, '.', 'isIOS', ')']))
            for name, before, after in changes:
                mutated = copy.deepcopy(recording_members)
                body = mutated[site]
                # initState already has an earlier PiP isIOS read. Mutate
                # only the desktop condition, never that accepted S2 site.
                start = includes(body, patch['after'])[0]
                end = start + len(patch['after'])
                condition = body[start:end]
                hits = includes(condition, before)
                assert len(hits) == 1, (site, name, hits)
                at = hits[0]
                condition[at:at + len(before)] = after
                body[start:end] = condition
                assert recording_site_errors(mutated), 'independent S2d site guard accepted ' + site + ': ' + name
                negatives.append('S2d ' + site + ': ' + name)
    return errors, dict(patched_declarations=len(patched), counted_patches=sum(len(r['patches']) for r in patched), predicate_occurrences=sum(sum(c.values()) for c in SITES.values()),
                        classified_spans=len(checkpoint['declarations']), active_phase=active['phase'], independent_negatives=negatives,
                        s2_declarations_preserved=len(accepted_patches), s2b_sites=len(S2B_SITES),
                        s2c_sites=1, s2c_classified_spans=len(extension['declarations']),
                        s2c_patched_declarations=1, s2c_predicate_occurrences=1,
                        s2d_sites=len(S2D_PATCHES), s2d_classified_spans=len(recording['declarations']),
                        s2d_patched_declarations=len(recording_patches), s2d_predicate_occurrences=2)


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
