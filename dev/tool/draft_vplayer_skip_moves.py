#!/usr/bin/env python3
"""Materialize the reviewed Phase-3 split in evidence, never in production."""
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
CONTROLLER = 'VpSkipSegmentController'
DEST = FEATURE + '/presentation/legacy_video_player/vp_skip_segment_controller.dart'
NAMES = ['_skipSegmentSettingsLoaded', '_skipSegmentsEnabled', '_skipSegmentProviderId',
         '_skipSegmentProvider', '_skipSegments', '_loadedSkipSegmentsKey',
         '_loadingSkipSegmentsKey', '_skipSegmentsFetchGeneration', '_skipSegmentsCache',
         '_skipSegmentsMediaReady', '_loadSkipSegmentSettings', '_currentSkipSegmentRequest',
         '_syncSkipSegmentsForCurrentContent', '_resetSkipSegmentState',
         '_activeSkipSegment', '_syncActiveSkipSegmentUi', '_skipActiveSegment']
HOST = ['_effectiveContentImdbId', '_effectiveContentType', '_effectiveContentSeason',
        '_effectiveContentEpisode', '_isTransitioning', '_duration', '_position',
        '_seriesPlaylist', '_findSeriesEpisodeForCurrentIndex', '_traktSeasonEpisode',
        '_playerCreated', '_playbackUiClock', '_player', '_activeSkipSegmentUi',
        '_traktScrobbleSeek', '_simklScrobbleSeek', '_mdblistScrobbleSeek']
IMPORTS = """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';
"""
INTERFACE = """abstract interface class VpSkipSegmentHost {
  bool get mounted;
  void setState(VoidCallback fn);
  String? get effectiveContentImdbId;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
  bool get isTransitioning;
  Duration get duration;
  Duration get position;
  set position(Duration v);
  SeriesPlaylist? get seriesPlaylist;
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist sp);
  ({int? season, int? episode}) traktSeasonEpisode();
  bool get playerCreated;
  PlaybackUiClockController get playbackUiClock;
  mk.Player get player;
  SkipSegmentUiController get activeSkipSegmentUi;
  void traktScrobbleSeek(Duration target);
  void simklScrobbleSeek(Duration target);
  void mdblistScrobbleSeek(Duration target);
}
"""
ADAPTER = """class _VpSkipSegmentHostAdapter implements VpSkipSegmentHost {
  _VpSkipSegmentHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
""" + ''.join('  @override\n  ' + line + '\n' for line in [
    'bool get mounted => _s.mounted;',
    'void setState(VoidCallback fn) => _s._vpSetState(fn);',
    'String? get effectiveContentImdbId => _s._effectiveContentImdbId;',
    'String? get effectiveContentType => _s._effectiveContentType;',
    'int? get effectiveContentSeason => _s._effectiveContentSeason;',
    'int? get effectiveContentEpisode => _s._effectiveContentEpisode;',
    'bool get isTransitioning => _s._isTransitioning;',
    'Duration get duration => _s._duration;',
    'Duration get position => _s._position;',
    'set position(Duration v) => _s._position = v;',
    'SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;',
    'SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist sp) => _s._findSeriesEpisodeForCurrentIndex(sp);',
    '({int? season, int? episode}) traktSeasonEpisode() => _s._traktSeasonEpisode();',
    'bool get playerCreated => _s._playerCreated;',
    'PlaybackUiClockController get playbackUiClock => _s._playbackUiClock;',
    'mk.Player get player => _s._player;',
    'SkipSegmentUiController get activeSkipSegmentUi => _s._activeSkipSegmentUi;',
    'void traktScrobbleSeek(Duration target) => _s._traktScrobbleSeek(target);',
    'void simklScrobbleSeek(Duration target) => _s._simklScrobbleSeek(target);',
    'void mdblistScrobbleSeek(Duration target) => _s._mdblistScrobbleSeek(target);',
]) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=3, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:10]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:10]},
        receiver_owners={'_skip': CONTROLLER}, receiver_paths={'_skip': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_skip'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST})
    measured = []
    constructor = STATE + '.' + STATE
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_skip', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted', 'setState']})
        values = tokens(spans[key])
        edits = [dict(before=[n], after=after, count=values.count(n)) for n, after in mapping.items() if n in values]
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == constructor:
            row.update(fate='patched', reason='Append eager inert skip collaborator assignment after the existing sleep assignment.',
                       test='dev/tool/test_dart_skip_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_skip', '=', CONTROLLER, '(', '_VpSkipSegmentHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_skip_segment_controller.dart';",
        STATE + '._skip': 'late final VpSkipSegmentController _skip;',
        '_VpSkipSegmentHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._skip':
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
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpSkipSegmentHost _host;\n'
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
    parser.add_argument('--base', default='fc24e32ae')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p3'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P3 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p3.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    print('PASS: complete Phase-3 virtual split, exhaustive ownership + P1/P2 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
