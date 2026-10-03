import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/material.dart';

typedef IptvSpotlightContentDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  Widget Function({bool tvPane, bool touchSelector, bool cockpit}) buildContent,
  void Function() closeSchedulePane,
  DateTime Function() Function() debugSpotlightNow,
  void Function() focusSpotlightSources,
  bool Function() isTelevision,
  void Function(IptvChannel channel, {bool fromPointer}) onChannelFocused,
  void Function(IptvChannel channel) openSchedulePane,
  Future<void> Function(IptvChannel channel, EpgProgramme programme)
  playCatchup,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  void Function(EpgProgramme programme)? Function(IptvChannel channel)
  recordProgrammeActionFor,
  Future<void> Function(IptvChannel channel, {EpgProgramme? programme})
  showSpotlightChannelActions,
});

class IptvSpotlightContent {
  final IptvSpotlightContentDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvSpotlightContent(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  Widget buildSpotlightContent(IptvSpotlightLayoutMode mode) {
    final scheduleChannel = _selectionState.scheduleChannel;
    final browser = buildSpotlightBrowser(mode);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            child: browser,
          ),
        ),
        if (scheduleChannel != null)
          ValueListenableBuilder<int>(
            valueListenable: IptvEpgService.instance.contextVersion,
            builder: (context, epgVersion, _) => IptvSchedulePane(
              // A guide published after the pane opened must replace the
              // once-loaded empty schedule with a fresh one.
              key: ValueKey(
                'spotlight-schedule-${scheduleChannel.url}-$epgVersion',
              ),
              channel: scheduleChannel,
              onClose: _deps.closeSchedulePane,
              isTelevision: _deps.isTelevision(),
              onPlayProgramme: (programme) =>
                  _deps.playCatchup(scheduleChannel, programme),
              onRecordProgramme: _deps.recordProgrammeActionFor(
                scheduleChannel,
              ),
            ),
          ),
      ],
    );
  }

  Widget buildSpotlightBrowser(IptvSpotlightLayoutMode mode) {
    if (!spotlightUsesTimeline) {
      return _deps.buildContent(tvPane: true, cockpit: false);
    }

    // Preserve the existing load/error/empty surfaces. The timeline only
    // replaces the populated live-channel renderer.
    if (_settingsState.playlists.isEmpty ||
        _settingsState.selectedPlaylist == null ||
        _catalogState.isLoading ||
        (_catalogState.errorMessage != null &&
            _catalogState.allChannels.isEmpty) ||
        _catalogState.filteredChannels.isEmpty) {
      return _deps.buildContent(tvPane: true, cockpit: false);
    }

    final selected = _settingsState.selectedPlaylist!;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<int>(
        valueListenable: IptvEpgService.instance.contextVersion,
        builder: (context, epgVersion, _) => SpotlightLiveTimeline(
          key: _focusState.spotlightTimelineKey,
          now: _deps.debugSpotlightNow(),
          channels: _catalogState.filteredChannels,
          sourceId: selected.id,
          loadGeneration: Object.hash(
            _catalogState.loadTicket,
            _catalogState.spotlightViewGeneration,
          ),
          scheduleLoader: (channel) =>
              IptvEpgService.instance.schedule(channel.url),
          controller: _focusState.spotlightTimelineController,
          epgContextVersion: epgVersion,
          onSelectionChanged: onSpotlightSelection,
          onExitUp: () => _focusState.categoryFilterFocusNode.requestFocus(),
          onExitLeft: _deps.focusSpotlightSources,
          onChannelActions: (entry) => _deps.showSpotlightChannelActions(
            entry.channel,
            programme: _previewState.spotlightProgrammeShown.value,
          ),
          onChannelActivate: (entry) =>
              unawaited(_deps.playChannel(entry.channel)),
          onProgrammeActivate: activateSpotlightProgramme,
          // Keep short programmes readable on a television: the preceding
          // half-hour ruler interval plus the following hour.
          windowDuration: const Duration(minutes: 90),
          height: constraints.maxHeight,
          identityWidth: mode == IptvSpotlightLayoutMode.wide ? 300 : 260,
          dense: true,
          rowHeight: 46,
          rulerHeight: 32,
        ),
      ),
    );
  }

  bool get spotlightUsesTimeline {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return false;
    // Saved shelves share the guide's row navigation, including its playable
    // no-guide and on-demand rows. Schedule lookup stays channel-based so
    // mixed Xtream providers use their own credentials without switching the
    // page's global XMLTV context for each row.
    if (selected.isFavorites || selected.isCustomList) return true;
    if (selected.isVirtual) return false;
    return !selected.isXtreamCodes ||
        _catalogState.selectedContentType == 'live';
  }

  void onSpotlightSelection(SpotlightTimelineSelection selection) {
    final channel = selection.entry.channel;
    _deps.onChannelFocused(channel, fromPointer: selection.fromPointer);
    if (identical(_previewState.previewShown.value, channel)) {
      _previewState.spotlightProgrammeShown.value = selection.programme;
    }
  }

  void activateSpotlightProgramme(
    SpotlightTimelineEntry entry,
    EpgProgramme programme,
  ) {
    final now = DateTime.now();
    if (programme.airsAt(now)) {
      unawaited(_deps.playChannel(entry.channel));
      return;
    }
    if (IptvEpgService.isCatchupAvailable(entry.channel, programme)) {
      unawaited(_deps.playCatchup(entry.channel, programme));
      return;
    }
    if (programme.start.isAfter(now)) {
      final record = _deps.recordProgrammeActionFor(entry.channel);
      if (record != null) {
        record(programme);
        return;
      }
    }
    // A programme without a direct replay/record action still opens the full
    // schedule, where the user can inspect the surrounding listings.
    _deps.openSchedulePane(entry.channel);
  }
}
