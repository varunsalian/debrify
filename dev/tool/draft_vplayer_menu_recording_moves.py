#!/usr/bin/env python3
"""Materialize the frozen Phase-13 four-file menu/recording boundary in evidence."""
import argparse,json,subprocess
from pathlib import Path
from check_verbatim_moves import ROOT as R, ensure_parser_package,parse
from check_settings_moves import tokens
from check_dart_moves import retained_manifest,check
from dart_move_partition import partition,frozen
from dart_move_history import git_text,check_earlier
from dart_move_fixture import edited_text,materialize
SOURCE='lib/screens/video_player_screen.dart';FEATURE='lib/features/video_player';STATE='_VideoPlayerScreenState'
BASE='1099a0039dab6023aef8c95754e4595e862e9a67'
GROUPS=[
 dict(name='VpPlayerMenuUi',receiver='_menuUi',file='vp_player_menu_ui.dart',names=['_showTracksSheet','_buildPlayerMenuPanel']),
 dict(name='VpPlayerMenu',receiver='_menu',file='vp_player_menu.dart',names=['_openPlayerMenuAt','_openPlayerMenuQuick','_hidePlayerMenu','_menuApplyTrackChange','_audioTrackChoiceChanged','_menuSelectAudio','_withManualSubtitleChoice','_menuSubtitlesOff','_menuSelectEmbeddedSubtitle','_menuSelectAddonSubtitle','_applyStremioSubtitleFromTracksSheet']),
 dict(name='VpIptvRecording',receiver='_recording',file='vp_iptv_recording.dart',names=['_toggleRecording','_startRecording','_stopRecording','_disarmStrayRecording','_refreshEngineRecordingState','_publishRecording','_canRecord','_recordingActiveNow','_engineRefreshTicket']),
 dict(name='VpIptvRecordingResources',receiver='_recordingResources',file='vp_iptv_recording_resources.dart',names=['_desktopCaptureForCurrent','_playingLiveUrl','_engineRecordUrlForCurrent','_recordingFileName','_currentRecordingResource','_tapMpvLogsForRecording','_untapMpvLogs','_recordingTargetPath']),
]
TYPES={
 '_activePlaylist':'List<PlaylistEntry>?','_addonSubtitleFetchToken':'int','_audioPassthroughEnabled':'bool','_cachedAddonSlots':'List<AddonSubtitleSlot>?','_cachedStremioSubtitles':'List<StremioSubtitle>?','_cachedSubtitleKey':'String?','_canFetchEpisodes':'bool','_continuousShuffleEnabled':'bool','_controlsVisible':'ValueNotifier<bool>','_currentIndex':'int','_currentIptvChannel':'IptvChannel?','_effectiveContentEpisode':'int?','_effectiveContentImdbId':'String?','_effectiveContentSeason':'int?','_effectiveContentType':'String?','_hasSubtitlePolicy':'bool','_hideTimer':'Timer?','_injectedSubtitleSlots':'List<AddonSubtitleSlot>?','_iptvZapBannerOwnsIdentity':'bool','_manualContentEpisode':'int?','_manualContentImdbId':'String?','_manualContentSeason':'int?','_manualContentType':'String?','_menuCacheKey':'String?','_menuCachedSlots':'List<AddonSubtitleSlot>?','_menuContentType':'String?','_menuEpisode':'int?','_menuImdbId':'String?','_menuSeason':'int?','_player':'mk.Player','_playerMenuInitialSection':'PlayerMenuSection','_playerMenuKey':'GlobalKey<PlayerMenuPanelState>','_selectedStremioSubtitleId':'String?','_seriesPlaylist':'SeriesPlaylist?','_showPlayerMenu':'bool','_singleFileImdbFetched':'bool','_singleFileImdbId':'String?','_subtitleAudioRevision':'int','_subtitleSelectionCorrection':'ValueNotifier<String?>','_tvRootFocus':'FocusNode','_userManuallySelectedSubtitle':'bool',
 '_currentStreamUrl':'String?','_engineFlagOn':'bool','_engineRefreshTicket':'int','_engineTaskId':'String?','_isRecording':'bool','_playerCreated':'bool','_recordLogSub':'StreamSubscription<mk.PlayerLog>?','_recordingStartGen':'int','_recordingSupported':'bool','_recordingTempPath':'String?',
}
ACTIONS={
 '_openPlayerMenuAt':'void openPlayerMenuAt(PlayerMenuSection section, {String? imdbId, String? contentType, int? season, int? episode, List<AddonSubtitleSlot>? cachedSlots, String? cacheKey})',
 '_hidePlayerMenu':'void hidePlayerMenu()',
 '_audioTrackChoiceChanged':'Future<void> audioTrackChoiceChanged(String audioId, String currentSubId)',
 '_withManualSubtitleChoice':'Future<bool> withManualSubtitleChoice(Future<bool> Function() apply)',
 '_applyStremioSubtitleFromTracksSheet':'Future<bool> applyStremioSubtitleFromTracksSheet(StremioSubtitle sub)',
 '_menuSelectAudio':'Future<void> menuSelectAudio(String audioId, String currentSubId)',
 '_menuSubtitlesOff':'Future<bool> menuSubtitlesOff(String audioId)',
 '_menuSelectEmbeddedSubtitle':'Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId)',
 '_menuSelectAddonSubtitle':'Future<bool> menuSelectAddonSubtitle(StremioSubtitle sub, String audioId)',
 '_captureIptvAudioLanguage':'void captureIptvAudioLanguage(String audioId)',
 '_fetchSingleFileMovieMetadata':'Future<void> fetchSingleFileMovieMetadata()',
 '_hideIptvZapBanner':'void hideIptvZapBanner({bool immediate = false})',
 '_playRandomOnce':'Future<void> playRandomOnce({bool disableContinuousShuffle = false})',
 '_setAudioPassthroughLive':'Future<void> setAudioPassthroughLive(bool enabled)',
 '_toggleContinuousShuffle':'Future<void> toggleContinuousShuffle()',
 '_tvReleaseFocusForOverlay':'void tvReleaseFocusForOverlay()',
 '_desktopCaptureForCurrent':'DesktopRecordingCapture? desktopCaptureForCurrent()',
 '_playingLiveUrl':'String? playingLiveUrl(IptvChannel channel)',
 '_engineRecordUrlForCurrent':'Future<String?> engineRecordUrlForCurrent()',
 '_recordingFileName':'String recordingFileName(String channelName)',
 '_currentRecordingResource':'Future<({String id, int revision})?> currentRecordingResource()',
 '_tapMpvLogsForRecording':'void tapMpvLogsForRecording()',
 '_untapMpvLogs':'void untapMpvLogs()',
 '_recordingTargetPath':"Future<String> recordingTargetPath(String channelName, {String extension = 'mkv'})",
}
ARGS={n:'()' for n in ACTIONS}
ARGS.update({
 '_openPlayerMenuAt':'(section, imdbId: imdbId, contentType: contentType, season: season, episode: episode, cachedSlots: cachedSlots, cacheKey: cacheKey)',
 '_audioTrackChoiceChanged':'(audioId, currentSubId)','_withManualSubtitleChoice':'(apply)','_applyStremioSubtitleFromTracksSheet':'(sub)',
 '_menuSelectAudio':'(audioId, currentSubId)','_menuSubtitlesOff':'(audioId)','_menuSelectEmbeddedSubtitle':'(subId, audioId)','_menuSelectAddonSubtitle':'(sub, audioId)',
 '_captureIptvAudioLanguage':'(audioId)','_hideIptvZapBanner':'(immediate: immediate)','_playRandomOnce':'(disableContinuousShuffle: disableContinuousShuffle)',
 '_setAudioPassthroughLive':'(enabled)','_playingLiveUrl':'(channel)','_recordingFileName':'(channelName)','_recordingTargetPath':'(channelName, extension: extension)',
})
CHAINS=[]
def chain(receiver, member, signature, args='()'):
 CHAINS.append(([receiver,'.',member],['_host','.',member],signature,args))
chain('_identify','currentPlaybackTitleForIdentity','String currentPlaybackTitleForIdentity()')
chain('_identify','identifyTitleAndFetchSubtitles','Future<TracksSheetSubtitleSearchResult?> identifyTitleAndFetchSubtitles()')
chain('_identify','subtitleIdentityLabelForSheet','String? subtitleIdentityLabelForSheet()')
chain('_subtitleSync','setActiveExternalSubtitlePath','void setActiveExternalSubtitlePath(String? path)','(path)')
chain('_subtitleSync','resetSubtitleSyncOffset','void resetSubtitleSyncOffset()')
chain('_subtitleSync','onSubtitleStyleChanged','void onSubtitleStyleChanged(SubtitleSettingsData settings)','(settings)')
chain('_subtitleSync','showSyncOverlayPanel','void showSyncOverlayPanel()')
chain('_trackPreferences','persistTrackChoice','Future<void> persistTrackChoice(String audioId, String subtitleId)','(audioId, subtitleId)')
chain('_subtitleApply','setSubtitleTrackWithDiagnostics','Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required String source, bool Function()? isCurrent})','(track, source: source, isCurrent: isCurrent)')
chain('_subtitleApply','showSubtitleFailureMessage','void showSubtitleFailureMessage(String message)','(message)')
chain('_subtitleLanguage','refreshSubtitleAudioPolicy','Future<void> refreshSubtitleAudioPolicy({bool reselect = true})','(reselect: reselect)')
chain('_addonSubtitles','downloadStremioSubtitleToTempFile','Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub)','(sub)')
chain('_addonSubtitles','applyExternalSubtitleTrack','Future<bool> applyExternalSubtitleTrack(mk.SubtitleTrack track)','(track)')
chain('_display','playbackSpeed','double get playbackSpeed','')
chain('_display','setPlaybackSpeed','void setPlaybackSpeed(double speed)','(speed)')
chain('_display','aspectMode','AspectMode get aspectMode','')
chain('_display','setAspectModeDirect','void setAspectModeDirect(AspectMode mode)','(mode)')
chain('_sleep','sleepTimerMode','SleepTimerMode get sleepTimerMode','')
chain('_sleep','sleepTimerArmedMinutes','int get sleepTimerArmedMinutes','')
chain('_sleep','sleepTimerMinutesLeft','int get sleepTimerMinutesLeft','')
chain('_sleep','applySleepTimerSelection','void applySleepTimerSelection(SleepTimerSelection picked)','(picked)')
CHAINS.append((['VpS2Hooks','.','isIOS'],['_host','.','isIOS'],'bool get isIOS',''))
WIDGETS={'iptvSourceId':'String?','iptvSources':'List<Map<String, dynamic>>?'}
imports={
'VpPlayerMenuUi':"""import 'dart:io';
import 'dart:async';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/tracks_sheet.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';
import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
""",
'VpPlayerMenu':"""import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/tracks_sheet.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
""",
'VpIptvRecording':"""import 'dart:async';
import 'dart:io';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
""",
'VpIptvRecordingResources':"""import 'dart:async';
import 'dart:io';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';
""",
}
for unused in ['package:debrify/models/iptv_playlist.dart','package:debrify/screens/video_player/services/subtitle_settings_service.dart','package:debrify/screens/video_player/widgets/tracks_sheet.dart']:
 imports['VpPlayerMenu']=imports['VpPlayerMenu'].replace("import '"+unused+"';\n",'')
imports={name:'\n'.join(sorted(text.strip().splitlines()))+'\n' for name,text in imports.items()}
FROZEN_HOSTS = {'VpPlayerMenuUi': ['List<PlaylistEntry>? get activePlaylist',
                    'Future<bool> applyStremioSubtitleFromTracksSheet(StremioSubtitle sub)',
                    'bool get audioPassthroughEnabled',
                    'Future<void> audioTrackChoiceChanged(String audioId, String currentSubId)',
                    'List<AddonSubtitleSlot>? get cachedAddonSlots',
                    'set cachedAddonSlots(List<AddonSubtitleSlot>? v)',
                    'set cachedStremioSubtitles(List<StremioSubtitle>? v)',
                    'String? get cachedSubtitleKey',
                    'set cachedSubtitleKey(String? v)',
                    'bool get canFetchEpisodes',
                    'void captureIptvAudioLanguage(String audioId)',
                    'bool get continuousShuffleEnabled',
                    'int get currentIndex',
                    'IptvChannel? get currentIptvChannel',
                    'int? get effectiveContentEpisode',
                    'String? get effectiveContentImdbId',
                    'int? get effectiveContentSeason',
                    'String? get effectiveContentType',
                    'Future<void> fetchSingleFileMovieMetadata()',
                    'void hidePlayerMenu()',
                    'List<AddonSubtitleSlot>? get injectedSubtitleSlots',
                    'bool get iptvZapBannerOwnsIdentity',
                    'int? get manualContentEpisode',
                    'String? get manualContentImdbId',
                    'int? get manualContentSeason',
                    'String? get manualContentType',
                    'String? get menuCacheKey',
                    'List<AddonSubtitleSlot>? get menuCachedSlots',
                    'String? get menuContentType',
                    'int? get menuEpisode',
                    'String? get menuImdbId',
                    'int? get menuSeason',
                    'Future<bool> menuSelectAddonSubtitle(StremioSubtitle sub, String audioId)',
                    'Future<void> menuSelectAudio(String audioId, String currentSubId)',
                    'Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId)',
                    'Future<bool> menuSubtitlesOff(String audioId)',
                    'void openPlayerMenuAt(PlayerMenuSection section, {String? imdbId, String? '
                    'contentType, int? season, int? episode, List<AddonSubtitleSlot>? cachedSlots, '
                    'String? cacheKey})',
                    'Future<void> playRandomOnce({bool disableContinuousShuffle = false})',
                    'mk.Player get player',
                    'PlayerMenuSection get playerMenuInitialSection',
                    'GlobalKey<PlayerMenuPanelState> get playerMenuKey',
                    'String? get selectedStremioSubtitleId',
                    'set selectedStremioSubtitleId(String? v)',
                    'SeriesPlaylist? get seriesPlaylist',
                    'Future<void> setAudioPassthroughLive(bool enabled)',
                    'bool get singleFileImdbFetched',
                    'String? get singleFileImdbId',
                    'ValueNotifier<String?> get subtitleSelectionCorrection',
                    'Future<void> toggleContinuousShuffle()',
                    'set userManuallySelectedSubtitle(bool v)',
                    'Future<bool> withManualSubtitleChoice(Future<bool> Function() apply)',
                    'String currentPlaybackTitleForIdentity()',
                    'Future<TracksSheetSubtitleSearchResult?> identifyTitleAndFetchSubtitles()',
                    'String? subtitleIdentityLabelForSheet()',
                    'void setActiveExternalSubtitlePath(String? path)',
                    'void resetSubtitleSyncOffset()',
                    'void onSubtitleStyleChanged(SubtitleSettingsData settings)',
                    'void showSyncOverlayPanel()',
                    'Future<void> persistTrackChoice(String audioId, String subtitleId)',
                    'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, '
                    '{required String source, bool Function()? isCurrent})',
                    'double get playbackSpeed',
                    'void setPlaybackSpeed(double speed)',
                    'AspectMode get aspectMode',
                    'void setAspectModeDirect(AspectMode mode)',
                    'SleepTimerMode get sleepTimerMode',
                    'int get sleepTimerArmedMinutes',
                    'int get sleepTimerMinutesLeft',
                    'void applySleepTimerSelection(SleepTimerSelection picked)'],
 'VpPlayerMenu': ['void setState(VoidCallback fn)',
                  'bool get mounted',
                  'int get addonSubtitleFetchToken',
                  'List<AddonSubtitleSlot>? get cachedAddonSlots',
                  'String? get cachedSubtitleKey',
                  'void captureIptvAudioLanguage(String audioId)',
                  'ValueNotifier<bool> get controlsVisible',
                  'int get currentIndex',
                  'int? get effectiveContentEpisode',
                  'String? get effectiveContentImdbId',
                  'int? get effectiveContentSeason',
                  'String? get effectiveContentType',
                  'bool get hasSubtitlePolicy',
                  'void hideIptvZapBanner({bool immediate = false})',
                  'Timer? get hideTimer',
                  'List<AddonSubtitleSlot>? get injectedSubtitleSlots',
                  'int? get manualContentEpisode',
                  'String? get manualContentImdbId',
                  'int? get manualContentSeason',
                  'String? get manualContentType',
                  'set menuCacheKey(String? v)',
                  'set menuCachedSlots(List<AddonSubtitleSlot>? v)',
                  'set menuContentType(String? v)',
                  'set menuEpisode(int? v)',
                  'set menuImdbId(String? v)',
                  'set menuSeason(int? v)',
                  'mk.Player get player',
                  'set playerMenuInitialSection(PlayerMenuSection v)',
                  'set selectedStremioSubtitleId(String? v)',
                  'SeriesPlaylist? get seriesPlaylist',
                  'bool get showPlayerMenu',
                  'set showPlayerMenu(bool v)',
                  'String? get singleFileImdbId',
                  'int get subtitleAudioRevision',
                  'set subtitleAudioRevision(int v)',
                  'void tvReleaseFocusForOverlay()',
                  'FocusNode get tvRootFocus',
                  'bool get userManuallySelectedSubtitle',
                  'set userManuallySelectedSubtitle(bool v)',
                  'String currentPlaybackTitleForIdentity()',
                  'void setActiveExternalSubtitlePath(String? path)',
                  'Future<void> persistTrackChoice(String audioId, String subtitleId)',
                  'Future<bool> setSubtitleTrackWithDiagnostics(mk.SubtitleTrack track, {required '
                  'String source, bool Function()? isCurrent})',
                  'void showSubtitleFailureMessage(String message)',
                  'Future<void> refreshSubtitleAudioPolicy({bool reselect = true})',
                  'Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub)',
                  'Future<bool> applyExternalSubtitleTrack(mk.SubtitleTrack track)'],
 'VpIptvRecording': ['void setState(VoidCallback fn)',
                     'BuildContext get context',
                     'bool get mounted',
                     'IptvChannel? get currentIptvChannel',
                     'Future<({String id, int revision})?> currentRecordingResource()',
                     'DesktopRecordingCapture? desktopCaptureForCurrent()',
                     'bool get engineFlagOn',
                     'Future<String?> engineRecordUrlForCurrent()',
                     'String? get engineTaskId',
                     'set engineTaskId(String? v)',
                     'bool get iptvZapBannerOwnsIdentity',
                     'bool get isRecording',
                     'set isRecording(bool v)',
                     'mk.Player get player',
                     'bool get playerCreated',
                     'String? playingLiveUrl(IptvChannel channel)',
                     'String recordingFileName(String channelName)',
                     'int get recordingStartGen',
                     'set recordingStartGen(int v)',
                     'bool get recordingSupported',
                     'Future<String> recordingTargetPath(String channelName, {String extension = '
                     "'mkv'})",
                     'String? get recordingTempPath',
                     'set recordingTempPath(String? v)',
                     'void tapMpvLogsForRecording()',
                     'void untapMpvLogs()',
                     'bool get isIOS'],
 'VpIptvRecordingResources': ['IptvChannel? get currentIptvChannel',
                              'String? get currentStreamUrl',
                              'mk.Player get player',
                              'StreamSubscription<mk.PlayerLog>? get recordLogSub',
                              'set recordLogSub(StreamSubscription<mk.PlayerLog>? v)',
                              'String? get iptvSourceId',
                              'List<Map<String, dynamic>>? get iptvSources']}

def build(package):
 original=git_text(BASE,SOURCE);spec=retained_manifest(SOURCE,FEATURE,original,BASE,package);u=parse({'base':original},package,ownership=True)['base'];spans,_,nodes=partition(u,[STATE]);byname={n:g for g in GROUPS for n in g['names']};allnames=set(byname);hostbindings={};widgetnames=[]
 for g in GROUPS:
  g['dest']=FEATURE+'/presentation/legacy_video_player/'+g['file'];g['forwarders']=[];g['hosts']=[];needed=set();writes=set();reads=set()
  for n in g['names']:
   v=tokens(spans[STATE+'.'+n]);needed.update(x for x in v if (x in TYPES or x in ACTIONS) and x not in g['names'])
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
  if g['name']!='VpPlayerMenuUi' and 'mounted' in values:g['forwarders'].insert(0,'bool get mounted => _s.mounted;')
  if g['name']!='VpPlayerMenuUi' and 'context' in values:g['forwarders'].insert(0,'BuildContext get context => _s.context;')
  if 'setState' in values:g['forwarders'].insert(0,'void setState(VoidCallback fn) => _s._vpSetState(fn);')
  for name,typ in WIDGETS.items():
   if any(values[i:i+3]==['widget','.',name] for i in range(len(values))):g['forwarders'].append(typ+' get '+name+' => _s.widget.'+name+';');widgetnames.append(name)
  for before,after,signature,args in CHAINS:
   if any(values[i:i+len(before)]==before for i in range(len(values))):g['forwarders'].append(signature+' => '+('' if before[0]=='VpS2Hooks' else '_s.')+''.join(before)+args+';')
 for g in GROUPS:
  if FROZEN_HOSTS is not None: assert [f.split(' => ')[0] for f in g['forwarders']]==FROZEN_HOSTS[g['name']],('Host drift',g['name'])
 spec.update(phase=13,status='draft',span_order=list(spans),patched_class_projection=['_VpDisplayModeHostAdapter','_VpSleepTimerHostAdapter'])
 spec['relocated_initializers']={STATE+'._engineRefreshTicket':{'target':'VpIptvRecording.engineRefreshTicket','initializer':'0','proof':'Literal integer; no allocation, Host read, scheduling or interaction with any other initializer; eager modifier preserved.'}}
 spec['seam_checkpoints']={'S':'dev/tool/dart_moves/vplayer_p1_seam.json','S2/S2b':'dev/tool/dart_moves/vplayer_p8_seam.json','S2c':'dev/tool/dart_moves/vplayer_p10_seam.json','S2d':{'manifest':'dev/tool/dart_moves/vplayer_p13_seam.json','original':BASE,'sites':{'initState':'retained native-support then live isIOS check','_toggleRecording':'moved native-support then live Host isIOS then recordingSupported'},'projection':'_VpIptvRecordingHostAdapter.isIOS => VpS2Hooks.isIOS'}}
 fields=['_engineRefreshTicket'];spec['guards']=dict(occurrence_field_bindings=dict(owners=[STATE],state_classes=[STATE],mandatory_qualification=True,owner_scoped_bare_fields={STATE+'._engineRefreshTicket':'VpIptvRecording'}),record_owners=[STATE],record_fields={STATE:fields},receiver_owners={g['receiver']:g['name'] for g in GROUPS},receiver_paths={g['receiver']:g['name'] for g in GROUPS},receiver_members={g['name']:[n[1:] for n in g['names']] for g in GROUPS},receivers=['_host',*[g['receiver'] for g in GROUPS]],live_state_receivers=['_host'],require_live_state_callbacks=True,host_property_bindings=hostbindings,registered_occurrence_substitutions=[dict(before=a,after=b,binding='unbound',role_change='Complete sibling chain to live Host projection') for a,b,_,_ in CHAINS]+[dict(before=['widget','.',n],after=['_host','.',n],binding='unbound',role_change='widget selector to live Host selector') for n in sorted(set(widgetnames))])
 measured=[]
 for row in spec['declarations']:
  key=row['original'];g=byname.get(key.split('.')[-1]) if key.startswith(STATE+'.') else None;moved=g is not None;mapping={n:([n[1:]] if moved and byname[n] is g else ['_host','.',n[1:]] if moved else [byname[n]['receiver'],'.',n[1:]]) for n in allnames}
  if moved:
   row.update(fate='moved',destination=g['dest'],target=g['name']+'.'+key.split('.')[-1][1:]);mapping.update({n:['_host','.',n[1:]] for n in g['hosts']});mapping['mounted']=['_host','.','mounted'];mapping['setState']=['_host','.','setState']
   if key!=STATE+'._showTracksSheet':mapping['context']=['_host','.','context']
  if moved and key==STATE+'._showTracksSheet':mapping.pop('mounted',None)
  vals=tokens(spans[key]);edits=[]
  for n,after in mapping.items():
   interpolation=sum(vals[i:i+2]==['$',n] for i in range(len(vals)))
   if interpolation:
    edits.append(dict(before=['$',n],after=['${',*after,'}'],count=interpolation))
    previous={vals[i-1] for i,x in enumerate(vals) if x==n and vals[i-1]!='$'}
    for p in sorted(previous):
     count=sum(vals[i:i+2]==[p,n] for i in range(len(vals)))
     edits.append(dict(before=[p,n],after=[p,*after],count=count))
   elif n in vals:edits.append(dict(before=[n],after=after,count=vals.count(n)))
  if moved:
   for before,after in [(a,b) for a,b,_,_ in CHAINS]+[(['widget','.',n],['_host','.',n]) for n in sorted(set(widgetnames))]:
    count=sum(vals[i:i+len(before)]==before for i in range(len(vals)))
    if count:edits.append(dict(before=before,after=after,count=count))
  if key in spec['patched_class_projection']:
   assert len(edits)==1 and edits[0]['count']==1, (key,edits)
   row.update(fate='patched',reason='Route the retained quick-menu forwarder to the menu owner.',test='dev/tool/test_dart_menu_recording_moves.py',patches=edits)
  elif edits:row['substitutions']=edits
  if edits:measured.append(dict(declaration=key,fate=row['fate'],edits=edits))
  if key==STATE+'.'+STATE:
   append=[]
   for g2 in GROUPS:append += [g2['receiver'],'=',g2['name'],'(','_'+g2['name']+'HostAdapter','(','this',')',')',';']
   row.update(fate='patched',reason='Append four eager inert collaborators after the P12 identify collaborators.',test='dev/tool/test_dart_menu_recording_moves.py',patches=[dict(before=[';','}'],after=[';',*append,'}'],count=1)])
 # Independent disjoint edits have a stable order in the frozen artifact.
 for row in spec['declarations']:
  if 'substitutions' in row:row['substitutions'].sort(key=lambda e:json.dumps(e['before']))
 retained={r['original'] for r in spec['declarations'] if r['fate']!='moved'};spec['span_order']=[k for k in spans if k in retained];scaff={};previous=STATE+'._identifyUi'
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
 parser.add_argument('--base', default=BASE, choices=[BASE])
 parser.add_argument('--parser-package', type=Path, required=True)
 parser.add_argument('--probe', type=Path, required=True)
 args=parser.parse_args()
 common=Path(subprocess.check_output(['git','rev-parse','--path-format=absolute','--git-common-dir'],text=True).strip())
 if not args.probe.resolve().is_relative_to(common/'refactor-evidence/vplayer/p13'):
  parser.error('probe must be under P13 evidence')
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
 assert all(v<=500 for v in sizes.values()),sizes
 (R/'dev/tool/dart_moves/vplayer_p13.json').write_text(json.dumps(spec,indent=2)+'\n')
 (args.probe/'remeasured.json').write_text(json.dumps(measured,indent=2)+'\n')
 (args.probe/'result.json').write_text(json.dumps(dict(errors=errors,sizes=sizes,hosts={g['name']:[f.split(' => ')[0] for f in g['forwarders']] for g in GROUPS}),indent=2)+'\n')
 print('PASS: complete P13 split, 30 moves, 25 historical destinations; application untouched')
 return 0

if __name__=='__main__':raise SystemExit(main())
