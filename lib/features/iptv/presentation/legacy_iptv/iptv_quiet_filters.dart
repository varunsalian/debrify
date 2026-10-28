import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_filter_bar.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';

typedef IptvQuietFiltersDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvSettingsState settingsState,
  bool Function() canShowCategoryOptions,
  Map<String, int> Function() categoryCounts,
  BuildContext Function() context,
  String? Function() effectiveCategory,
  void Function() focusFirstChannel,
  bool Function() isTelevision,
  void Function({bool openAddSource}) navigateToSettings,
  void Function(String? category) onCategoryChanged,
  void Function(String contentType) onContentTypeChanged,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  VoidCallback? Function() onUpArrowFromFilters,
  Future<void> Function(String category) promptCategoryOptions,
  Future<void> Function() promptCreateList,
});

class IptvQuietFilters {
  final IptvQuietFiltersDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvSettingsState _settingsState;

  IptvQuietFilters(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _settingsState = _deps.settingsState;

  bool get _canShowCategoryOptions => _deps.canShowCategoryOptions();

  Map<String, int> get _categoryCounts => _deps.categoryCounts();

  String? get _effectiveCategory => _deps.effectiveCategory();

  /// The Discover-style quiet filter line: bare dot-separated text segments
  /// (source • [Live/Movies] • category • count) instead of boxed pills.
  Widget buildQuietFilters() {
    final app = AppThemeScope.of(_deps.context());
    return SeeAllFilterBar(
      isTelevision: _deps.isTelevision(),
      quiet: true,
      buildChips: () => [
        // The Sources dropdown — EVERY source in one place: Favorites,
        // Continue watching, and each playlist. Replaces the old left rail.
        // Holds _playlistFilterFocusNode so every wire into "the first filter"
        // (down-from-search-field, revalidate focus repair, focusFirstFilter)
        // keeps working.
        StremioDropdown<String>(
          value: _settingsState.selectedPlaylist?.id ?? '',
          quiet: true,
          quietAccent: true,
          isTelevision: _deps.isTelevision(),
          focusNode: _focusState.playlistFilterFocusNode,
          onUpArrowPressed: _deps.onUpArrowFromFilters(),
          onDownArrowPressed: _deps.focusFirstChannel,
          options: sourceDropdownOptions(),
          onSelected: (id) {
            if (id == IptvSelectionState.kNewListSentinel) {
              _deps.promptCreateList();
              return;
            }
            if (id == IptvSelectionState.kAddPlaylistSentinel) {
              _deps.navigateToSettings();
              return;
            }
            if (id == IptvSelectionState.kAddAddonSentinel) {
              navigateToAddons();
              return;
            }
            for (final p in _settingsState.playlists) {
              if (p.id == id) {
                _deps.onPlaylistChanged(p);
                return;
              }
            }
          },
        ),
        if (_settingsState.selectedPlaylist?.isXtreamCodes ?? false)
          StremioDropdown<String>(
            label: 'type',
            value: _catalogState.selectedContentType,
            quiet: true,
            isTelevision: _deps.isTelevision(),
            focusNode: _focusState.contentTypeFocusNode,
            onUpArrowPressed: _deps.onUpArrowFromFilters(),
            onDownArrowPressed: _deps.focusFirstChannel,
            options: const [
              StremioDropdownOption('live', 'Live TV'),
              StremioDropdownOption('vod', 'Movies'),
              StremioDropdownOption('series', 'Series'),
            ],
            onSelected: _deps.onContentTypeChanged,
          ),
        if (_catalogState.categories.isNotEmpty)
          StremioDropdown<String>(
            label: 'category',
            value: _effectiveCategory ?? '',
            quiet: true,
            isTelevision: _deps.isTelevision(),
            focusNode: _focusState.categoryFilterFocusNode,
            onUpArrowPressed: _deps.onUpArrowFromFilters(),
            onDownArrowPressed: _deps.focusFirstChannel,
            options: [
              StremioDropdownOption(
                '',
                'All · ${_catalogState.allChannels.length}',
              ),
              for (final cat in _catalogState.categories)
                StremioDropdownOption(
                  cat,
                  '$cat · ${_categoryCounts[cat] ?? 0}',
                  // "All" is deliberately not holdable — there is no such
                  // category to hide.
                  holdable: _canShowCategoryOptions,
                ),
            ],
            holdHint: _deps.isTelevision()
                ? 'HOLD OK FOR OPTIONS'
                : 'HOLD FOR OPTIONS',
            onOptionHold: _deps.promptCategoryOptions,
            onSelected: (v) => _deps.onCategoryChanged(v.isEmpty ? null : v),
          ),
        // Non-focusable count — DPAD skips straight over it.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            _catalogState.isLoading
                ? 'Loading…'
                : '${_catalogState.filteredChannels.length} channel'
                      '${_catalogState.filteredChannels.length == 1 ? '' : 's'}'
                      // The list is still streaming in — never present a
                      // partial count as final.
                      '${_catalogState.isLoadingMore ? ' • loading more…' : ''}',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.40),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  /// The Sources dropdown, grouped: the two derived shelves, then the user's
  /// own lists, their playlists, and any live-TV catalogs their Stremio addons
  /// expose — each ending with the action that adds another one of its kind.
  ///
  /// The grouping mirrors the order [_loadSettings] already builds, so this
  /// only draws the lines where the list already changes character.
  List<StremioDropdownOption<String>> sourceDropdownOptions() {
    final quickAccess = [
      for (final p in _settingsState.playlists)
        if (p.isFavorites || p.isContinueWatching || p.isSports) p,
    ];
    final lists = [
      for (final p in _settingsState.playlists)
        if (p.isCustomList) p,
    ];
    final addons = [
      for (final p in _settingsState.playlists)
        if (p.isStremioAddon) p,
    ];
    final playlists = [
      for (final p in _settingsState.playlists)
        if (!p.isVirtual) p,
    ];

    return [
      if (quickAccess.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_quick__', 'Quick access'),
        for (final p in quickAccess) StremioDropdownOption(p.id, p.name),
      ],
      // Always shown, empty or not — it is where "New list" lives, and a user
      // with no lists yet is exactly who needs to find it.
      const StremioDropdownOption.header('__hdr_lists__', 'Your lists'),
      for (final p in lists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(
        IptvSelectionState.kNewListSentinel,
        '＋ New list',
      ),
      const StremioDropdownOption.header('__hdr_playlists__', 'Your playlists'),
      for (final p in playlists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(
        IptvSelectionState.kAddPlaylistSentinel,
        '＋ Add playlist',
      ),
      // Only for people who actually run addons — an empty section would push
      // Stremio at everyone else.
      if (addons.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_addons__', 'Stremio Addons'),
        for (final p in addons) StremioDropdownOption(p.id, p.name),
        const StremioDropdownOption(
          IptvSelectionState.kAddAddonSentinel,
          '＋ Add addon',
        ),
      ],
    ];
  }

  /// Open the Addons hub. Tab-switch rather than a pushed route: the hub is a
  /// tab body with no app bar of its own, so pushing it would strand the user
  /// with no way back.
  void navigateToAddons() {
    MainPageBridge.switchTab?.call(MainTab.addons);
  }
}
