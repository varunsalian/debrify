import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catchup.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_categories.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_desktop_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_guide_context.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_navigation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_record_now.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_source_counts.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';

typedef IptvRecordingsCompositionExternalSections = ({
  IptvCatchup Function() catchup,
  IptvCategories Function() categoryActions,
  IptvFavorites Function() favorites,
  IptvGuideContext Function() guideContext,
  IptvRowProjection Function() rowProjection,
  IptvSettingsLoading Function() settingsLoading,
});

/// Constructs the recordings sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvRecordingsComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvRecordingsCompositionExternalSections _external;

  IptvRecordingsComposition(this._view, this._states, this._external);

  late final IptvScheduleActions scheduleActions = IptvScheduleActions((
    focusState: _states.focusState,
    recordingState: _states.recordingState,
    selectionState: _states.selectionState,
    context: () => _view.context(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    playCatchup: (IptvChannel channel, EpgProgramme programme) =>
        _external.catchup().playCatchup(channel, programme),
    recordingResourceFor: (IptvChannel channel) =>
        recordNow.recordingResourceFor(channel),
    refreshScheduledCount: () => recordingSupport.refreshScheduledCount(),
    setState: _view.setState,
  ));

  late final IptvRecordingSupport recordingSupport = IptvRecordingSupport((
    recordingState: _states.recordingState,
    context: () => _view.context(),
    mounted: () => _view.mounted(),
    refreshAndroidRecordingState: () =>
        androidRecording.refreshAndroidRecordingState(),
    setState: _view.setState,
  ));

  late final IptvRecordNow recordNow = IptvRecordNow((
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    context: () => _view.context(),
    mounted: () => _view.mounted(),
    originPlaylistIdFor: (IptvChannel channel) =>
        _external.favorites().originPlaylistIdFor(channel),
    setState: _view.setState,
    stageRecordingFileName: (String channelName) =>
        recordingSupport.stageRecordingFileName(channelName),
  ));

  late final IptvSourceCounts sourceStatistics = IptvSourceCounts((
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));

  late final IptvAndroidRecording androidRecording = IptvAndroidRecording((
    recordingState: _states.recordingState,
    context: () => _view.context(),
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));

  late final IptvDesktopRecording desktopRecording = IptvDesktopRecording((
    context: () => _view.context(),
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));

  late final IptvNavigation navigation = IptvNavigation((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    context: () => _view.context(),
    focusNodeFor: (IptvChannel channel) =>
        _external.rowProjection().focusNodeFor(channel),
    initRecordingSupport: () => recordingSupport.initRecordingSupport(),
    loadSettings: ({bool forceReload = false}) =>
        _external.settingsLoading().loadSettings(forceReload: forceReload),
    mounted: () => _view.mounted(),
    refreshAfterHiddenChange: () =>
        _external.categoryActions().refreshAfterHiddenChange(),
    updateEpgContext:
        (
          IptvPlaylist playlist,
          IptvParseResult result,
          int ticket, {
          bool quiet = false,
        }) => _external.guideContext().updateEpgContext(
          playlist,
          result,
          ticket,
          quiet: quiet,
        ),
  ));
}
