#!/usr/bin/env python3
"""FINAL P18 evidence-only materialization on the P17 merge (249566376); never writes lib/."""
import argparse
import json
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
BASE='249566376'
EVIDENCE='refactor-evidence/vplayer/p18'
GROUPS=[
 dict(name='VpPlaybackEnded',receiver='_playbackEnded',file='vp_playback_ended.dart',names=['_onPlaybackEnded']),
 dict(name='VpEpisodeNext',receiver='_episodeNext',file='vp_episode_next.dart',names=['_goToNextEpisode','_handleSeriesNextEpisode']),
 dict(name='VpEpisodeAdjacent',receiver='_episodeAdjacent',file='vp_episode_adjacent.dart',names=['_findNextEpisodeIndex','_getMainGroupIndices','_findPreviousEpisodeIndex','_hasNextEpisode','_hasPreviousEpisode','_fetchNextEpisodeInPlayer','_goToPreviousEpisode','_resolveAdjacentWithCachedGuide','_adjacentEpisode']),
 dict(name='VpShuffle',receiver='_shuffle',file='vp_shuffle.dart',names=['_shuffleBag','_showShuffle','_showShuffleInProgress','_activeShowShuffleGeneration','_showRandomPlaybackMenu','_toggleContinuousShuffle','_playRandomOnce','_playShowShuffle','_shuffleEligibleIndices','_pickShuffleIndex']),
 dict(name='VpEpisodeTitleInfo',receiver='_episodeTitleInfo',file='vp_episode_title_info.dart',names=['_getCurrentEpisodeTitle','_getCurrentEpisodeTitleInfo','_getCurrentEpisodeSubtitle','_getEnhancedMetadata']),
 dict(name='VpPlaylistLoad',receiver='_playlistLoad',file='vp_playlist_load.dart',names=['_clearTransitionOnFailure','_loadPlaylistIndex','_loadPlaylistIndexAttempt','_setManualSelectionMode']),
 dict(name='VpPlaylistEntryResolve',receiver='_playlistEntryResolve',file='vp_playlist_entry_resolve.dart',names=['_resolvePlaylistEntryUrl']),
 dict(name='VpMediaWaits',receiver='_mediaWaits',file='vp_media_waits.dart',names=['_waitForVideoReady','_waitForDuration','_waitForVideoMetadata']),
 dict(name='VpPikPakRetry',receiver='_pikPakRetry',file='vp_pikpak_retry.dart',names=['_playPikPakVideoWithRetry']),
 dict(name='VpMetadataPreload',receiver='_metadataPreload',file='vp_metadata_preload.dart',names=['_preloadEpisodeInfo','_retryAddonSubtitleFetchAfterSeriesMetadata','_fetchSingleFileMovieMetadata','_saveImdbIdToPlaylist','_saveSeriesPosterToPlaylist']),
]
# _seriesNextDispatched and _manualSelectionResetTimer stay State-owned: the
# scanner partition gives each same-line `//` comment to the NEXT member, so
# relocating either field would carry its neighbour's comment and strand its own.
FIELDS=['_shuffleBag','_showShuffle','_showShuffleInProgress','_activeShowShuffleGeneration']
TYPES={
 '_validationGateActive':'bool','_currentIptvChannel':'IptvChannel?','_iptvLiveRecovery':'IptvLiveRecovery','_hasIptvNext':'bool','_currentIptvIndex':'int','_continuousShuffleEnabled':'bool','_isAutoAdvancing':'bool','_sleepStopLatched':'bool','_activeMediaShouldPlay':'bool','_hasStremioTvNext':'bool','_activePlaylist':'List<PlaylistEntry>?',
 '_isTransitioning':'bool','_tvScrubGeneration':'int','_player':'mk.Player','_singleFileImdbId':'String?','_singleFileImdbFetched':'bool','_tvStaticMessage':'String','_tvStaticSubtext':'String','_pikPakRetryId':'int','_activeHttpHeaders':'Map<String, String>?','_currentStreamUrl':'String?','_duration':'Duration','_dynamicTitle':'String','_seriesPlaylist':'SeriesPlaylist?','_currentIndex':'int',
 '_canFetchEpisodes':'bool','_episodeFetchInProgress':'bool','_playlistIdentityToken':'int','_episodeNavigationGeneration':'int','_syntheticGuidePlaylist':'SeriesPlaylist?',
 '_hideTimer':'Timer?','_showShuffleGeneration':'int','_episodeMetadataReady':'Future<void>?','_currentSeriesImdbId':'String?','_random':'math.Random',
 '_effectiveContentTitle':'String?','_effectiveContentSeason':'int?','_effectiveContentEpisode':'int?','_effectiveStremioTvChannels':'List<Map<String, dynamic>>?','_hasStremioTvGuide':'bool','_effectiveIptvChannels':'List<IptvChannel>?',
 '_isManualEpisodeSelection':'bool','_allowResumeForManualSelection':'bool','_transitionStopTimer':'Timer?','_transitionPhaseTimer':'Timer?','_rainbowController':'AnimationController','_transitionRunning':'bool','_rainbowActive':'bool','_activeOpenedMedia':'mk.Media?','_activeMediaUserPaused':'bool','_resumeVerifyEpoch':'int','_resumeWriteGuard':'ResumeWriteGuard','_pausedByLifecycle':'bool','_serverWatch':'MediaServerWatchController','_openedWatchSource':'Torrent?',
 '_isPlaying':'bool','_seriesNextDispatched':'bool','_manualSelectionResetTimer':'Timer?','_isPikPakRetrying':'bool','_pikPakRetryMessage':'String?','_pikPakRetryCount':'int','_trackPreferencesReadyForAddonSubtitles':'bool',
}
ACTIONS={
 '_clearBufferingIndicator':('void clearBufferingIndicator()','()'),'_startTransitionOverlay':('void startTransitionOverlay()','()'),'_tvAbandonScrub':('void tvAbandonScrub()','()'),'_resetSubtitleState':('void resetSubtitleState()','()'),'_scheduleAutoHide':('void scheduleAutoHide()','()'),
 '_openMedia':('Future<void> openMedia(mk.Media media, {required bool play, bool? desiredPlay, bool liveStream = false, EpisodePlaybackRequest? request, bool Function()? beforeOpen, Torrent? source, int? preserveStartupEpoch})','(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)'),
 '_randomStartOffset':('Duration? randomStartOffset(Duration total)','(total)'),'_percentStartOffset':('Duration? percentStartOffset(Duration total)','(total)'),
 '_traktSeasonEpisode':('({int? season, int? episode}) traktSeasonEpisode()','()'),'_constructPlaylistItemData':('Map<String, dynamic>? constructPlaylistItemData()','()'),
 # Sibling routing (moved in this phase): targets resolve to _s.<receiver>.<name>.
 '_playShowShuffle':('Future<bool> playShowShuffle({bool autoAdvance = false})','(autoAdvance: autoAdvance)'),
 '_pickShuffleIndex':('int? pickShuffleIndex()','()'),
 '_loadPlaylistIndex':('Future<bool> loadPlaylistIndex(int index, {bool autoplay = false, EpisodePlaybackRequest? request, bool skipInitialSave = false, bool preferLocalResume = false, bool suppressResume = false, Torrent? manualValidationSource, int? manualValidationSourceIndex})','(index, autoplay: autoplay, request: request, skipInitialSave: skipInitialSave, preferLocalResume: preferLocalResume, suppressResume: suppressResume, manualValidationSource: manualValidationSource, manualValidationSourceIndex: manualValidationSourceIndex)'),
 '_findNextEpisodeIndex':('int findNextEpisodeIndex()','()'),
 '_goToNextEpisode':('Future<void> goToNextEpisode()','()'),
 '_fetchNextEpisodeInPlayer':('Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false})','(autoAdvance: autoAdvance)'),
 '_handleSeriesNextEpisode':('Future<bool> handleSeriesNextEpisode()','()'),
 '_setManualSelectionMode':('void setManualSelectionMode({bool allowResume = false})','(allowResume: allowResume)'),
 '_playPikPakVideoWithRetry':('Future<bool> playPikPakVideoWithRetry(String videoUrl, {String? overrideProvider, String? overridePikPakFileId, bool isDebrifyTV = false, bool showFailure = true, EpisodePlaybackRequest? request})','(videoUrl, overrideProvider: overrideProvider, overridePikPakFileId: overridePikPakFileId, isDebrifyTV: isDebrifyTV, showFailure: showFailure, request: request)'),
 '_waitForVideoReady':('Future<void> waitForVideoReady()','()'),
 '_getMainGroupIndices':('List<int> getMainGroupIndices(List<PlaylistEntry> entries)','(entries)'),
 '_preloadEpisodeInfo':('Future<void> preloadEpisodeInfo()','()'),
 '_resolvePlaylistEntryUrl':('Future<String> resolvePlaylistEntryUrl(int index)','(index)'),
 '_waitForVideoMetadata':('Future<bool> waitForVideoMetadata({int timeoutSeconds = 15, required int retryId, int additionalMonitoringSeconds = 0})','(timeoutSeconds: timeoutSeconds, retryId: retryId, additionalMonitoringSeconds: additionalMonitoringSeconds)'),
}
WIDGET={'requestMagicNext':'Future<Map<String, String>?> Function()?','startFromRandom':'bool','startAtPercent':'double?','contentType':'String?','contentImdbId':'String?','contentSeason':'int?','contentEpisode':'int?','contentTitle':'String?','title':'String','subtitle':'String?','seriesSourceFetcher':'SeriesSourceFetcher?','viewMode':'PlaylistViewMode?','rdTorrentId':'String?','torboxTorrentId':'String?','pikpakCollectionId':'String?'}
def chain(owner,member,forwarders,name=None):
 return dict(before=[owner,'.',member],name=name or member,forwarders=forwarders)
CHAINS=[
 chain('_resumeSave','observeServerWatch',['void observeServerWatch({bool completed = false}) => _s._resumeSave.observeServerWatch(completed: completed);']),
 chain('_resumeSave','saveResume',['Future<void> saveResume() => _s._resumeSave.saveResume();']),
 chain('_resumeRestore','maybeRestoreResume',['Future<void> maybeRestoreResume({bool preferLocalResume = false, bool verifyLanding = false}) => _s._resumeRestore.maybeRestoreResume(preferLocalResume: preferLocalResume, verifyLanding: verifyLanding);']),
 chain('_trakt','stopTraktHeartbeat',['void stopTraktHeartbeat() => _s._trakt.stopTraktHeartbeat();']),
 chain('_trakt','traktScrobble',['void traktScrobble(String action) => _s._trakt.traktScrobble(action);']),
 chain('_simkl','stopSimklHeartbeat',['void stopSimklHeartbeat() => _s._simkl.stopSimklHeartbeat();']),
 chain('_simkl','simklScrobble',['void simklScrobble(String action) => _s._simkl.simklScrobble(action);']),
 chain('_mdblist','mdblistStop',['void mdblistStop({bool complete = false}) => _s._mdblist.mdblistStop(complete: complete);']),
 chain('_mdblist','updateMdblistPosition',['void updateMdblistPosition() => _s._mdblist.updateMdblistPosition();']),
 chain('_mdblist','switchMdblistTarget',['Future<void> switchMdblistTarget() => _s._mdblist.switchMdblistTarget();']),
 chain('_completion','markCurrentEpisodeAsFinished',['Future<void> markCurrentEpisodeAsFinished() => _s._completion.markCurrentEpisodeAsFinished();']),
 chain('_completion','markCurrentMovieAsFinished',['Future<void> markCurrentMovieAsFinished() => _s._completion.markCurrentMovieAsFinished();']),
 chain('_completion','resetLocalCompletionState',['void resetLocalCompletionState() => _s._completion.resetLocalCompletionState();']),
 chain('_sleep','sleepTimerMode',['SleepTimerMode get sleepTimerMode => _s._sleep.sleepTimerMode;']),
 chain('_sleep','cancelSleepTimer',['void cancelSleepTimer() => _s._sleep.cancelSleepTimer();']),
 chain('_sleep','showSleepTimerToast',['void showSleepTimerToast(String message) => _s._sleep.showSleepTimerToast(message);']),
 chain('_iptvSwitch','switchToIptvChannel',['Future<void> switchToIptvChannel(int index, {bool quietRecovery = false}) => _s._iptvSwitch.switchToIptvChannel(index, quietRecovery: quietRecovery);']),
 chain('_stremioTv','goToNextStremioTvSlot',['Future<bool> goToNextStremioTvSlot({bool resumeCurrentOnFailure = true}) => _s._stremioTv.goToNextStremioTvSlot(resumeCurrentOnFailure: resumeCurrentOnFailure);']),
 chain('_subtitleApply','setSubtitleTrackWithDiagnostics',['Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent}) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(track, source: source, isCurrent: isCurrent);']),
 chain('_pip','iosPipSession',['PlayerPipSession? get iosPipSession => _s._pip.iosPipSession;']),
 chain('_menu','openPlayerMenuQuick',['void openPlayerMenuQuick(PlayerMenuSection section) => _s._menu.openPlayerMenuQuick(section);']),
 chain('_episodeGuide','buildSyntheticGuide',['(SeriesPlaylist, List<PlaylistEntry>)? buildSyntheticGuide() => _s._episodeGuide.buildSyntheticGuide();']),
 chain('_episodeFetch','fetchAndPlayEpisode',['Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(int season, int episode, {int? shuffleGeneration, bool autoAdvance = false, EpisodePlaybackRequest? request}) => _s._episodeFetch.fetchAndPlayEpisode(season, episode, shuffleGeneration: shuffleGeneration, autoAdvance: autoAdvance, request: request);']),
 chain('_skip','skipSegmentsMediaReady',['set skipSegmentsMediaReady(bool v) => _s._skip.skipSegmentsMediaReady = v;']),
 chain('_skip','resetSkipSegmentState',['void resetSkipSegmentState() => _s._skip.resetSkipSegmentState();']),
 chain('_startupCandidates','tryOpenStartupVod',['Future<bool> tryOpenStartupVod(String url, {Duration timeout = const Duration(seconds: 12), Map<String, String>? httpHeaders, Torrent? source, int? sourceIndex, int attempt = 1, int maxAttempts = 1}) => _s._startupCandidates.tryOpenStartupVod(url, timeout: timeout, httpHeaders: httpHeaders, source: source, sourceIndex: sourceIndex, attempt: attempt, maxAttempts: maxAttempts);']),
 chain('_trackPreferences','restoreTrackPreferences',['Future<void> restoreTrackPreferences() => _s._trackPreferences.restoreTrackPreferences();']),
 chain('_addonSubtitles','fetchAndMaybeAutoSelectAddonSubtitle',['Future<void> fetchAndMaybeAutoSelectAddonSubtitle() => _s._addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle();']),
]
SHADOWED_CONTEXT={'_showRandomPlaybackMenu':[(['ScaffoldMessenger','.','of','(','context'],['ScaffoldMessenger','.','of','(','_host','.','context']),([':','context',','],[':','_host','.','context',','])]}
# The formatter wraps a named record whose receiver-qualified line exceeds 80
# columns and adds its trailing comma; named-record commas are pinned, so the
# exact formatter-only edit is declared here (count 1, values unchanged).
FORMATTER_EDITS={'_getCurrentEpisodeTitleInfo':[([']','.','title',',','fetched',':','false',')'],[']','.','title',',','fetched',':','false',',',')'])]}
COMMON="import 'dart:async';\nimport 'package:flutter/material.dart';\nimport 'package:media_kit/media_kit.dart' as mk;\nimport 'package:debrify/models/playlist_entry.dart';\nimport 'package:debrify/models/series_playlist.dart';\nimport 'package:debrify/models/torrent.dart';\nimport 'package:debrify/utils/episode_playback_request.dart';\n"
def imp(*paths):return ''.join("import '"+x+";\n" if ' as ' in x else "import '"+x+"';\n" if x.startswith('dart:') else "import 'package:debrify/"+x+"';\n" for x in paths)
IMPORTS={g['name']:COMMON for g in GROUPS}
IMPORTS['VpPlaybackEnded']+=imp('models/iptv_playlist.dart','screens/video_player/services/iptv_live_recovery.dart','screens/video_player/widgets/sleep_timer_sheet.dart')
IMPORTS['VpEpisodeNext']+=imp('services/next_episode_service.dart','services/series_source_fetcher.dart','screens/video_player/player_pip_route.dart')
IMPORTS['VpEpisodeAdjacent']+=imp('models/playlist_view_mode.dart','services/adjacent_episode_resolver.dart','services/next_episode_service.dart','services/series_source_fetcher.dart')
IMPORTS['VpShuffle']+=imp('dart:math\' as math','models/playlist_view_mode.dart','services/series_source_fetcher.dart','utils/show_shuffle.dart','screens/video_player/widgets/player_menu_panel.dart','features/video_player/presentation/vp_random_choice_tile.dart')
IMPORTS['VpEpisodeTitleInfo']+=imp('models/iptv_playlist.dart')
IMPORTS['VpPlaylistLoad']+=imp('services/media_server_watch_sync.dart','services/resume_write_guard.dart','screens/video_player/constants/timing_constants.dart')
IMPORTS['VpPlaylistEntryResolve']+=imp('services/alldebrid_service.dart','services/debrid_service.dart','services/pikpak_api_service.dart','services/premiumize_service.dart','services/torbox_service.dart','services/storage/alldebrid_storage.dart','services/storage/premiumize_storage.dart','services/storage/real_debrid_storage.dart','services/storage/torbox_storage.dart')
IMPORTS['VpMetadataPreload']+=imp('services/movie_metadata_service.dart','services/storage/playlist_artwork_storage.dart','services/storage/playlist_metadata_storage.dart','utils/movie_parser.dart')

# Measured on the first probe compile: COMMON lines a destination never uses.
DROP={
 'VpPlaybackEnded':['models/series_playlist.dart','media_kit'],
 'VpEpisodeAdjacent':['media_kit','services/adjacent_episode_resolver.dart'],
 'VpShuffle':['media_kit'],
 'VpEpisodeTitleInfo':['models/torrent.dart','utils/episode_playback_request.dart','flutter/material.dart','media_kit'],
 'VpPlaylistEntryResolve':['models/series_playlist.dart','models/torrent.dart','utils/episode_playback_request.dart','flutter/material.dart','media_kit'],
 'VpMediaWaits':['models/playlist_entry.dart','models/series_playlist.dart','models/torrent.dart','utils/episode_playback_request.dart'],
 'VpPikPakRetry':['models/series_playlist.dart'],
 'VpMetadataPreload':['models/playlist_entry.dart','models/torrent.dart','utils/episode_playback_request.dart','media_kit'],
}
for c,drops in DROP.items():
 IMPORTS[c]=''.join(l+'\n' for l in IMPORTS[c].splitlines() if not any(d in l for d in drops))

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
   indices=occurrences(vals,[n]);write=any(vals[i+1] in ['=','++','--','??=','+='] for i in indices);read=any(vals[i+1] not in ['='] for i in indices);name=n[1:]
   if read:g['forwarders'].append(typ+' get '+name+' => _s.'+n+';')
   if write:g['forwarders'].append('set '+name+'('+typ+' v) => _s.'+n+' = v;')
   g['hosts'].append(n);hostbindings['_host.'+name]=STATE+'.'+n
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
 spec.update(phase=18,status='FINAL',span_order=list(spans),finalization=dict(label='FINAL',preparation_base=BASE,history='All seventeen applied phases; every earlier destination derived without a whitelist.'),provisional=dict(label='FINAL',preparation_base=BASE,pending=[],host_contracts={g['name']:g['forwarders'] for g in GROUPS},construction='Final assignments follow all five P17 collaborators.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Complete live collaborator chain via facade routing') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:byname[n]['name'] for n in FIELDS}),record_owners=[STATE],record_fields={STATE:FIELDS},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],adapter_state_prefixes=['_s'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 retained_sites=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None
  mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in byname};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping.update({n:['_host','.',n] for n in ['mounted','context','setState']})
  for n,after in mapping.items():
   if n not in vals:continue
   if moved and n=='context' and key.split('.')[-1] in SHADOWED_CONTEXT:
    # showDialog(context: context, builder: (context) {...}): only the State's
    # own reads move to the Host; the label, the builder parameter and the
    # builder's Navigator.of(context) keep the dialog context.
    for before,after2 in SHADOWED_CONTEXT[key.split('.')[-1]]:
     count=len(occurrences(vals,before))
     if count:edits.append(dict(before=before,after=after2,count=count))
    continue
   edits+=name_edits(vals,n,after)
  if moved:
   for before,after2 in FORMATTER_EDITS.get(key.split('.')[-1],[]):
    count=len(occurrences(vals,before));assert count==1,(key,before,count)
    edits.append(dict(before=before,after=after2,count=count))
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
   row.update(fate='patched',reason='Ten inert eager assignments after all five accepted P17 collaborators.',test='dev/tool/test_dart_navigation_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._episodeGuide'
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
 assert all(v<=500 for k,v in sizes.items() if k!='facade'),sizes
 if not a.no_check and not errors:(R/'dev/tool/dart_moves/vplayer_p18.json').write_text(json.dumps(spec,indent=2)+'\n')
 for file,value in [('membership.json',measured),('retained-sites.json',sites),('hosts.json',spec['provisional']['host_contracts']),('spec.json',spec),('result.json',dict(label='FINAL',comparison_errors=errors,sizes=sizes,retained_references=len(sites)))]: (a.probe/file).write_text(json.dumps(value,indent=2)+'\n')
 print('FINAL differences',len(errors),sizes,'retained',len(sites))
if __name__=='__main__':main()
