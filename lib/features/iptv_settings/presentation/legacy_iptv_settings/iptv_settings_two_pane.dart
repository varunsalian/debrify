import 'dart:async' show unawaited;

import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsTwoPaneLayoutDeps = ({
  GlobalKey<IptvSettingsTwoPaneState> twoPaneKey,
  bool Function() openAddSource,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsPreferencesOwner preferencesOwner,
  Future<void> Function() pickAutoRefresh,
  List<IptvListMeta> Function() customLists,
  String Function() startupChannelLabel,
  String Function() lastLiveChannelLabel,
  IptvSettingsInputOwner inputOwner,
  void Function(VoidCallback) setState,
  Widget Function() buildUrlTabContent,
  Widget Function() buildFileTabContent,
  Widget Function() buildXcTabContent,
  IptvSettingsFocusOwner focusOwner,
  Future<void> Function(IptvPlaylist? playlist) setDefaultPlaylist,
  Future<void> Function(IptvPlaylist playlist) refreshPlaylist,
  Future<void> Function(IptvPlaylist playlist) editPlaylist,
  Future<void> Function(IptvPlaylist playlist) removePlaylist,
  Future<void> Function() createList,
  Future<void> Function() openChannelOrder,
  Future<void> Function(IptvPlaylist playlist) openCategoryOrder,
  Future<void> Function(IptvPlaylist playlist) openHiddenCategories,
  void Function(FocusNode node) focusAndReveal,
  Future<void> Function(IptvListMeta list) showListActions,
  Future<void> Function(bool enabled) setStartupEnabled,
  Future<void> Function(String? mode) setStartupMode,
  Future<void> Function() pickStartupChannel,
  Future<void> Function(bool value) setChannelPreviewEnabled,
  Future<void> Function(bool value) setTrackContinueWatching,
  bool Function() appearanceVisible,
  Future<void> Function(String style) setIptvStyle,
  Future<void> Function(String style) setPlayerGuideStyle,
  IptvSettingsRecordingOwner recordingOwner,
  bool Function() mounted,
  Future<void> Function() openScheduledRecordings,
  Future<void> Function() pickMaxConcurrent,
  Future<void> Function() requestBatteryExemption,
});

class IptvSettingsTwoPaneLayout {
  IptvSettingsTwoPaneLayout(this._deps);
  final IptvSettingsTwoPaneLayoutDeps _deps;

  Widget buildTwoPane() {
    return IptvSettingsTwoPane(
      key: _deps.twoPaneKey,
      openAddSource: _deps.openAddSource(),
      playlists: _deps.sourcesOwner.playlists,
      defaultPlaylistId: _deps.sourcesOwner.defaultPlaylistId,
      refreshingIds: _deps.sourcesOwner.refreshingIds,
      autoRefreshHours: _deps.preferencesOwner.autoRefreshHours,
      onPickAutoRefresh: _deps.pickAutoRefresh,
      customLists: _deps.customLists(),
      startupEnabled: _deps.preferencesOwner.startupEnabled,
      startupMode: _deps.preferencesOwner.startupMode,
      startupChannelLabel: _deps.startupChannelLabel(),
      lastLiveChannelLabel: _deps.lastLiveChannelLabel(),
      hasStartupChannel: _deps.preferencesOwner.startupChannel != null,
      hasLastLiveChannel: _deps.preferencesOwner.lastLiveChannel != null,
      addMethod: _deps.inputOwner.tabController.index,
      // Kept on the shared TabController so the two layouts agree about which
      // method is chosen across a resize.
      onAddMethodChanged: (i) {
        if (_deps.inputOwner.tabController.index == i) return;
        _deps.setState(() => _deps.inputOwner.tabController.index = i);
      },
      urlFormBuilder: (_) => _deps.buildUrlTabContent(),
      fileFormBuilder: (_) => _deps.buildFileTabContent(),
      xtreamFormBuilder: (_) => _deps.buildXcTabContent(),
      // The forms' own up-arrow targets are these nodes, so reusing them for
      // the method chooser keeps every hand-off inside them valid here.
      urlMethodFocusNode: _deps.focusOwner.urlTabFocusNode,
      fileMethodFocusNode: _deps.focusOwner.fileTabFocusNode,
      xtreamMethodFocusNode: _deps.focusOwner.xcTabFocusNode,
      onSetDefault: (p) => _deps.setDefaultPlaylist(
        _deps.sourcesOwner.defaultPlaylistId == p.id ? null : p,
      ),
      onRefresh: _deps.refreshPlaylist,
      onEdit: _deps.editPlaylist,
      onDelete: _deps.removePlaylist,
      onCreateList: _deps.createList,
      onManageChannelOrder: () => unawaited(_deps.openChannelOrder()),
      onManageCategoryOrder: (playlist) =>
          unawaited(_deps.openCategoryOrder(playlist)),
      onManageHidden: (playlist) =>
          unawaited(_deps.openHiddenCategories(playlist)),
      hiddenCounts: _deps.sourcesOwner.hiddenCounts,
      onFocusFirstFormField: () =>
          _deps.focusAndReveal(switch (_deps.inputOwner.tabController.index) {
            1 => _deps.focusOwner.importFileButtonFocusNode,
            2 => _deps.focusOwner.xcNameFocusNode,
            _ => _deps.focusOwner.nameInputFocusNode,
          }),
      onListActions: _deps.showListActions,
      onToggleStartup: _deps.setStartupEnabled,
      onStartupModeChanged: _deps.setStartupMode,
      onPickStartupChannel: _deps.pickStartupChannel,
      channelPreviewEnabled: _deps.preferencesOwner.channelPreviewEnabled,
      onToggleChannelPreview: _deps.setChannelPreviewEnabled,
      trackContinueWatching: _deps.preferencesOwner.trackContinueWatching,
      onToggleTrackContinueWatching: _deps.setTrackContinueWatching,
      showAppearanceSection: _deps.appearanceVisible(),
      iptvStyle: _deps.preferencesOwner.iptvStyle,
      onIptvStyleChanged: (v) => unawaited(_deps.setIptvStyle(v)),
      playerGuideStyle: _deps.preferencesOwner.playerGuideStyle,
      onPlayerGuideStyleChanged: (v) => unawaited(_deps.setPlayerGuideStyle(v)),
      showRecordingSection: _deps.recordingOwner.recordingSectionVisible,
      showEngineToggle: _deps.recordingOwner.engineToggleVisible,
      recordingEngineEnabled: _deps.recordingOwner.recordingEngineOn,
      scheduledCount: _deps.recordingOwner.scheduledCount,
      onToggleRecordingEngine: (enabled) async {
        await LiveRecordingService.setEngineEnabled(enabled);
        if (_deps.mounted()) {
          _deps.setState(
            () => _deps.recordingOwner.recordingEngineOn = enabled,
          );
        }
      },
      onOpenScheduledRecordings: () =>
          unawaited(_deps.openScheduledRecordings()),
      maxConcurrentRecordings: _deps.recordingOwner.maxConcurrent,
      onPickMaxConcurrent: () => unawaited(_deps.pickMaxConcurrent()),
      batteryExempt: _deps.recordingOwner.batteryExempt,
      onRequestBatteryExemption: () =>
          unawaited(_deps.requestBatteryExemption()),
    );
  }
}
