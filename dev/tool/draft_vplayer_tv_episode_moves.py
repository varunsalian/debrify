#!/usr/bin/env python3
"""FINAL P17 evidence-only materialization on accepted P16 (2ee7e94ac); never writes lib/."""
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
BASE='2ee7e94ac'
GROUPS=[
 dict(name='VpDebrifyTvChannels',receiver='_debrifyChannels',file='vp_debrify_tv_channels.dart',names=['_parseChannelDirectory','_showChannelGuideOverlay','_hideChannelGuideOverlay','_goToChannelById','_goToNextChannel']),
 dict(name='VpDebrifyTvBanner',receiver='_debrifyBanner',file='vp_debrify_tv_banner.dart',names=['_debrifyBannerTimer','_syncPlaybackClockVisibility','_raiseDebrifyBanner','_armDebrifyBannerTimer','_hideDebrifyBanner']),
 dict(name='VpStremioTvChannels',receiver='_stremioTv',file='vp_stremio_tv_channels.dart',names=['_findInitialStremioTvChannelId','_showStremioTvGuideOverlay','_hideStremioTvGuide','_setStremioTvNextLoading','_applyStremioTvGuidePlaybackData','_parseStremioTvSources','_switchToStremioTvChannel','_goToNextStremioTvSlot']),
 dict(name='VpEpisodeFetch',receiver='_episodeFetch',file='vp_episode_fetch.dart',names=['_packCoversSeason','_fetchAndPlayEpisode','_tryEpisodeCandidate','_prepareNextDirectEpisode']),
 dict(name='VpEpisodeGuide',receiver='_episodeGuide',file='vp_episode_guide.dart',names=['_syntheticGuideEntries','_buildSyntheticGuide','_showPlaylistSheet']),
]
FIELDS=['_debrifyBannerTimer','_syntheticGuideEntries']
TYPES={
 '_channelEntries':'List<ChannelEntry>', '_currentChannelId':'String?', '_currentChannelName':'String?', '_currentChannelNumber':'int?', '_showChannelGuide':'bool', '_controlsVisible':'ValueNotifier<bool>', '_isTransitioning':'bool', '_tvScrubGeneration':'int', '_player':'mk.Player', '_tvStaticMessage':'String', '_tvStaticSubtext':'String', '_singleFileImdbId':'String?', '_singleFileImdbFetched':'bool', '_pikPakRetryId':'int', '_activeHttpHeaders':'Map<String, String>?', '_currentStreamUrl':'String?', '_dynamicTitle':'String', '_duration':'Duration',
 '_debrifyTvOwnsIdentity':'bool', '_anyPlayerOverlayOpen':'bool', '_showDebrifyBanner':'bool', '_debrifyBannerFloatingMounted':'bool', '_playbackUiClock':'PlaybackUiClockController',
 '_hasStremioTvGuide':'bool', '_showStremioTvGuide':'bool', '_showStremioTvNextLoading':'bool', '_effectiveStremioTvChannels':'List<Map<String, dynamic>>?', '_stremioTvChannelsOverride':'List<Map<String, dynamic>>?', '_currentStremioTvChannelId':'String?', '_currentStremioTvContentImdbId':'String?', '_currentStremioTvContentType':'String?', '_currentStremioTvContentSeason':'int?', '_currentStremioTvContentEpisode':'int?', '_currentStremioTvContentTitle':'String?', '_stremioSourcesOverride':'List<Torrent>?', '_resolveStremioSourceOverride':'Future<String?> Function(Torrent)?', '_currentSourceIndex':'int', '_transitionStopTimer':'Timer?', '_transitionPhaseTimer':'Timer?', '_transitionPhase':'int', '_transitionPhase2Started':'DateTime?', '_rainbowController':'AnimationController', '_transitionRunning':'bool', '_rainbowActive':'bool',
 '_canFetchEpisodes':'bool', '_episodeFetchInProgress':'bool', '_episodeNavigationGeneration':'int', '_playlistIdentityToken':'int', '_sleepStopLatched':'bool', '_showShuffleGeneration':'int', '_effectiveSources':'List<Torrent>?', '_augmentedSources':'List<Torrent>?', '_isAutoAdvancing':'bool', '_validationGateActive':'bool', '_isPlaying':'bool', '_position':'Duration',
 '_syntheticGuidePlaylist':'SeriesPlaylist?', '_currentSeriesImdbId':'String?', '_activePlaylist':'List<PlaylistEntry>?', '_seriesPlaylist':'SeriesPlaylist?', '_currentIndex':'int', '_episodeMetadataReady':'Future<void>?', '_seriesImdbKnownAtLaunch':'bool',
}
ACTIONS={
 '_tvAbandonScrub':('void tvAbandonScrub()','()'), '_clearBufferingIndicator':('void clearBufferingIndicator()','()'), '_startTransitionOverlay':('void startTransitionOverlay()','()'), '_resetSubtitleState':('void resetSubtitleState()','()'),
 '_openMedia':('Future<void> openMedia(mk.Media media, {required bool play, bool? desiredPlay, bool liveStream = false, EpisodePlaybackRequest? request, bool Function()? beforeOpen, Torrent? source, int? preserveStartupEpoch})','(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)'),
 '_waitForVideoReady':('Future<void> waitForVideoReady()','()'), '_randomStartOffset':('Duration? randomStartOffset(Duration total)','(total)'), '_percentStartOffset':('Duration? percentStartOffset(Duration total)','(total)'), '_hideIptvZapBanner':('void hideIptvZapBanner({bool immediate = false})','(immediate: immediate)'), '_raiseDebrifyBanner':('void raiseDebrifyBanner()','()'),
 '_setManualSelectionMode':('void setManualSelectionMode({bool allowResume = false})','(allowResume: allowResume)'),
 '_traktSeasonEpisode':('({int? season, int? episode}) traktSeasonEpisode()','()'), '_preloadEpisodeInfo':('Future<void> preloadEpisodeInfo()','()'), '_constructPlaylistItemData':('Map<String, dynamic>? constructPlaylistItemData()','()'),
 '_loadPlaylistIndex':('Future<bool> loadPlaylistIndex(int index, {bool autoplay = false, EpisodePlaybackRequest? request, bool skipInitialSave = false, bool preferLocalResume = false, bool suppressResume = false, Torrent? manualValidationSource, int? manualValidationSourceIndex})','(index, autoplay: autoplay, request: request, skipInitialSave: skipInitialSave, preferLocalResume: preferLocalResume, suppressResume: suppressResume, manualValidationSource: manualValidationSource, manualValidationSourceIndex: manualValidationSourceIndex)'),
 '_fetchAndPlayEpisode':('Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(int season, int episode, {int? shuffleGeneration, bool autoAdvance = false, EpisodePlaybackRequest? request})','(season, episode, shuffleGeneration: shuffleGeneration, autoAdvance: autoAdvance, request: request)'),
}
WIDGET={'channelDirectory':'List<Map<String, dynamic>>?', 'requestChannelById':'Future<Map<String, dynamic>?> Function(String)?', 'requestNextChannel':'Future<Map<String, dynamic>?> Function()?', 'startFromRandom':'bool', 'startAtPercent':'double?', 'hideSeekbar':'bool', 'stremioTvCurrentChannelId':'String?', 'stremioTvNextProvider':'Future<Map<String, dynamic>?> Function(String)?', 'seriesSourceFetcher':'SeriesSourceFetcher?', 'resolveSourceToPlaylist':'SourcePlaylistResolve?', 'title':'String', 'videoUrl':'String', 'contentTitle':'String?', 'viewMode':'PlaylistViewMode?'}
CHAINS=[dict(before=['_iptvBanner','.','hideIptvZapBanner'],name='hideIptvZapBanner',signature='void hideIptvZapBanner({bool immediate = false})',args='(immediate: immediate)'),dict(before=['_sourcePlaylistSwitch','.','switchToSourcePlaylist'],name='switchToSourcePlaylist',signature='Future<bool> switchToSourcePlaylist(int sourceIndex, List<PlaylistEntry> newPlaylist, {int? targetSeason, int? targetEpisode, bool validateExplicitSelection = false, bool suppressResume = false, EpisodePlaybackRequest? request})',args='(sourceIndex, newPlaylist, targetSeason: targetSeason, targetEpisode: targetEpisode, validateExplicitSelection: validateExplicitSelection, suppressResume: suppressResume, request: request)'),dict(before=['_subtitleApply','.','setSubtitleTrackWithDiagnostics'],name='setSubtitleTrackWithDiagnostics',signature='Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})',args='(track, source: source, isCurrent: isCurrent)'),dict(before=['_completion','.','resetLocalCompletionState'],name='resetLocalCompletionState',signature='void resetLocalCompletionState()',args='()'),dict(before=['_identify','.','currentSeasonEpisodeForIdentity'],name='currentSeasonEpisodeForIdentity',signature='VpSeasonEpisodeSelection? currentSeasonEpisodeForIdentity()',args='()')]
COMMON="""import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/models/torrent.dart';
"""
IMPORTS={
 'VpDebrifyTvChannels': COMMON+"import 'package:debrify/screens/video_player/models/channel_entry.dart';\n",
 'VpDebrifyTvBanner':"import 'dart:async';\nimport 'package:flutter/foundation.dart';\nimport 'package:debrify/screens/video_player/constants/timing_constants.dart';\nimport 'package:debrify/screens/video_player/services/playback_ui_clock.dart';\n",
 'VpStremioTvChannels': COMMON,
 'VpEpisodeFetch': COMMON.replace("import 'package:media_kit/media_kit.dart' as mk;\n","")+"import 'package:debrify/models/playlist_entry.dart';\nimport 'package:debrify/models/series_playlist.dart';\nimport 'package:debrify/models/source_playlist_resolver.dart';\nimport 'package:debrify/services/series_source_fetcher.dart';\nimport 'package:debrify/utils/series_parser.dart';\nimport 'package:debrify/services/source_selection_diagnostics.dart';\nimport 'package:debrify/features/video_player/application/vp_format.dart';\nimport 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';\n",
 'VpEpisodeGuide':"import 'package:flutter/material.dart';\nimport 'package:debrify/models/playlist_entry.dart';\nimport 'package:debrify/models/playlist_view_mode.dart';\nimport 'package:debrify/models/series_playlist.dart';\nimport 'package:debrify/models/torrent.dart';\nimport 'package:debrify/utils/episode_playback_request.dart';\nimport 'package:debrify/utils/series_parser.dart';\nimport 'package:debrify/screens/video_player/widgets/playlist_sheet.dart';\nimport 'package:debrify/features/video_player/application/vp_format.dart';\n",
}

def sorted_imports(block):
 """P16 layout: dart: section, blank line, sorted package: section."""
 lines=sorted(set(l for l in block.splitlines() if l))
 dart=[l for l in lines if l.startswith("import 'dart:")];rest=[l for l in lines if l not in dart]
 return '\n\n'.join('\n'.join(x) for x in (dart,rest) if x)+'\n'

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
   indices=occurrences(vals,[n]);write=any(vals[i+1] in ['=','++','--','??='] for i in indices);read=any(vals[i+1]!='=' for i in indices);name=n[1:]
   if read:g['forwarders'].append(typ+' get '+name+' => _s.'+n+';')
   if write:g['forwarders'].append('set '+name+'('+typ+' v) => _s.'+n+' = v;')
   g['hosts'].append(n);hostbindings['_host.'+name]=STATE+'.'+n
  for n,(sig,args) in ACTIONS.items():
   if n not in vals or n in g['names']:continue
   target='_s.'+(byname[n]['receiver']+'.'+n[1:] if n in byname else n)
   g['forwarders'].append(sig+' => '+target+args+';');g['hosts'].append(n);hostbindings['_host.'+n[1:]]=STATE+'.'+n
  for n,sig,target in [('mounted','bool get mounted','_s.mounted'),('context','BuildContext get context','_s.context'),('setState','void setState(VoidCallback fn)','_s._vpSetState(fn)')]:
   if n in vals and not (n=='context' and g['name']=='VpEpisodeGuide'):g['forwarders'].append(sig+' => '+target+';')
  for name,typ in WIDGET.items():
   if occurrences(vals,['widget','.',name]):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';')
  for c in CHAINS:
   if occurrences(vals,c['before']):g['forwarders'].append(c['signature']+' => _s.'+''.join(c['before'])+c['args']+';')
 spec.update(phase=17,status='FINAL',span_order=list(spans),finalization=dict(label='FINAL',preparation_base='be4cd78aa',accepted_p16='2ee7e94ac',history='All sixteen applied phases; every earlier destination derived without a whitelist.'),provisional=dict(label='FINAL',preparation_base=BASE,pending=[],host_contracts={g['name']:g['forwarders'] for g in GROUPS},future_routing={'hideIptvZapBanner':'_s._iptvBanner.hideIptvZapBanner(immediate: immediate)','switchToSourcePlaylist':'_s._sourcePlaylistSwitch.switchToSourcePlaylist(sourceIndex, newPlaylist, targetSeason: targetSeason, targetEpisode: targetEpisode, validateExplicitSelection: validateExplicitSelection, suppressResume: suppressResume, request: request)'},construction='Preparation follows P14; final assignments must follow all five P16 collaborators.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Complete live collaborator chain via facade routing') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:byname[n]['name'] for n in FIELDS}),record_owners=[STATE],record_fields={STATE:FIELDS},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 retained_sites=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None
  mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in byname};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping.update({n:['_host','.',n] for n in ['mounted','context','setState'] if n!='context' or g['name']!='VpEpisodeGuide'})
  for n,after in mapping.items():
   if n in vals:edits+=name_edits(vals,n,after)
  if moved:
   for r in registrations:
    count=len(occurrences(vals,r['before']))
    if count:edits.append(dict(before=r['before'],after=r['after'],count=count))
  else:
   for tok in spans[key]['tokens']:
    if not tok.get('comment') and tok['text'] in byname:
     retained_sites.append(dict(declaration=key,member=tok['text'],offset=tok['offset'],line=original[:tok['offset']].count('\n')+1))
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Five inert eager assignments after all five accepted P16 collaborators.',test='dev/tool/test_dart_tv_episode_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 assert len(retained_sites)==36,len(retained_sites)
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._sourcePlaylistSwitch'
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
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parser-package',type=Path,required=True);p.add_argument('--probe',type=Path,required=True);a=p.parse_args();common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip());assert a.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p17')
 ensure_parser_package(a.parser_package.parent.parent,a.parser_package);original,spec,sources,measured,sites=build(a.parser_package);a.probe.mkdir(parents=True,exist_ok=True)
 for path,content in sources.items():
  out=a.probe/path;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(content)
 subprocess.run(['nice','-n','19','dart','format',*[str(a.probe/p) for p in sources]],check=True,stdout=subprocess.DEVNULL)
 formatted={path:(a.probe/path).read_text() for path in sources};errors=check(spec,original,formatted,a.parser_package);assert not errors,errors
 sizes={g['name']:len(formatted[g['dest']].splitlines()) for g in GROUPS}
 if sizes['VpEpisodeFetch']>500 and '_prepareNextDirectEpisode' in GROUPS[3]['names']:
  GROUPS[3]['names'].remove('_prepareNextDirectEpisode');GROUPS[4]['names'].append('_prepareNextDirectEpisode');IMPORTS['VpEpisodeGuide']+="import 'dart:async';\nimport 'package:debrify/services/series_source_fetcher.dart';\nimport 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';\n";return main()
 assert all(v<=500 for v in sizes.values()),sizes
 (R/'dev/tool/dart_moves/vplayer_p17.json').write_text(json.dumps(spec,indent=2)+'\n')
 from dart_move_history import earlier_sources,check_earlier
 history_errors=check_earlier(spec,a.parser_package);assert not history_errors,history_errors
 protected=len(earlier_sources(spec))
 for file,value in [('membership.json',measured),('retained-sites.json',sites),('hosts.json',spec['provisional']['host_contracts']),('result.json',dict(label='FINAL',comparison_errors=errors,sizes=sizes,moved=25,retained_references=len(sites),protected_earlier_destinations=protected,history='All sixteen applied phases protected'))]: (a.probe/file).write_text(json.dumps(value,indent=2)+'\n')
 print('FINAL zero comparison differences',sizes,'retained',len(sites),'protected earlier destinations',protected)
if __name__=='__main__':main()
