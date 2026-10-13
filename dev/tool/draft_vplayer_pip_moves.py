#!/usr/bin/env python3
"""Materialize the reviewed Phase-8 split in evidence, never in production."""
import argparse
import json
from pathlib import Path
import subprocess

from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_settings_moves import tokens
from check_dart_moves import retained_manifest, check
from dart_move_partition import partition, frozen
from dart_move_history import git_text, check_earlier
from dart_move_fixture import edited_text, materialize

SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
STATE = '_VideoPlayerScreenState'
CONTROLLER = 'VpPipLifecycle'
DEST = FEATURE + '/presentation/legacy_video_player/vp_pip_lifecycle.dart'
NAMES = ['_iosPipStarting', '_iosPipDetached', '_iosPipSession',
         '_lastIosPipPositionSecond', '_backgroundedAt', '_enterPip',
         '_armPipAutoEnter', '_pushPipState', '_onPipModeChanged',
         '_restoreIosPipPlayer', '_onPipAction', '_pauseForBackground',
         '_resumeFromBackground', '_syncWakelock']
HOST = ['_player', '_playerCreated', '_isTransitioning', '_isPipActive',
        '_isPlaying', '_hasAnyNext', '_hideTimer', '_controlsVisible',
        '_setNativeSubtitleVisibilityForTrack', '_togglePlay', '_goToNextEpisode',
        '_cancelPendingIptvCatchup', '_rendererFallbackInProgress',
        '_pausedByLifecycle', '_iptvStartOverActive', '_activeMediaShouldPlay',
        '_activeMediaUserPaused', '_iptvLiveRecovery', '_iptvReconnectText',
        '_currentIptvChannel', '_sleepStopLatched']
CHAINS = [(['VpS2Hooks', '.', name], ['_host', '.', name]) for name in ['isIOS', 'isAndroid']] + [
    ([receiver, '.', name], ['_host', '.', name]) for receiver, name in [
        ('_trakt', 'traktScrobbleSeek'), ('_simkl', 'simklScrobbleSeek'),
        ('_mdblist', 'mdblistScrobbleSeek'), ('_display', 'landscapeLocked')]]
IMPORTS = """import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
"""
FORWARDERS = [
    'bool get mounted => _s.mounted;',
    'BuildContext get context => _s.context;',
    'void setState(VoidCallback fn) => _s._vpSetState(fn);',
    'Object get pipOwner => _s;',
    'bool get isIOS => VpS2Hooks.isIOS;',
    'bool get isAndroid => VpS2Hooks.isAndroid;',
    'mk.Player get player => _s._player;',
    'bool get playerCreated => _s._playerCreated;',
    'bool get isTransitioning => _s._isTransitioning;',
    'bool get isPipActive => _s._isPipActive;',
    'set isPipActive(bool v) => _s._isPipActive = v;',
    'bool get isPlaying => _s._isPlaying;',
    'bool get hasAnyNext => _s._hasAnyNext;',
    'Timer? get hideTimer => _s._hideTimer;',
    'ValueNotifier<bool> get controlsVisible => _s._controlsVisible;',
    'Future<void> setNativeSubtitleVisibilityForTrack(mk.SubtitleTrack track) => _s._setNativeSubtitleVisibilityForTrack(track);',
    'void togglePlay() => _s._togglePlay();',
    'Future<void> goToNextEpisode() => _s._goToNextEpisode();',
    'void cancelPendingIptvCatchup({bool hideFeedback = true}) => _s._cancelPendingIptvCatchup(hideFeedback: hideFeedback);',
    'bool get rendererFallbackInProgress => _s._rendererFallbackInProgress;',
    'bool get pausedByLifecycle => _s._pausedByLifecycle;',
    'set pausedByLifecycle(bool v) => _s._pausedByLifecycle = v;',
    'bool get iptvStartOverActive => _s._iptvStartOverActive;',
    'bool get activeMediaShouldPlay => _s._activeMediaShouldPlay;',
    'bool get activeMediaUserPaused => _s._activeMediaUserPaused;',
    'IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;',
    'ValueNotifier<String?> get iptvReconnectText => _s._iptvReconnectText;',
    'IptvChannel? get currentIptvChannel => _s._currentIptvChannel;',
    'bool get sleepStopLatched => _s._sleepStopLatched;',
    'void traktScrobbleSeek(Duration position) => _s._trakt.traktScrobbleSeek(position);',
    'void simklScrobbleSeek(Duration position) => _s._simkl.simklScrobbleSeek(position);',
    'void mdblistScrobbleSeek(Duration position) => _s._mdblist.mdblistScrobbleSeek(position);',
    'bool get landscapeLocked => _s._display.landscapeLocked;',
]
INTERFACE = 'abstract interface class VpPipLifecycleHost {\n' + ''.join(
    '  ' + line.split(' => ')[0] + ';\n' for line in FORWARDERS) + '}\n'
ADAPTER = 'class _VpPipLifecycleHostAdapter implements VpPipLifecycleHost {\n  _VpPipLifecycleHostAdapter(this._s);\n  final _VideoPlayerScreenState _s;\n' + ''.join(
    '  @override\n  ' + line + '\n' for line in FORWARDERS) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=8, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:5]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:5]},
        receiver_owners={'_pip': CONTROLLER, 'this': CONTROLLER}, receiver_paths={'_pip': CONTROLLER, 'this': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        host_owner_identity=['_host.pipOwner'],
        receivers=['_host', '_pip'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST},
        registered_occurrence_substitutions=[dict(before=before, after=after, binding='unbound',
            role_change='State collaborator or platform chain to live Host projection') for before, after in CHAINS])
    measured = []
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_pip', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'context', 'setState']})
            mapping['this'] = ['_host', '.', 'pipOwner']
            if key == STATE + '._resumeFromBackground':
                mapping['_backgroundedAt'] = ['this', '.', 'backgroundedAt']
                row['owned_this_fields'] = {'_backgroundedAt': 2}
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            assert not any(values[i:i+2] == ['$', name] for i in range(len(values)-1)), (key, name)
            count = values.count(name)
            if count: edits.append(dict(before=[name], after=after, count=count))
        if moved:
            for before, after in CHAINS:
                count = sum(values[i:i+len(before)] == before for i in range(len(values)-len(before)+1))
                if count: edits.append(dict(before=before, after=after, count=count))
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == STATE + '.' + STATE:
            row.update(fate='patched', reason='Append the eager inert PiP assignment after local completion.',
                       test='dev/tool/test_dart_pip_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_pip', '=', CONTROLLER, '(', '_VpPipLifecycleHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_pip_lifecycle.dart';",
        STATE + '._pip': 'late final VpPipLifecycle _pip;',
        '_VpPipLifecycleHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._pip':
            index = next(i for i,k in enumerate(spec['span_order']) if k in spans and spans[k]['start'] > spans[STATE + '.' + NAMES[0]]['start'])
        else: index = spec['span_order'].index(STATE + ':close') + 1
        spec['span_order'].insert(index, key)
    bykey = {r['original']: r for r in spec['declarations']}
    facade = ''.join(scaffolds[k] + '\n' if k in scaffolds else edited_text(original, spans[k],
                     bykey[k].get('substitutions', []) + bykey[k].get('patches', [])) for k in spec['span_order'])
    parsed = parse({SOURCE: facade}, package, ownership=True)[SOURCE]
    physical, orders, _ = partition(parsed, [STATE])
    spec['facade_orders'], spec['facade_directives'] = orders, parsed['directives']
    spec['scaffolding'][SOURCE] = frozen({k: physical[k] for k in scaffolds})
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpPipLifecycleHost _host;\n'
    for row in spec['declarations']:
        if row['fate'] == 'moved': dest += edited_text(original, spans[row['original']], row.get('substitutions', []))
    dest += '\n}\n'
    unit = parse({DEST: dest}, package, ownership=True)[DEST]
    physical, orders, _ = partition(unit, [CONTROLLER])
    targets = {r['target'] for r in spec['declarations'] if r['fate'] == 'moved'}
    spec['destinations'][DEST] = dict(directives=unit['directives'], orders=orders, span_order=list(physical), split_containers=[CONTROLLER])
    spec['scaffolding'][DEST] = frozen({k:v for k,v in physical.items() if k not in targets})
    return original, spec, measured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='21b19c944')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p8'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P8 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p8.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(content)
    print('PASS: complete Phase-8 virtual split, exhaustive ownership + P1–P7 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
