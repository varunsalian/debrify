#!/usr/bin/env python3
"""Draft the approved Phase-11 three-collaborator split in evidence only."""
import argparse
import json
import subprocess
from pathlib import Path
from check_verbatim_moves import ROOT as R, ensure_parser_package
from check_verbatim_moves import parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest,check
from dart_move_partition import partition,frozen
from dart_move_history import git_text,check_earlier
from dart_move_fixture import edited_text,materialize
SOURCE='lib/screens/video_player_screen.dart';FEATURE='lib/features/video_player';STATE='_VideoPlayerScreenState'
GROUPS=[dict(name='VpSubtitleLanguagePolicy',receiver='_subtitleLanguage',file='vp_subtitle_language_policy.dart',names=['_applyDefaultAudioLanguage','_audioAllowsAutomaticSubtitles','_refreshSubtitleAudioPolicy','_applyDefaultSubtitleLanguage','_applyForcedSubtitle']),dict(name='VpTrackPreferences',receiver='_trackPreferences',file='vp_track_preferences.dart',names=['_restoreTrackPreferences','_persistTrackChoice']),dict(name='VpAddonSubtitles',receiver='_addonSubtitles',file='vp_addon_subtitles.dart',names=['_subtitlePrioritySelectionQueue','_tempSubtitleFiles','_downloadStremioSubtitleToTempFile','_applyExternalSubtitleTrack','_cleanupTempSubtitleFilesSync','_fetchAndMaybeAutoSelectAddonSubtitle','_applySubtitleSourcePriority','_applySubtitlePriorityUpdate'])]
TYPES={'_player':'mk.Player','_addonSubtitleFetchToken':'int','_subtitleForcedOnly':'bool','_subtitleOnlyForeignAudio':'bool','_subtitlePreferredAudio':'String?','_subtitleSelectedAudio':'String?','_hasSubtitlePolicy':'bool','_userManuallySelectedSubtitle':'bool','_trackPreferencesReadyForAddonSubtitles':'bool','_subtitleAudioRevision':'int','_embeddedSubtitleApplied':'bool','_selectedStremioSubtitleId':'String?','_cachedAddonSlots':'List<AddonSubtitleSlot>?','_seriesPlaylist':'SeriesPlaylist?','_isIptvSeriesContext':'bool','_iptvSwitchTicket':'int','_activeSubtitleApplyAttempt':'VpSubtitleApplyAttempt?','_effectiveContentImdbId':'String?','_manualContentImdbId':'String?','_manualContentType':'String?','_manualContentSeason':'int?','_manualContentEpisode':'int?','_currentStremioTvContentSeason':'int?','_currentStremioTvContentEpisode':'int?','_effectiveContentType':'String?','_effectiveContentSeason':'int?','_effectiveContentEpisode':'int?','_singleFileImdbId':'String?','_cachedSubtitleKey':'String?','_cachedStremioSubtitles':'List<StremioSubtitle>?'}
ACTIONS={'_applyDefaultAudioLanguage':'Future<void> applyDefaultAudioLanguage()','_audioAllowsAutomaticSubtitles':'bool get audioAllowsAutomaticSubtitles','_refreshSubtitleAudioPolicy':'Future<void> refreshSubtitleAudioPolicy({bool reselect = true})','_applyDefaultSubtitleLanguage':'Future<bool> applyDefaultSubtitleLanguage({bool ignoreSourcePriority = false})','_applyForcedSubtitle':'Future<bool> applyForcedSubtitle(String? language, bool Function() current)','_fetchAndMaybeAutoSelectAddonSubtitle':'Future<void> fetchAndMaybeAutoSelectAddonSubtitle()','_applySubtitleSourcePriority':'Future<void> applySubtitleSourcePriority(List<AddonSubtitleSlot> slots, int token, {bool discoveryReady = true})','_applyIptvAudioPreference':'Future<void> applyIptvAudioPreference(int ticket)','_findSeriesEpisodeForCurrentIndex':'SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist seriesPlaylist)'}
ARGS={'_applyDefaultAudioLanguage':'()','_audioAllowsAutomaticSubtitles':'','_refreshSubtitleAudioPolicy':'(reselect: reselect)','_applyDefaultSubtitleLanguage':'(ignoreSourcePriority: ignoreSourcePriority)','_applyForcedSubtitle':'(language, current)','_fetchAndMaybeAutoSelectAddonSubtitle':'()','_applySubtitleSourcePriority':'(slots, token, discoveryReady: discoveryReady)','_applyIptvAudioPreference':'(ticket)','_findSeriesEpisodeForCurrentIndex':'(seriesPlaylist)'}
CHAINS=[(['_subtitleSync','.','setActiveExternalSubtitlePath'],['_host','.','setActiveExternalSubtitlePath'],'void setActiveExternalSubtitlePath(String? path)','(path)'),(['_subtitleApply','.','waitForSubtitleTracks'],['_host','.','waitForSubtitleTracks'],'Future<void> waitForSubtitleTracks({required int token})','(token: token)'),(['_subtitleApply','.','setSubtitleTrackWithDiagnostics'],['_host','.','setSubtitleTrackWithDiagnostics'],'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})','(track, source: source, isCurrent: isCurrent)')]
imports={
'VpSubtitleLanguagePolicy':"import 'package:debrify/models/stremio_subtitle.dart';\nimport 'package:debrify/models/subtitle_source_priority.dart';\nimport 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';\nimport 'package:debrify/screens/video_player/utils/language_mapping.dart';\nimport 'package:debrify/screens/video_player/utils/subtitle_audio_policy.dart';\nimport 'package:debrify/services/storage/subtitle_settings_storage.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:media_kit/media_kit.dart' as mk;\n",
'VpTrackPreferences':"import 'dart:async';\nimport 'package:debrify/features/video_player/application/vp_subtitle_identity.dart';\nimport 'package:debrify/features/video_player/models/vp_subtitle_apply_attempt.dart';\nimport 'package:debrify/models/series_playlist.dart';\nimport 'package:debrify/services/storage/track_preferences_storage.dart';\nimport 'package:debrify/services/storage/subtitle_settings_storage.dart';\nimport 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';\nimport 'package:debrify/screens/video_player/utils/language_mapping.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:media_kit/media_kit.dart' as mk;\n",
'VpAddonSubtitles':"import 'dart:async';\nimport 'dart:io';\nimport 'package:debrify/models/custom_series_identity.dart';\nimport 'package:debrify/models/series_playlist.dart';\nimport 'package:debrify/models/stremio_subtitle.dart';\nimport 'package:debrify/screens/video_player/services/external_subtitle_payload.dart';\nimport 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';\nimport 'package:debrify/screens/video_player/utils/subtitle_priority_selection.dart';\nimport 'package:debrify/services/storage/subtitle_settings_storage.dart';\nimport 'package:debrify/services/stremio_subtitle_service.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:http/http.dart' as http;\nimport 'package:media_kit/media_kit.dart' as mk;\nimport 'package:path_provider/path_provider.dart';\n"}

FROZEN_HOSTS = {'VpSubtitleLanguagePolicy': ['bool get mounted', 'int get addonSubtitleFetchToken', 'Future<void> applySubtitleSourcePriority(List<AddonSubtitleSlot> slots, int token, {bool discoveryReady = true})', 'List<AddonSubtitleSlot>? get cachedAddonSlots', 'set embeddedSubtitleApplied(bool v)', 'bool get hasSubtitlePolicy', 'mk.Player get player', 'set selectedStremioSubtitleId(String? v)', 'int get subtitleAudioRevision', 'set subtitleAudioRevision(int v)', 'bool get subtitleForcedOnly', 'bool get subtitleOnlyForeignAudio', 'String? get subtitlePreferredAudio', 'String? get subtitleSelectedAudio', 'set subtitleSelectedAudio(String? v)', 'bool get trackPreferencesReadyForAddonSubtitles', 'bool get userManuallySelectedSubtitle', 'void setActiveExternalSubtitlePath(String? path)', 'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})'], 'VpTrackPreferences': ['VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt', 'int get addonSubtitleFetchToken', 'Future<void> applyDefaultAudioLanguage()', 'Future<bool> applyDefaultSubtitleLanguage({bool ignoreSourcePriority = false})', 'Future<void> applyIptvAudioPreference(int ticket)', 'set embeddedSubtitleApplied(bool v)', 'Future<void> fetchAndMaybeAutoSelectAddonSubtitle()', 'bool get hasSubtitlePolicy', 'int get iptvSwitchTicket', 'bool get isIptvSeriesContext', 'mk.Player get player', 'Future<void> refreshSubtitleAudioPolicy({bool reselect = true})', 'SeriesPlaylist? get seriesPlaylist', 'set trackPreferencesReadyForAddonSubtitles(bool v)', 'set userManuallySelectedSubtitle(bool v)', 'String get title', 'Future<void> waitForSubtitleTracks({required int token})', 'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})'], 'VpAddonSubtitles': ['bool get mounted', 'int get addonSubtitleFetchToken', 'Future<bool> applyDefaultSubtitleLanguage({bool ignoreSourcePriority = false})', 'Future<bool> applyForcedSubtitle(String? language, bool Function() current)', 'bool get audioAllowsAutomaticSubtitles', 'List<AddonSubtitleSlot>? get cachedAddonSlots', 'set cachedAddonSlots(List<AddonSubtitleSlot>? v)', 'List<StremioSubtitle>? get cachedStremioSubtitles', 'set cachedStremioSubtitles(List<StremioSubtitle>? v)', 'String? get cachedSubtitleKey', 'set cachedSubtitleKey(String? v)', 'int? get currentStremioTvContentEpisode', 'int? get currentStremioTvContentSeason', 'int? get effectiveContentEpisode', 'String? get effectiveContentImdbId', 'int? get effectiveContentSeason', 'String? get effectiveContentType', 'bool get embeddedSubtitleApplied', 'set embeddedSubtitleApplied(bool v)', 'SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist seriesPlaylist)', 'int? get manualContentEpisode', 'String? get manualContentImdbId', 'int? get manualContentSeason', 'String? get manualContentType', 'mk.Player get player', 'String? get selectedStremioSubtitleId', 'set selectedStremioSubtitleId(String? v)', 'SeriesPlaylist? get seriesPlaylist', 'String? get singleFileImdbId', 'int get subtitleAudioRevision', 'bool get subtitleForcedOnly', 'bool get trackPreferencesReadyForAddonSubtitles', 'bool get userManuallySelectedSubtitle', 'int? get contentSeason', 'int? get contentEpisode', 'void setActiveExternalSubtitlePath(String? path)', 'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})']}

def build(package):
 original=git_text('7fdf59370',SOURCE);spec=retained_manifest(SOURCE,FEATURE,original,'7fdf59370',package);u=parse({'base':original},package,ownership=True)['base'];spans,_,nodes=partition(u,[STATE]);byname={n:g for g in GROUPS for n in g['names']};allnames=set(byname);hostbindings={};widgetnames=[]
 for g in GROUPS:
  g['dest']=FEATURE+'/presentation/legacy_video_player/'+g['file'];g['forwarders']=[];g['hosts']=[];needed=set();writes=set();reads=set()
  for n in g['names']:
   v=tokens(spans[STATE+'.'+n]);needed.update(x for x in v if x in TYPES or x in ACTIONS and x not in g['names'])
   for i,x in enumerate(v):
    if x in TYPES and not (i+1<len(v) and v[i+1]=='='):reads.add(x)
    if x in TYPES and ((i+1<len(v) and v[i+1] in ['=','++','--','+=','-=']) or (i and v[i-1] in ['++','--'])):writes.add(x)
  for n in sorted(needed):
   if n in TYPES:
    if n in reads:g['forwarders'].append(TYPES[n]+' get '+n[1:]+' => _s.'+n+';')
    if n in writes:g['forwarders'].append('set '+n[1:]+'('+TYPES[n]+' v) => _s.'+n+' = v;')
   else:
    owner=byname.get(n);target='_s.'+(owner['receiver']+'.'+n[1:] if owner else n)
    g['forwarders'].append(ACTIONS[n]+' => '+target+ARGS[n]+';')
   g['hosts'].append(n);hostbindings['_host.'+n[1:]]=STATE+'.'+n
  values=[x for n in g['names'] for x in tokens(spans[STATE+'.'+n])]
  if 'mounted' in values:g['forwarders'].insert(0,'bool get mounted => _s.mounted;')
  for name,typ in [('title','String'),('contentSeason','int?'),('contentEpisode','int?')]:
   if any(values[i:i+3]==['widget','.',name] for i in range(len(values))):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';');widgetnames.append(name)
  for before,after,signature,args in CHAINS:
   if any(values[i:i+len(before)]==before for i in range(len(values))):g['forwarders'].append(signature+' => _s.'+''.join(before)+args+';')
 for g in GROUPS:
  assert [f.split(' => ')[0] for f in g['forwarders']] == FROZEN_HOSTS[g['name']], ('Host drift', g['name'])
 spec.update(phase=11,status='draft',span_order=list(spans),patched_class_projection=['_VpSubtitleApplyHostAdapter'])
 fields=['_subtitlePrioritySelectionQueue','_tempSubtitleFiles'];spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:'VpAddonSubtitles' for n in fields}),record_owners=[STATE],record_fields={STATE:fields},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=[dict(before=a,after=b,binding='unbound',role_change='Complete sibling chain to live Host projection') for a,b,_,_ in CHAINS]+[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='widget selector to live Host selector') for n in sorted(set(widgetnames))])
 measured=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None;mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in allnames}
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping['mounted']=['_host','.','mounted']
  vals=tokens(spans[key]);edits=[]
  for n,after in mapping.items():
   assert not any(vals[i:i+2]==['$',n] for i in range(len(vals))),(key,n,'interpolation')
   if n in vals:edits.append(dict(before=[n],after=after,count=vals.count(n)))
  if moved:
   for before,after in [(a,b) for a,b,_,_ in CHAINS]+[(['widget','.',n],['_host','.',n]) for n in sorted(set(widgetnames))]:
    count=sum(vals[i:i+len(before)]==before for i in range(len(vals)))
    if count:edits.append(dict(before=before,after=after,count=count))
  if key=='_VpSubtitleApplyHostAdapter':
   assert len(edits)==1 and edits[0]['count']==1;row.update(fate='patched',reason='Redirect the frozen persistence forwarder only.',test='dev/tool/test_dart_subtitle_sources_moves.py',patches=edits)
  elif edits:row['substitutions']=edits
  if edits:measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Append three eager inert collaborators after subtitleApply in table order.',test='dev/tool/test_dart_subtitle_sources_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 # Independent disjoint edits have a stable order in the frozen artifact.
 for row in spec['declarations']:
  if 'substitutions' in row:row['substitutions'].sort(key=lambda e:json.dumps(e['before']))
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._subtitleApply'
 for i,g in enumerate(GROUPS):
  host=g['name']+'Host';adapter='_'+host+'Adapter';key=STATE+'.'+g['receiver'];scaff['@directive:'+str(len(u['directives'])+i)]="import '../"+g['dest'][4:]+"';";scaff[key]='late final '+g['name']+' '+g['receiver']+';';scaff[adapter]='class '+adapter+' implements '+host+' {\n  '+adapter+'(this._s);\n  final _VideoPlayerScreenState _s;\n'+''.join('  @override\n  '+f+'\n' for f in g['forwarders'])+'}\n'
  at=spec['span_order'].index(previous)+1;spec['span_order'].insert(at,key);previous=key
 for key in scaff:
  if key.startswith('@directive:'):spec['span_order'].insert(next(i for i,k in enumerate(spec['span_order']) if not k.startswith('@directive:')),key)
  elif not key.startswith(STATE+'.'):spec['span_order'].insert(spec['span_order'].index(STATE+':close')+1,key)
 bykey={r['original']:r for r in spec['declarations']};facade=''.join(scaff[k]+'\n' if k in scaff else edited_text(original,spans[k],bykey[k].get('substitutions',[])+bykey[k].get('patches',[])) for k in spec['span_order']);pu=parse({SOURCE:facade},package,ownership=True)[SOURCE];physical,orders,_=partition(pu,[STATE]);spec['facade_orders']=orders;spec['facade_directives']=pu['directives'];spec['scaffolding'][SOURCE]=frozen({k:physical[k] for k in scaff})
 for g in GROUPS:
  c=g['name'];host=c+'Host';dest=imports[c]+'abstract interface class '+host+' {\n'+''.join('  '+f.split(' => ')[0]+';\n' for f in g['forwarders'])+'}\n\nclass '+c+' {\n  '+c+'(this._host);\n  final '+host+' _host;\n'
  for row in spec['declarations']:
   if row['fate']=='moved' and row['destination']==g['dest']:dest+=edited_text(original,spans[row['original']],row.get('substitutions',[]))
  dest+='\n}\n';pu=parse({g['dest']:dest},package,ownership=True)[g['dest']];physical,orders,_=partition(pu,[c]);targets={r['target'] for r in spec['declarations'] if r['fate']=='moved' and r['destination']==g['dest']};spec['destinations'][g['dest']]=dict(directives=pu['directives'],orders=orders,span_order=list(physical),split_containers=[c]);spec['scaffolding'][g['dest']]=frozen({k:v for k,v in physical.items() if k not in targets})
 return original,spec,measured


def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--base', default='7fdf59370', choices=['7fdf59370'])
 parser.add_argument('--parser-package', type=Path, required=True)
 parser.add_argument('--probe', type=Path, required=True)
 args=parser.parse_args()
 common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip())
 if not args.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p11'):
  parser.error('probe must be under P11 evidence')
 ensure_parser_package(args.parser_package.parent.parent,args.parser_package)
 original,spec,measured=build(args.parser_package)
 sources=materialize(spec,original,args.parser_package)
 args.probe.mkdir(parents=True,exist_ok=True)
 for path,content in sources.items():
  out=args.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(content)
  subprocess.run(['nice','-n','19','dart','format',str(out)],check=True,stdout=subprocess.DEVNULL)
 formatted={p:(args.probe/p).read_text() for p in sources}
 errors=check(spec,original,formatted,args.parser_package)+check_earlier(spec,args.parser_package)
 for error in errors:print(error)
 if errors:return 1
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS}
 assert list(sizes.values())==[303,282,412],sizes
 (R/'dev/tool/dart_moves/vplayer_p11.json').write_text(json.dumps(spec,indent=2)+'\n')
 (args.probe/'remeasured.json').write_text(json.dumps(measured,indent=2)+'\n')
 (args.probe/'result.json').write_text(json.dumps(dict(errors=errors,sizes=sizes,hosts=FROZEN_HOSTS),indent=2)+'\n')
 print('PASS: complete P11 split, 15 moves, 20 historical destinations; application untouched')
 return 0

if __name__=='__main__':raise SystemExit(main())
