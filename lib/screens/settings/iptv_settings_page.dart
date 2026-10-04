import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sections.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_composition.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
export 'package:debrify/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart'
    show IptvSharedSourceDeleteDialog;
import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/application/normalize_xtream_server_url.dart';
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import '../../services/analytics_service.dart';
import '../../utils/platform_util.dart';
import '../../services/live_recording_service.dart';
import 'iptv_settings_two_pane.dart';

class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key, this.openAddSource = false});

  @visibleForTesting
  static bool showsAppearance({
    required bool isTelevision,
    required bool isDesktop,
  }) => isTelevision || isDesktop;

  /// Opened by an "Add playlist" affordance rather than from the settings
  /// list: land on the add form itself instead of making the user find it.
  /// The wide layout opens its Add pane (see [IptvSettingsTwoPane]); the
  /// single column already puts Add Playlist first, so it needs nothing.
  final bool openAddSource;

  @override
  State<IptvSettingsPage> createState() => _IptvSettingsPageState();
}

class _IptvSettingsPageState extends State<IptvSettingsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = IptvSettingsFocusOwner();
  final _input = IptvSettingsInputOwner();
  final _sources = IptvSettingsSourcesOwner();
  final _preferences = IptvSettingsPreferencesOwner();
  final r = IptvSettingsRecordingOwner();
  final l = IptvSettingsLayoutOwner();
  IptvSettingsSections? _sectionCache;
  IptvSettingsSections get _sections =>
      _sectionCache ??= createIptvSettingsSections(
        (
          mounted: () => mounted,
          setState: setState,
          twoPaneKey: _twoPaneKey,
          openAddSource: () => widget.openAddSource,
          context: () => context,
          appearanceVisible: () => _appearanceVisible,
        ),
        (
          focusOwner: _focus,
          inputOwner: _input,
          sourcesOwner: _sources,
          preferencesOwner: _preferences,
          recordingOwner: r,
          layoutOwner: l,
        ),
      );

  final GlobalKey<IptvSettingsTwoPaneState> _twoPaneKey = GlobalKey();
  static final bool _isDesktopPlatform =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _appearanceVisible => IptvSettingsPage.showsAppearance(
    isTelevision: PlatformUtil.isTelevision,
    isDesktop: _isDesktopPlatform,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.screenView('iptv_settings');
    _input.tabController = TabController(length: 3, vsync: this);
    // Rebuild on tab change so the inactive tabs' ExcludeFocus updates —
    // otherwise DPAD traversal can wander into off-screen tab content.
    _input.tabController.addListener(_onTabChanged);
    // An "Add playlist" deep-link lands on the Sources sub-view, where the
    // add forms live — the hub would be an extra hop the user didn't ask for.
    if (widget.openAddSource) l.phoneSection = IptvSettingsPhoneSection.sources;
    _sections.loadSettings.loadSettings();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _input.tabController.removeListener(_onTabChanged);
    _input.tabController.dispose();
    _input.nameController.dispose();
    _input.urlController.dispose();
    _input.epgUrlController.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.hubSourcesFocusNode.dispose();
    _focus.phoneViewMarker.dispose();
    _focus.nameInputFocusNode.dispose();
    _focus.urlInputFocusNode.dispose();
    _focus.epgUrlInputFocusNode.dispose();
    _focus.addButtonFocusNode.dispose();
    _focus.importFileButtonFocusNode.dispose();
    _input.xcNameController.dispose();
    _input.xcServerController.dispose();
    _input.xcUsernameController.dispose();
    _input.xcPasswordController.dispose();
    _focus.xcNameFocusNode.dispose();
    _focus.xcServerFocusNode.dispose();
    _focus.xcUsernameFocusNode.dispose();
    _focus.xcPasswordFocusNode.dispose();
    _focus.xcLoginButtonFocusNode.dispose();
    _focus.urlTabFocusNode.dispose();
    _focus.fileTabFocusNode.dispose();
    _focus.xcTabFocusNode.dispose();
    _focus.scheduledRecordingsFocusNode.dispose();
    _focus.maxConcurrentFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _focus.batteryFocusNode.dispose();
    for (final node in _focus.playlistFocusNodes) {
      node.dispose();
    }
    for (final node in _focus.listFocusNodes) {
      node.dispose();
    }
    for (final node in _focus.hiddenFocusNodes) {
      node.dispose();
    }
    _focus.createListFocusNode.dispose();
    _focus.startupChannelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !r.recheckBatteryOnResume) return;
    r.recheckBatteryOnResume = false;
    unawaited(
      LiveRecordingService.isIgnoringBatteryOptimizations().then((exempt) {
        if (mounted) setState(() => r.batteryExempt = exempt);
      }),
    );
  }
}

/// Frozen original-code characterization seam. Each invocation reads the actual
/// owner and action tear-offs; no service, clock or constructor seam is added.
@visibleForTesting
Map<String, dynamic> iptvSettingsTestAccess(State state) {
  final s = state as _IptvSettingsPageState;
  return {
    'twoPaneKey': s._twoPaneKey,
    'tabController': s._input.tabController,
    'nameController': s._input.nameController,
    'urlController': s._input.urlController,
    'epgUrlController': s._input.epgUrlController,
    'xcNameController': s._input.xcNameController,
    'xcServerController': s._input.xcServerController,
    'xcUsernameController': s._input.xcUsernameController,
    'xcPasswordController': s._input.xcPasswordController,
    'playlists': s._sources.playlists,
    'lists': s._sources.lists,
    'hiddenCounts': s._sources.hiddenCounts,
    'defaultPlaylistId': s._sources.defaultPlaylistId,
    'loading': s._sources.loading,
    'twoPaneActive': s.l.twoPaneActive,
    'refreshingIds': s._sources.refreshingIds,
    'isAdding': s._input.isAdding,
    'isXcAdding': s._input.isXcAdding,
    'playlistFocusNodes': s._focus.playlistFocusNodes,
    'listFocusNodes': s._focus.listFocusNodes,
    'hiddenFocusNodes': s._focus.hiddenFocusNodes,
    'startupEnabled': s._preferences.startupEnabled,
    'startupMode': s._preferences.startupMode,
    'startupChannel': s._preferences.startupChannel,
    'lastLiveChannel': s._preferences.lastLiveChannel,
    'channelPreviewEnabled': s._preferences.channelPreviewEnabled,
    'trackContinueWatching': s._preferences.trackContinueWatching,
    'iptvStyle': s._preferences.iptvStyle,
    'playerGuideStyle': s._preferences.playerGuideStyle,
    'autoRefreshHours': s._preferences.autoRefreshHours,
    'recordingSectionVisible': s.r.recordingSectionVisible,
    'engineToggleVisible': s.r.engineToggleVisible,
    'recordingEngineOn': s.r.recordingEngineOn,
    'scheduledCount': s.r.scheduledCount,
    'maxConcurrent': s.r.maxConcurrent,
    'batteryExempt': s.r.batteryExempt,
    'recheckBatteryOnResume': s.r.recheckBatteryOnResume,
    'hubSourcesFocusNode': s._focus.hubSourcesFocusNode,
    'phoneViewMarker': s._focus.phoneViewMarker,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'urlTabFocusNode': s._focus.urlTabFocusNode,
    'fileTabFocusNode': s._focus.fileTabFocusNode,
    'xcTabFocusNode': s._focus.xcTabFocusNode,
    'nameInputFocusNode': s._focus.nameInputFocusNode,
    'urlInputFocusNode': s._focus.urlInputFocusNode,
    'epgUrlInputFocusNode': s._focus.epgUrlInputFocusNode,
    'addButtonFocusNode': s._focus.addButtonFocusNode,
    'importFileButtonFocusNode': s._focus.importFileButtonFocusNode,
    'xcNameFocusNode': s._focus.xcNameFocusNode,
    'xcServerFocusNode': s._focus.xcServerFocusNode,
    'xcUsernameFocusNode': s._focus.xcUsernameFocusNode,
    'xcPasswordFocusNode': s._focus.xcPasswordFocusNode,
    'xcLoginButtonFocusNode': s._focus.xcLoginButtonFocusNode,
    'createListFocusNode': s._focus.createListFocusNode,
    'addPlaylist': s._sections.urlAdd.addPlaylist,
    'importFromFile': s._sections.fileImport.importFromFile,
    'addXtreamCodes': s._sections.xtreamAdd.addXtreamCodes,
    'removePlaylist': s._sections.sourceRemoval.removePlaylist,
    'setDefaultPlaylist': s._sections.sourceRefresh.setDefaultPlaylist,
    'refreshPlaylist': s._sections.sourceRefresh.refreshPlaylist,
    'editPlaylist': s._sections.sourceEdit.editPlaylist,
    'createList': s._sections.listsActions.createList,
    'renameList': s._sections.listsActions.renameList,
    'deleteList': s._sections.listsActions.deleteList,
    'moveList': s._sections.listsActions.moveList,
    'showListActions': s._sections.listsActions.showListActions,
    'setStartupEnabled': s._sections.preferencesActions.setStartupEnabled,
    'setStartupMode': s._sections.preferencesActions.setStartupMode,
    'setChannelPreviewEnabled':
        s._sections.preferencesActions.setChannelPreviewEnabled,
    'setTrackContinueWatching':
        s._sections.preferencesActions.setTrackContinueWatching,
    'setIptvStyle': s._sections.preferencesActions.setIptvStyle,
    'setPlayerGuideStyle': s._sections.preferencesActions.setPlayerGuideStyle,
    'pickAutoRefresh': s._sections.preferencesActions.pickAutoRefresh,
    'pickStartupChannel': s._sections.preferencesActions.pickStartupChannel,
    'pickMaxConcurrent': s._sections.recordingActions.pickMaxConcurrent,
    'openScheduledRecordings':
        s._sections.recordingActions.openScheduledRecordings,
    'requestBatteryExemption':
        s._sections.recordingActions.requestBatteryExemption,
    'runProfileAction': s._sections.profileActions.runProfileAction,
    'normalizeXtreamServerUrl': normalizeXtreamServerUrl,
    'loadSettings': s._sections.loadSettings.loadSettings,
    'catalogKeysFor': s._sections.catalogActions.catalogKeysFor,
    'catalogOwnerReferencesFor':
        s._sections.catalogActions.catalogOwnerReferencesFor,
    'reloadHiddenCounts': s._sections.catalogActions.reloadHiddenCounts,
    'ensureFocusNodes': s._sections.focusActions.ensureFocusNodes,
    'focusContentAfterTabSwitch':
        s._sections.focusActions.focusContentAfterTabSwitch,
    'focusAndReveal': s._sections.focusActions.focusAndReveal,
    'phoneSection': s.l.phoneSection.name,
    'customLists': s._sections.listsActions.customLists,
    'hideableSources': s._sections.catalogActions.hideableSources,
    'categoryOrderSources': s._sections.catalogActions.categoryOrderSources,
    'appearanceVisible': s._appearanceVisible,
    'startupChannelLabel': s._sections.preferencesActions.startupChannelLabel,
    'lastLiveChannelLabel': s._sections.preferencesActions.lastLiveChannelLabel,
    'lifecycle': s.didChangeAppLifecycleState,
    'enterPhoneSection': (String name) => s._sections.layoutActions
        .enterPhoneSection(IptvSettingsPhoneSection.values.byName(name)),
  };
}
