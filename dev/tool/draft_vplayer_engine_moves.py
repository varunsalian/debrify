#!/usr/bin/env python3
"""FINAL P19 evidence-only materialization on the reviewed S2f checkpoint; never writes lib/.

Engine I: audio output, video-output lease, tvOS decode remedy/display match,
decoder probe and renderer fallback. Protects all eighteen applied phases.
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
from draft_vplayer_resume_moves import occurrences, name_edits
SOURCE='lib/screens/video_player_screen.dart'
FEATURE='lib/features/video_player'
STATE='_VideoPlayerScreenState'
# S2f reviewed checkpoint (c8c8a6ffc) plus its docs-only review fold.
BASE='4c97c4687'
EVIDENCE='refactor-evidence/vplayer/p19'
GROUPS=[
 dict(name='VpAudioOutput',receiver='_audioOutput',file='vp_audio_output.dart',names=['_audioEffectSessionId','_setExternalAudioTrack','_attachAudioEffectSession','_releaseAudioEffectSession','_passthroughFlipChain','_setAudioPassthroughLive','_applyPassthroughFlip','_configurePlayerAudio']),
 dict(name='VpVideoOutputLease',receiver='_videoOutputLease',file='vp_video_output_lease.dart',names=['_outputLease','_outputLeaseTimeout','_claimVideoOutput','_releaseVideoOutput']),
 dict(name='VpTvosVideo',receiver='_tvosVideo',file='vp_tvos_video.dart',names=['_lastTvosDisplayMatchSignature','_installTvosDecodeRemedy','_resetTvosDisplayMatchForMediaBoundary','_scheduleTvosDisplayMatch']),
 dict(name='VpDecoderProbe',receiver='_decoderProbe',file='vp_decoder_probe.dart',names=['_androidPlayerDiagnosticChannel','_mediaServerFrameGeneration','_handleDecoderProbeParams','_installDecoderObservers','_scheduleDecoderProbe','_reportActiveVideoDecoder','_emitDecoderDiagnosticOnce','_releasePlayerDiagnostic']),
 dict(name='VpRendererFallback',receiver='_rendererFallback',file='vp_renderer_fallback.dart',names=['_scheduleRendererStartupValidation','_validateRendererStartup','_canFallbackExplicitRenderer','_fallbackExplicitRendererToAutomatic']),
]
# Single-writer fields (frozen ownership table); both statics stay static.
FIELDS=['_audioEffectSessionId','_passthroughFlipChain','_outputLease','_outputLeaseTimeout','_lastTvosDisplayMatchSignature','_androidPlayerDiagnosticChannel','_mediaServerFrameGeneration']
TYPES={
 '_appleMultichannelEnabled':'bool','_audioPassthroughEnabled':'bool','_player':'mk.Player','_systemAudioEffectsEnabled':'bool','_tvosForceStereoAudio':'bool','_tvosLegacyAudioOutput':'bool','_tvosRouteOutputChannels':'int',
 '_screenDisposed':'bool','_contentDisplayMatchMode':'ContentDisplayMatchMode','_tvosDecodeRemedy':'TvosDecodeRemedy?','_tvosDisplayMatchTimer':'Timer?','_tvosDisplayMatchToken':'int',
 '_androidVideoRendererMode':'AndroidVideoRendererMode','_decoderProbeGeneration':'int','_decoderProbeParams':'mk.VideoParams?','_decoderProbeTimer':'Timer?','_decoderProbeToken':'int','_lastDecoderDiagnosticSignature':'String?','_openedWatchSource':'Torrent?','_playerInstanceGeneration':'int','_rendererStartupGuardToken':'int','_rendererStartupValidationGeneration':'int',
 '_activeExternalSubtitlePath':'String?','_activeMediaShouldPlay':'bool','_activeMediaUserPaused':'bool','_activeOpenedMedia':'mk.Media?','_currentIptvChannel':'IptvChannel?','_duration':'Duration','_iptvErrorsMuted':'bool','_isPlaying':'bool','_isReady':'bool','_isRecording':'bool','_isTransitioning':'bool','_pausedByLifecycle':'bool','_playerCreated':'bool','_position':'Duration','_rendererFallbackInProgress':'bool','_rendererValidatedForSession':'bool','_resumeVerifyEpoch':'int','_resumeWriteGuard':'ResumeWriteGuard','_showBufferingIndicator':'ValueNotifier<bool>','_sleepStopLatched':'bool','_stremioTvStartupSeek':'DeferredStartupSeek','_stremioTvStartupWatch':'ChannelStartupWatch?',
}
# State-owned statics read through a static Host getter (P15 iptvZapPageSize precedent).
STATICS={'_tvReleaseLogChannel':'MethodChannel'}
ACTIONS={
 '_createPlayerInstance':('void createPlayerInstance(AndroidVideoRendererMode rendererMode)','(rendererMode)'),
 '_cancelPlayerInstanceSubscriptions':('Future<void> cancelPlayerInstanceSubscriptions()','()'),
 '_openMedia':('Future<void> openMedia(mk.Media media, {required bool play, bool? desiredPlay, bool liveStream = false, EpisodePlaybackRequest? request, bool Function()? beforeOpen, Torrent? source, int? preserveStartupEpoch})','(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)'),
 # Sibling routing (moved in this phase): targets resolve to _s.<receiver>.<name>.
 '_scheduleDecoderProbe':('void scheduleDecoderProbe()','()'),
 '_resetTvosDisplayMatchForMediaBoundary':('void resetTvosDisplayMatchForMediaBoundary()','()'),
 '_scheduleTvosDisplayMatch':('void scheduleTvosDisplayMatch(mk.VideoParams params)','(params)'),
 '_scheduleRendererStartupValidation':('void scheduleRendererStartupValidation()','()'),
 '_attachAudioEffectSession':('Future<void> attachAudioEffectSession()','()'),
 '_claimVideoOutput':('Future<void> claimVideoOutput()','()'),
 '_configurePlayerAudio':('Future<void> configurePlayerAudio(mk.Player player)','(player)'),
 '_releaseAudioEffectSession':('void releaseAudioEffectSession()','()'),
 '_releasePlayerDiagnostic':('void releasePlayerDiagnostic(String fields)','(fields)'),
 '_setExternalAudioTrack':('Future<void> setExternalAudioTrack(String audioUrl)','(audioUrl)'),
}
WIDGET={'audioUrl':'String?'}
def chain(owner,member,forwarders,name=None):
 return dict(before=[owner,'.',member],name=name or member,forwarders=forwarders)
CHAINS=[
 # Live S2b/S2f projections (P1-1/P1-2): never cached; only the facade names VpS2Hooks.
 chain('VpS2Hooks','isAndroid',['bool get isAndroid => VpS2Hooks.isAndroid;']),
 chain('VpS2Hooks','isAndroidRendererValidation',['bool get isAndroidRendererValidation => VpS2Hooks.isAndroidRendererValidation;']),
 chain('_subtitleSync','subtitleAutoSync',['MediaKitSubtitleAutoSync? get subtitleAutoSync => _s._subtitleSync.subtitleAutoSync;']),
 chain('_subtitleSync','disposeSubtitleAutoSync',['Future<void> disposeSubtitleAutoSync() => _s._subtitleSync.disposeSubtitleAutoSync();']),
 chain('_subtitleSync','installSubtitleAutoSyncForPlayer',['void installSubtitleAutoSyncForPlayer(mk.Player player) => _s._subtitleSync.installSubtitleAutoSyncForPlayer(player);']),
 chain('_mediaWaits','waitForVideoReady',['Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();']),
 chain('_resumeRestore','seekForResume',['Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) => _s._resumeRestore.seekForResume(targetMs, verifyLanding: verifyLanding);']),
 chain('_trackPreferences','restoreTrackPreferences',['Future<void> restoreTrackPreferences() => _s._trackPreferences.restoreTrackPreferences();']),
 chain('_startupGate','watchStremioTvStartup',['void watchStremioTvStartup(String url) => _s._startupGate.watchStremioTvStartup(url);']),
 chain('_startupGate','reportStartupFailure',['Future<void> reportStartupFailure({bool Function()? isCurrent}) => _s._startupGate.reportStartupFailure(isCurrent: isCurrent);']),
]
# Earlier scaffolding adapters whose forwarders reach a moved member: receiver rewrites only.
PATCHED=['_VpSourceSwitchHostAdapter','_VpStartupGateHostAdapter','_VpPlayerMenuUiHostAdapter']
EXPECTED_HOSTS={'VpAudioOutput':(8,9),'VpVideoOutputLease':(1,1),'VpTvosVideo':(8,11),'VpDecoderProbe':(18,23),'VpRendererFallback':(50,57)}
def imp(*paths):return ''.join("import '"+x+";\n" if ' as ' in x else "import '"+x+"';\n" if x.startswith('dart:') else "import 'package:"+x+"';\n" if x.startswith(('flutter/','media_kit')) else "import 'package:debrify/"+x+"';\n" for x in paths)
IMPORTS={
 'VpAudioOutput':imp('dart:io','flutter/foundation.dart','package:media_kit/media_kit.dart\' as mk','services/audio_effect_session_service.dart','services/storage/player_settings_storage.dart','services/storage/subtitle_settings_storage.dart','utils/language_mapping.dart','utils/platform_util.dart','utils/player_audio_config.dart','screens/video_player/services/media_kit_subtitle_auto_sync.dart'),
 'VpVideoOutputLease':imp('dart:async','flutter/foundation.dart','utils/platform_util.dart','widgets/video_output_lease.dart'),
 'VpTvosVideo':imp('dart:async','flutter/foundation.dart','package:media_kit/media_kit.dart\' as mk','models/content_display_match_mode.dart','services/tvos_decode_remedy.dart','services/tvos_display_match_service.dart','utils/platform_util.dart'),
 'VpDecoderProbe':imp('dart:async','dart:io','flutter/foundation.dart','flutter/services.dart','services/source_selection_diagnostics.dart','package:media_kit/media_kit.dart\' as mk','models/android_video_renderer_mode.dart','models/torrent.dart','services/tvos_decode_remedy.dart','utils/platform_util.dart'),
 'VpRendererFallback':imp('dart:async','flutter/material.dart','package:media_kit/media_kit.dart\' as mk','models/android_video_renderer_mode.dart','models/iptv_playlist.dart','models/torrent.dart','services/resume_write_guard.dart','services/startup_stream_policy.dart','services/storage/player_settings_storage.dart','utils/episode_playback_request.dart','utils/platform_util.dart','screens/video_player/services/android_renderer_startup_fallback.dart'),
}
DROP={'VpDecoderProbe':['flutter/foundation.dart']}
for c,drops in DROP.items():
 IMPORTS[c]=''.join(l+'\n' for l in IMPORTS[c].splitlines() if not any(d in l for d in drops))

def sorted_imports(block):
 """P16 layout: dart: section, blank line, sorted package: section."""
 lines=sorted(set(l for l in block.splitlines() if l))
 dart=[l for l in lines if l.startswith("import 'dart:")];rest=[l for l in lines if l not in dart]
 return '\n\n'.join('\n'.join(x) for x in (dart,rest) if x)+'\n'

def host_name(f):
 head=f.split(' => ')[0]
 return (re.search(r'\b(?:get|set)\s+(\w+)',head) or re.search(r'(\w+)\s*\(',head)).group(1)

def build(package):
 original=git_text(BASE,SOURCE)
 spec=retained_manifest(SOURCE,FEATURE,original,BASE,package)
 u=parse({'base':original},package,ownership=True)['base']
 spans,_,nodes=partition(u,[STATE])
 byname={n:g for g in GROUPS for n in g['names']}
 hostbindings={};measured=[]
 for g in GROUPS:
  g['dest']=FEATURE+'/presentation/legacy_video_player/'+g['file'];g['forwarders']=[];g['hosts']=[]
  vals=[v for n in g['names'] for v in tokens(spans[STATE+'.'+n])]
  for n,typ in sorted(TYPES.items()):
   if n not in vals:continue
   indices=occurrences(vals,[n]);write=any(vals[i+1] in ['=','++','--','??=','+='] or vals[i-1] in ['++','--'] for i in indices);read=any(vals[i+1] not in ['='] for i in indices);name=n[1:]
   if read:g['forwarders'].append(typ+' get '+name+' => _s.'+n+';')
   if write:g['forwarders'].append('set '+name+'('+typ+' v) => _s.'+n+' = v;')
   g['hosts'].append(n);hostbindings['_host.'+name]=STATE+'.'+n
  for n,typ in STATICS.items():
   if n not in vals:continue
   g['forwarders'].append(typ+' get '+n[1:]+' => '+STATE+'.'+n+';');g['hosts'].append(n);hostbindings['_host.'+n[1:]]=STATE+'.'+n
  for n,(sig,args) in ACTIONS.items():
   if n not in vals or n in g['names']:continue
   target='_s.'+(byname[n]['receiver']+'.'+n[1:] if n in byname else n)
   g['forwarders'].append(sig+' => '+target+args+';');g['hosts'].append(n);hostbindings['_host.'+n[1:]]=STATE+'.'+n
  for n,sig,target in [('mounted','bool get mounted','_s.mounted'),('context','BuildContext get context','_s.context'),('setState','void setState(VoidCallback fn)','_s._vpSetState(fn)')]:
   if n in vals:g['forwarders'].append(sig+' => '+target+';')
  for name,typ in WIDGET.items():
   if occurrences(vals,['widget','.',name]):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';')
  for c in CHAINS:
   if occurrences(vals,c['before']):g['forwarders']+=c['forwarders']
  g['host_names']=[host_name(f) for f in g['forwarders']]
  assert len(g['forwarders'])==len(set(g['forwarders'])),g['name']
  if EXPECTED_HOSTS is not None:assert (len(set(g['host_names'])),len(g['host_names']))==EXPECTED_HOSTS[g['name']],(g['name'],g['host_names'])
 spec.update(phase=19,status='applied',span_order=list(spans),patched_class_projection=PATCHED,finalization=dict(label='FINAL',preparation_base=BASE,accepted_p18='46bc00ce7',seam_original=BASE,history='All eighteen applied phases; every earlier destination derived without a whitelist.'),provisional=dict(label='FINAL',preparation_base=BASE,pending=[],host_contracts={g['name']:g['forwarders'] for g in GROUPS},construction='Final assignments follow all ten P18 collaborators.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Live S2b/S2f projection' if c['before'][0]=='VpS2Hooks' else 'Complete live collaborator chain via facade routing') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:byname[n]['name'] for n in FIELDS}),record_owners=[STATE],record_fields={STATE:FIELDS},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],adapter_state_prefixes=['_s'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 retained_sites=[];patched=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None
  mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in byname};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping.update({n:['_host','.',n] for n in ['mounted','context','setState']})
  for n,after in mapping.items():
   if n not in vals:continue
   edits+=name_edits(vals,n,after)
  if moved:
   for r in registrations:
    count=len(occurrences(vals,r['before']))
    if count:edits.append(dict(before=r['before'],after=r['after'],count=count))
  else:
   for tok in spans[key]['tokens']:
    if not tok.get('comment') and tok['text'] in byname:
     retained_sites.append(dict(declaration=key,member=tok['text'],offset=tok['offset'],line=original[:tok['offset']].count('\n')+1,substitution=byname[tok['text']]['receiver']+'.'+tok['text'][1:]))
  if not moved and not key.startswith(STATE+'.') and edits:
   assert key in PATCHED and all(e['count']==1 for e in edits),(key,edits)
   row.update(fate='patched',reason='Route the P16/P17 adapter forwarder to its P19 owner, preserving every earlier rewrite.',test='dev/tool/draft_vplayer_engine_moves.py',patches=sorted(edits,key=lambda e:json.dumps(e['before'])));patched.append(key);measured.append(dict(declaration=key,fate='patched',edits=edits));edits=[]
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Five inert eager assignments after all ten accepted P18 collaborators.',test='dev/tool/draft_vplayer_engine_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 assert sorted(patched)==sorted(PATCHED),patched
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._metadataPreload'
 for i,g in enumerate(GROUPS):
  host=g['name']+'Host';adapter='_'+host+'Adapter';key=STATE+'.'+g['receiver'];scaff['@directive:'+str(len(u['directives'])+i)]="import '../"+g['dest'][4:]+"';";scaff[key]='late final '+g['name']+' '+g['receiver']+';';scaff[adapter]='class '+adapter+' implements '+host+' {\n  '+adapter+'(this._s);\n  final _VideoPlayerScreenState _s;\n'+''.join('  @override\n  '+f+'\n' for f in g['forwarders'])+'}\n';at=spec['span_order'].index(previous)+1;spec['span_order'].insert(at,key);previous=key
 for key in scaff:
  if key.startswith('@directive:'):spec['span_order'].insert(next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:')),key)
  elif not key.startswith(STATE+'.'):spec['span_order'].insert(spec['span_order'].index(STATE+':close')+1,key)
 bykey={r['original']:r for r in spec['declarations']};facade=''.join(scaff[k]+'\n' if k in scaff else edited_text(original,spans[k],bykey[k].get('substitutions',[])+bykey[k].get('patches',[])) for k in spec['span_order']);pu=parse({SOURCE:facade},package,ownership=True)[SOURCE];physical,orders,_=partition(pu,[STATE]);spec['facade_orders']=orders;spec['facade_directives']=pu['directives'];spec['scaffolding'][SOURCE]=frozen({k:physical[k] for k in scaff});sources={SOURCE:facade}
 for g in GROUPS:
  c=g['name'];host=c+'Host';dest=sorted_imports(IMPORTS[c])+'abstract interface class '+host+' {\n'+''.join('  '+f.split(' => ')[0]+';\n' for f in g['forwarders'])+'}\n\nclass '+c+' {\n  '+c+'(this._host);\n  final '+host+' _host;\n'
  for row in spec['declarations']:
   if row['fate']=='moved' and row['destination']==g['dest']:dest+=edited_text(original,spans[row['original']],row.get('substitutions',[]))
  dest+='\n}\n';sources[g['dest']]=dest;pu=parse({g['dest']:dest},package,ownership=True)[g['dest']];physical,orders,_=partition(pu,[c]);targets={r['target'] for r in spec['declarations'] if r['fate']=='moved' and r['destination']==g['dest']};spec['destinations'][g['dest']]=dict(directives=pu['directives'],orders=orders,span_order=list(physical),split_containers=[c]);spec['scaffolding'][g['dest']]=frozen({k:v for k,v in physical.items() if k not in targets})
 return original,spec,sources,measured,retained_sites

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--probe',type=Path,required=True);p.add_argument('--no-check',action='store_true');a=p.parse_args();common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip());assert a.probe.resolve().is_relative_to(common/EVIDENCE)
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package);original,spec,sources,measured,sites=build(a.parser_package);a.probe.mkdir(parents=True,exist_ok=True)
 for path,content in sources.items():
  out=a.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(content)
 subprocess.run(['nice','-n','19','dart','format',*[str(a.probe/p) for p in sources]],check=True,stdout=subprocess.DEVNULL)
 formatted={path:(a.probe/path).read_text() for path in sources}
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS};sizes['facade']=len(formatted[SOURCE].splitlines())
 errors=[] if a.no_check else check(spec,original,formatted,a.parser_package)
 hosts={g['name']:dict(names=len(set(g['host_names'])),declarations=len(g['host_names'])) for g in GROUPS}
 if not a.no_check and not errors and all(v<=500 for k,v in sizes.items() if k!='facade'):(R/'dev/tool/dart_moves/vplayer_p19.json').write_text(json.dumps(spec,indent=2)+'\n')
 for file,value in [('membership.json',measured),('retained-sites.json',sites),('hosts.json',spec['provisional']['host_contracts']),('spec.json',spec),('result.json',dict(label='FINAL',comparison_errors=errors,sizes=sizes,hosts=hosts,retained_references=len(sites)))]: (a.probe/file).write_text(json.dumps(value,indent=2)+'\n')
 print('FINAL differences',len(errors),sizes,hosts,'retained',len(sites))
 for e in errors[:40]:print(' ',e)
 assert all(v<=500 for k,v in sizes.items() if k!='facade'),sizes
if __name__=='__main__':main()
