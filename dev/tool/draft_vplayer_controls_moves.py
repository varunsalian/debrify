#!/usr/bin/env python3
"""PROVISIONAL P21 (21a) evidence-only materialization on the phase-20 merge; never writes lib/.

Controls runtime: chrome visibility and auto-hide, the TV remote's key routing
and cinema scrub, touch/pointer gestures, dock preferences and geometry
invalidation, and the transition/buffering overlay actions. Protects all
twenty applied phases.
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
# Phase-20 merge; the phase-21 branch changes no lib/ file before step 1.
BASE='5214f7a7e'
EVIDENCE='refactor-evidence/vplayer/p21'
# Construction order (design "Scaffolding"): transition, dock, controls, remote, gestures.
GROUPS=[
 dict(name='VpTransitionOverlay',receiver='_transitionOverlay',file='vp_transition_overlay.dart',names=['_tvStaticMessages','_startTransitionOverlay','_clearBufferingIndicator']),
 dict(name='VpDockLayout',receiver='_dockLayout',file='vp_dock_layout.dart',names=['_dockGeometrySignature','_lastDockGeometrySignature','_refreshDockGeometry','_loadDockPrefs']),
 dict(name='VpControlsRuntime',receiver='_controlsRuntime',file='vp_controls_runtime.dart',names=['_tvReleaseFocusForOverlay','_tvAutoHideBlocked','_scheduleAutoHide','_tvShowBar','_tvHideBar','_closeTopPlayerOverlay','_toggleControls','_onControlsVisibilityChanged','_togglePlay','_wakeControlsOnPointer']),
 dict(name='VpTvRemote',receiver='_tvRemote',file='vp_tv_remote.dart',names=['_tvLastArrowAt','_tvScrubWasPlaying','_tvScrubRepeats','_tvScrubStartedAtGeneration','_tvScrubBegin','_tvScrubStep','_tvScrubCommit','_tvAbandonScrub','_tvScrubCancel','_openTvGuide','_handleTvKey']),
 dict(name='VpPlayerGestures',receiver='_gestures',file='vp_player_gestures.dart',names=['_panIgnore','_mode','_gestureStartPosition','_gestureStartVideoPosition','_gestureStartVolume','_gestureStartBrightness','_handleDoubleTap','_onPanStart','_onPanUpdate','_onPanEnd']),
]
# Single-writer fields (frozen field ownership table, 21a).
FIELDS=['_tvStaticMessages','_lastDockGeometrySignature','_tvAutoHideBlocked','_tvLastArrowAt','_tvScrubWasPlaying','_tvScrubRepeats','_tvScrubStartedAtGeneration','_panIgnore','_mode','_gestureStartPosition','_gestureStartVideoPosition','_gestureStartVolume','_gestureStartBrightness']
TYPES={
 '_activeMediaShouldPlay':'bool','_activeMediaUserPaused':'bool','_anyPlayerOverlayOpen':'bool','_bufferingDebounceTimer':'Timer?','_channelEntries':'List<ChannelEntry>','_controlsVisible':'ValueNotifier<bool>',
 '_dockExtent':'ValueNotifier<double>','_dockGeometryGeneration':'int','_dockPalette':'PlayerDockPalette','_dockSize':'PlayerDockSize','_dockStyle':'PlayerDockStyle','_duration':'Duration',
 '_effectiveIptvChannels':'List<IptvChannel>?','_engineFlagOn':'bool','_hasStremioTvGuide':'bool','_hideTimer':'Timer?','_infoPanelGeneration':'int','_infoPanelHeight':'double',
 '_iptvSheetKey':'GlobalKey<IptvChannelSheetState>','_isAnyOverlayOpen':'bool','_isPlaying':'bool','_isReady':'bool','_isTransitioning':'bool','_lastInfoPanelSignature':'String',
 '_player':'mk.Player','_playerMenuKey':'GlobalKey<PlayerMenuPanelState>','_position':'Duration','_rainbowActive':'bool','_rainbowController':'AnimationController','_ripple':'DoubleTapRipple?',
 '_seekHud':'ValueNotifier<SeekHudState?>','_showBufferingIndicator':'ValueNotifier<bool>','_showChannelGuide':'bool','_showIptvChannelSheet':'bool','_showPlayerMenu':'bool','_showSourceSheet':'bool','_showStremioTvGuide':'bool','_showSyncOverlay':'bool',
 '_sleepStopLatched':'bool','_transitionPhase':'int','_transitionPhaseTimer':'Timer?','_transitionRunning':'bool','_transitionStopTimer':'Timer?','_tvBarScope':'FocusScopeNode','_tvNoTimeline':'bool',
 '_tvPlayPauseFocus':'FocusNode','_tvProgressFocus':'FocusNode','_tvRootFocus':'FocusNode','_tvScrubGeneration':'int','_tvScrubTarget':'Duration?','_tvStaticMessage':'String','_tvStaticSubtext':'String','_verticalHud':'ValueNotifier<VerticalHudState?>',
}
STATICS={}
ACTIONS={
 # Retained State member (shared derivation; build and the display adapter read it too).
 '_dockBand':('double dockBand(double legacy)','(legacy)'),
 # Sibling routing (moved in this phase): targets resolve to _s.<receiver>.<name>.
 '_scheduleAutoHide':('void scheduleAutoHide()','()'),
 '_tvShowBar':('void tvShowBar()','()'),
 '_tvHideBar':('void tvHideBar()','()'),
 '_togglePlay':('void togglePlay()','()'),
}
WIDGET={'hideOptions':'bool','hideSeekbar':'bool','requestChannelById':'Future<Map<String, dynamic>?> Function(String channelId)?'}
def chain(owner,member,forwarders,name=None):
 return dict(before=[owner,'.',member],name=name or member,forwarders=forwarders)
def fw(recv,sig,args,name):
 return chain(recv,name,[sig+' => _s.'+recv+'.'+name+args+';'])
def prop(recv,name,typ,get=True,set=True):
 return chain(recv,name,([typ+' get '+name+' => _s.'+recv+'.'+name+';'] if get else [])+(['set '+name+'('+typ+' v) => _s.'+recv+'.'+name+' = v;'] if set else []))
CHAINS=[
 fw('_debrifyBanner','void hideDebrifyBanner({bool immediate = false})','(immediate: immediate)','hideDebrifyBanner'),
 fw('_debrifyBanner','void syncPlaybackClockVisibility()','()','syncPlaybackClockVisibility'),
 fw('_debrifyChannels','void hideChannelGuideOverlay()','()','hideChannelGuideOverlay'),
 fw('_debrifyChannels','void showChannelGuideOverlay()','()','showChannelGuideOverlay'),
 fw('_iptvBanner','void hideIptvZapBanner({bool immediate = false})','(immediate: immediate)','hideIptvZapBanner'),
 fw('_iptvBanner','void syncIptvBannerTicker()','()','syncIptvBannerTicker'),
 fw('_iptvGuide','void hideIptvChannelSheet()','()','hideIptvChannelSheet'),
 fw('_iptvGuide','void showIptvChannelSheetOverlay()','()','showIptvChannelSheetOverlay'),
 fw('_mdblist','void mdblistScrobbleSeek(Duration target)','(target)','mdblistScrobbleSeek'),
 fw('_menu','void hidePlayerMenu()','()','hidePlayerMenu'),
 fw('_recording','Future<void> refreshEngineRecordingState()','()','refreshEngineRecordingState'),
 fw('_resumeSave','Future<void> saveResume({bool debounced = false, Duration? positionOverride})','(debounced: debounced, positionOverride: positionOverride)','saveResume'),
 fw('_simkl','void simklScrobbleSeek(Duration seekTarget)','(seekTarget)','simklScrobbleSeek'),
 prop('_skip','activeSkipSegment','SkipSegment?',set=False),
 fw('_skip','void skipActiveSegment()','()','skipActiveSegment'),
 fw('_sourceSwitch','void hideSourceSheet()','()','hideSourceSheet'),
 fw('_stremioTv','void hideStremioTvGuide()','()','hideStremioTvGuide'),
 fw('_stremioTv','void showStremioTvGuideOverlay()','()','showStremioTvGuideOverlay'),
 fw('_subtitleSync','void hideSyncOverlay()','()','hideSyncOverlay'),
 fw('_trakt','void traktScrobbleSeek(Duration seekTarget)','(seekTarget)','traktScrobbleSeek'),
 fw('_zapLadder','void zapIptvChannel(int delta)','(delta)','zapIptvChannel'),
 prop('_zapRing','canZapIptvChannel','bool',set=False),
]
# Earlier scaffolding adapters whose forwarders reach a moved member: receiver rewrites only (30 sites, 16 adapters).
PATCHED=['_VpPlayerStartupHostAdapter','_VpPlaylistLoadHostAdapter','_VpShuffleHostAdapter','_VpEpisodeAdjacentHostAdapter','_VpEpisodeNextHostAdapter','_VpStremioTvChannelsHostAdapter','_VpDebrifyTvChannelsHostAdapter','_VpSourcePlaylistSwitchHostAdapter','_VpSourceSwitchHostAdapter','_VpIptvChannelSwitchHostAdapter','_VpIptvGuideCatchupHostAdapter','_VpPlayerMenuHostAdapter','_VpSubtitleAutoSyncHostAdapter','_VpPipLifecycleHostAdapter','_VpDisplayModeHostAdapter','_VpSleepTimerHostAdapter']
EXPECTED_HOSTS={'VpTransitionOverlay':(12,12),'VpDockLayout':(13,17),'VpControlsRuntime':(38,39),'VpTvRemote':(33,34),'VpPlayerGestures':(14,14)}
SIZE_LIMIT={}
def imp(*paths):return ''.join("import '"+x+";\n" if ' as ' in x else "import '"+x+"';\n" if x.startswith('dart:') else "import 'package:"+x+"';\n" if x.startswith(('flutter/','media_kit')) else "import 'package:debrify/"+x+"';\n" for x in paths)
MK="package:media_kit/media_kit.dart' as mk"
MATH="dart:math' as math"
IMPORTS={
 'VpTransitionOverlay':imp('dart:async',MATH,'flutter/widgets.dart','screens/video_player/constants/timing_constants.dart'),
 'VpDockLayout':imp('flutter/widgets.dart','screens/video_player/widgets/dock_style.dart','services/storage/player_appearance_storage.dart'),
 'VpControlsRuntime':imp('dart:async','flutter/widgets.dart',MK,'screens/video_player/constants/timing_constants.dart','screens/video_player/widgets/iptv_channel_sheet.dart','screens/video_player/widgets/player_menu_panel.dart','utils/platform_util.dart'),
 'VpTvRemote':imp('flutter/services.dart','flutter/widgets.dart',MK,'models/iptv_playlist.dart','screens/video_player/models/channel_entry.dart','services/skip_segment_service.dart'),
 'VpPlayerGestures':imp('dart:async',MATH,'flutter/material.dart',MK,'screens/video_player/constants/timing_constants.dart','screens/video_player/models/gesture_state.dart','screens/video_player/models/hud_state.dart','services/player_display_controls.dart'),
}
DROP={}
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
 spec.update(phase=21,status='provisional',span_order=list(spans),patched_class_projection=PATCHED,finalization=dict(label='PROVISIONAL',preparation_base=BASE,accepted_p20=BASE,seam_original=BASE,history='All twenty applied phases; every earlier destination derived without a whitelist.'),provisional=dict(label='PROVISIONAL',preparation_base=BASE,pending=['M5 record (re-baseline only if M5 lands a non-docs fix)'],host_contracts={g['name']:g['forwarders'] for g in GROUPS},construction='Five inert eager late-final assignments follow all six P20 collaborators.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Complete live collaborator chain via facade routing') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:byname[n]['name'] for n in FIELDS}),record_owners=[STATE],record_fields={STATE:FIELDS},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],adapter_state_prefixes=['_s'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 retained_sites=[];patched=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None
  mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in byname};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping.update({n:['_host','.',n] for n in ['mounted','context','setState']})
   assert 'this' not in vals,key
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
   row.update(fate='patched',reason='Route the P15-P20 adapter forwarder to its P21 owner, preserving every earlier rewrite.',test='dev/tool/draft_vplayer_controls_moves.py',patches=sorted(edits,key=lambda e:json.dumps(e['before'])));patched.append(key);measured.append(dict(declaration=key,fate='patched',edits=edits));edits=[]
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Five inert eager assignments after all six accepted P20 collaborators.',test='dev/tool/draft_vplayer_controls_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 assert sorted(patched)==sorted(PATCHED),patched
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._playerStartup'
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
 if not a.no_check and not errors and all(v<=SIZE_LIMIT.get(k,500) for k,v in sizes.items() if k!='facade'):(R/'dev/tool/dart_moves/vplayer_p21.json').write_text(json.dumps(spec,indent=2)+'\n')
 for file,value in [('membership.json',measured),('retained-sites.json',sites),('hosts.json',spec['provisional']['host_contracts']),('spec.json',spec),('result.json',dict(label='PROVISIONAL',comparison_errors=errors,sizes=sizes,hosts=hosts,retained_references=len(sites)))]: (a.probe/file).write_text(json.dumps(value,indent=2)+'\n')
 print('PROVISIONAL differences',len(errors),sizes,hosts,'retained',len(sites))
 for e in errors[:40]:print(' ',e)
 assert all(v<=SIZE_LIMIT.get(k,500) for k,v in sizes.items() if k!='facade'),sizes
if __name__=='__main__':main()
