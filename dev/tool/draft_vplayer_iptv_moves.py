#!/usr/bin/env python3
"""FINAL P15 materialization on accepted P14; production writes are separate."""
import argparse
import json
import re
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT, ensure_parser_package, parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest, check
from dart_move_partition import partition, frozen
from dart_move_history import git_text
from dart_move_fixture import edited_text, materialize
SOURCE = 'lib/screens/video_player_screen.dart'
FEATURE = 'lib/features/video_player'
STATE = '_VideoPlayerScreenState'
BASE = 'be4cd78aa'
GROUPS = [
 dict(name='VpIptvZapRing', receiver='_zapRing', file='vp_iptv_zap_ring.dart', fields=3, names=['_iptvZapSourceId','_iptvZapRequestTicket','_iptvZapArmingPaging','_reanchorIptvRingToCategory','_canZapIptvChannel','_resetIptvZapPaging','_ensureIptvZapPagingArmed','_requestIptvZapPage','_parseIptvZapPage','_installIptvZapWindow','_mergeIptvZapPage']),
 dict(name='VpIptvZapLadder', receiver='_zapLadder', file='vp_iptv_zap_ladder.dart', fields=5, names=['_kIptvZapEdgeMargin','_iptvZapDrainingInputs','_iptvZapCachedOriginCategory','_iptvZapCachedDirection','_iptvZapCachedPage','_clearIptvZapBoundaryCache','_zapIptvChannel','_prefetchIptvZapPage','_adjacentIptvCategory','_prefetchAdjacentIptvCategory','_consumeCachedAdjacentIptvCategory','_enterIptvZapCategory','_requestAdjacentIptvCategory','_queuePendingIptvZapInput','_drainPendingIptvZapInputs']),
 dict(name='VpIptvGuideCatchup', receiver='_iptvGuide', file='vp_iptv_guide_catchup.dart', fields=1, names=['_iptvCatchupRequests','_iptvStartOverTimelineVisible','_toggleIptvStartOverTimeline','_canStartOverCurrentIptv','_iptvLiveEdgeAction','_toggleIptvStartOver','_startIptvProgrammeFromBeginning','_persistIptvGuideContext','_anchorIptvGuideCategory','_applyIptvGuideCategory','_cancelPendingIptvCatchup','_beginIptvCatchupRequest','_isCurrentIptvCatchupRequest','_showIptvChannelSheetOverlay','_hideIptvChannelSheet','_switchToIptvGuideChannel','_playIptvCatchup']),
 dict(name='VpIptvChannelSwitch', receiver='_iptvSwitch', file='vp_iptv_channel_switch.dart', fields=0, names=['_iptvRecoveryEligible','_performIptvLiveRetune','_switchToIptvChannel','_switchToIptvSource']),
 dict(name='VpIptvLiveSources', receiver='_iptvSources', file='vp_iptv_live_sources.dart', fields=0, names=['_onIptvStreamError','_setIptvSources','_initIptvStremioSources','_tryOpenLiveStream']),
 dict(name='VpIptvWatchMemory', receiver='_iptvMemory', file='vp_iptv_watch_memory.dart', fields=4, names=['_lastLiveChannelTimer','_lastLiveChannelArmedUrl','_lastLiveChannelSettle','_preferredIptvAudioLanguage','_noteLiveChannelPlaying','_iptvSeriesAudioKey','_captureIptvAudioLanguage','_applyIptvAudioPreference','_recordIptvWatchForChannel']),
 dict(name='VpIptvZapBanner', receiver='_iptvBanner', file='vp_iptv_zap_banner.dart', fields=4, names=['_iptvZapHideTimer','_iptvZapTicker','_iptvZapEpgTicket','_iptvArchiveRetryAt','_prepareIptvBannerData','_raiseIptvZapBanner','_hideIptvZapBanner','_syncIptvBannerTicker','_refreshIptvBannerEpgIfEnded','_loadIptvZapBannerEpg']),
]

# Method signatures preserve all defaults; forwarders remain synchronous.
ARGS = {
 '_anchorIptvGuideCategory':'(channel, categories: categories)',
 '_clearIptvZapBoundaryCache':'()', '_applyIptvGuideCategory':'(category, categories)',
 '_ensureIptvZapPagingArmed':'()',
 '_installIptvZapWindow':'(page, preservePlayingChannel: preservePlayingChannel)',
 '_mergeIptvZapPage':'(page)',
 '_requestIptvZapPage':'(category: category, offset: offset, fromEnd: fromEnd)',
 '_switchToIptvChannel':'(index, quietRecovery: quietRecovery)',
 '_hideIptvZapBanner':'(immediate: immediate)',
 '_iptvRecoveryEligible':'()',
 '_openMedia':'(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)',
 '_reanchorIptvRingToCategory':'(channel, switchTicket: switchTicket)',
 '_resetIptvZapPaging':'()', '_scheduleAutoHide':'()',
 '_stopRecording':'(userInitiated: userInitiated)',
 '_applyIptvAudioPreference':'(ticket)',
 '_cancelPendingIptvCatchup':'(hideFeedback: hideFeedback)',
 '_clearBufferingIndicator':'()', '_hideIptvChannelSheet':'()',
 '_hideSourceSheet':'()', '_prepareIptvBannerData':'(channel)',
 '_raiseIptvZapBanner':'()', '_recordIptvWatchForChannel':'(channel)',
 '_refreshEngineRecordingState':'()',
 '_setIptvSources':'(channelKey, candidates, currentIndex: currentIndex)',
 '_startTransitionOverlay':'()',
 '_tryOpenLiveStream':'(url, timeout: timeout, httpHeaders: httpHeaders)',
 '_tvAbandonScrub':'()',
}
WIDGET_TYPES = dict(iptvBrowseProvider='Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?',
 iptvSourceId='String?', iptvCategories='List<String>?', iptvContentType='String?',
 iptvSourceName='String?', iptvStartIndex='int?', videoUrl='String')
IMPORTS = {
 'Timer':"import 'dart:async';", 'unawaited':"import 'dart:async';",
 'Completer':"import 'dart:async';", 'StreamSubscription':"import 'dart:async';",
 'math':"import 'dart:math' as math;",
 'mk':"import 'package:media_kit/media_kit.dart' as mk;",
 **{n:"import 'package:flutter/material.dart';" for n in ['BuildContext','VoidCallback','ValueNotifier','FocusNode','AnimationController','ScaffoldMessenger','SnackBar','Text','WidgetsBinding']},
 'listEquals':"import 'package:flutter/foundation.dart';",
 'debugPrint':"import 'package:flutter/foundation.dart';",
 'iptvAdjacentZapCategory':"import 'package:debrify/utils/iptv_player_paging.dart';",
 'IptvChannel':"import 'package:debrify/models/iptv_playlist.dart';",
 'IptvGuideContext':"import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';",
 'VpIptvZapPage':"import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';",
 'IptvCatchupRequestGate':"import 'package:debrify/features/video_player/models/iptv_catchup_request_gate.dart';",
 'iptvChannelFromBrowsePayload':"import 'package:debrify/utils/iptv_player_paging.dart';",
 'iptvMergeZapWindow':"import 'package:debrify/utils/iptv_player_paging.dart';",
 'StremioIptvService':"import 'package:debrify/services/stremio_iptv_service.dart';",
 'StremioIptvCandidate':"import 'package:debrify/services/stremio_iptv_service.dart';",
 **{n:"import 'package:debrify/models/torrent.dart';" for n in ['Torrent','StreamType']},
 **{n:"import 'package:debrify/services/iptv_epg_service.dart';" for n in ['IptvEpgService','EpgProgramme','EpgNowNext']},
 'PlatformUtil':"import 'package:debrify/utils/platform_util.dart';",
 'IptvTuneDiagnostics':"import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';",
 'IptvLiveRecovery':"import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';",
 'ResumeWriteGuard':"import 'package:debrify/services/resume_write_guard.dart';",
 'SleepTimerMode':"import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';",
 'EpisodePlaybackRequest':"import 'package:debrify/utils/episode_playback_request.dart';",
 'IptvHistoryStorage':"import 'package:debrify/services/storage/iptv_history_storage.dart';",
 'IptvAudioStorage':"import 'package:debrify/services/storage/iptv_audio_storage.dart';",
 'IptvLastChannelStorage':"import 'package:debrify/services/storage/iptv_last_channel_storage.dart';",
 'SubtitleSettingsStorage':"import 'package:debrify/services/storage/subtitle_settings_storage.dart';",
 'LanguageMapper':"import 'package:debrify/screens/video_player/utils/language_mapping.dart';",
}

EARLIER = [
 ('_recording','stopRecording','Future<void> stopRecording({bool userInitiated = true})','(userInitiated: userInitiated)'),
 ('_recording','refreshEngineRecordingState','Future<void> refreshEngineRecordingState()','()'),
 ('_recording','engineFlagOn','bool get engineFlagOn',''),
]

def public(name):
 return 'iptvZapPageSize' if name == '_kIptvZapPageSize' else name.removeprefix('_')

def signature(node, name):
 code = [t['text'] for t in node['tokens'] if not t['comment']]
 at=code.index(name)
 if code[at-1]=='get':
  return ' '.join(code[:at-1]), True
 if node['kind']=='FieldDeclarationImpl':
  return ' '.join(t for t in code[:at] if t not in ['static','const','final','late']), True
 level=0; end=None
 for i in range(at+1,len(code)):
  if code[i]=='(':level+=1
  if code[i]==')':
   level-=1
   if level==0:end=i;break
 assert end is not None,name
 return ' '.join(code[:at]+[public(name)]+code[at+1:end+1]),False

def build(package):
 original=git_text(BASE,SOURCE)
 spec=retained_manifest(SOURCE,FEATURE,original,BASE,package)
 unit=parse({'base':original},package,ownership=True)['base']
 spans,_,nodes=partition(unit,[STATE])
 owners={n:g for g in GROUPS for n in g['names']}
 members={k[len(STATE)+1:]:v for k,v in nodes.items() if k.startswith(STATE+'.')}
 bindings={};selectors=set();retained=[]
 for g in GROUPS:
  g['dest']=FEATURE+'/presentation/legacy_video_player/'+g['file']
  needed=set();reads=set();writes=set();values=[]
  for n in g['names']:
   v=tokens(spans[STATE+'.'+n]);values+=v
   needed.update(x for x in v if x in members and x not in g['names'])
   for i,x in enumerate(v):
    if x not in members:continue
    following=v[i+1] if i+1<len(v) else ''
    if following!='=':reads.add(x)
    if following in ['=','++','--','+=','-='] or i and v[i-1] in ['++','--']:writes.add(x)
  needed.difference_update(['_sleep','_recording','_recordingResources'])
  g['needed']=sorted(needed);g['forwarders']=[]
  for n in sorted(needed):
   sig,prop=signature(members[n],n)
   if prop:
    if n in reads:g['forwarders'].append(sig+' get '+public(n)+' => '+('_VideoPlayerScreenState.' if n=='_kIptvZapPageSize' else '_s.')+n+';')
    if n in writes:g['forwarders'].append('set '+public(n)+'('+sig+' v) => _s.'+n+' = v;')
   else:
    owner=owners.get(n);target=('_s.'+owner['receiver']+'.'+public(n)) if owner else '_s.'+n
    g['forwarders'].append(sig+' => '+target+ARGS[n]+';')
   bindings['_host.'+public(n)]=STATE+'.'+n
  for n,typ in [('mounted','bool'),('context','BuildContext')]:
   if n in values and not (n=='context' and g['name']=='VpIptvZapRing'):
    g['forwarders'].append(typ+' get '+n+' => _s.'+n+';')
  if 'setState' in values:g['forwarders'].append('void setState(VoidCallback fn) => _s._vpSetState(fn);')
  for n,typ in WIDGET_TYPES.items():
   if any(values[i:i+3]==['widget','.',n] for i in range(len(values))):
    g['forwarders'].append(typ+' get '+n+' => _s.widget.'+n+';');selectors.add(n)
  if '_sleep' in values:g['forwarders'].append('SleepTimerMode get sleepTimerMode => _s._sleep.sleepTimerMode;')
  for receiver,member,sig,args in EARLIER:
   if receiver in values and member in values:
    g['forwarders'].append(sig+' => _s.'+receiver+'.'+member+args+';')
  # Preserve the reviewed Host declaration order and spellings when a prior
  # extraction changes a State method into a complete collaborator chain.
  expected=json.loads((ROOT/'dev/tool/dart_moves/vplayer_p15_hosts.json').read_text())['hosts'][g['name']]
  canonical=lambda sig:tuple(re.findall(r'[A-Za-z_]\w*|[0-9]+|\S',sig))
  actual={canonical(f.split(' => ')[0]):f.split(' => ',1)[1] for f in g['forwarders']}
  assert set(actual)=={canonical(sig) for sig in expected},(g['name'],set(actual)-{canonical(sig) for sig in expected},{canonical(sig) for sig in expected}-set(actual))
  g['forwarders']=[sig+' => '+actual[canonical(sig)] for sig in expected]
 spec.update(phase=15,status='FINAL',finalization=dict(accepted_p14_base=BASE,accepted_p13='238df16f4',preparation_base='1d7699d2e',history='All fourteen applied phases; every earlier destination derived without a whitelist.'),patched_class_projection=['_VpTrackPreferencesHostAdapter','_VpPipLifecycleHostAdapter','_VpPlayerMenuUiHostAdapter','_VpPlayerMenuHostAdapter'])
 fields={n:g['name'] for g in GROUPS for n in g['names'][:g['fields']]}
 chain=dict(before=['_sleep','.','sleepTimerMode'],after=['_host','.','sleepTimerMode'],binding='unbound',role_change='Live sleep state projection')
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:owner for n,owner in fields.items()}),record_owners=[STATE],record_fields={STATE:list(fields)},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[public(n) for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=bindings,registered_occurrence_substitutions=[chain]+[dict(before=[receiver,'.',member],after=['_host','.',member],binding='unbound',role_change='Live accepted P13 recording projection') for receiver,member,_,_ in EARLIER]+[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='Live widget selector') for n in sorted(selectors)])
 for row in spec['declarations']:
  key=row['original'];g=owners.get(key[len(STATE)+1:]) if key.startswith(STATE+'.') else None
  v=tokens(spans[key]);edits=[]
  mapping={n:([public(n)] if g and owners[n] is g else ['_host','.',public(n)] if g else [owners[n]['receiver'],'.',public(n)]) for n in owners}
  if g:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+public(key.split('.')[-1]))
   mapping.update({n:['_host','.',public(n)] for n in g['needed']})
   mapping.update(mounted=['_host','.','mounted'],setState=['_host','.','setState'])
   if key!=STATE+'._persistIptvGuideContext':mapping['context']=['_host','.','context']
  for n,after in mapping.items():
   count=v.count(n)
   if count:
    assert not any(v[i:i+2]==['$',n] for i in range(len(v))),(key,n,'interpolation')
    edits.append(dict(before=[n],after=after,count=count))
  if g:
   for before,after in [(chain['before'],chain['after']), *[([receiver,'.',member],['_host','.',member]) for receiver,member,_,_ in EARLIER], *[(['widget','.',n],['_host','.',n]) for n in sorted(selectors)]]:
    count=sum(v[i:i+len(before)]==before for i in range(len(v)))
    if count:edits.append(dict(before=before,after=after,count=count))
  if key in spec['patched_class_projection'] and edits:
   row.update(fate='patched',reason='Redirect approved P8/P11/P13 IPTV actions on accepted P14; preserve all earlier rewrites and the State-owned P11 ticket.',test='dev/tool/draft_vplayer_iptv_moves.py',patches=edits)
  elif edits:row['substitutions']=edits
  if edits and not g:
   for edit in edits:
    ts=spans[key]['tokens']; before=edit['before']
    for i,t in enumerate(ts):
     if [q['text'] for q in ts[i:i+len(before)]]==before:
      retained.append(dict(declaration=key,line=original[:t['offset']].count('\n')+1,offset=t['offset'],before=before,after=edit['after']))
  if key==STATE+'.'+STATE:
   append=[t for g2 in GROUPS for t in [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']]
   row.update(fate='patched',reason='Seven eager inert assignments after all accepted P14 collaborators.',test='dev/tool/draft_vplayer_iptv_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
  if 'substitutions' in row:row['substitutions'].sort(key=lambda e:json.dumps(e['before']))
 spec['span_order']=[k for k in spans if k not in {r['original'] for r in spec['declarations'] if r['fate']=='moved'}]
 scaffold={};previous=STATE+'._resumeSave'
 for i,g in enumerate(GROUPS):
  host=g['name']+'Host';adapter='_'+host+'Adapter';key=STATE+'.'+g['receiver']
  scaffold['@directive:'+str(len(unit['directives'])+i)]="import '../"+g['dest'][4:]+"';"
  scaffold[key]='late final '+g['name']+' '+g['receiver']+';'
  scaffold[adapter]='class '+adapter+' implements '+host+' {\n  '+adapter+'(this._s);\n  final _VideoPlayerScreenState _s;\n'+''.join('  @override\n  '+f+'\n' for f in g['forwarders'])+'}\n'
  spec['span_order'].insert(spec['span_order'].index(previous)+1,key);previous=key
 for key in scaffold:
  if key.startswith('@directive:'):spec['span_order'].insert(next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:')),key)
  elif not key.startswith(STATE+'.'):spec['span_order'].insert(spec['span_order'].index(STATE+':close')+1,key)
 bykey={r['original']:r for r in spec['declarations']}
 facade=''.join(scaffold[k]+'\n' if k in scaffold else edited_text(original,spans[k],bykey[k].get('substitutions',[])+bykey[k].get('patches',[])) for k in spec['span_order'])
 parsed=parse({SOURCE:facade},package,ownership=True)[SOURCE];physical,orders,_=partition(parsed,[STATE]);spec['facade_orders']=orders;spec['facade_directives']=parsed['directives'];spec['scaffolding'][SOURCE]=frozen({k:physical[k] for k in scaffold})
 for g in GROUPS:
  c=g['name'];host=c+'Host'
  dest='abstract interface class '+host+' {\n'+''.join('  '+f.split(' => ')[0]+';\n' for f in g['forwarders'])+'}\n\nclass '+c+' {\n  '+c+'(this._host);\n  final '+host+' _host;\n'
  values=set()
  for row in spec['declarations']:
   if row['fate']=='moved' and row['destination']==g['dest']:
    dest+=edited_text(original,spans[row['original']],row.get('substitutions',[]));values.update(tokens(spans[row['original']]))
  for f in g['forwarders']:
   values.update(re.findall(r'[A-Za-z_]\w*',f))
  dest='\n'.join(sorted({imp for symbol,imp in IMPORTS.items() if symbol in values}))+'\n\n'+dest+'\n}\n'
  parsed=parse({g['dest']:dest},package,ownership=True)[g['dest']];physical,orders,_=partition(parsed,[c]);targets={r['target'] for r in spec['declarations'] if r['fate']=='moved' and r['destination']==g['dest']}
  spec['destinations'][g['dest']]=dict(directives=parsed['directives'],orders=orders,span_order=list(physical),split_containers=[c]);spec['scaffolding'][g['dest']]=frozen({k:v for k,v in physical.items() if k not in targets})
 return original,spec,retained

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--parser-package',type=Path,required=True)
 parser.add_argument('--probe',type=Path,required=True)
 args=parser.parse_args()
 common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip())
 assert args.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p15')
 assert args.parser_package.resolve().is_relative_to(ROOT/'.dart_tool/vplayer_parser')
 ensure_parser_package(args.parser_package.parents[1],args.parser_package)
 original,spec,retained=build(args.parser_package)
 frozen_hosts=ROOT/'dev/tool/dart_moves/vplayer_p15_hosts.json'
 if frozen_hosts.exists():
  assert {g['name']:[f.split(' => ')[0] for f in g['forwarders']] for g in GROUPS} == json.loads(frozen_hosts.read_text())['hosts'], 'frozen Host drift'
 sources=materialize(spec,original,args.parser_package)
 args.probe.mkdir(parents=True,exist_ok=True)
 for path,content in sources.items():
  out=args.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(content)
  subprocess.run(['nice','-n','19','dart','format',str(out)],check=True,stdout=subprocess.DEVNULL)
 formatted={p:(args.probe/p).read_text() for p in sources}
 errors=check(spec,original,formatted,args.parser_package)
 (args.probe/'comparison.json').write_text(json.dumps(errors,indent=2)+'\n')
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS}
 result=dict(status='FINAL',base=BASE,history_satisfied=True,protected_earlier_destinations=len(__import__('dart_move_history').earlier_sources(spec)),sizes=sizes,hosts={g['name']:[f.split(' => ')[0] for f in g['forwarders']] for g in GROUPS},adapters_to_regenerate=['_VpPipLifecycleHostAdapter','_VpPlayerMenuUiHostAdapter','_VpPlayerMenuHostAdapter','_VpTrackPreferencesHostAdapter'])
 (args.probe/'hosts-and-sizes.json').write_text(json.dumps(result,indent=2)+'\n')
 (args.probe/'retained-sites.json').write_text(json.dumps(retained,indent=2)+'\n')
 (ROOT/'dev/tool/dart_moves/vplayer_p15.json').write_text(json.dumps(spec,indent=2)+'\n')
 assert not errors,'\n'.join(errors)
 assert all(v<=500 for v in sizes.values()),sizes
 print('PASS FINAL body/ownership comparison:',sizes,len(retained),'retained sites')

if __name__=='__main__': main()
