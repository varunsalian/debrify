#!/usr/bin/env python3
"""FINAL P16 evidence materialization on accepted P15 plus reviewed S2e.

Never writes application files. Protects all fifteen applied historical phases.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT as R, ensure_parser_package, parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest, check
from dart_move_partition import partition, frozen
from dart_move_history import git_text
from dart_move_fixture import edited_text

SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
STATE = '_VideoPlayerScreenState'
BASE = '2dadfc7a4'
GROUPS = [
 dict(name='VpStartupCandidates', receiver='_startupCandidates', file='vp_startup_candidates.dart', names=['_openStartupDebridDirect', '_tryOpenStartupVod', '_commitValidatedStremioSource', '_startupSourceFields']),
 dict(name='VpStartupFailover', receiver='_startupFailover', file='vp_startup_failover.dart', names=['_openInitialVodWithFailover']),
 dict(name='VpStartupGate', receiver='_startupGate', file='vp_startup_gate.dart', names=['_resumeTrackingAfterValidationGate', '_watchStremioTvStartup', '_reportStartupFailure', '_setStartupGateActive', '_setStartupGateMessage']),
 dict(name='VpSourceSwitch', receiver='_sourceSwitch', file='vp_source_switch.dart', names=['_pendingSourcePlaylist', '_sourcePlaylistResolution', '_showSourceSheetOverlay', '_hideSourceSheet', '_buildSourceSheetResolver', '_handleSourceSelected', '_switchToStremioSource']),
 dict(name='VpSourcePlaylistSwitch', receiver='_sourcePlaylistSwitch', file='vp_source_playlist_switch.dart', names=['_switchToSourcePlaylist']),
]
TYPES = {
 'context':'BuildContext', '_player':'mk.Player', '_androidVideoRendererMode':'AndroidVideoRendererMode',
 '_rendererValidatedForSession':'bool', '_rendererFallbackInProgress':'bool',
 '_serverWatch':'MediaServerWatchController', '_openedWatchSource':'Torrent?',
 '_currentSourceIndex':'int', '_screenDisposed':'bool', '_effectiveSources':'List<Torrent>?',
 '_effectiveResolver':'Future<String?> Function(Torrent)?',
 '_effectiveContentType':'String?', '_effectiveContentSeason':'int?', '_effectiveContentEpisode':'int?',
 '_startupGateOverlayHidden':'bool', '_activeHttpHeaders':'Map<String, String>?',
 '_currentStreamUrl':'String?', '_activePlaylist':'List<PlaylistEntry>?', '_currentIndex':'int',
 '_cachedSeriesPlaylist':'SeriesPlaylist?', '_playlistIdentityToken':'int',
 '_startupGateActive':'bool', '_startupGateMessage':'String', '_validationGateActive':'bool',
 '_isPlaying':'bool', '_duration':'Duration', '_stremioTvStartupWatch':'ChannelStartupWatch?',
 '_stremioTvStartupSeek':'DeferredStartupSeek', '_resumeVerifyEpoch':'int',
 '_playerInstanceGeneration':'int', '_decoderProbeGeneration':'int',
 '_showSourceSheet':'bool', '_controlsVisible':'ValueNotifier<bool>', '_iptvChannelKey':'String?',
 '_resumeWriteGuard':'ResumeWriteGuard', '_position':'Duration', '_manualSourceGateActive':'bool',
 '_isTransitioning':'bool', '_tvScrubGeneration':'int', '_transitionStopTimer':'Timer?',
 '_transitionPhaseTimer':'Timer?', '_transitionPhase':'int', '_transitionPhase2Started':'DateTime?',
 '_rainbowController':'AnimationController', '_transitionRunning':'bool', '_rainbowActive':'bool',
 '_episodeNavigationGeneration':'int', '_seriesPlaylist':'SeriesPlaylist?',
 '_syntheticGuidePlaylist':'SeriesPlaylist?', '_currentSeriesImdbId':'String?',
 '_episodeMetadataReady':'Future<void>?', '_isManualEpisodeSelection':'bool',
 '_allowResumeForManualSelection':'bool',
}
ACTIONS = {
 '_openMedia': ('Future<void> openMedia(mk.Media media, {required bool play, bool? desiredPlay, bool liveStream = false, EpisodePlaybackRequest? request, bool Function()? beforeOpen, Torrent? source, int? preserveStartupEpoch})', '(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)'),
 '_tryOpenStartupVod': ('Future<bool> tryOpenStartupVod(String url, {Duration timeout = const Duration(seconds: 12), Map<String, String>? httpHeaders, Torrent? source, int? sourceIndex, int attempt = 1, int maxAttempts = 1})', '(url, timeout: timeout, httpHeaders: httpHeaders, source: source, sourceIndex: sourceIndex, attempt: attempt, maxAttempts: maxAttempts)'),
 '_openStartupDebridDirect': ('Future<bool> openStartupDebridDirect(String url, {Map<String, String>? httpHeaders, Torrent? source, int? sourceIndex, int attempt = 1, int maxAttempts = 1, Duration timeout = const Duration(seconds: 12)})', '(url, httpHeaders: httpHeaders, source: source, sourceIndex: sourceIndex, attempt: attempt, maxAttempts: maxAttempts, timeout: timeout)'),
 '_startupSourceFields': ('String startupSourceFields(int? index, Torrent? source)', '(index, source)'),
 '_commitValidatedStremioSource': ('Future<void> commitValidatedStremioSource(Torrent? source)', '(source)'),
 '_setStartupGateActive': ('void setStartupGateActive(bool active)', '(active)'),
 '_setStartupGateMessage': ('void setStartupGateMessage(String message)', '(message)'),
 '_canFallbackExplicitRenderer': ('bool canFallbackExplicitRenderer({required int instanceGeneration, required int mediaGeneration})', '(instanceGeneration: instanceGeneration, mediaGeneration: mediaGeneration)'),
 '_hideIptvZapBanner': ('void hideIptvZapBanner({bool immediate = false})', '(immediate: immediate)'),
 '_switchToIptvSource': ('Future<void> switchToIptvSource(int index, String url)', '(index, url)'),
 '_switchToSourcePlaylist': ('Future<bool> switchToSourcePlaylist(int sourceIndex, List<PlaylistEntry> newPlaylist, {int? targetSeason, int? targetEpisode, bool validateExplicitSelection = false, bool suppressResume = false, EpisodePlaybackRequest? request})', '(sourceIndex, newPlaylist, targetSeason: targetSeason, targetEpisode: targetEpisode, validateExplicitSelection: validateExplicitSelection, suppressResume: suppressResume, request: request)'),
 '_resumeTrackingAfterValidationGate': ('void resumeTrackingAfterValidationGate()', '()'),
 '_tvAbandonScrub': ('void tvAbandonScrub()', '()'),
 '_startTransitionOverlay': ('void startTransitionOverlay()', '()'),
 '_clearBufferingIndicator': ('void clearBufferingIndicator()', '()'),
 '_resetSubtitleState': ('void resetSubtitleState()', '()'),
 '_waitForVideoReady': ('Future<void> waitForVideoReady()', '()'),
 '_setExternalAudioTrack': ('Future<void> setExternalAudioTrack(String url)', '(url)'),
 '_traktSeasonEpisode': ('({int? season, int? episode}) traktSeasonEpisode()', '()'),
 '_preloadEpisodeInfo': ('Future<void> preloadEpisodeInfo()', '()'),
 '_loadPlaylistIndex': ('Future<bool> loadPlaylistIndex(int index, {bool autoplay = false, EpisodePlaybackRequest? request, bool skipInitialSave = false, bool preferLocalResume = false, bool suppressResume = false, Torrent? manualValidationSource, int? manualValidationSourceIndex})', '(index, autoplay: autoplay, request: request, skipInitialSave: skipInitialSave, preferLocalResume: preferLocalResume, suppressResume: suppressResume, manualValidationSource: manualValidationSource, manualValidationSourceIndex: manualValidationSourceIndex)'),
 '_hideSourceSheet': ('void hideSourceSheet()', '()'),
 'setState': ('void setState(VoidCallback fn)', '(fn)'),
}
WIDGET = {
 'onStremioSourceCommitted':'Future<void> Function(Torrent)?',
 'startupFailoverEnabled':'bool', 'startupResolverProvider':'String?',
 'resolveSourceToPlaylist':'SourcePlaylistResolve?', 'title':'String',
 'onStartupSourcesExhausted':'Future<void> Function()?', 'audioUrl':'String?',
}
CHAINS = [dict(before=['VpS2Hooks','.','isAndroid'], name='isAndroid', type='bool', target='VpS2Hooks.isAndroid')]
for root,member,typ in [('_trakt','traktLastScrobbleAction','String?'), ('_simkl','simklScrobbleEnabled','bool'), ('_simkl','simklLastScrobbleAction','String?')]:
 CHAINS.append(dict(before=[root,'.',member], name=member, type=typ))
for root,member,sig,args in [
 ('_iptvBanner','hideIptvZapBanner','void hideIptvZapBanner({bool immediate = false})','(immediate: immediate)'),
 ('_iptvSwitch','switchToIptvSource','Future<void> switchToIptvSource(int index, String url)','(index, url)'),
 ('_trakt','traktScrobble','void traktScrobble(String action)','(action)'),
 ('_trakt','startTraktHeartbeat','void startTraktHeartbeat()','()'),
 ('_simkl','startSimklHeartbeat','void startSimklHeartbeat()','()'),
 ('_mdblist','updateMdblistPosition','void updateMdblistPosition()','()'),
 ('_mdblist','mdblistPlay','void mdblistPlay()','()'),
 ('_mdblist','switchMdblistTarget','Future<void> switchMdblistTarget()','()'),
 ('_resumeRestore','seekForResume','Future<void> seekForResume(int posMs, {bool verifyLanding = false})','(posMs, verifyLanding: verifyLanding)'),
 ('_resumeSave','saveResume','Future<void> saveResume({bool debounced = false, Duration? positionOverride})','(debounced: debounced, positionOverride: positionOverride)'),
 ('_trackPreferences','restoreTrackPreferences','Future<void> restoreTrackPreferences()','()'),
]:
 CHAINS.append(dict(before=[root,'.',member], name=member, signature=sig, args=args))
IMPORTS = {}
COMMON = "import 'package:debrify/models/torrent.dart';\n"
for name in [g['name'] for g in GROUPS]:
 IMPORTS[name] = COMMON
IMPORTS['VpStartupCandidates'] += """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/startup_stream_policy.dart';
"""
IMPORTS['VpStartupFailover'] += """import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/startup_stream_policy.dart';
"""
IMPORTS['VpStartupGate'] += """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/services/startup_stream_policy.dart';
"""
for name in ['VpSourceSwitch','VpSourcePlaylistSwitch']:
 IMPORTS[name] += """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
"""
IMPORTS['VpSourceSwitch'] += """import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/features/video_player/models/vp_manual_source_validation_failure.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
"""
# Imports are new frozen scaffolding, not a license to edit moved bodies.
IMPORTS['VpSourceSwitch'] = IMPORTS['VpSourceSwitch'].replace(
 "import 'package:debrify/models/series_playlist.dart';\n", '')
for name, text in IMPORTS.items():
 lines = text.splitlines()
 dart = sorted(line for line in lines if line.startswith("import 'dart:"))
 packages = sorted(line for line in lines if line.startswith("import 'package:"))
 IMPORTS[name] = ('\n'.join(dart) + '\n\n' if dart else '') + '\n'.join(packages) + '\n'
EXPECTED_HOSTS = {
 'VpStartupCandidates': (10, 10), 'VpStartupFailover': (26, 29),
 'VpStartupGate': (28, 31), 'VpSourceSwitch': (46, 53),
 'VpSourcePlaylistSwitch': (48, 58),
}
PATCHED = ['_VpIptvChannelSwitchHostAdapter']

def occurrences(vals,before):return [i for i in range(len(vals)) if vals[i:i+len(before)]==before]
def name_edits(vals,name,after):
 positions=[i for i,v in enumerate(vals) if v==name];inter=[i for i in positions if i and vals[i-1]=='$'];bare=[i for i in positions if i not in inter];out=[]
 if inter:out.append(dict(before=['$',name],after=['${',*after,'}'],count=len(inter)))
 if bare and not inter:out.append(dict(before=[name],after=after,count=len(bare)))
 elif bare:
  patterns={tuple([name,vals[i+1]]) for i in bare}
  for pattern in sorted(patterns):
   assert len(occurrences(vals,list(pattern)))==sum(vals[i:i+2]==list(pattern) for i in bare),(name,pattern)
   out.append(dict(before=list(pattern),after=[*after,pattern[1]],count=len(occurrences(vals,list(pattern)))))
 return out

def build(package):
 original=git_text(BASE,SOURCE);spec=retained_manifest(SOURCE,FEATURE,original,BASE,package);u=parse({'base':original},package,ownership=True)['base'];spans,_,nodes=partition(u,[STATE]);byname={n:g for g in GROUPS for n in g['names']};allnames=set(byname);hostbindings={};registrations=[];measured=[]
 for g in GROUPS:
  g['dest']=FEATURE+'/presentation/legacy_video_player/'+g['file'];g['forwarders']=[];g['hosts']=[];vals=[v for n in g['names'] for v in tokens(spans[STATE+'.'+n])]
  for n in sorted(TYPES):
   if n not in vals or n in g['names']:continue
   typ=TYPES[n];write=any(vals[i+1:i+2] in [['='],['++'],['--']] for i in occurrences(vals,[n]));read=any(vals[i+1:i+2]!=['='] for i in occurrences(vals,[n]));name=n.lstrip('_')
   if read:g['forwarders'].append(typ+' get '+name+' => _s.'+n+';')
   if write:g['forwarders'].append('set '+name+'('+typ+' v) => _s.'+n+' = v;')
   g['hosts'].append(n)
   if n!='context':hostbindings['_host.'+name]=STATE+'.'+n
  for n,(signature,args) in ACTIONS.items():
   if n in vals and n not in g['names']:
    target='_s.'+(byname[n]['receiver']+'.'+n.lstrip('_') if n in byname else '_vpSetState' if n=='setState' else n);g['forwarders'].append(signature+' => '+target+args+';');g['hosts'].append(n)
    if n!='setState':hostbindings['_host.'+n.lstrip('_')]=STATE+'.'+n
  if 'mounted' in vals:g['forwarders'].append('bool get mounted => _s.mounted;')
  for name,typ in WIDGET.items():
   if occurrences(vals,['widget','.',name]):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';')
  for c in CHAINS:
   indices=occurrences(vals,c['before'])
   if not indices:continue
   target=c.get('target', '_s.'+''.join(c['before']));name=c['name']
   if 'type' in c:
    write=any(vals[i+len(c['before']):i+len(c['before'])+1]==['='] for i in indices);read=any(vals[i+len(c['before']):i+len(c['before'])+1]!=['='] for i in indices)
    if read:g['forwarders'].append(c['type']+' get '+name+' => '+target+';')
    if write:g['forwarders'].append('set '+name+'('+c['type']+' v) => '+target+' = v;')
   else:g['forwarders'].append(c['signature']+' => '+target+c['args']+';')
  names=[(re.search(r'\b(?:get|set)\s+(\w+)',f.split(' => ')[0]) or re.search(r'(\w+)\s*\(',f.split(' => ')[0])).group(1) for f in g['forwarders']];g['host_names']=names;assert len(g['forwarders'])==len(set(g['forwarders'])),g['name'];assert (len(set(names)),len(names))==EXPECTED_HOSTS[g['name']],(g['name'],names)
 spec.update(phase=16,status='FINAL',span_order=list(spans),patched_class_projection=PATCHED,finalization=dict(label='FINAL',preparation_base='be4cd78aa',accepted_p15='ed7c6717a',seam_original=BASE,history='All fifteen applied phases; every earlier destination derived without a whitelist.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Complete live chain to exact facade Host projection') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'._pendingSourcePlaylist':'VpSourceSwitch',STATE+'._sourcePlaylistResolution':'VpSourceSwitch'}),record_owners=[STATE],record_fields={STATE:['_pendingSourcePlaylist','_sourcePlaylistResolution']},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None;mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in allnames};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n.lstrip('_')] for n in g['hosts']});mapping['mounted']=['_host','.','mounted']
  for n,after in mapping.items():
   if n in vals:edits+=name_edits(vals,n,after)
  if moved:
   for before,after in [(r['before'],r['after']) for r in registrations]:
    indices=occurrences(vals,before)
    if indices:edits.append(dict(before=before,after=after,count=len(indices)))
  if key in PATCHED:
   assert len(edits)==1 and edits[0]['count']==1,(key,edits);row.update(fate='patched',reason='Route P15 owner hideSourceSheet to its P16 owner, preserving every earlier rewrite.',test='dev/tool/draft_vplayer_startup_moves.py',patches=edits);edits=[]
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Five inert eager assignments after all seven accepted P15 collaborators.',test='dev/tool/draft_vplayer_startup_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._iptvBanner'
 for i,g in enumerate(GROUPS):
  host=g['name']+'Host';adapter='_'+host+'Adapter';key=STATE+'.'+g['receiver'];scaff['@directive:'+str(len(u['directives'])+i)]="import '../"+g['dest'][4:]+"';";scaff[key]='late final '+g['name']+' '+g['receiver']+';';scaff[adapter]='class '+adapter+' implements '+host+' {\n  '+adapter+'(this._s);\n  final _VideoPlayerScreenState _s;\n'+''.join('  @override\n  '+f+'\n' for f in g['forwarders'])+'}\n';at=spec['span_order'].index(previous)+1;spec['span_order'].insert(at,key);previous=key
 for key in scaff:
  if key.startswith('@directive:'):spec['span_order'].insert(next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:')),key)
  elif not key.startswith(STATE+'.'):spec['span_order'].insert(spec['span_order'].index(STATE+':close')+1,key)
 bykey={r['original']:r for r in spec['declarations']};facade=''.join(scaff[k]+'\n' if k in scaff else edited_text(original,spans[k],bykey[k].get('substitutions',[])+bykey[k].get('patches',[])) for k in spec['span_order']);pu=parse({SOURCE:facade},package,ownership=True)[SOURCE];physical,orders,_=partition(pu,[STATE]);spec['facade_orders']=orders;spec['facade_directives']=pu['directives'];spec['scaffolding'][SOURCE]=frozen({k:physical[k] for k in scaff});sources={SOURCE:facade}
 for g in GROUPS:
  c=g['name'];host=c+'Host';dest=IMPORTS[c]+'abstract interface class '+host+' {\n'+''.join('  '+f.split(' => ')[0]+';\n' for f in g['forwarders'])+'}\n\nclass '+c+' {\n  '+c+'(this._host);\n  final '+host+' _host;\n'
  for row in spec['declarations']:
   if row['fate']=='moved' and row['destination']==g['dest']:dest+=edited_text(original,spans[row['original']],row.get('substitutions',[]))
  dest+='\n}\n';sources[g['dest']]=dest;pu=parse({g['dest']:dest},package,ownership=True)[g['dest']];physical,orders,_=partition(pu,[c]);targets={r['target'] for r in spec['declarations'] if r['fate']=='moved' and r['destination']==g['dest']};spec['destinations'][g['dest']]=dict(directives=pu['directives'],orders=orders,span_order=list(physical),split_containers=[c]);spec['scaffolding'][g['dest']]=frozen({k:v for k,v in physical.items() if k not in targets})
 return original,spec,sources,measured


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--parser-package',type=Path,required=True)
 p.add_argument('--probe',type=Path,required=True)
 a=p.parse_args()
 common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip())
 assert a.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p16')
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package)
 original,spec,sources,measured=build(a.parser_package)
 a.probe.mkdir(parents=True,exist_ok=True)
 for path,text in sources.items():
  out=a.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(text)
 subprocess.run(['nice','-n','19','dart','format',*[str(a.probe/p) for p in sources]],check=True)
 formatted={path:(a.probe/path).read_text() for path in sources}
 errors=check(spec,original,formatted,a.parser_package)
 assert not errors,errors
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS}
 assert all(v<=500 for v in sizes.values()),sizes
 hosts={g['name']:g['forwarders'] for g in GROUPS}
 spec['finalization']['host_contracts'] = hosts
 # Scan scanner occurrences, never comments or substrings, outside moved spans.
 unit=parse({'base':original},a.parser_package,ownership=True)['base']
 spans,_,_=partition(unit,[STATE])
 byname={n:g for g in GROUPS for n in g['names']}
 retained=[]
 for row in spec['declarations']:
  if row['fate']=='moved':continue
  for token in spans[row['original']]['tokens']:
   name=token['text']
   if token['comment'] or name not in byname:continue
   offset=token['offset']
   retained.append(dict(declaration=row['original'],member=name,
       line=original.count('\n',0,offset)+1,
       substitution=byname[name]['receiver']+'.'+name[1:],
       p15_adapter=row['original']=='_VpIptvChannelSwitchHostAdapter'))
 assert len(retained)==22,retained
 (a.probe.parent/'retained-sites.json').write_text(json.dumps(dict(
     label='FINAL',original=BASE,sites=retained,count=len(retained),
     after_p15='21 facade sites plus the single owner adapter, regenerated on accepted P15.'),indent=2)+'\n')
 assert not next(r for r in spec['declarations'] if r['original']==STATE+'.dispose').get('substitutions')
 (a.probe.parent/'field-inertness.json').write_text(json.dumps(dict(
     pendingSourcePlaylist='Implicit null, no allocation/call/Host read.',
     sourcePlaylistResolution='Literal zero, no allocation/call/Host read.',
     constructors='Five inert field-assigning constructors; eager facade assignments.',
     activeHttpHeaders='Retained in original relative member position.',
     dispose='Retained unchanged.'),indent=2)+'\n')
 assert len(set(GROUPS[0]['host_names']))==10,hosts[GROUPS[0]['name']]
 (R/'dev/tool/dart_moves/vplayer_p16.json').write_text(json.dumps(spec,indent=2)+'\n')
 (a.probe.parent/'membership.json').write_text(json.dumps(measured,indent=2)+'\n')
 (a.probe.parent/'hosts.json').write_text(json.dumps(hosts,indent=2)+'\n')
 from dart_move_history import earlier_sources,check_earlier
 history_errors=check_earlier(spec,a.parser_package)
 assert not history_errors,history_errors
 (a.probe.parent/'result.json').write_text(json.dumps(dict(label='FINAL',comparison_errors=errors,sizes=sizes,hosts={g['name']:dict(names=len(set(g['host_names'])),declarations=len(g['host_names'])) for g in GROUPS},protected_earlier_destinations=len(earlier_sources(spec)),patched_adapter='_VpIptvChannelSwitchHostAdapter.hideSourceSheet'),indent=2)+'\n')
 print('FINAL zero comparison differences',sizes,'all fifteen historical phases protected')

if __name__=='__main__':main()
