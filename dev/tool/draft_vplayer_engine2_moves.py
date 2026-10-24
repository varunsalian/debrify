#!/usr/bin/env python3
"""FINAL P20 evidence-only materialization on the phase-19 merge; never writes lib/.

Engine II: startup orchestration, player instance, instance subscriptions,
media open, network tuning and player defaults. Protects all nineteen
applied phases.
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
# Phase-19 merge; the phase-20 branch changes no lib/ file before step 1.
BASE='0f5bfb161'
EVIDENCE='refactor-evidence/vplayer/p20'
GROUPS=[
 dict(name='VpPlayerDefaults',receiver='_playerDefaults',file='vp_player_defaults.dart',names=['_loadPlayerDefaults']),
 dict(name='VpPlayerInstance',receiver='_playerInstance',file='vp_player_instance.dart',names=['_playerPresentationInitialized','_createPlayerInstance','_onPlayerInstanceReady']),
 dict(name='VpPlayerSubscriptions',receiver='_playerSubscriptions',file='vp_player_subscriptions.dart',names=['_bindPlayerInstanceSubscriptions','_cancelPlayerInstanceSubscriptions']),
 dict(name='VpNetworkTuning',receiver='_networkTuner',file='vp_network_tuning.dart',names=['_networkTuningDefaults','_networkTuningChain','_applyNetworkTuning','_applyNetworkTuningInner']),
 dict(name='VpMediaOpen',receiver='_mediaOpen',file='vp_media_open.dart',names=['_networkTuning','_beginMediaGeneration','_openMedia']),
 dict(name='VpPlayerStartup',receiver='_playerStartup',file='vp_player_startup.dart',names=['_initializePlayer','_getLastPlayedEpisode']),
]
# Single-writer fields (frozen ownership table, resolution P2-1).
FIELDS=['_playerPresentationInitialized','_networkTuningDefaults','_networkTuningChain','_networkTuning']
TYPES={
 '_activeHttpHeaders':'Map<String, String>?','_activeMediaShouldPlay':'bool','_activeMediaUserPaused':'bool','_activeOpenedMedia':'mk.Media?','_activePlaylist':'List<PlaylistEntry>?','_activeSkipSegmentUi':'SkipSegmentUiController','_activeSubtitleApplyAttempt':'VpSubtitleApplyAttempt?','_androidVideoRendererMode':'AndroidVideoRendererMode','_anyPlayerOverlayOpen':'bool','_appleMultichannelEnabled':'bool','_audioPassthroughEnabled':'bool','_autosaveTimer':'Timer?',
 '_bufferingDebounceTimer':'Timer?','_bufferingSub':'StreamSubscription?','_completedSub':'StreamSubscription?','_contentDisplayMatchMode':'ContentDisplayMatchMode','_controlsVisible':'ValueNotifier<bool>','_currentIndex':'int','_currentIptvChannel':'IptvChannel?','_currentSourceIndex':'int','_currentStreamUrl':'String?',
 '_decoderProbeGeneration':'int','_decoderProbeParams':'mk.VideoParams?','_decoderProbeTimer':'Timer?','_decoderProbeToken':'int','_durSub':'StreamSubscription?','_duration':'Duration','_dynamicTitle':'String',
 '_effectiveContentTitle':'String?','_effectiveContentType':'String?','_effectiveIptvChannels':'List<IptvChannel>?','_effectiveSources':'List<Torrent>?','_effectiveStremioTvChannels':'List<Map<String, dynamic>>?','_engineFlagOn':'bool','_episodeMetadataReady':'Future<void>?',
 '_hasSubtitlePolicy':'bool','_hideTimer':'Timer?','_iptvDiag':'IptvTuneDiagnostics','_iptvErrorSub':'StreamSubscription?','_iptvLiveRecovery':'IptvLiveRecovery','_isPikPakRetrying':'bool','_isPipActive':'bool','_isPlaying':'bool','_isReady':'bool','_isTransitioning':'bool',
 '_lastDecoderDiagnosticSignature':'String?','_openedWatchSource':'Torrent?','_paramsSub':'StreamSubscription?','_pausedByLifecycle':'bool','_playSub':'StreamSubscription?','_playbackUiClock':'PlaybackUiClockController','_player':'mk.Player','_playerCreated':'bool','_playerGuideStyle':'PlayerGuideStyle','_playerGuideTokens':'IptvStyleTokens?','_playerInstanceGeneration':'int','_posSub':'StreamSubscription?','_position':'Duration',
 '_rainbowActive':'bool','_rainbowController':'AnimationController','_recordingSupported':'bool','_rendererStartupErrorSub':'StreamSubscription?','_rendererStartupGuardToken':'int','_rendererStartupValidationGeneration':'int','_resumeVerifyEpoch':'int','_resumeWriteGuard':'ResumeWriteGuard',
 '_screenDisposed':'bool','_seriesPlaylist':'SeriesPlaylist?','_serverWatch':'MediaServerWatchController','_showBufferingIndicator':'ValueNotifier<bool>','_stremioTvStartupSeek':'DeferredStartupSeek','_stremioTvStartupWatch':'ChannelStartupWatch?','_subtitleDiagnosticLogSub':'StreamSubscription<mk.PlayerLog>?','_subtitleForcedOnly':'bool','_subtitleOnlyForeignAudio':'bool','_subtitlePreferredAudio':'String?','_systemAudioEffectsEnabled':'bool',
 '_trackSub':'StreamSubscription?','_transitionPhase':'int','_transitionPhase2Started':'DateTime?','_transitionPhaseTimer':'Timer?','_transitionRunning':'bool','_transitionStopTimer':'Timer?','_tvBarScope':'FocusScopeNode','_tvPlayPauseFocus':'FocusNode','_tvosDecodeRemedy':'TvosDecodeRemedy?','_tvosForceSoftwareDecode':'bool','_tvosForceStereoAudio':'bool','_tvosLegacyAudioOutput':'bool','_tvosRouteOutputChannels':'int',
 '_validationGateActive':'bool','_videoController':'mkv.VideoController','_watchOpenEpoch':'int',
}
STATICS={'_tvReleaseLogChannel':'MethodChannel'}
OPEN_SIG='Future<void> openMedia(mk.Media media, {required bool play, bool? desiredPlay, bool liveStream = false, EpisodePlaybackRequest? request, bool Function()? beforeOpen, Torrent? source, int? preserveStartupEpoch})'
OPEN_ARGS='(media, play: play, desiredPlay: desiredPlay, liveStream: liveStream, request: request, beforeOpen: beforeOpen, source: source, preserveStartupEpoch: preserveStartupEpoch)'
ACTIONS={
 # Retained State members (facade-owned; phase 21 or shared with adapters).
 '_loadDockPrefs':('Future<void> loadDockPrefs()','()'),
 '_randomStartOffset':('Duration? randomStartOffset(Duration duration)','(duration)'),
 '_percentStartOffset':('Duration? percentStartOffset(Duration duration)','(duration)'),
 '_scheduleAutoHide':('void scheduleAutoHide()','()'),
 # Sibling routing (moved in this phase): targets resolve to _s.<receiver>.<name>.
 '_loadPlayerDefaults':('Future<void> loadPlayerDefaults()','()'),
 '_createPlayerInstance':('void createPlayerInstance(AndroidVideoRendererMode rendererMode)','(rendererMode)'),
 '_bindPlayerInstanceSubscriptions':('void bindPlayerInstanceSubscriptions(int instanceGeneration, mk.Player player)','(instanceGeneration, player)'),
 '_applyNetworkTuning':('Future<void> applyNetworkTuning(mk.NativePlayer platform, NetworkTuning tuning, {required bool liveStream, required int generation})','(platform, tuning, liveStream: liveStream, generation: generation)'),
 '_openMedia':(OPEN_SIG,OPEN_ARGS),
}
WIDGET={'audioUrl':'String?','contentEpisode':'int?','contentSeason':'int?','disableAutoResume':'bool','httpHeaders':'Map<String, String>?','iptvStartIndex':'int?','requestMagicNext':'Future<Map<String, String>?> Function()?','startAtPercent':'double?','startFromRandom':'bool','startIndex':'int?','title':'String','videoUrl':'String'}
def chain(owner,member,forwarders,name=None):
 return dict(before=[owner,'.',member],name=name or member,forwarders=forwarders)
def fw(recv,sig,args,name):
 return chain(recv,name,[sig+' => _s.'+recv+'.'+name+args+';'])
def prop(recv,name,typ,get=True,set=True):
 return chain(recv,name,([typ+' get '+name+' => _s.'+recv+'.'+name+';'] if get else [])+(['set '+name+'('+typ+' v) => _s.'+recv+'.'+name+' = v;'] if set else []))
CHAINS=[
 # Live S2b projections (resolution P1-1): never cached; only the facade names VpS2Hooks.
 chain('VpS2Hooks','isAndroid',['bool get isAndroid => VpS2Hooks.isAndroid;']),
 chain('VpS2Hooks','isIOS',['bool get isIOS => VpS2Hooks.isIOS;']),
 # Private test seams (resolution P1-2): plain forwarders to the facade-private hooks.
 chain('VideoPlayerScreenTestHooks','_createPlayer',['mk.Player createPlayer({required mk.PlayerConfiguration configuration}) => VideoPlayerScreenTestHooks._createPlayer(configuration: configuration);'],name='createPlayer'),
 chain('VideoPlayerScreenTestHooks','_createVideoController',['mkv.VideoController createVideoController(mk.Player player, {required mkv.VideoControllerConfiguration configuration}) => VideoPlayerScreenTestHooks._createVideoController(player, configuration: configuration);'],name='createVideoController'),
 fw('_audioOutput','Future<void> attachAudioEffectSession()','()','attachAudioEffectSession'),
 fw('_audioOutput','Future<void> configurePlayerAudio(mk.Player player)','(player)','configurePlayerAudio'),
 fw('_audioOutput','Future<void> setExternalAudioTrack(String audioUrl)','(audioUrl)','setExternalAudioTrack'),
 fw('_completion','void checkAndApplyLocalCompletion()','()','checkAndApplyLocalCompletion'),
 fw('_debrifyBanner','void raiseDebrifyBanner()','()','raiseDebrifyBanner'),
 fw('_decoderProbe','void handleDecoderProbeParams(mk.VideoParams params)','(params)','handleDecoderProbeParams'),
 fw('_decoderProbe','Future<void> installDecoderObservers(int instanceGeneration, mk.Player player)','(instanceGeneration, player)','installDecoderObservers'),
 fw('_display','Future<void> applyAspectVideoZoom()','()','applyAspectVideoZoom'),
 prop('_display','aspectMode','AspectMode'),
 fw('_episodeAdjacent','List<int> getMainGroupIndices(List<PlaylistEntry> entries)','(entries)','getMainGroupIndices'),
 fw('_episodeFetch','void prepareNextDirectEpisode()','()','prepareNextDirectEpisode'),
 fw('_iptvBanner','void prepareIptvBannerData(IptvChannel channel)','(channel)','prepareIptvBannerData'),
 fw('_iptvBanner','void raiseIptvZapBanner()','()','raiseIptvZapBanner'),
 fw('_iptvGuide','void anchorIptvGuideCategory(IptvChannel channel, {Object? categories})','(channel, categories: categories)','anchorIptvGuideCategory'),
 fw('_iptvMemory','void noteLiveChannelPlaying()','()','noteLiveChannelPlaying'),
 fw('_iptvSources','void onIptvStreamError(String error)','(error)','onIptvStreamError'),
 fw('_mdblist','void mdblistPause()','()','mdblistPause'),
 fw('_mdblist','void mdblistPlay()','()','mdblistPlay'),
 fw('_mdblist','void updateMdblistPosition()','()','updateMdblistPosition'),
 fw('_mediaWaits','Future<void> waitForVideoReady()','()','waitForVideoReady'),
 fw('_metadataPreload','Future<void> preloadEpisodeInfo()','()','preloadEpisodeInfo'),
 fw('_pikPakRetry','Future<bool> playPikPakVideoWithRetry(String videoUrl, {String? overrideProvider, String? overridePikPakFileId, bool isDebrifyTV = false, bool showFailure = true, EpisodePlaybackRequest? request})','(videoUrl, overrideProvider: overrideProvider, overridePikPakFileId: overridePikPakFileId, isDebrifyTV: isDebrifyTV, showFailure: showFailure, request: request)','playPikPakVideoWithRetry'),
 fw('_pip','void armPipAutoEnter()','()','armPipAutoEnter'),
 prop('_pip','iosPipStarting','bool',set=False),
 prop('_pip','lastIosPipPositionSecond','int'),
 fw('_pip','void pushPipState()','()','pushPipState'),
 fw('_pip','void syncWakelock(bool playing)','(playing)','syncWakelock'),
 fw('_playbackEnded','Future<void> onPlaybackEnded()','()','onPlaybackEnded'),
 fw('_playlistEntryResolve','Future<String> resolvePlaylistEntryUrl(int index)','(index)','resolvePlaylistEntryUrl'),
 fw('_playlistLoad','Future<bool> loadPlaylistIndex(int index, {bool autoplay = false, EpisodePlaybackRequest? request, bool skipInitialSave = false, bool preferLocalResume = false, bool suppressResume = false, Torrent? manualValidationSource, int? manualValidationSourceIndex})','(index, autoplay: autoplay, request: request, skipInitialSave: skipInitialSave, preferLocalResume: preferLocalResume, suppressResume: suppressResume, manualValidationSource: manualValidationSource, manualValidationSourceIndex: manualValidationSourceIndex)','loadPlaylistIndex'),
 fw('_recording','Future<void> refreshEngineRecordingState()','()','refreshEngineRecordingState'),
 fw('_rendererFallback','Future<void> fallbackExplicitRendererToAutomatic({required int instanceGeneration, required int mediaGeneration, required String reason})','(instanceGeneration: instanceGeneration, mediaGeneration: mediaGeneration, reason: reason)','fallbackExplicitRendererToAutomatic'),
 fw('_resumeKeys','String resumeIdForEntry(PlaylistEntry entry)','(entry)','resumeIdForEntry'),
 fw('_resumeRestore','Future<void> maybeRestoreResume({bool preferLocalResume = false, bool verifyLanding = false})','(preferLocalResume: preferLocalResume, verifyLanding: verifyLanding)','maybeRestoreResume'),
 fw('_resumeRestore','Future<void> seekForResume(int targetMs, {bool verifyLanding = false})','(targetMs, verifyLanding: verifyLanding)','seekForResume'),
 fw('_resumeSave','void observeServerWatch({bool completed = false})','(completed: completed)','observeServerWatch'),
 fw('_resumeSave','Future<void> saveResume({bool debounced = false, Duration? positionOverride})','(debounced: debounced, positionOverride: positionOverride)','saveResume'),
 prop('_simkl','simklLastScrobbleAction','String?'),
 fw('_simkl','void simklScrobble(String action)','(action)','simklScrobble'),
 prop('_simkl','simklScrobbleEnabled','bool',set=False),
 fw('_simkl','void startSimklHeartbeat()','()','startSimklHeartbeat'),
 fw('_simkl','void stopSimklHeartbeat()','()','stopSimklHeartbeat'),
 prop('_skip','skipSegmentsMediaReady','bool',get=False),
 fw('_skip','void syncActiveSkipSegmentUi()','()','syncActiveSkipSegmentUi'),
 fw('_skip','void syncSkipSegmentsForCurrentContent()','()','syncSkipSegmentsForCurrentContent'),
 fw('_startupCandidates','Future<void> commitValidatedStremioSource(Torrent? source)','(source)','commitValidatedStremioSource'),
 fw('_startupFailover','Future<bool> openInitialVodWithFailover(String initialUrl, {Map<String, String>? httpHeaders, bool initialAttemptAlreadyFailed = false})','(initialUrl, httpHeaders: httpHeaders, initialAttemptAlreadyFailed: initialAttemptAlreadyFailed)','openInitialVodWithFailover'),
 fw('_startupGate','Future<void> reportStartupFailure({bool Function()? isCurrent})','(isCurrent: isCurrent)','reportStartupFailure'),
 fw('_startupGate','void resumeTrackingAfterValidationGate()','()','resumeTrackingAfterValidationGate'),
 fw('_startupGate','void setStartupGateActive(bool active)','(active)','setStartupGateActive'),
 fw('_startupGate','void watchStremioTvStartup(String url)','(url)','watchStremioTvStartup'),
 fw('_subtitleApply','Future<void> handleSubtitleApplyFailure(VpSubtitleApplyAttempt attempt, String reason)','(attempt, reason)','handleSubtitleApplyFailure'),
 fw('_subtitleLanguage','Future<void> refreshSubtitleAudioPolicy({bool reselect = true})','(reselect: reselect)','refreshSubtitleAudioPolicy'),
 fw('_subtitleSync','void installSubtitleAutoSyncForPlayer(mk.Player player)','(player)','installSubtitleAutoSyncForPlayer'),
 prop('_subtitleSync','subtitleAutoSync','MediaKitSubtitleAutoSync?',set=False),
 prop('_subtitleSync','subtitleAutoSyncEnabled','bool'),
 fw('_trackPreferences','Future<void> restoreTrackPreferences()','()','restoreTrackPreferences'),
 fw('_trakt','void startTraktHeartbeat()','()','startTraktHeartbeat'),
 fw('_trakt','void stopTraktHeartbeat()','()','stopTraktHeartbeat'),
 prop('_trakt','traktLastScrobbleAction','String?',set=False),
 fw('_trakt','void traktScrobble(String action)','(action)','traktScrobble'),
 fw('_tvosVideo','void installTvosDecodeRemedy(mk.Player player)','(player)','installTvosDecodeRemedy'),
 fw('_tvosVideo','void resetTvosDisplayMatchForMediaBoundary()','()','resetTvosDisplayMatchForMediaBoundary'),
 fw('_videoOutputLease','Future<void> claimVideoOutput()','()','claimVideoOutput'),
 fw('_zapRing','void ensureIptvZapPagingArmed()','()','ensureIptvZapPagingArmed'),
]
# PlayerVisibility keys owners by identity (resolution P3-2): `this` becomes the State itself.
OWNER=dict(before=['this'],name='visibilityOwner',forwarders=['Object get visibilityOwner => _s;'])
# Earlier scaffolding adapters whose forwarders reach a moved member: receiver rewrites only.
PATCHED=['_VpRendererFallbackHostAdapter','_VpPikPakRetryHostAdapter','_VpPlaylistLoadHostAdapter','_VpEpisodeNextHostAdapter','_VpStremioTvChannelsHostAdapter','_VpDebrifyTvChannelsHostAdapter','_VpSourcePlaylistSwitchHostAdapter','_VpSourceSwitchHostAdapter','_VpStartupCandidatesHostAdapter','_VpIptvLiveSourcesHostAdapter','_VpIptvChannelSwitchHostAdapter','_VpIptvGuideCatchupHostAdapter']
EXPECTED_HOSTS={'VpPlayerDefaults':(16,20),'VpPlayerInstance':(26,27),'VpPlayerSubscriptions':(74,94),'VpNetworkTuning':(1,1),'VpMediaOpen':(34,42),'VpPlayerStartup':(70,75)}
SIZE_LIMIT={'VpPlayerStartup':800}
def imp(*paths):return ''.join("import '"+x+";\n" if ' as ' in x else "import '"+x+"';\n" if x.startswith('dart:') else "import 'package:"+x+"';\n" if x.startswith(('flutter/','media_kit')) else "import 'package:debrify/"+x+"';\n" for x in paths)
MK="package:media_kit/media_kit.dart' as mk"
MKV="package:media_kit_video/media_kit_video.dart' as mkv"
IMPORTS={
 'VpPlayerDefaults':imp('dart:io','flutter/foundation.dart','flutter/services.dart','models/content_display_match_mode.dart','screens/video_player/models/gesture_state.dart','screens/video_player/widgets/player_guide_style.dart','services/storage/iptv_appearance_storage.dart','services/storage/player_network_storage.dart','services/storage/player_settings_storage.dart','services/storage/subtitle_settings_storage.dart','services/tvos_display_match_service.dart','utils/platform_util.dart','widgets/iptv/styles/iptv_style.dart'),
 'VpPlayerInstance':imp('dart:async','flutter/widgets.dart',MK,MKV,'models/android_video_renderer_mode.dart','models/iptv_playlist.dart','utils/platform_util.dart'),
 'VpPlayerSubscriptions':imp('dart:async','flutter/widgets.dart',MK,'features/video_player/models/vp_subtitle_apply_attempt.dart','models/iptv_playlist.dart','models/torrent.dart','screens/video_player/constants/timing_constants.dart','screens/video_player/services/android_renderer_startup_fallback.dart','screens/video_player/services/iptv_live_recovery.dart','screens/video_player/services/iptv_tune_diagnostics.dart','screens/video_player/services/media_kit_subtitle_auto_sync.dart','screens/video_player/services/playback_ui_clock.dart','services/player_visibility.dart','services/profiles/profile_lock_controller.dart','services/source_selection_diagnostics.dart','services/startup_stream_policy.dart'),
 'VpNetworkTuning':imp('flutter/foundation.dart',MK,'screens/video_player/services/network_tuning.dart'),
 'VpMediaOpen':imp('dart:async','flutter/foundation.dart',MK,'models/torrent.dart','screens/video_player/services/network_tuning.dart','screens/video_player/services/playback_ui_clock.dart','screens/video_player/services/skip_segment_ui_controller.dart','services/direct_source_authorization.dart','services/media_server_watch_sync.dart','services/player_visibility.dart','services/resume_write_guard.dart','services/source_selection_diagnostics.dart','services/startup_stream_policy.dart','services/tvos_decode_remedy.dart','utils/episode_playback_request.dart'),
 'VpPlayerStartup':imp('dart:async','dart:io','flutter/foundation.dart',MK,'models/android_video_renderer_mode.dart','models/iptv_playlist.dart','models/profiles/profile_policy.dart','models/series_playlist.dart','models/torrent.dart','screens/video_player/models/playlist_entry.dart','screens/video_player/services/iptv_live_recovery.dart','screens/video_player/services/iptv_tune_diagnostics.dart','services/android_native_downloader.dart','services/live_recording_service.dart','services/profiles/profile_policy_guard.dart','services/profiles/profile_runtime.dart','services/startup_stream_policy.dart','services/storage/episode_resume_storage.dart','services/storage/player_settings_storage.dart','services/storage/video_progress_storage.dart','utils/episode_playback_request.dart','utils/platform_util.dart'),
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
  for c in CHAINS+[OWNER]:
   if occurrences(vals,c['before']):g['forwarders']+=c['forwarders']
  g['host_names']=[host_name(f) for f in g['forwarders']]
  assert len(g['forwarders'])==len(set(g['forwarders'])),g['name']
  if EXPECTED_HOSTS is not None:assert (len(set(g['host_names'])),len(g['host_names']))==EXPECTED_HOSTS[g['name']],(g['name'],g['host_names'])
 spec.update(phase=20,status='applied',span_order=list(spans),patched_class_projection=PATCHED,finalization=dict(label='FINAL',preparation_base=BASE,accepted_p19=BASE,seam_original=BASE,history='All nineteen applied phases; every earlier destination derived without a whitelist.'),provisional=dict(label='FINAL',preparation_base=BASE,pending=[],host_contracts={g['name']:g['forwarders'] for g in GROUPS},construction='Six inert eager assignments follow all five P19 collaborators.'))
 registrations=[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='live widget selector') for n in WIDGET]+[dict(before=c['before'],after=['_host','.',c['name']],binding='unbound',role_change='Live S2b projection' if c['before'][0]=='VpS2Hooks' else 'Private test seam forwarder' if c['before'][0]=='VideoPlayerScreenTestHooks' else 'Complete live collaborator chain via facade routing') for c in CHAINS]
 spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'.'+n:byname[n]['name'] for n in FIELDS}),record_owners=[STATE],record_fields={STATE:FIELDS},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],host_owner_identity=['_host.'+OWNER['name']],adapter_state_prefixes=['_s'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=registrations)
 retained_sites=[];patched=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None
  mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in byname};vals=tokens(spans[key]);edits=[]
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping.update({n:['_host','.',n] for n in ['mounted','context','setState']})
   if 'this' in vals:mapping['this']=['_host','.',OWNER['name']]
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
   row.update(fate='patched',reason='Route the P16-P19 adapter forwarder to its P20 owner, preserving every earlier rewrite.',test='dev/tool/draft_vplayer_engine2_moves.py',patches=sorted(edits,key=lambda e:json.dumps(e['before'])));patched.append(key);measured.append(dict(declaration=key,fate='patched',edits=edits));edits=[]
  if edits:row['substitutions']=sorted(edits,key=lambda e:json.dumps(e['before']));measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Six inert eager assignments after all five accepted P19 collaborators.',test='dev/tool/draft_vplayer_engine2_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 assert sorted(patched)==sorted(PATCHED),patched
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._rendererFallback'
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
 if not a.no_check and not errors and all(v<=SIZE_LIMIT.get(k,500) for k,v in sizes.items() if k!='facade'):(R/'dev/tool/dart_moves/vplayer_p20.json').write_text(json.dumps(spec,indent=2)+'\n')
 for file,value in [('membership.json',measured),('retained-sites.json',sites),('hosts.json',spec['provisional']['host_contracts']),('spec.json',spec),('result.json',dict(label='FINAL',comparison_errors=errors,sizes=sizes,hosts=hosts,retained_references=len(sites)))]: (a.probe/file).write_text(json.dumps(value,indent=2)+'\n')
 print('FINAL differences',len(errors),sizes,hosts,'retained',len(sites))
 for e in errors[:40]:print(' ',e)
 assert all(v<=SIZE_LIMIT.get(k,500) for k,v in sizes.items() if k!='facade'),sizes
if __name__=='__main__':main()
