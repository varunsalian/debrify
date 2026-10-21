#!/usr/bin/env python3
"""S2/S2b/S2c/S2d/S2e/S2f ownership, default/order and installation/reference guards."""
import argparse
import json
import re
from pathlib import Path

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_dart_moves import run_manifest
from check_settings_moves import tokens
from vplayer_checkpoint_proof import run_current_manifest
from dart_move_history import git_text, load_manifest
from vplayer_source_reader import read

SOURCE = 'lib/screens/video_player_screen.dart'
MANIFEST = 'dev/tool/dart_moves/vplayer_p8_seam.json'
S2C_MANIFEST = 'dev/tool/dart_moves/vplayer_p10_seam.json'
S2D_MANIFEST = 'dev/tool/dart_moves/vplayer_p13_seam.json'
S2E_MANIFEST = 'dev/tool/dart_moves/vplayer_p16_seam.json'
S2F_MANIFEST = 'dev/tool/dart_moves/vplayer_p19_seam.json'
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

S2E_SITES = ('_openStartupDebridDirect', '_tryOpenStartupVod')
S2E_PATCH = dict(before=['Platform', '.', 'isAndroid'],
                 after=[HOOK, '.', 'isAndroid'], count=1)
S2E_CONDITION = [
    'if', '(', 'AndroidRendererStartupFallback', '.', 'isRendererFailure',
    '(', 'error', ')', '&&', 'AndroidRendererStartupFallback', '.', 'shouldArm',
    '(', 'isAndroid', ':', HOOK, '.', 'isAndroid', ',',
    'isAndroidTv', ':', 'PlatformUtil', '.', 'isAndroidTvCached', ',',
    'mode', ':', '_androidVideoRendererMode', ',',
    'alreadyValidated', ':', '_rendererValidatedForSession', ',',
    'fallbackInProgress', ':', '_rendererFallbackInProgress', ',', ')', ')',
]


VALIDATION = 'isAndroidRendererValidation'
S2F_PATCHES = {
    '_installDecoderObservers': dict(
        before=['!', 'Platform', '.', 'isAndroid', ')', 'return', ';'],
        after=['!', HOOK, '.', VALIDATION, ')', 'return', ';'], count=1),
    '_scheduleRendererStartupValidation': dict(
        before=['isAndroid', ':', 'Platform', '.', 'isAndroid', ','],
        after=['isAndroid', ':', HOOK, '.', VALIDATION, ','], count=1),
}
_GETTER = ['_installed', '?.', 'android', '?.', 'call', '(', ')', '??',
           'Platform', '.', 'isAndroid', ';']
S2F_HOOK_PATCHES = [
    dict(before=['this', '.', 'android', '}'],
         after=['this', '.', 'android', ',', 'this', '.', 'androidRendererValidation', '}'],
         count=1),
    dict(before=['?', 'android', ';', 'static'],
         after=['?', 'android', ';', 'final', 'bool', 'Function', '(', ')', '?',
                'androidRendererValidation', ';', 'static'], count=1),
    dict(before=[*_GETTER, '}'],
         after=[*_GETTER, 'static', 'bool', 'get', VALIDATION, '=>', '_installed', '?.',
                'androidRendererValidation', '?.', 'call', '(', ')', '??', 'Platform',
                '.', 'isAndroid', ';', '}'], count=1),
]
# Exact S2f contexts: the NativePlayer check precedes the observer gate, and
# the validation predicate is the first shouldArm argument.
S2F_CONTEXTS = {
    '_installDecoderObservers': [
        'if', '(', 'platform', 'is', '!', 'mk', '.', 'NativePlayer', ')', 'return', ';',
        'if', '(', '!', HOOK, '.', VALIDATION, ')', 'return', ';'],
    '_scheduleRendererStartupValidation': [
        'if', '(', '!', 'AndroidRendererStartupFallback', '.', 'shouldArm', '(',
        'isAndroid', ':', HOOK, '.', VALIDATION, ',',
        'isAndroidTv', ':', 'PlatformUtil', '.', 'isAndroidTvCached', ','],
}


def apply_patches(body, patches):
    body = list(body)
    for patch in patches:
        hits = includes(body, patch['before'])
        assert len(hits) == patch['count'] == 1, (patch['before'], hits)
        at = hits[0]
        body[at:at + len(patch['before'])] = patch['after']
    return body


RENDERER_FALLBACK = 'lib/features/video_player/presentation/legacy_video_player/vp_renderer_fallback.dart'
DECODER_PROBE = 'lib/features/video_player/presentation/legacy_video_player/vp_decoder_probe.dart'
# P19 resolution P1-1/P1-2 and P3: the fallback Host projects both live
# predicates; the probe Host projects only renderer validation.
ENGINE_PROJECTIONS = {
    '_VpRendererFallbackHostAdapter': ('isAndroid', VALIDATION),
    '_VpDecoderProbeHostAdapter': (VALIDATION,),
}

# P20 resolution P1-1/R2: startup projects live isAndroid (S2b site);
# subscriptions and media open project live isIOS (frozen S2 sites).
P20_DIR = 'lib/features/video_player/presentation/legacy_video_player/'
P20_SITES = [
    ('_initializePlayer', P20_DIR + 'vp_player_startup.dart', 'isAndroid'),
    ('_bindPlayerInstanceSubscriptions', P20_DIR + 'vp_player_subscriptions.dart', 'isIOS'),
    ('_openMedia', P20_DIR + 'vp_media_open.dart', 'isIOS'),
]
P20_PROJECTIONS = {
    '_VpPlayerStartupHostAdapter': ('isAndroid',),
    '_VpPlayerSubscriptionsHostAdapter': ('isIOS',),
    '_VpMediaOpenHostAdapter': ('isIOS',),
}


def p20_projection_errors(adapters):
    """Relocated P20 owners read each predicate live through the facade."""
    errors = []
    for adapter, predicates in P20_PROJECTIONS.items():
        members = adapters.get(adapter, {})
        for predicate in predicates:
            expected = ['@', 'override', 'bool', 'get', predicate, '=>', HOOK, '.', predicate, ';']
            if members.get(predicate) != expected:
                errors.append('P20 live Host projection changed: ' + adapter + '.' + predicate)
        for predicate in {'isAndroid', 'isIOS', VALIDATION} - set(predicates):
            if predicate in members:
                errors.append('P20 unexpected Host projection: ' + adapter + '.' + predicate)
    return errors


def p20_site_errors(bodies):
    """Each relocated P20 site reads its live projection exactly once."""
    errors = []
    for site, _, predicate in P20_SITES:
        body = bodies.get(site, [])
        if len(includes(body, ['_host', '.', predicate])) != 1 or HOOK in body:
            errors.append('P20 relocated site predicate count changed: ' + site)
    return errors


def engine_projection_errors(adapters):
    """Relocated S2b/S2f owners read each predicate live through the facade."""
    errors = []
    for adapter, predicates in ENGINE_PROJECTIONS.items():
        members = adapters.get(adapter, {})
        for predicate in predicates:
            expected = ['@', 'override', 'bool', 'get', predicate, '=>', HOOK, '.', predicate, ';']
            if members.get(predicate) != expected:
                errors.append('P19 live Host projection changed: ' + adapter + '.' + predicate)
        for predicate in {'isAndroid', VALIDATION} - set(predicates):
            if predicate in members:
                errors.append('P19 unexpected Host projection: ' + adapter + '.' + predicate)
    return errors


def validation_site_errors(members):
    """One dedicated predicate per S2f site, in its original operand position."""
    return ['S2f validation predicate default/count/order changed: ' + name
            for name, context in S2F_CONTEXTS.items()
            if len(includes(members.get(name, []), context)) != 1
            or members.get(name, []).count(HOOK) != 1]


def candidate_site_errors(members):
    """Exact short-circuit and argument order; one live predicate per site."""
    return ['S2e candidate predicate default/count/order changed: ' + name
            for name in S2E_SITES
            if len(includes(members.get(name, []), S2E_CONDITION)) != 1
            or members.get(name, []).count(HOOK) != 1]


def candidate_projection_errors(members):
    """Candidates read each predicate/renderer value live at its original site."""
    expected = {
        'isAndroid': ['@', 'override', 'bool', 'get', 'isAndroid', '=>',
                      HOOK, '.', 'isAndroid', ';'],
        'androidVideoRendererMode': [
            '@', 'override', 'AndroidVideoRendererMode', 'get',
            'androidVideoRendererMode', '=>', '_s', '.',
            '_androidVideoRendererMode', ';'],
        **{name: ['@', 'override', 'bool', 'get', name, '=>', '_s', '.',
                  '_' + name, ';']
           for name in ['rendererValidatedForSession', 'rendererFallbackInProgress']},
    }
    return ['S2e live Host projection changed: ' + name
            for name, body in expected.items() if members.get(name) != body]


def includes(body, seq):
    return [i for i in range(len(body)) if body[i:i + len(seq)] == seq]


def default_errors(members):
    errors = []
    for name, callback, default in [('isIOS', 'ios', 'isIOS'), ('isAndroid', 'android', 'isAndroid'),
                                    (VALIDATION, 'androidRendererValidation', 'isAndroid')]:
        expected = ['static', 'bool', 'get', name, '=>', '_installed', '?.', callback,
                    '?.', 'call', '(', ')', '??', 'Platform', '.', default, ';']
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
    # Re-derived S2e exhaustively retains the accepted P15 facade.
    assert recording == load_manifest(S2D_MANIFEST, '1099a0039dab6023aef8c95754e4595e862e9a67')
    candidates = load_manifest(S2E_MANIFEST)
    assert candidates['base'] == 'ed7c6717a' and candidates['checkpoint'] == 'S2e'
    candidate_patches = {r['original']: r['patches'] for r in candidates['declarations']
                         if r['fate'] == 'patched'}
    assert candidate_patches == {'_VideoPlayerScreenState.' + n: [S2E_PATCH] for n in S2E_SITES}
    accepted_candidates = load_manifest(S2E_MANIFEST, '574b2a85e')
    assert candidate_patches == {
        r['original']: r['patches'] for r in accepted_candidates['declarations']
        if r['fate'] == 'patched'}
    assert all(r['fate'] in {'retained', 'patched'} for r in candidates['declarations'])
    assert candidates['destinations'] == candidates['scaffolding'] == {}
    validation = load_manifest(S2F_MANIFEST)
    assert validation['base'] == '46bc00ce7' and validation['checkpoint'] == 'S2f'
    validation_patches = {r['original']: r['patches'] for r in validation['declarations']
                          if r['fate'] == 'patched'}
    assert validation_patches == {
        **{'_VideoPlayerScreenState.' + n: [patch] for n, patch in S2F_PATCHES.items()},
        HOOK: S2F_HOOK_PATCHES}
    assert all(r['fate'] in {'retained', 'patched'} for r in validation['declarations'])
    assert validation['destinations'] == validation['scaffolding'] == {}
    applied = []
    for path in (ROOT / 'dev/tool/dart_moves').glob('*.json'):
        candidate = json.loads(path.read_text())
        if isinstance(candidate, dict) and candidate.get('series') == 'vplayer' and candidate.get('status') in {'applied', 'checkpoint'}:
            applied.append((path, candidate))
    active_path, active = max(applied, key=lambda item: (item[1]['phase'], item[1]['status'] == 'applied'))
    errors = run_current_manifest(active_path, package)
    sources = {p.relative_to(ROOT).as_posix(): p.read_text() for p in (ROOT / 'lib').rglob('*.dart')}
    errors += source_errors(sources)
    unit = parse({SOURCE: sources[SOURCE]}, package, ownership=True)[SOURCE]
    hook = next(n for n in unit['declarations'] if n['name'] == HOOK)
    # The accepted S2 hook plus exactly the three reviewed S2f insertions.
    assert tokens(hook) == apply_patches(checkpoint['scaffolding'][SOURCE][HOOK], S2F_HOOK_PATCHES)
    members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']] for n in hook['members']}
    errors += default_errors(members) + installation_errors(members)
    state = next(n for n in unit['declarations'] if n['name'] == '_VideoPlayerScreenState')
    renderer_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                        for n in state['members'] if n['name'] in {*S2B_SITES, S2C_SITE}}
    candidate_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                         for n in state['members']
                         if n['name'] in S2E_SITES}
    candidate_projection_members = None
    if not candidate_members:
        for name in S2E_SITES:
            resolved = read('_VideoPlayerScreenState.' + name, package)
            assert resolved['path'] == 'lib/features/video_player/presentation/legacy_video_player/vp_startup_candidates.dart'
            moved = parse({'live': resolved['source']}, package, ownership=True)['live']['declarations'][0]
            body = [t['text'] for t in moved['tokens'] if not t['comment']]
            for member, after in [
                ('isAndroid', [HOOK, '.', 'isAndroid']),
                ('androidVideoRendererMode', ['_androidVideoRendererMode']),
                ('rendererValidatedForSession', ['_rendererValidatedForSession']),
                ('rendererFallbackInProgress', ['_rendererFallbackInProgress']),
            ]:
                before = ['_host', '.', member]
                hits = includes(body, before)
                assert len(hits) == 1, (name, member, hits)
                at = hits[0]
                body[at:at + len(before)] = after
            candidate_members[name] = body
        adapter = next(n for n in unit['declarations'] if n['name'] == '_VpStartupCandidatesHostAdapter')
        candidate_projection_members = {
            n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
            for n in adapter['members']}
        errors += candidate_projection_errors(candidate_projection_members)
    errors += candidate_site_errors(candidate_members)
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
    validation_members = {n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                          for n in state['members'] if n['name'] in S2F_PATCHES}
    # P19 relocates S2b _canFallbackExplicitRenderer and both S2f sites. As
    # for S2c/S2e: resolve the LIVE owner through the validating reader,
    # assert its destination, restore only the exact live Host projection
    # (once), then apply the unchanged original-condition proof.
    engine_projection_members = None
    relocated_sites = 0
    for site, path, predicate, members_by_site in [
        ('_canFallbackExplicitRenderer', RENDERER_FALLBACK, 'isAndroid', renderer_members),
        ('_scheduleRendererStartupValidation', RENDERER_FALLBACK, VALIDATION, validation_members),
        ('_installDecoderObservers', DECODER_PROBE, VALIDATION, validation_members),
    ]:
        if site in members_by_site:
            continue
        resolved = read('_VideoPlayerScreenState.' + site, package)
        assert resolved['path'] == path, (site, resolved['path'])
        moved = parse({'live': resolved['source']}, package, ownership=True)['live']['declarations'][0]
        body = [t['text'] for t in moved['tokens'] if not t['comment']]
        before = ['_host', '.', predicate]
        hits = includes(body, before)
        assert len(hits) == 1, (site, hits)
        at = hits[0]
        body[at:at + len(before)] = [HOOK, '.', predicate]
        members_by_site[site] = body
        relocated_sites += 1
    if relocated_sites:
        assert relocated_sites == 3, relocated_sites
        engine_projection_members = {}
        for adapter_name in ['_VpRendererFallbackHostAdapter', '_VpDecoderProbeHostAdapter']:
            adapter = next(n for n in unit['declarations'] if n['name'] == adapter_name)
            engine_projection_members[adapter_name] = {
                n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                for n in adapter['members']}
        errors += engine_projection_errors(engine_projection_members)
    # P20 relocates the S2b `_initializePlayer` site and the two S2 isIOS
    # sites. Same procedure: validating reader, asserted destination, the
    # exact once-only live projection; S2b then restores the original
    # condition for the unchanged site proof. Counted separately (R2).
    p20_relocated_sites = 0
    p20_bodies = {}
    p20_projection_members = None
    for site, path, predicate in P20_SITES:
        if site in {n['name'] for n in state['members']}:
            continue
        resolved = read('_VideoPlayerScreenState.' + site, package)
        assert resolved['path'] == path, (site, resolved['path'])
        moved = parse({'live': resolved['source']}, package, ownership=True)['live']['declarations'][0]
        body = [t['text'] for t in moved['tokens'] if not t['comment']]
        p20_bodies[site] = list(body)
        if site in S2B_SITES:
            hits = includes(body, ['_host', '.', predicate])
            assert len(hits) == 1, (site, hits)
            body[hits[0]:hits[0] + 3] = [HOOK, '.', predicate]
            renderer_members[site] = body
        p20_relocated_sites += 1
    if p20_relocated_sites:
        assert p20_relocated_sites == 3, p20_relocated_sites
        errors += p20_site_errors(p20_bodies)
        p20_projection_members = {}
        for adapter_name in P20_PROJECTIONS:
            adapter = next(n for n in unit['declarations'] if n['name'] == adapter_name)
            p20_projection_members[adapter_name] = {
                n['name']: [t['text'] for t in n['tokens'] if not t['comment']]
                for n in adapter['members']}
        errors += p20_projection_errors(p20_projection_members)
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
    errors += validation_site_errors(validation_members)
    negatives = []
    if self_test:
        import copy
        if candidate_projection_members is not None:
            for name, before, after in [
                ('wrong predicate', [HOOK, '.', 'isAndroid'], [HOOK, '.', 'isIOS']),
                ('override bypassed', [HOOK], ['Platform']),
                ('cached predicate', [HOOK, '.', 'isAndroid'], ['_cachedAndroid']),
                ('predicate twice', [HOOK, '.', 'isAndroid'],
                 [HOOK, '.', 'isAndroid', '&&', HOOK, '.', 'isAndroid']),
            ]:
                mutated = copy.deepcopy(candidate_projection_members)
                body = mutated['isAndroid']
                hits = includes(body, before)
                assert len(hits) == 1
                at = hits[0]
                body[at:at + len(before)] = after
                assert candidate_projection_errors(mutated) == [
                    'S2e live Host projection changed: isAndroid'], name
                negatives.append('S2e projection: ' + name)
            for member in ['androidVideoRendererMode', 'rendererValidatedForSession',
                           'rendererFallbackInProgress']:
                mutated = copy.deepcopy(candidate_projection_members)
                body = mutated[member]
                body[body.index('_s')] = '_cachedState'
                assert candidate_projection_errors(mutated) == [
                    'S2e live Host projection changed: ' + member], member
                negatives.append('S2e projection: cached ' + member)
        for name, getter, old, new in [
            ('wrong iOS default', 'isIOS', 'isIOS', 'isAndroid'),
            ('wrong Android default', 'isAndroid', 'isAndroid', 'isIOS'),
            ('override ignored', 'isIOS', '_installed', 'null'),
            ('default eager', 'isIOS', '??', '|'),
            ('callback twice', 'isIOS', 'call', 'callTwice'),
            ('wrong renderer-validation default', VALIDATION, 'isAndroid', 'isIOS'),
            ('renderer-validation reads android callback', VALIDATION,
             'androidRendererValidation', 'android'),
            ('renderer-validation override ignored', VALIDATION, '_installed', 'null'),
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
        mutated = copy.deepcopy(renderer_members)
        body = mutated['_canFallbackExplicitRenderer']
        at = includes(body, [HOOK, '.', 'isAndroid'])[0]
        body[at + 2] = VALIDATION
        assert renderer_site_errors(mutated), 'S2b accepted the validation predicate'
        negatives.append('S2b _canFallbackExplicitRenderer: wrong hook predicate')
        for site, context in S2F_CONTEXTS.items():
            for name in ['wrong predicate', 'wrong hook predicate', 'override bypassed',
                         'predicate twice', 'operand order', 'TV predicate changed']:
                if site == '_installDecoderObservers' and name == 'TV predicate changed':
                    continue
                mutated = copy.deepcopy(validation_members)
                body = mutated[site]
                start = includes(body, context)[0]
                hook_at = start + context.index(HOOK)
                if name == 'wrong predicate':
                    body[hook_at + 2] = 'isIOS'
                elif name == 'wrong hook predicate':
                    body[hook_at + 2] = 'isAndroid'
                elif name == 'override bypassed':
                    body[hook_at] = 'Platform'
                elif name == 'predicate twice':
                    body[hook_at:hook_at] = [HOOK, '.', VALIDATION, '&&']
                elif name == 'operand order':
                    end = start + len(context)
                    if site == '_installDecoderObservers':
                        # The gate before the NativePlayer check.
                        body[start:end] = [*context[11:], *context[:11]]
                    else:
                        body[start:end] = [*context[:7], *context[13:], *context[7:13]]
                else:
                    body[body.index('isAndroidTvCached', start)] = 'isTelevision'
                assert validation_site_errors(mutated), 'independent S2f guard accepted ' + site + ': ' + name
                negatives.append('S2f ' + site + ': ' + name)
        if engine_projection_members is not None:
            for adapter, predicates in ENGINE_PROJECTIONS.items():
                for predicate in predicates:
                    other = 'isAndroid' if predicate == VALIDATION else VALIDATION
                    for name, before, after in [
                        ('wrong hook predicate', [HOOK, '.', predicate], [HOOK, '.', other]),
                        ('override bypassed', [HOOK], ['Platform']),
                        ('cached predicate', [HOOK, '.', predicate], ['_cachedPredicate']),
                        ('predicate twice', [HOOK, '.', predicate],
                         [HOOK, '.', predicate, '&&', HOOK, '.', predicate]),
                    ]:
                        mutated = copy.deepcopy(engine_projection_members)
                        body = mutated[adapter][predicate]
                        hits = includes(body, before)
                        assert len(hits) == 1, (adapter, predicate, name, hits)
                        at = hits[0]
                        body[at:at + len(before)] = after
                        assert engine_projection_errors(mutated) == [
                            'P19 live Host projection changed: ' + adapter + '.' + predicate], name
                        negatives.append('P19 ' + adapter + '.' + predicate + ': ' + name)
            mutated = copy.deepcopy(engine_projection_members)
            mutated['_VpDecoderProbeHostAdapter']['isAndroid'] = [
                '@', 'override', 'bool', 'get', 'isAndroid', '=>', HOOK, '.', 'isAndroid', ';']
            assert engine_projection_errors(mutated) == [
                'P19 unexpected Host projection: _VpDecoderProbeHostAdapter.isAndroid']
            negatives.append('P19 probe Host gains isAndroid')
        if p20_projection_members is not None:
            for adapter, predicates in P20_PROJECTIONS.items():
                for predicate in predicates:
                    other = 'isIOS' if predicate == 'isAndroid' else 'isAndroid'
                    for name, before, after in [
                        ('wrong hook predicate', [HOOK, '.', predicate], [HOOK, '.', other]),
                        ('override bypassed', [HOOK], ['Platform']),
                        ('cached predicate', [HOOK, '.', predicate], ['_cachedPredicate']),
                        ('predicate twice', [HOOK, '.', predicate],
                         [HOOK, '.', predicate, '&&', HOOK, '.', predicate]),
                    ]:
                        mutated = copy.deepcopy(p20_projection_members)
                        body = mutated[adapter][predicate]
                        hits = includes(body, before)
                        assert len(hits) == 1, (adapter, predicate, name, hits)
                        body[hits[0]:hits[0] + len(before)] = after
                        assert p20_projection_errors(mutated) == [
                            'P20 live Host projection changed: ' + adapter + '.' + predicate], name
                        negatives.append('P20 ' + adapter + '.' + predicate + ': ' + name)
            mutated = copy.deepcopy(p20_projection_members)
            mutated['_VpMediaOpenHostAdapter']['isAndroid'] = [
                '@', 'override', 'bool', 'get', 'isAndroid', '=>', HOOK, '.', 'isAndroid', ';']
            assert p20_projection_errors(mutated) == [
                'P20 unexpected Host projection: _VpMediaOpenHostAdapter.isAndroid']
            negatives.append('P20 media open Host gains isAndroid')
            for site, _, predicate in P20_SITES:
                for name, edit in [
                    ('projection twice', lambda b: b.__setitem__(slice(0, 0), ['_host', '.', predicate])),
                    ('projection removed', lambda b: b.__setitem__(slice(includes(b, ['_host', '.', predicate])[0], includes(b, ['_host', '.', predicate])[0] + 3), ['false'])),
                    ('raw hook', lambda b: b.__setitem__(slice(includes(b, ['_host', '.', predicate])[0], includes(b, ['_host', '.', predicate])[0] + 3), [HOOK, '.', predicate])),
                ]:
                    mutated = copy.deepcopy(p20_bodies)
                    edit(mutated[site])
                    assert p20_site_errors(mutated), 'P20 site guard accepted ' + site + ': ' + name
                    negatives.append('P20 ' + site + ': ' + name)
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
        valid_operand_swaps = {}
        for site in S2E_SITES:
            for name, before, after in [
                ('wrong predicate', [HOOK, '.', 'isAndroid'], [HOOK, '.', 'isIOS']),
                ('override bypassed', [HOOK], ['Platform']),
                ('predicate twice', [HOOK, '.', 'isAndroid'],
                 [HOOK, '.', 'isAndroid', '&&', HOOK, '.', 'isAndroid']),
                ('short-circuit removed', ['error', ')', '&&'], ['error', ')', '&']),
                # Swap complete boolean operands, preserving both calls and &&.
                ('operand order', S2E_CONDITION[2:-1],
                 [*S2E_CONDITION[9:-1], '&&', *S2E_CONDITION[2:8]]),
                ('argument order', ['isAndroid', ':', HOOK, '.', 'isAndroid', ',',
                                    'isAndroidTv', ':', 'PlatformUtil', '.', 'isAndroidTvCached'],
                 ['isAndroidTv', ':', 'PlatformUtil', '.', 'isAndroidTvCached', ',',
                  'isAndroid', ':', HOOK, '.', 'isAndroid']),
                ('TV predicate changed', ['isAndroidTvCached'], ['isTelevision']),
                ('renderer mode changed', ['_androidVideoRendererMode'], ['_cachedMode']),
                ('validation snapshot changed', ['_rendererValidatedForSession'], ['true']),
                ('fallback snapshot changed', ['_rendererFallbackInProgress'], ['false']),
            ]:
                mutated = copy.deepcopy(candidate_members)
                body = mutated[site]
                hits = includes(body, before)
                assert len(hits) == 1, (site, name, hits)
                at = hits[0]
                body[at:at + len(before)] = after
                assert candidate_site_errors(mutated) == [
                    'S2e candidate predicate default/count/order changed: ' + site], name
                if name == 'operand order':
                    from collections import Counter
                    assert Counter(before) == Counter(after), site
                    valid_operand_swaps[site] = 'bool validSwap() => ' + ' '.join(after) + ';'
                negatives.append('S2e ' + site + ': ' + name)
        # The actual two swapped expressions must parse: rejection above is
        # for changed evaluation order, never parser recovery/missing operands.
        assert set(valid_operand_swaps) == set(S2E_SITES)
        parse(valid_operand_swaps, package, ownership=True)
    return errors, dict(patched_declarations=len(patched), counted_patches=sum(len(r['patches']) for r in patched), predicate_occurrences=sum(sum(c.values()) for c in SITES.values()),
                        classified_spans=len(checkpoint['declarations']), active_phase=active['phase'], independent_negatives=negatives,
                        s2_declarations_preserved=len(accepted_patches), s2b_sites=len(S2B_SITES),
                        s2c_sites=1, s2c_classified_spans=len(extension['declarations']),
                        s2c_patched_declarations=1, s2c_predicate_occurrences=1,
                        s2d_sites=len(S2D_PATCHES), s2d_classified_spans=len(recording['declarations']),
                        s2d_patched_declarations=len(recording_patches), s2d_predicate_occurrences=2,
                        s2e_sites=2, s2e_classified_spans=len(candidates['declarations']),
                        s2e_patched_declarations=2, s2e_predicate_occurrences=2,
                        s2e_valid_operand_order_negatives=2 if self_test else 0,
                        s2f_sites=len(S2F_PATCHES), s2f_classified_spans=len(validation['declarations']),
                        s2f_patched_declarations=len(validation_patches), s2f_hook_insertions=len(S2F_HOOK_PATCHES),
                        p19_relocated_sites=relocated_sites, p20_relocated_sites=p20_relocated_sites)


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
