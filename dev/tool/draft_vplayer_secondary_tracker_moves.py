#!/usr/bin/env python3
"""Materialize the reviewed Phase-6 split in evidence, never in production."""
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
COMMON = [
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
]
SHARED_IMPORTS = """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
"""
SIMKL = dict(
    controller='VpSimklScrobbler', receiver='_simkl',
    names=['_simklScrobbleEnabled', '_launchSimklPercentSpent', '_simklEpisodeProgress',
           '_simklLastScrobbleAction', '_simklHeartbeatTimer', '_initSimklScrobble',
           '_simklSeriesSEUnresolved', '_simklScrobble', '_startSimklHeartbeat',
           '_stopSimklHeartbeat', '_simklScrobbleSeek', '_currentEpisodeSimklPercent'],
    fields=5,
    forwarders=COMMON + [
        'bool get simklScrobble => _s.widget.simklScrobble;',
        'double traktProgress() => _s._trakt.traktProgress();',
        'SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;',
        'List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;',
        'int get currentIndex => _s._currentIndex;',
        'String? get effectiveContentType => _s._effectiveContentType;',
        'int? get effectiveContentSeason => _s._effectiveContentSeason;',
        'int? get effectiveContentEpisode => _s._effectiveContentEpisode;',
    ],
    imports=SHARED_IMPORTS + """import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
""")
MDBLIST = dict(
    controller='VpMdblistScrobbler', receiver='_mdblist',
    names=['_mdblistEpisodeProgress', '_launchMdblistPercentSpent', '_mdblistSession',
           '_mdblistTarget', '_initMdblistScrobble', '_updateMdblistPosition',
           '_mdblistPlay', '_mdblistPause', '_mdblistStop', '_mdblistScrobbleSeek',
           '_switchMdblistTarget', '_currentEpisodeMdblistPercent'],
    fields=3,
    forwarders=COMMON + [
        'bool get mdblistScrobble => _s.widget.mdblistScrobble;',
        'Duration get position => _s._position;',
        'Duration get persistablePosition => _s._persistablePosition;',
        'Future<void> get playerInitializationFuture => _s._playerInitializationFuture;',
    ],
    imports=SHARED_IMPORTS + """import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
""")
TRACKERS = [SIMKL, MDBLIST]
CHAIN = dict(before=['_trakt', '.', 'traktProgress'], after=['_host', '.', 'traktProgress'],
             binding='unbound', role_change='State-owned Trakt receiver invocation to live Simkl Host invocation')


def draft(base, package):
    original = git_text(base, SOURCE)
    spec = retained_manifest(SOURCE, FEATURE, original, base, package)
    unit = parse({'base': original}, package, ownership=True)['base']
    spans, _, nodes = partition(unit, [STATE])
    spec.update(phase=6, status='draft', span_order=list(spans),
                patched_class_projection=['_VpSkipSegmentHostAdapter'])
    hosts = {}
    widget = ['contentImdbId', 'contentType', 'simklScrobble', 'mdblistScrobble']
    for tracker in TRACKERS:
        tracker['destination'] = FEATURE + '/presentation/legacy_video_player/vp' + tracker['receiver'] + '_scrobbler.dart'
        for forwarder in tracker['forwarders']:
            if '=> _s._' in forwarder and 'traktProgress()' not in forwarder:
                original_name = forwarder.split('=> _s.')[1].split('(')[0].rstrip(';')
                hosts['_host.' + original_name[1:]] = STATE + '.' + original_name
    spec['guards'] = dict(
        occurrence_field_bindings=dict(owners=[STATE], state_classes=[STATE], mandatory_qualification=True,
            owner_scoped_bare_fields={STATE + '.' + n: t['controller'] for t in TRACKERS for n in t['names'][:t['fields']]}),
        record_owners=[STATE], record_fields={STATE: [n for t in TRACKERS for n in t['names'][:t['fields']]]},
        receiver_owners={t['receiver']: t['controller'] for t in TRACKERS},
        receiver_paths={t['receiver']: t['controller'] for t in TRACKERS},
        receiver_members={t['controller']: [n[1:] for n in t['names']] for t in TRACKERS},
        receivers=['_host', '_simkl', '_mdblist'], live_state_receivers=['_host'], require_live_state_callbacks=True,
        host_property_bindings=hosts,
        registered_occurrence_substitutions=[CHAIN] + [dict(before=['widget', '.', name], after=['_host', '.', name],
            binding='unbound', role_change='widget selector read to live Host selector read') for name in widget])
    measured = []
    for row in spec['declarations']:
        key = row['original']
        tracker = next((t for t in TRACKERS if key in [STATE + '.' + n for n in t['names']]), None)
        moved = tracker is not None
        mapping = {n: ([n[1:]] if moved else [t['receiver'], '.', n[1:]]) for t in TRACKERS for n in t['names']}
        if moved:
            row.update(fate='moved', destination=tracker['destination'], target=tracker['controller'] + '.' + key.split('.')[-1][1:])
            mapping['mounted'] = ['_host', '.', 'mounted']
            # Preserve punctuation in the explicit Host chains.
            mapping.update({v.split('.')[-1]: ['_host', '.', k.split('.')[-1]] for k,v in hosts.items()})
        values = tokens(spans[key])
        edits = []
        for name, after in mapping.items():
            interpolation = sum(values[i:i+2] == ['$', name] for i in range(len(values)-1))
            bare_count = values.count(name) - interpolation
            if bare_count:
                if not interpolation:
                    edits.append(dict(before=[name], after=after, count=bare_count))
                else:
                    contexts = set()
                    for i,v in enumerate(values):
                        if v != name or (i and values[i-1] == '$'): continue
                        width = 2
                        while any(values[j:j+width] == values[i:i+width] and j and values[j-1] == '$'
                                  for j in range(len(values))): width += 1
                        contexts.add(tuple(values[i:i+width]))
                    assert sum(sum(values[i:i+len(c)] == list(c) for i in range(len(values))) for c in contexts) == bare_count
                    for c in sorted(contexts):
                        edits.append(dict(before=list(c), after=[*after, *c[1:]],
                                          count=sum(values[i:i+len(c)] == list(c) for i in range(len(values)))))
            if interpolation:
                edits.append(dict(before=['$', name], after=['${', *after, '}'], count=interpolation))
        if moved:
            for before, after in [(CHAIN['before'], CHAIN['after']), *[(['widget', '.', n], ['_host', '.', n]) for n in widget]]:
                count = sum(values[i:i+len(before)] == before for i in range(len(values)-len(before)+1))
                if count: edits.append(dict(before=before, after=after, count=count))
        if key == '_VpSkipSegmentHostAdapter':
            assert len(edits) == 2 and all(e['count'] == 1 for e in edits)
            row.update(fate='patched', reason='Keep the P5 Trakt forwarder and redirect the two remaining skip Host tracker seek forwarders to P6 collaborators.',
                       test='dev/tool/test_dart_secondary_tracker_moves.py', patches=edits)
        elif edits: row['substitutions'] = edits
        if edits:
            measured.append(dict(declaration=key, fate=row['fate'], line=original[:spans[key]['start']].count('\n')+1,
                                 end=original[:spans[key]['end']].count('\n')+1, edits=edits))
        if key == STATE + '.' + STATE:
            append = []
            for t in TRACKERS:
                append += [t['receiver'], '=', t['controller'], '(', '_'+t['controller']+'HostAdapter', '(', 'this', ')', ')', ';']
            row.update(fate='patched', reason='Append eager inert Simkl then MDBList assignments after the existing Trakt assignment.',
                       test='dev/tool/test_dart_secondary_tracker_moves.py', patches=[dict(before=[';', '}'], after=[';', *append, '}'], count=1)])
    retained = {r['original'] for r in spec['declarations'] if r['fate'] != 'moved'}
    spec['span_order'] = [k for k in spans if k in retained]
    scaffolds = {}
    for i,t in enumerate(TRACKERS):
        c=t['controller']; host=c+'Host'; adapter='_'+host+'Adapter'
        scaffolds['@directive:'+str(len(unit['directives'])+i)] = "import '../" + t['destination'][4:] + "';"
        scaffolds[STATE+'.'+t['receiver']] = 'late final '+c+' '+t['receiver']+';'
        scaffolds[adapter] = 'class '+adapter+' implements '+host+' {\n  '+adapter+'(this._s);\n  final _VideoPlayerScreenState _s;\n'+''.join('  @override\n  '+f+'\n' for f in t['forwarders'])+'}\n'
    for key in scaffolds:
        if key.startswith('@directive:'): index=next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:'))
        elif key.startswith(STATE+'.'):
            first=STATE+'.'+next(t['names'][0] for t in TRACKERS if key.endswith(t['receiver']))
            index=next(i for i,k in enumerate(spec['span_order']) if k in spans and spans[k]['start'] > spans[first]['start'])
        else: index=spec['span_order'].index(STATE+':close')+1
        spec['span_order'].insert(index,key)
    bykey={r['original']:r for r in spec['declarations']}
    facade=''.join(scaffolds[k]+'\n' if k in scaffolds else edited_text(original,spans[k],bykey[k].get('substitutions',[])+bykey[k].get('patches',[])) for k in spec['span_order'])
    parsed=parse({SOURCE:facade},package,ownership=True)[SOURCE];physical,orders,_=partition(parsed,[STATE])
    spec['facade_orders'],spec['facade_directives']=orders,parsed['directives']
    spec['scaffolding'][SOURCE]=frozen({k:physical[k] for k in scaffolds})
    for t in TRACKERS:
        c=t['controller'];host=c+'Host'
        dest=t['imports']+'abstract interface class '+host+' {\n'+''.join('  '+f.split(' => ')[0]+';\n' for f in t['forwarders'])+'}\n\nclass '+c+' {\n  '+c+'(this._host);\n  final '+host+' _host;\n'
        for row in spec['declarations']:
            if row['fate']=='moved' and row['destination']==t['destination']:dest+=edited_text(original,spans[row['original']],row.get('substitutions',[]))
        dest+='\n}\n';parsed=parse({t['destination']:dest},package,ownership=True)[t['destination']]
        physical,orders,_=partition(parsed,[c]);targets={r['target'] for r in spec['declarations'] if r['fate']=='moved' and r['destination']==t['destination']}
        spec['destinations'][t['destination']]=dict(directives=parsed['directives'],orders=orders,span_order=list(physical),split_containers=[c])
        spec['scaffolding'][t['destination']]=frozen({k:v for k,v in physical.items() if k not in targets})
    return original,spec,measured


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base',default='ea7901ead')
    parser.add_argument('--parser-package',type=Path,required=True)
    parser.add_argument('--probe',type=Path,required=True)
    args=parser.parse_args()
    common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip())
    evidence=common/'refactor-evidence/vplayer/p6'
    if not args.probe.resolve().is_relative_to(evidence):parser.error('probe must be under P6 evidence')
    ensure_parser_package(args.parser_package.parent.parent,args.parser_package)
    original,spec,measured=draft(args.base,args.parser_package)
    sources=materialize(spec,original,args.parser_package)
    errors=check(spec,original,sources,args.parser_package)+check_earlier(spec,args.parser_package)
    for error in errors:print(error)
    if errors:return 1
    (ROOT/'dev/tool/dart_moves/vplayer_p6.json').write_text(json.dumps(spec,indent=2)+'\n')
    args.probe.mkdir(parents=True,exist_ok=True)
    (args.probe/'remeasured.json').write_text(json.dumps(measured,indent=2)+'\n')
    for path,content in sources.items():
        target=args.probe/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(content)
    print('PASS: complete Phase-6 virtual split, exhaustive ownership + P1–P5 destinations; app untouched')
    return 0


if __name__=='__main__':raise SystemExit(main())
