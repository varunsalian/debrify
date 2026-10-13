#!/usr/bin/env python3
"""Materialize the reviewed Phase-7 split in evidence, never in production."""
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
CONTROLLER = 'VpLocalCompletion'
DEST = FEATURE + '/presentation/legacy_video_player/vp_local_completion.dart'
NAMES = ['_currentEpisodeMarkedAsFinished', '_currentMovieMarkedAsFinished',
         '_currentMovieRewatchStarted', '_movieCompletionThreshold',
         '_episodeCompletionThreshold', '_forceLocalCompletionTracking',
         '_loadLocalCompletionThresholds', '_loadTrackingPolicy',
         '_usesLocalCompletionTracking', '_currentLocalMovieImdbId',
         '_resetLocalCompletionState', '_markCurrentEpisodeAsFinished',
         '_markCurrentMovieAsFinished', '_checkAndApplyLocalCompletion']
HOST = ['_effectiveIptvChannels', '_effectiveContentImdbId', '_effectiveContentType',
        '_seriesPlaylist', '_activePlaylist', '_currentIndex', '_position',
        '_duration', '_validationGateActive', '_resumeKey']
WIDGET = ['traktScrobble', 'simklScrobble', 'mdblistScrobble', 'stremioTvChannels',
          'contentType', 'contentSeason', 'contentEpisode', 'contentImdbId',
          'contentTitle', 'title']
IMPORTS = """import 'dart:async';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
"""
FORWARDERS = [
    'bool get mounted => _s.mounted;',
    'bool get traktScrobble => _s.widget.traktScrobble;',
    'bool get simklScrobble => _s.widget.simklScrobble;',
    'bool get mdblistScrobble => _s.widget.mdblistScrobble;',
    'List<Map<String, dynamic>>? get stremioTvChannels => _s.widget.stremioTvChannels;',
    'String? get contentType => _s.widget.contentType;',
    'int? get contentSeason => _s.widget.contentSeason;',
    'int? get contentEpisode => _s.widget.contentEpisode;',
    'String? get contentImdbId => _s.widget.contentImdbId;',
    'String? get contentTitle => _s.widget.contentTitle;',
    'String get title => _s.widget.title;',
    'List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;',
    'String? get effectiveContentImdbId => _s._effectiveContentImdbId;',
    'String? get effectiveContentType => _s._effectiveContentType;',
    'SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;',
    'List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;',
    'int get currentIndex => _s._currentIndex;',
    'Duration get position => _s._position;',
    'Duration get duration => _s._duration;',
    'bool get validationGateActive => _s._validationGateActive;',
    'String get resumeKey => _s._resumeKey;',
]
INTERFACE = 'abstract interface class VpLocalCompletionHost {\n' + ''.join(
    '  ' + line.split(' => ')[0] + ';\n' for line in FORWARDERS) + '}\n'
ADAPTER = 'class _VpLocalCompletionHostAdapter implements VpLocalCompletionHost {\n  _VpLocalCompletionHostAdapter(this._s);\n  final _VideoPlayerScreenState _s;\n' + ''.join(
    '  @override\n  ' + line + '\n' for line in FORWARDERS) + '}\n'


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=7, status='draft', span_order=list(spans))
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: CONTROLLER for n in NAMES[:6]}),
        record_owners=[STATE], record_fields={STATE: NAMES[:6]},
        receiver_owners={'_completion': CONTROLLER}, receiver_paths={'_completion': CONTROLLER},
        receiver_members={CONTROLLER: [n[1:] for n in NAMES]},
        receivers=['_host', '_completion'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings={'_host.' + n[1:]: STATE + '.' + n for n in HOST},
        registered_occurrence_substitutions=[dict(before=['widget', '.', name],
            after=['_host', '.', name], binding='unbound', role_change='widget selector read to live Host selector read')
            for name in WIDGET])
    measured = []
    for row in spec['declarations']:
        key = row['original']
        moved = key in [STATE + '.' + n for n in NAMES]
        mapping = {n: ([n[1:]] if moved else ['_completion', '.', n[1:]]) for n in NAMES}
        if moved:
            row.update(fate='moved', destination=DEST, target=CONTROLLER + '.' + key.split('.')[-1][1:])
            mapping.update({n: ['_host', '.', n[1:]] for n in HOST})
            mapping['mounted'] = ['_host', '.', 'mounted']
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            assert not any(values[i:i+2] == ['$', name] for i in range(len(values)-1)), (key, name)
            count = values.count(name)
            if count: edits.append(dict(before=[name], after=after, count=count))
        if moved:
            for name in WIDGET:
                before = ['widget', '.', name]
                count = sum(values[i:i+3] == before for i in range(len(values)-2))
                if count: edits.append(dict(before=before, after=['_host', '.', name], count=count))
        if edits:
            row['substitutions'] = edits
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 declaration_line=original[:nodes[key]['start']].count('\n')+1 if key in nodes else None,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == STATE + '.' + STATE:
            row.update(fate='patched', reason='Append the eager inert local-completion assignment after MDBList.',
                       test='dev/tool/test_dart_completion_moves.py', patches=[dict(before=[';', '}'], after=[
                           ';', '_completion', '=', CONTROLLER, '(', '_VpLocalCompletionHostAdapter', '(', 'this', ')', ')', ';', '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {
        '@directive:' + str(len(unit['directives'])): "import '../features/video_player/presentation/legacy_video_player/vp_local_completion.dart';",
        STATE + '._completion': 'late final VpLocalCompletion _completion;',
        '_VpLocalCompletionHostAdapter': ADAPTER,
    }
    for key in scaffolds:
        if key.startswith('@directive:'):
            index = next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key == STATE + '._completion':
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
    dest = IMPORTS + INTERFACE + '\nclass ' + CONTROLLER + ' {\n  ' + CONTROLLER + '(this._host);\n  final VpLocalCompletionHost _host;\n'
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
    parser.add_argument('--base', default='2defa5100')
    parser.add_argument('--parser-package', type=Path, required=True)
    parser.add_argument('--probe', type=Path, required=True)
    args = parser.parse_args()
    common = Path(subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    evidence = common / 'refactor-evidence/vplayer/p7'
    if not args.probe.resolve().is_relative_to(evidence): parser.error('probe must be under P7 evidence')
    ensure_parser_package(args.parser_package.parent.parent, args.parser_package)
    original, spec, measured = draft(args.base, args.parser_package)
    sources = materialize(spec, original, args.parser_package)
    errors = check(spec, original, sources, args.parser_package) + check_earlier(spec, args.parser_package)
    for error in errors: print(error)
    if errors: return 1
    (ROOT / 'dev/tool/dart_moves/vplayer_p7.json').write_text(json.dumps(spec, indent=2)+'\n')
    args.probe.mkdir(parents=True, exist_ok=True)
    (args.probe / 'remeasured.json').write_text(json.dumps(measured, indent=2)+'\n')
    for path, content in sources.items():
        target = args.probe / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(content)
    print('PASS: complete Phase-7 virtual split, exhaustive ownership + P1–P6 destinations; app untouched')
    return 0


if __name__ == '__main__': raise SystemExit(main())
