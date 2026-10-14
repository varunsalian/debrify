#!/usr/bin/env python3
"""Evidence-only PROVISIONAL P14 split; history must be regenerated after P13."""
import argparse,json,subprocess,re
from pathlib import Path
from check_verbatim_moves import ROOT as R,ensure_parser_package,parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest,check
from dart_move_partition import partition,frozen
from dart_move_history import git_text
from dart_move_fixture import edited_text
SOURCE='lib/screens/video_player_screen.dart';FEATURE='lib/features/video_player';STATE='_VideoPlayerScreenState';BASE='1d7699d2e'
GROUPS=[dict(name='VpResumeKeys',receiver='_resumeKeys',file='vp_resume_keys.dart',names=['_resumeKey','_torboxResumeKeyForEntry','_pikpakResumeKeyForEntry','_resumeIdForEntry']),dict(name='VpResumeRestore',receiver='_resumeRestore',file='vp_resume_restore.dart',names=['_maybeRestoreResume','_seekForResume','_verifyResumeLanding','_resumeSeekLanded']),dict(name='VpResumeSave',receiver='_resumeSave',file='vp_resume_save.dart',names=['_getEnhancedPlaybackState','_resumeSaveBlocked','_observeServerWatch','_saveResume','_saveResumeLocked'])]
TYPES={'_activePlaylist':'List<PlaylistEntry>?','_currentIndex':'int','_currentIptvIndex':'int','_effectiveContentEpisode':'int?','_effectiveContentImdbId':'String?','_effectiveContentSeason':'int?','_effectiveIptvChannels':'List<IptvChannel>?','_allowResumeForManualSelection':'bool','_duration':'Duration','_isAutoAdvancing':'bool','_isManualEpisodeSelection':'bool','_player':'mk.Player','_resumeVerifyEpoch':'int','_resumeWriteGuard':'ResumeWriteGuard','_screenDisposed':'bool','_currentIptvChannel':'IptvChannel?','_currentStreamUrl':'String?','_currentStremioTvContentTitle':'String?','_effectiveContentTitle':'String?','_effectiveContentType':'String?','_iptvGuideContextOverride':'IptvGuideContext?','_isPlaying':'bool','_isReady':'bool','_isTransitioning':'bool','_openedWatchSource':'Torrent?','_position':'Duration','_resumeSaveLock':'Lock','_seriesPlaylist':'SeriesPlaylist?','_serverWatch':'MediaServerWatchController','_validationGateActive':'bool'}
ACTIONS={'_waitForDuration':('Future<void> waitForDuration()','()'),'_traktSeasonEpisode':('({int? season, int? episode}) traktSeasonEpisode()','()'),'_getEnhancedPlaybackState':('Future<Map<String, dynamic>?> getEnhancedPlaybackState()','()'),'_resumeIdForEntry':('String resumeIdForEntry(PlaylistEntry entry)','(entry)'), '_resumeKey':('String get resumeKey','')}
WIDGET={'title':'String','videoUrl':'String','contentImdbId':'String?','iptvSourceId':'String?','resumePolicy':'PlaybackResumePolicy','traktProgressPercent':'double?','mdblistProgressPercent':'double?','simklProgressPercent':'double?'}
CHAINS=[]
for root,member,typ in [('_trakt','launchTraktPercentSpent','bool'),('_simkl','launchSimklPercentSpent','bool'),('_mdblist','launchMdblistPercentSpent','bool'),('_completion','currentLocalMovieImdbId','String?'),('_completion','currentMovieMarkedAsFinished','bool'),('_display','playbackSpeed','double'),('_display','aspectMode','AspectMode'),('_display','speedBeforeHold','double?')]:CHAINS.append(dict(before=[root,'.',member],name=member,type=typ))
for root,member in [('_trakt','currentEpisodeTraktPercent'),('_simkl','currentEpisodeSimklPercent'),('_mdblist','currentEpisodeMdblistPercent')]:CHAINS.append(dict(before=[root,'.',member],name=member,signature='Future<double?> '+member+'({bool forGuide = false})',args='(forGuide: forGuide)'))
CHAINS.append(dict(before=['_display','.','applyAspectVideoZoom'],name='applyAspectVideoZoom',signature='Future<void> applyAspectVideoZoom()',args='()'))
CHAINS.append(dict(before=['VideoPlayerScreen','.','readLocalResume'],name='readLocalResume',signature='Future<Map<String, dynamic>?> readLocalResume({required String? contentId, required String resumeKey, required Future<Map<String, dynamic>?> Function() enhanced})',args='(contentId: contentId, resumeKey: resumeKey, enhanced: enhanced)'))
IMPORTS={
'VpResumeKeys':"""import 'package:flutter/foundation.dart';
import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
""",
'VpResumeRestore':"""import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
""",
'VpResumeSave':"""import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/utils/series_parser.dart';
"""}
PATCHED=['_VpLocalCompletionHostAdapter','_VpDisplayModeHostAdapter','_VpSleepTimerHostAdapter']
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
   if n not in vals:continue
   typ=TYPES[n];write=any(vals[i+1:i+2] in [['='],['++'],['--']] for i in occurrences(vals,[n]));read=any(vals[i+1:i+2]!=['='] for i in occurrences(vals,[n]));name=n[1:]
   if read:g['forwarders'].append(typ+' get '+name+' => _s.'+n+';')
   if write:g['forwarders'].append('set '+name+'('+typ+' v) => _s.'+n+' = v;')
   g['hosts'].append(n);hostbindings['_host.'+name]=STATE+'.'+n
  for n,(signature,args) in ACTIONS.items():
   if n in vals and n not in g['names']:
    target='_s.'+(byname[n]['receiver']+'.'+n[1:] if n in byname else n);g['forwarders'].append(signature+' => '+target+args+';');g['hosts'].append(n);hostbindings['_host.'+n[1:]]=STATE+'.'+n
  if 'mounted' in vals:g['forwarders'].append('bool get mounted => _s.mounted;')
  for name,typ in WIDGET.items():
   if occurrences(vals,['widget','.',name]):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';')
  for c in CHAINS:
   indices=occurrences(vals,c['before'])
   if not indices:continue
   target=('' if c['name']=='readLocalResume' else '_s.')+''.join(c['before']);name=c['name']
   if 'type' in c:
    write=any(vals[i+len(c['before']):i+len(c['before'])+1]==['='] for i in indices);read=any(vals[i+len(c['before']):i+len(c['before'])+1]!=['='] for i in indices)
    if read:g['forwarders'].append(c['type']+' get '+name+' => '+target+';')
    if write:g['forwarders'].append('set '+name+'('+c['type']+' v) => '+target+' = v;')
   else:g['forwarders'].append(c['signature']+' => '+target+c['args']+';')
  names=[(re.search(r'\b(?:get|set)\s+(\w+)',f.split(' => ')[0]) or re.search(r'(\w+)\s*\(',f.split(' => ')[0])).group(1) for f in g['forwarders']];expected={'VpResumeKeys':(9,9),'VpResumeRestore':(27,31),'VpResumeSave':(37,37)}[g['name']];assert (len(set(names)),len(names))==expected,(g['name'],names,expected)
 spec.update(phase=14,status='PROVISIONAL',span_order=list(spans),patched_class_projection=PATCHED,provisional=dict(label='PROVISIONAL — no P13 history claim',preparation_base=BASE,required_regeneration='After accepted P13 merge: all facade/import/order/adapter proofs, frozen construction after P13, analyzer and mutation inputs; P13 manifest/history and S2d proof. No dummy manifest or history relaxation.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Complete live chain or static readLocalResume to exact facade Host projection') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={}),record_owners=[STATE],record_fields={STATE:[]},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None;mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in allnames};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping['mounted']=['_host','.','mounted']
  for n,after in mapping.items():
   if n in vals:edits+=name_edits(vals,n,after)
  if moved:
   for before,after in [(r['before'],r['after']) for r in registrations]:
    indices=occurrences(vals,before)
    if indices:edits.append(dict(before=before,after=after,count=len(indices)))
  if key in PATCHED:
   assert len(edits)==1 and edits[0]['count']==1,(key,edits);row.update(fate='patched',reason='PROVISIONAL P14 receiver rewrite; regenerate preserving P13 openPlayerMenuQuick rewrites on accepted P13 base.',test='dev/tool/test_dart_resume_moves.py',patches=edits);edits=[]
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='PROVISIONAL inert assignments after P12; regenerate after P13 assignments.',test='dev/tool/test_dart_resume_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._identifyUi'
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
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--probe',type=Path,required=True);a=p.parse_args();common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip());assert a.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p14')
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package);original,spec,sources,measured=build(a.parser_package);a.probe.mkdir(parents=True,exist_ok=True)
 for path,text in sources.items():
  out=a.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(text);subprocess.run(['nice','-n','19','dart','format',str(out)],check=True,stdout=subprocess.DEVNULL)
 formatted={path:(a.probe/path).read_text() for path in sources};errors=check(spec,original,formatted,a.parser_package);assert not errors,errors
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS};assert all(v<=500 for v in sizes.values()),sizes
 (R/'dev/tool/dart_moves/vplayer_p14.json').write_text(json.dumps(spec,indent=2)+'\n');(a.probe/'membership.json').write_text(json.dumps(measured,indent=2)+'\n');(a.probe/'hosts.json').write_text(json.dumps({g['name']:g['forwarders'] for g in GROUPS},indent=2)+'\n');(a.probe/'result.json').write_text(json.dumps(dict(label='PROVISIONAL',comparison_errors=errors,sizes=sizes,history='BLOCKED until accepted P13; no check_earlier claim',patched_adapters=PATCHED),indent=2)+'\n');print('PROVISIONAL zero comparison differences',sizes,'NO history claim')
if __name__=='__main__':main()
