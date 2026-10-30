import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/browse/browse_search_header.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef IptvSpotlightFocusDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvRecordingState recordingState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  void Function() applyFilters,
  List<IptvListMeta> Function() customLists,
  void Function() focusFirstChannel,
  bool Function() isTelevision,
  bool Function() mounted,
  VoidCallback? Function() onUpArrowFromFilters,
  Widget? Function() searchHeader,
  String Function() searchQuery,
  StateSetter setState,
});

class IptvSpotlightFocus {
  final IptvSpotlightFocusDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvRecordingState _recordingState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvSpotlightFocus(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _recordingState = _deps.recordingState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  void setSpotlightSourcesExpanded(bool expanded) {
    if (!_deps.mounted() ||
        _selectionState.spotlightSourcesExpanded == expanded) {
      return;
    }
    _deps.setState(() => _selectionState.spotlightSourcesExpanded = expanded);
  }

  void closeSpotlightSources() {
    setSpotlightSourcesExpanded(false);
    focusSpotlightContentEntry();
  }

  void exitSpotlightSourcesToApp() {
    final focusSidebar = MainPageBridge.focusTvSidebar;
    if (!_deps.isTelevision() || focusSidebar == null) return;
    setSpotlightSourcesExpanded(false);
    focusSidebar();
  }

  void focusSpotlightSources() {
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      setSpotlightSourcesExpanded(true);
      final remembered = _focusState.spotlightRailScope.focusedChild;
      // A search field hidden by the collapsed drawer cannot receive focus.
      // Enter on the first source instead of leaving focus on an empty scope.
      if (remembered != null &&
          remembered is! FocusScopeNode &&
          remembered.canRequestFocus) {
        _focusState.spotlightRailScope.requestFocus();
      } else {
        _focusState.playlistFilterFocusNode.requestFocus();
      }
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  void focusSpotlightHero() {
    if (_focusSportsBoard()) return;
    if (_focusState.spotlightPrimaryFocusNode.context != null) {
      _focusState.spotlightPrimaryFocusNode.requestFocus();
    } else {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  Widget spotlightControlNavigation(Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_focusState.spotlightPrimaryFocusNode.context != null) {
          _focusState.spotlightPrimaryFocusNode.requestFocus();
        } else {
          focusSpotlightSearchOrExit();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_selectionState.scheduleChannel == null &&
            !_focusState.spotlightTimelineController.restoreFocus()) {
          _deps.focusFirstChannel();
        }
        return _selectionState.scheduleChannel == null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.arrowLeft &&
          (_focusState.contentTypeFocusNode.hasFocus ||
              (!(_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
                  _focusState.categoryFilterFocusNode.hasFocus))) {
        focusSpotlightSources();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );

  void openSpotlightSearch() {
    final search = _deps.searchHeader();
    if (search is! BrowseSearchHeader) return;
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      setSpotlightSourcesExpanded(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() ||
          (_selectionState.spotlightLayoutMode ==
                  IptvSpotlightLayoutMode.wide &&
              !_selectionState.spotlightSourcesExpanded)) {
        return;
      }
      if (search.focusNode.canRequestFocus) search.focusNode.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void focusSpotlightSearchOrExit() {
    if (_deps.searchHeader() is BrowseSearchHeader) {
      openSpotlightSearch();
    } else {
      _deps.onUpArrowFromFilters()?.call();
    }
  }

  void focusSpotlightSearchResults() {
    _selectionState.searchDebounce?.cancel();
    _deps.applyFilters();
    final query = _deps.searchQuery();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || _deps.searchQuery() != query) return;
      // Keep an empty search editable. A matching query enters its first row.
      if (_catalogState.filteredChannels.isEmpty) {
        openSpotlightSearch();
        return;
      }
      setSpotlightSourcesExpanded(false);
      _deps.focusFirstChannel();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The Sports shelf shows only its board (no hero, no category control):
  /// enter it where focus last was, else on its first control. False on any
  /// other shelf.
  bool _focusSportsBoard() {
    if (!(_settingsState.selectedPlaylist?.isSports ?? false)) return false;
    final scope = _focusState.spotlightSportsScope;
    (scope.focusedChild ?? scope.traversalDescendants.firstOrNull)
        ?.requestFocus();
    return true;
  }

  void focusSpotlightContentEntry() {
    if (_focusSportsBoard()) return;
    if (_catalogState.filteredChannels.isNotEmpty) {
      if (!_focusState.spotlightTimelineController.restoreFocus()) {
        _deps.focusFirstChannel();
      }
      return;
    }
    if ((_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
        _focusState.contentTypeFocusNode.canRequestFocus) {
      _focusState.contentTypeFocusNode.requestFocus();
      return;
    }
    if (_focusState.categoryFilterFocusNode.canRequestFocus) {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  int? get spotlightSelectedSourceCount {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return null;
    if (!_catalogState.isLoading) return _catalogState.allChannels.length;
    if (selected.isFavorites) return _membershipState.favoriteUrls.length;
    if (selected.isContinueWatching) {
      return _recordingState.continueWatchingCount;
    }
    if (selected.isCustomList) {
      for (final list in _customLists) {
        if (selected.customListId == list.id) return list.channelCount;
      }
    }
    return _recordingState.sourceCounts[selected.id];
  }
}
