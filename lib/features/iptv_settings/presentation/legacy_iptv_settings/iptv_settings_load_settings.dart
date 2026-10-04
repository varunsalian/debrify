import 'dart:io' show Platform;

import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'iptv_settings_focus_owner.dart';
import 'iptv_settings_layout_owner.dart';
import 'iptv_settings_preferences_owner.dart';
import 'iptv_settings_recording_owner.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsLoadSettingsDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsPreferencesOwner preferencesOwner,
  IptvSettingsRecordingOwner recordingOwner,
  void Function() ensureFocusNodes,
  void Function() reloadHiddenCounts,
  GlobalKey<IptvSettingsTwoPaneState> twoPaneKey,
  bool Function() openAddSource,
  IptvSettingsLayoutOwner layoutOwner,
  IptvSettingsFocusOwner focusOwner,
});

class IptvSettingsLoadSettings {
  IptvSettingsLoadSettings(this._deps);
  final IptvSettingsLoadSettingsDeps _deps;

  Future<void> loadSettings() async {
    final startingScope = ProfileRuntime.scope.value;
    // The wide layout reports per-source counts and freshness straight from
    // the catalog. Opening once here keeps every row's read synchronous —
    // a DPAD move must never await.
    try {
      await IptvCatalogDb.open();
    } catch (_) {
      // A catalog that won't open just means "no stats"; the page still works.
    }
    final playlists = await IptvPlaylistStorage.getIptvPlaylists(
      forSettings: true,
    );
    final defaultId = await IptvPlaylistStorage.getIptvDefaultPlaylist();
    final lists = await IptvFavoritesStorage.getIptvLists();
    final startupEnabled = await StartupIptvStorage.getStartupIptvEnabled();
    final startupMode = await StartupIptvStorage.getStartupIptvMode();
    final startupChannel = await StartupIptvStorage.getStartupIptvChannel();
    final lastLive = await IptvLastChannelStorage.getIptvLastLiveChannel();
    final trackCw = await IptvHistoryStorage.getIptvTrackContinueWatching();
    final channelPreviewEnabled =
        await IptvAppearanceStorage.getIptvChannelPreviewEnabled();
    final iptvStyle = await IptvAppearanceStorage.getIptvStyle();
    final playerGuideStyle =
        await IptvAppearanceStorage.getIptvPlayerGuideStyle();
    final autoRefreshHours = await IptvCatalogRefreshService.getIntervalHours();
    final engineSupported =
        !kIsWeb &&
        Platform.isAndroid &&
        (await LiveRecordingService.engineSupport()) != 'unsupported';
    final desktopSched = DesktopScheduleService.instance.isSupported;
    final recordingEngineOn =
        engineSupported && await LiveRecordingService.engineEnabled();
    final scheduleCount = engineSupported
        ? (await LiveRecordingService.listSchedules()).length
        : desktopSched
        ? (await DesktopScheduleService.instance.list()).length
        : 0;
    final maxConcurrent = await LiveRecordingService.maxConcurrent();
    final batteryExempt = engineSupported && !PlatformUtil.isTelevision
        ? await LiveRecordingService.isIgnoringBatteryOptimizations()
        : null;

    if (!_deps.mounted() || ProfileRuntime.scope.value != startingScope) return;

    _deps.setState(() {
      _deps.sourcesOwner.playlists = playlists;
      _deps.sourcesOwner.defaultPlaylistId = defaultId;
      _deps.sourcesOwner.lists = lists;
      _deps.preferencesOwner.startupEnabled = startupEnabled;
      _deps.preferencesOwner.startupMode = startupMode;
      _deps.preferencesOwner.startupChannel = startupChannel;
      _deps.preferencesOwner.lastLiveChannel = lastLive;
      _deps.preferencesOwner.trackContinueWatching = trackCw;
      _deps.preferencesOwner.channelPreviewEnabled = channelPreviewEnabled;
      _deps.preferencesOwner.iptvStyle = iptvStyle;
      _deps.preferencesOwner.playerGuideStyle = playerGuideStyle;
      _deps.preferencesOwner.autoRefreshHours = autoRefreshHours;
      _deps.recordingOwner.recordingSectionVisible =
          engineSupported || desktopSched;
      _deps.recordingOwner.engineToggleVisible = engineSupported;
      _deps.recordingOwner.recordingEngineOn = recordingEngineOn;
      _deps.recordingOwner.scheduledCount = scheduleCount;
      _deps.recordingOwner.maxConcurrent = maxConcurrent;
      _deps.recordingOwner.batteryExempt = batteryExempt;
      _deps.sourcesOwner.loading = false;
    });
    _deps.ensureFocusNodes();
    _deps.reloadHiddenCounts();

    // TV entry focus: land on the first tab (not a TextField, so no keyboard
    // pops) so DPAD users are never stranded on nothing.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        // Only a bare FocusScopeNode as primary focus means DPAD is
        // stranded — don't steal focus the user already placed somewhere.
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        // In the wide layout the tab nodes belong to the Add pane, which is
        // not what the page opens on — requesting focus on an unmounted node
        // would leave DPAD exactly as stranded as doing nothing. Ask the rail
        // instead. Keyed off the mounted widget rather than _twoPaneActive:
        // that flag is set by a later post-frame than this one.
        final twoPane = _deps.twoPaneKey.currentState;
        if (twoPane != null) {
          // Arrived from an "Add playlist" button: hand DPAD to the add method
          // chooser, not to the rail — the user already chose the destination.
          if (_deps.openAddSource()) {
            twoPane.focusAddPane();
          } else {
            twoPane.focusRail();
          }
          return;
        }
        // Narrow: an add-source deep-link opened straight onto the Sources
        // sub-view where the URL tab is mounted; a normal entry sits on the
        // hub, whose first row is the landing.
        if (_deps.layoutOwner.phoneSection ==
            IptvSettingsPhoneSection.sources) {
          _deps.focusOwner.urlTabFocusNode.requestFocus();
        } else {
          _deps.focusOwner.hubSourcesFocusNode.requestFocus();
        }
      });
    }
  }
}
