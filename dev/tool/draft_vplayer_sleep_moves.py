#!/usr/bin/env python3
"""Materialize the reviewed Phase-2 split in evidence, never in production."""
import argparse
import json
from pathlib import Path
import subprocess
from check_verbatim_moves import ROOT, parse, ensure_parser_package
from check_settings_moves import tokens
from check_dart_moves import retained_manifest, check
from dart_move_partition import partition, frozen
from dart_move_history import git_text, check_earlier
from dart_move_fixture import edited_text, render, materialize

SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
STATE = '_VideoPlayerScreenState'
CONTROLLER = 'VpSleepTimerController'
DEST = FEATURE + '/presentation/legacy_video_player/vp_sleep_timer_controller.dart'
NAMES = ['_sleepTimerMode', '_sleepTimerDeadline', '_sleepTimerArmedMinutes', '_sleepTimer',
         '_sleepTimerMinutesLeft', '_sleepTimerButtonLabel', '_showSleepTimerSheet',
         '_applySleepTimerSelection', '_startSleepCountdown', '_cancelSleepTimer',
         '_fireSleepTimer', '_showSleepTimerToast']
HOST = ['_openPlayerMenuQuick', '_hideTimer', '_currentIptvChannel', '_scheduleAutoHide',
        '_sleepStopLatched', '_activeMediaShouldPlay', '_playerCreated', '_saveResume', '_player']
IMPORTS = """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
"""
INTERFACE = """abstract interface class VpSleepTimerHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  void openPlayerMenuQuick(PlayerMenuSection section);
  Timer? get hideTimer;
  IptvChannel? get currentIptvChannel;
  void scheduleAutoHide();
  set sleepStopLatched(bool v);
  set activeMediaShouldPlay(bool v);
  bool get playerCreated;
  Future<void> saveResume();
  mk.Player get player;
}
"""
ADAPTER = """class _VpSleepTimerHostAdapter implements VpSleepTimerHost {
  _VpSleepTimerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  void openPlayerMenuQuick(PlayerMenuSection section) => _s._openPlayerMenuQuick(section);
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  void scheduleAutoHide() => _s._scheduleAutoHide();
  @override
  set sleepStopLatched(bool v) => _s._sleepStopLatched = v;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  bool get playerCreated => _s._playerCreated;
  @override
  Future<void> saveResume() => _s._saveResume();
  @override
  mk.Player get player => _s._player;
}
"""


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=2, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:4]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:4]},
        receiver_owners={'_sleep': CONTROLLER},
        receiver_paths={'_sleep': CONTROLLER}, receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_sleep'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST})
    measured = []
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_sleep', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'context', 'setState']})
        values = tokens(spans[key])
        edits = [dict(before=[n], after=after, count=values.count(n)) for n, after in mapping.items() if n in values]
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1, declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffold_texts = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_sleep_timer_controller.dart';",
        STATE + '._sleep': 'late final VpSleepTimerController _sleep;',
        STATE + '.' + STATE: STATE + '() { _sleep = VpSleepTimerController(_VpSleepTimerHostAdapter(this)); }',
        STATE + '._vpSetState': 'void _vpSetState(VoidCallback fn) => setState(fn);',
        '_VpSleepTimerHostAdapter': ADAPTER,
    }
    for key in scaffold_texts:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._sleep':
            index = next(i for i,k in enumerate(spec['span_order']) if k in spans and spans[k]['start'] > spans[STATE + '._sleepTimerMode']['start'])
        elif key == '_VpSleepTimerHostAdapter':
            index = spec['span_order'].index(STATE + ':close') + 1
        else:
            index = spec['span_order'].index(STATE + ':header') + 1
            if key.endswith('._vpSetState'): index += 1
        spec['span_order'].insert(index, key)
    bykey = {r['original']: r for r in spec['declarations']}
    facade = ''.join(scaffold_texts[k] + '\n' if k in scaffold_texts else
                     edited_text(original, spans[k], bykey[k].get('substitutions', [])) for k in spec['span_order'])
    parsed = parse({SOURCE: facade}, package, ownership=True)[SOURCE]
    phys, orders, _ = partition(parsed, [STATE])
    spec['facade_orders'] = orders
    spec['facade_directives'] = parsed['directives']
    spec['scaffolding'][SOURCE] = frozen({k: phys[k] for k in scaffold_texts})
    dest = IMPORTS + INTERFACE + '\nclass VpSleepTimerController {\n  VpSleepTimerController(this._host);\n  final VpSleepTimerHost _host;\n'
    for row in spec['declarations']:
        if row['fate'] == 'moved': dest += edited_text(original, spans[row['original']], row.get('substitutions', []))
    dest += '\n}\n'
    unit = parse({DEST: dest}, package, ownership=True)[DEST]
    physical, orders, _ = partition(unit, [CONTROLLER])
    moved_targets = {r['target'] for r in spec['declarations'] if r['fate'] == 'moved'}
    spec['destinations'][DEST] = dict(directives=unit['directives'], orders=orders, span_order=list(physical), split_containers=[CONTROLLER])
    spec['scaffolding'][DEST] = frozen({k:v for k,v in physical.items() if k not in moved_targets})
    return original, spec, measured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='31a347ad2')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p2'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P2 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p2.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    print('PASS: complete Phase-2 virtual split, exhaustive ownership + P1 destinations; app untouched')
    return 0

if __name__ == '__main__': raise SystemExit(main())
