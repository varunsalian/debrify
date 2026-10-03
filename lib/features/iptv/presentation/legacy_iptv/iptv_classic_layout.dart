import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_filters.dart';
import 'package:flutter/material.dart';

typedef IptvClassicLayoutDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  bool Function() anyRecordingLive,
  Widget Function({bool tvPane, bool touchSelector, bool cockpit}) buildContent,
  bool Function() canShowCategoryOptions,
  Map<String, int> Function() categoryCounts,
  String? Function() effectiveCategory,
  void Function() focusFirstChannel,
  void Function({bool openAddSource}) navigateToSettings,
  void Function(String? category) onCategoryChanged,
  void Function(String contentType) onContentTypeChanged,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  VoidCallback? Function() onUpArrowFromFilters,
  void Function() openScheduledRecordings,
  Future<void> Function(String category) promptCategoryOptions,
});

class IptvClassicLayout {
  final IptvClassicLayoutDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvClassicLayout(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  bool get _anyRecordingLive => _deps.anyRecordingLive();

  bool get _canShowCategoryOptions => _deps.canShowCategoryOptions();

  Map<String, int> get _categoryCounts => _deps.categoryCounts();

  String? get _effectiveCategory => _deps.effectiveCategory();

  /// The single-pane layout: boxed filter bar over a full-width channel list.
  /// Phones keep it (no embedded preview there), and TV/desktop fall back to
  /// it when the canvas can't fit two panes.
  Widget buildClassic() {
    return Column(
      children: [
        // Filters bar
        IptvFiltersBar(
          playlists: _settingsState.playlists,
          selectedPlaylist: _settingsState.selectedPlaylist,
          categories: _catalogState.categories,
          selectedCategory: _effectiveCategory,
          categoryCounts: _categoryCounts,
          channelCount: _catalogState.filteredChannels.length,
          isLoading: _catalogState.isLoading,
          isLoadingMore: _catalogState.isLoadingMore,
          onPlaylistChanged: _deps.onPlaylistChanged,
          onCategoryChanged: _deps.onCategoryChanged,
          onAddPlaylist: _deps.navigateToSettings,
          playlistFocusNode: _focusState.playlistFilterFocusNode,
          categoryFocusNode: _focusState.categoryFilterFocusNode,
          showContentTypeFilter:
              _settingsState.selectedPlaylist?.isXtreamCodes ?? false,
          selectedContentType: _catalogState.selectedContentType,
          onContentTypeChanged: _deps.onContentTypeChanged,
          contentTypeFocusNode: _focusState.contentTypeFocusNode,
          onUpArrowPressed: _deps.onUpArrowFromFilters(),
          onDownArrowPressed: _deps.focusFirstChannel,
          onOpenRecordings: _recordingState.pageCanRecord
              ? _deps.openScheduledRecordings
              : null,
          recordingLive: _anyRecordingLive,
          onCategoryOptions: _canShowCategoryOptions
              ? _deps.promptCategoryOptions
              : null,
        ),

        // Content
        Expanded(child: _deps.buildContent()),
      ],
    );
  }
}
