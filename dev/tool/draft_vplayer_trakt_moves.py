#!/usr/bin/env python3
"""Materialize the reviewed Phase-5 split in evidence, never in production."""
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
CONTROLLER = 'VpTraktScrobbler'
DEST = FEATURE + '/presentation/legacy_video_player/vp_trakt_scrobbler.dart'
NAMES = ['_traktScrobbleEnabled', '_launchTraktPercentSpent', '_traktEpisodeProgress',
         '_traktLastScrobbleAction', '_traktHeartbeatTimer', '_initTraktScrobble',
         '_traktProgress', '_traktScrobble', '_startTraktHeartbeat', '_stopTraktHeartbeat',
         '_traktScrobbleSeek', '_currentEpisodeTraktPercent']
HOST = ['_validationGateActive', '_isPlaying', '_duration', '_effectiveContentImdbId',
        '_currentSeriesImdbId', '_episodeTrackerProgressImdbId', '_traktSeasonEpisode',
        '_bindEpisodeTrackerProgressIdentity', '_persistablePosition', '_resumeWriteGuard',
        '_stremioTvStartupSeek', '_seriesPlaylist', '_activePlaylist', '_currentIndex',
        '_effectiveContentType', '_effectiveContentSeason', '_effectiveContentEpisode']
WIDGET = ['traktScrobble', 'contentImdbId', 'contentType']
IMPORTS = """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
"""
FORWARDERS = [
    'bool get mounted => _s.mounted;',
    'bool get validationGateActive => _s._validationGateActive;',
    'bool get isPlaying => _s._isPlaying;',
    'Duration get duration => _s._duration;',
    'String? get effectiveContentImdbId => _s._effectiveContentImdbId;',
    'String? get contentImdbId => _s.widget.contentImdbId;',
    'String? get contentType => _s.widget.contentType;',
    'String? get currentSeriesImdbId => _s._currentSeriesImdbId;',
    'String? get episodeTrackerProgressImdbId => _s._episodeTrackerProgressImdbId;',
    '({int? season, int? episode}) traktSeasonEpisode() => _s._traktSeasonEpisode();',
    'void bindEpisodeTrackerProgressIdentity(String imdbId) => _s._bindEpisodeTrackerProgressIdentity(imdbId);',
    'bool get traktScrobble => _s.widget.traktScrobble;',
    'Duration get persistablePosition => _s._persistablePosition;',
    'ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;',
    'DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;',
    'SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;',
    'List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;',
    'int get currentIndex => _s._currentIndex;',
    'String? get effectiveContentType => _s._effectiveContentType;',
    'int? get effectiveContentSeason => _s._effectiveContentSeason;',
    'int? get effectiveContentEpisode => _s._effectiveContentEpisode;',
]
INTERFACE = 'abstract interface class VpTraktScrobblerHost {\n' + ''.join(
    '  ' + line.split(' => ')[0] + ';\n' for line in FORWARDERS) + '}\n'
ADAPTER = 'class _VpTraktScrobblerHostAdapter implements VpTraktScrobblerHost {\n  _VpTraktScrobblerHostAdapter(this._s);\n  final _VideoPlayerScreenState _s;\n' + ''.join(
    '  @override\n  ' + line + '\n' for line in FORWARDERS) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=5, status='draft', span_order=list(spans),
                patched_class_projection=['_VpSkipSegmentHostAdapter'])
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:5]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:5]},
        receiver_owners={'_trakt': CONTROLLER}, receiver_paths={'_trakt': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_trakt'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST},
        registered_occurrence_substitutions=[dict(before=['widget', '.', name],
            after=['_host', '.', name], binding='unbound', role_change='widget selector read to live Host selector read')
            for name in WIDGET])
    measured = []
    constructor = STATE + '.' + STATE
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_trakt', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping.update({n: ['_host', '.', n] for n in ['mounted']})
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
        if moved:
            edits += [dict(before=['widget', '.', name], after=['_host', '.', name],
                           count=sum(values[i:i+3] == ['widget', '.', name]
                                     for i in range(len(values)-2)))
                      for name in WIDGET if any(values[i:i+3] == ['widget', '.', name]
                                               for i in range(len(values)-2))]
        if key == '_VpSkipSegmentHostAdapter':
            assert edits == [dict(before=['_traktScrobbleSeek'], after=['_trakt', '.', 'traktScrobbleSeek'], count=1)]
            row.update(fate='patched', reason='Redirect the skip Host Trakt seek forwarder to the P5 collaborator; retain all borrowed seek guards and earlier controller bodies.',
                       test='dev/tool/test_dart_trakt_moves.py', patches=edits)
            edits = []
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == constructor:
            row.update(fate='patched', reason='Append eager inert Trakt collaborator assignment after the existing sleep, skip and display assignments.',
                       test='dev/tool/test_dart_trakt_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_trakt', '=', CONTROLLER, '(', '_VpTraktScrobblerHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_trakt_scrobbler.dart';",
        STATE + '._trakt': 'late final VpTraktScrobbler _trakt;',
        '_VpTraktScrobblerHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._trakt':
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
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpTraktScrobblerHost _host;\n'
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
    parser.add_argument('--base', default='315028407')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p5'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P5 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p5.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    print('PASS: complete Phase-5 virtual split, exhaustive ownership + P1/P2/P3/P4 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
