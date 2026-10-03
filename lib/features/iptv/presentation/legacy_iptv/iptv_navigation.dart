import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

typedef IptvNavigationDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  BuildContext Function() context,

  FocusNode Function(IptvChannel channel) focusNodeFor,
  Future<void> Function() initRecordingSupport,
  Future<void> Function({bool forceReload}) loadSettings,
  bool Function() mounted,
  Future<void> Function() refreshAfterHiddenChange,
  void Function(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    bool quiet,
  })
  updateEpgContext,
});

class IptvNavigation {
  final IptvNavigationDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvNavigation(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  void navigateToSettings({bool openAddSource = true}) {
    // Captured for the EPG-URL-edit case below: _loadSettings only reloads
    // the playlist when the SELECTION changes, so an edit to the current
    // playlist's guide URL would otherwise sit inert until a manual playlist
    // switch — "EPG URL saved" with nothing happening.
    final beforeId = _settingsState.selectedPlaylist?.id;
    final beforeEpgUrl = _settingsState.selectedPlaylist?.epgUrl;
    // Settings owns the hidden-categories manager, so a trip through it can
    // reveal (or hide) a category behind this page's back. Captured here
    // because _loadSettings only reloads the catalog when the SELECTION
    // changes — otherwise the facades keep the row count and category list
    // they were built with while the category was hidden.
    final beforeHidden = _catalogState.hiddenCategories;
    final beforeCatalogKey = _catalogState.dbSnapshot?.catalogKey;
    Navigator.of(_deps.context())
        .push(
          MaterialPageRoute(
            builder: (_) => IptvSettingsPage(openAddSource: openAddSource),
          ),
        )
        .then((_) async {
          // Reload settings when returning
          await _deps.loadSettings();
          if (!_deps.mounted()) return;
          // Only for the SAME catalog: a settings trip that changed the
          // selection has already been re-presented from scratch, hidden set
          // included, and comparing across two catalogs' rules is meaningless.
          final snap = _catalogState.dbSnapshot;
          if (snap != null &&
              snap.catalogKey == beforeCatalogKey &&
              !setEquals(
                beforeHidden,
                IptvCatalogDb.hiddenGroups(snap.catalogKey),
              )) {
            await _deps.refreshAfterHiddenChange();
            if (!_deps.mounted()) return;
          }
          // Settings is where the recording-engine toggle lives: re-probe so
          // enabling exposes the stage/rail affordances immediately, and
          // disabling actually takes them away instead of leaving Record and
          // scheduling active until the page remounts.
          unawaited(_deps.initRecordingSupport());
          final current = _settingsState.selectedPlaylist;
          final result = _catalogState.lastLoadResult;
          if (current != null &&
              current.id == beforeId &&
              current.epgUrl != beforeEpgUrl &&
              result != null) {
            _deps.updateEpgContext(current, result, _catalogState.loadTicket);
          }
        });
  }

  void navigateToManageSources() {
    navigateToSettings(openAddSource: false);
  }

  /// Focus the first channel card (for DPAD navigation from filters)
  void focusFirstChannel() {
    // Only focus if we have filtered channels
    if (_catalogState.filteredChannels.isNotEmpty) {
      if (_selectionState.spotlightLayoutMode !=
              IptvSpotlightLayoutMode.classic &&
          _focusState.spotlightTimelineController.focusFirstChannel()) {
        return;
      }
      _deps.focusNodeFor(_catalogState.filteredChannels.first).requestFocus();
    }
  }
}
