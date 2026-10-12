#!/usr/bin/env python3
"""Materialize the reviewed Phase-4 split in evidence, never in production."""
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
CONTROLLER = 'VpDisplayModeController'
DEST = FEATURE + '/presentation/legacy_video_player/vp_display_mode_controller.dart'
NAMES = ['_aspectMode', '_playbackSpeed', '_speedBeforeHold', '_landscapeLocked',
         '_applyAspectVideoZoom', '_cycleAspectMode', '_changeSpeed', '_onSpeedButton',
         '_onAspectButton', '_setPlaybackSpeed', '_setAspectModeDirect',
         '_onLongPressStart', '_onLongPressEnd', '_toggleOrientation', '_currentFit',
         '_getCustomAspectRatio']
HOST = ['_player', '_scheduleAutoHide', '_saveResume', '_openPlayerMenuQuick',
        '_aspectRatioHud', '_speedHoldHud', '_isPlaying', '_controlsVisible', '_dockBand']
IMPORTS = """import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
"""
INTERFACE = """abstract interface class VpDisplayModeHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  mk.Player get player;
  void scheduleAutoHide();
  Future<void> saveResume();
  void openPlayerMenuQuick(PlayerMenuSection section);
  ValueNotifier<AspectRatioHudState?> get aspectRatioHud;
  ValueNotifier<bool> get speedHoldHud;
  bool get isPlaying;
  ValueNotifier<bool> get controlsVisible;
  double dockBand(double legacy);
  bool get hideBackButton;
  bool get hideOptions;
}
"""
ADAPTER = """class _VpDisplayModeHostAdapter implements VpDisplayModeHost {
  _VpDisplayModeHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
""" + ''.join('  @override\n  ' + line + '\n' for line in [
    'bool get mounted => _s.mounted;',
    'BuildContext get context => _s.context;',
    'void setState(VoidCallback fn) => _s._vpSetState(fn);',
    'mk.Player get player => _s._player;',
    'void scheduleAutoHide() => _s._scheduleAutoHide();',
    'Future<void> saveResume() => _s._saveResume();',
    'void openPlayerMenuQuick(PlayerMenuSection section) => _s._openPlayerMenuQuick(section);',
    'ValueNotifier<AspectRatioHudState?> get aspectRatioHud => _s._aspectRatioHud;',
    'ValueNotifier<bool> get speedHoldHud => _s._speedHoldHud;',
    'bool get isPlaying => _s._isPlaying;',
    'ValueNotifier<bool> get controlsVisible => _s._controlsVisible;',
    'double dockBand(double legacy) => _s._dockBand(legacy);',
    'bool get hideBackButton => _s.widget.hideBackButton;',
    'bool get hideOptions => _s.widget.hideOptions;',
]) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=4, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:4]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:4]},
        receiver_owners={'_display': CONTROLLER}, receiver_paths={'_display': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_display'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST},
        registered_occurrence_substitutions=[dict(before=['widget', '.', name],
            after=['_host', '.', name], binding='unbound', role_change='widget selector read to live Host selector read')
            for name in ['hideBackButton', 'hideOptions']])
    measured = []
    constructor = STATE + '.' + STATE
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_display', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'context', 'setState']})
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            interpolation = sum(values[i:i+2] == ['$', name] for i in range(len(values)-1))
            bare_count = values.count(name) - interpolation
            if bare_count:
                if interpolation:
                    # A bare-name edit would overlap the explicit interpolation.
                    # The sole mixed case is the retained defaults assignment.
                    assert key == STATE + '._loadPlayerDefaults' and name == '_aspectMode' and bare_count == 1
                    edits.append(dict(before=[name, '='], after=[*after, '='], count=1))
                else:
                    edits.append(dict(before=[name], after=after, count=bare_count))
            if interpolation:
                edits.append(dict(before=['$', name], after=['${', *after, '}'], count=interpolation))
        if moved and key.endswith('._onLongPressStart'):
            edits += [dict(before=['widget', '.', name], after=['_host', '.', name], count=1)
                      for name in ['hideBackButton', 'hideOptions']]
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == constructor:
            row.update(fate='patched', reason='Append eager inert display collaborator assignment after the existing sleep and skip assignments.',
                       test='dev/tool/test_dart_display_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_display', '=', CONTROLLER, '(', '_VpDisplayModeHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_display_mode_controller.dart';",
        STATE + '._display': 'late final VpDisplayModeController _display;',
        '_VpDisplayModeHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._display':
            index = next(i for i,k in enumerate(spec['span_order']) if k in spans and spans[k]['start'] > spans[STATE + '.' + NAMES[0]]['start'])
        else:
            index = spec['span_order'].index(STATE + ':close') + 1
        spec['span_order'].insert(index, key)
    bykey = {r['original']: r for r in spec['declarations']}
    facade = ''.join(scaffolds[k] + '\n' if k in scaffolds else edited_text(original, spans[k],
                     bykey[k].get('substitutions', []) + bykey[k].get('patches', [])) for k in spec['span_order'])
    parsed = parse({SOURCE: facade}, package, ownership=True)[SOURCE]
    physical, orders, _ = partition(parsed, [STATE])
    spec['facade_orders'], spec['facade_directives'] = orders, parsed['directives']
    spec['scaffolding'][SOURCE] = frozen({k: physical[k] for k in scaffolds})
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpDisplayModeHost _host;\n'
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
    parser.add_argument('--base', default='890df14d8')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p4'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P4 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p4.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    print('PASS: complete Phase-4 virtual split, exhaustive ownership + P1/P2/P3 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
