#!/usr/bin/env python3
"""Materialize the reviewed Phase-9 split in evidence, never in production."""
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
CONTROLLER = 'VpSubtitleAutoSync'
DEST = FEATURE + '/presentation/legacy_video_player/vp_subtitle_auto_sync.dart'
NAMES = ['_subtitleAutoSyncEnabled', '_subtitleAutoSync', '_autoSyncWindowActive',
         '_autoSyncPillHold', '_autoSyncPillPhaseTimer',
         '_installSubtitleAutoSyncForPlayer', '_disposeSubtitleAutoSync',
         '_applyAutoSubtitleSyncOffset', '_showSubtitleAutoSyncNotice',
         '_openAutoSyncPillWindow', '_showAutoSyncPillResult', '_hideAutoSyncPill',
         '_setActiveExternalSubtitlePath', '_loadSubtitleSettings',
         '_onSubtitleStyleChanged', '_applySubtitleSyncOffset', '_resetSubtitleSyncOffset',
         '_showSyncOverlayPanel', '_hideSyncOverlay', '_buildSyncOverlay', '_buildSliderSyncOverlay']
HOST = ['_player', '_position', '_isPlaying', '_audioPassthroughEnabled',
        '_subtitleSettings', '_activeExternalSubtitlePath', '_autoSyncPill',
        '_controlsVisible', '_showSyncOverlay', '_tvReleaseFocusForOverlay']
IMPORTS = """import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
"""
FORWARDERS = [
    'bool get mounted => _s.mounted;',
    'void setState(VoidCallback fn) => _s._vpSetState(fn);',
    'mk.Player get player => _s._player;',
    'Duration get position => _s._position;',
    'bool get isPlaying => _s._isPlaying;',
    'bool get audioPassthroughEnabled => _s._audioPassthroughEnabled;',
    'SubtitleSettingsData? get subtitleSettings => _s._subtitleSettings;',
    'set subtitleSettings(SubtitleSettingsData? v) => _s._subtitleSettings = v;',
    'String? get activeExternalSubtitlePath => _s._activeExternalSubtitlePath;',
    'set activeExternalSubtitlePath(String? v) => _s._activeExternalSubtitlePath = v;',
    'ValueNotifier<AutoSyncPillModel?> get autoSyncPill => _s._autoSyncPill;',
    'ValueNotifier<bool> get controlsVisible => _s._controlsVisible;',
    'set showSyncOverlay(bool v) => _s._showSyncOverlay = v;',
    'void tvReleaseFocusForOverlay() => _s._tvReleaseFocusForOverlay();',
]
INTERFACE = 'abstract interface class VpSubtitleAutoSyncHost {\n' + ''.join(
    '  ' + line.split(' => ')[0] + ';\n' for line in FORWARDERS) + '}\n'
ADAPTER = 'class _VpSubtitleAutoSyncHostAdapter implements VpSubtitleAutoSyncHost {\n  _VpSubtitleAutoSyncHostAdapter(this._s);\n  final _VideoPlayerScreenState _s;\n' + ''.join(
    '  @override\n  ' + line + '\n' for line in FORWARDERS) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=9, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:5]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:5]},
        receiver_owners={'_subtitleSync': CONTROLLER}, receiver_paths={'_subtitleSync': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_subtitleSync'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST})
    measured = []
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_subtitleSync', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'setState']})
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            interpolation = sum(values[i:i+2] == ['$', name] for i in range(len(values)-1))
            if interpolation and len(after) > 1:
                bare_count = values.count(name) - interpolation
                if bare_count:
                    # The only mixed retained occurrence assigns the enable flag.
                    assert key == STATE + '._loadPlayerDefaults' and name == '_subtitleAutoSyncEnabled' and bare_count == 1
                    edits.append(dict(before=[name, '='], after=[*after, '='], count=1))
                edits.append(dict(before=['$', name], after=['${', *after, '}'], count=interpolation))
            else:
                count = values.count(name)
                if count: edits.append(dict(before=[name], after=after, count=count))
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == STATE + '.' + STATE:
            row.update(fate='patched', reason='Append the eager inert subtitle auto-sync assignment after PiP.',
                       test='dev/tool/test_dart_subtitle_sync_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_subtitleSync', '=', CONTROLLER, '(', '_VpSubtitleAutoSyncHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_subtitle_auto_sync.dart';",
        STATE + '._subtitleSync': 'late final VpSubtitleAutoSync _subtitleSync;',
        '_VpSubtitleAutoSyncHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._subtitleSync':
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
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpSubtitleAutoSyncHost _host;\n'
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
    parser.add_argument('--base', default='bd671bd09')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p9'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P9 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p9.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(content)
    print('PASS: complete Phase-9 virtual split, exhaustive ownership + P1–P8 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
