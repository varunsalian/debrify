#!/usr/bin/env python3
"""Materialize the reviewed Phase-10 split in evidence, never in production."""
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
CONTROLLER = 'VpSubtitleApply'
DEST = FEATURE + '/presentation/legacy_video_player/vp_subtitle_apply.dart'
NAMES = ['_waitForSubtitleTracks', '_setNativeSubtitleVisibilityForTrack',
         '_setSubtitleTrackWithDiagnostics', '_handleSubtitleApplyFailure',
         '_showSubtitleFailureMessage']
HOST = ['_player', '_addonSubtitleFetchToken', '_isPipActive',
        '_androidVideoRendererMode', '_selectedStremioSubtitleId',
        '_activeExternalSubtitlePath', '_subtitleSelectionCorrection', '_playerMenuKey',
        '_persistTrackChoice', '_subtitleDiagnosticGeneration', '_activeSubtitleApplyAttempt']
CHAINS = [(['VpS2Hooks', '.', 'isIOS'], ['_host', '.', 'isIOS']),
          (['VpS2Hooks', '.', 'isAndroid'], ['_host', '.', 'isAndroid']),
          (['_pip', '.', 'iosPipStarting'], ['_host', '.', 'iosPipStarting']),
          (['_subtitleSync', '.', 'setActiveExternalSubtitlePath'], ['_host', '.', 'setActiveExternalSubtitlePath'])]
IMPORTS = """import 'package:debrify/features/video_player/application/vp_subtitle_identity.dart';
import 'package:debrify/features/video_player/models/vp_subtitle_apply_attempt.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
"""
FORWARDERS = [
    'bool get mounted => _s.mounted;',
    'BuildContext get context => _s.context;',
    'void setState(VoidCallback fn) => _s._vpSetState(fn);',
    'mk.Player get player => _s._player;',
    'int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;',
    'bool get isIOS => VpS2Hooks.isIOS;',
    'bool get isAndroid => VpS2Hooks.isAndroid;',
    'bool get isPipActive => _s._isPipActive;',
    'bool get iosPipStarting => _s._pip.iosPipStarting;',
    'AndroidVideoRendererMode get androidVideoRendererMode => _s._androidVideoRendererMode;',
    'String? get selectedStremioSubtitleId => _s._selectedStremioSubtitleId;',
    'set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;',
    'String? get activeExternalSubtitlePath => _s._activeExternalSubtitlePath;',
    'ValueNotifier<String?> get subtitleSelectionCorrection => _s._subtitleSelectionCorrection;',
    'GlobalKey<PlayerMenuPanelState> get playerMenuKey => _s._playerMenuKey;',
    'void setActiveExternalSubtitlePath(String? path) => _s._subtitleSync.setActiveExternalSubtitlePath(path);',
    'Future<void> persistTrackChoice(String audio, String subtitle) => _s._persistTrackChoice(audio, subtitle);',
    'int get subtitleDiagnosticGeneration => _s._subtitleDiagnosticGeneration;',
    'set subtitleDiagnosticGeneration(int v) => _s._subtitleDiagnosticGeneration = v;',
    'VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt => _s._activeSubtitleApplyAttempt;',
    'set activeSubtitleApplyAttempt(VpSubtitleApplyAttempt? v) => _s._activeSubtitleApplyAttempt = v;',
]
INTERFACE = 'abstract interface class VpSubtitleApplyHost {\n' + ''.join(
    '  ' + line.split(' => ')[0] + ';\n' for line in FORWARDERS) + '}\n'
ADAPTER = 'class _VpSubtitleApplyHostAdapter implements VpSubtitleApplyHost {\n  _VpSubtitleApplyHostAdapter(this._s);\n  final _VideoPlayerScreenState _s;\n' + ''.join(
    '  @override\n  ' + line + '\n' for line in FORWARDERS) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=10, status='draft', span_order=list(spans),
                patched_class_projection=['_VpPipLifecycleHostAdapter'])
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={}),
        record_owners=[STATE], record_fields={STATE: []},
        receiver_owners={'_subtitleApply': CONTROLLER}, receiver_paths={'_subtitleApply': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_subtitleApply'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST},
        registered_occurrence_substitutions=[dict(before=before, after=after, binding='unbound',
            role_change='State collaborator or platform chain to live Host projection') for before,after in CHAINS])
    measured = []
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_subtitleApply', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'context', 'setState']})
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            interpolation = sum(values[i:i+2] == ['$', name] for i in range(len(values)-1))
            assert not interpolation, (key, name)
            count = values.count(name)
            if count: edits.append(dict(before=[name], after=after, count=count))
        if moved:
            for before, after in CHAINS:
                count = sum(values[i:i+len(before)] == before for i in range(len(values)))
                if count: edits.append(dict(before=before, after=after, count=count))
        if key == '_VpPipLifecycleHostAdapter':
            assert len(edits) == 1 and edits[0]['count'] == 1
            row.update(fate='patched', reason='Redirect the retained PiP visibility forwarder to the apply bridge.',
                       test='dev/tool/test_dart_subtitle_apply_moves.py', patches=edits)
        elif edits:
            row['substitutions'] = edits
        if edits:
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == STATE + '.' + STATE:
            row.update(fate='patched', reason='Append the eager inert subtitle apply assignment after subtitleSync.',
                       test='dev/tool/test_dart_subtitle_apply_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_subtitleApply', '=', CONTROLLER, '(', '_VpSubtitleApplyHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_subtitle_apply.dart';",
        STATE + '._subtitleApply': 'late final VpSubtitleApply _subtitleApply;',
        '_VpSubtitleApplyHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._subtitleApply':
            index = spec['span_order'].index(STATE + '._subtitleSync') + 1
        else: index = spec['span_order'].index(STATE + ':close') + 1
        spec['span_order'].insert(index, key)
    bykey = {r['original']: r for r in spec['declarations']}
    facade = ''.join(scaffolds[k] + '\n' if k in scaffolds else edited_text(original, spans[k],
                     bykey[k].get('substitutions', []) + bykey[k].get('patches', [])) for k in spec['span_order'])
    parsed = parse({SOURCE: facade}, package, ownership=True)[SOURCE]
    physical, orders, _ = partition(parsed, [STATE])
    spec['facade_orders'], spec['facade_directives'] = orders, parsed['directives']
    spec['scaffolding'][SOURCE] = frozen({k: physical[k] for k in scaffolds})
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpSubtitleApplyHost _host;\n'
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
    parser.add_argument('--base', default='a2e034cb3')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p10'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P10 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p10.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(content)
    print('PASS: complete Phase-10 virtual split, exhaustive ownership + P1–P9 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
