import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/spotlight_category_picker_dialog.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/utils/tv_keys.dart' show TvHeldKeyGuard;
import 'package:debrify/widgets/browse/browse_search_header.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_category_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_content_type_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_rail.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_shell.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef IptvSpotlightLayoutDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvRecordingState recordingState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  bool Function() anyRecordingLive,
  Widget Function(IptvSpotlightLayoutMode mode) buildSpotlightContent,
  Widget Function(IptvSpotlightLayoutMode mode) buildSpotlightHero,
  bool Function() canShowCategoryOptions,
  Map<String, int> Function() categoryCounts,
  void Function() closeSpotlightSources,
  BuildContext Function() context,
  List<IptvListMeta> Function() customLists,
  String? Function() effectiveCategory,
  void Function() exitSpotlightSourcesToApp,
  void Function() focusSpotlightHero,
  void Function() focusSpotlightSearchOrExit,
  void Function() focusSpotlightSearchResults,
  void Function() focusSpotlightSources,
  bool Function() isTelevision,
  bool Function() mounted,
  void Function() navigateToAddons,
  void Function() navigateToManageSources,
  void Function({bool openAddSource}) navigateToSettings,
  void Function(String? category) onCategoryChanged,
  void Function(String contentType) onContentTypeChanged,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  void Function() openScheduledRecordings,
  void Function() openSpotlightSearch,
  Future<void> Function(String category) promptCategoryOptions,
  Future<void> Function() promptCreateList,
  Widget? Function() searchHeader,
  void Function(bool expanded) setSpotlightSourcesExpanded,
  Widget Function(Widget child) spotlightControlNavigation,
  int? Function() spotlightSelectedSourceCount,
});

class IptvSpotlightLayout {
  final IptvSpotlightLayoutDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvRecordingState _recordingState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvSpotlightLayout(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _recordingState = _deps.recordingState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  bool get _anyRecordingLive => _deps.anyRecordingLive();

  bool get _canShowCategoryOptions => _deps.canShowCategoryOptions();

  Map<String, int> get _categoryCounts => _deps.categoryCounts();

  List<IptvListMeta> get _customLists => _deps.customLists();

  String? get _effectiveCategory => _deps.effectiveCategory();

  int? get _spotlightSelectedSourceCount =>
      _deps.spotlightSelectedSourceCount();

  Widget buildSpotlight(
    BoxConstraints constraints,
    IptvSpotlightLayoutMode mode,
  ) {
    final selected = _settingsState.selectedPlaylist;
    final sports = selected?.isSports ?? false;
    return SpotlightShell(
      mode: mode,
      searchSlot: buildSpotlightSearch(mode),
      sourcesWrapper: (child) => FocusScope(
        node: _focusState.spotlightRailScope,
        onFocusChange: (focused) {
          // Dialogs opened from the drawer temporarily own focus. Keep the
          // search available for their return instead of hiding its field.
          if (!focused && ModalRoute.of(_deps.context())?.isCurrent != false) {
            _deps.setSpotlightSourcesExpanded(false);
          }
        },
        onKeyEvent: (_, event) {
          if (!_deps.isTelevision() &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (event is KeyDownEvent) _deps.closeSpotlightSources();
            return KeyEventResult.handled;
          }

          // MainPage's automatic sidebar fallback deliberately excludes
          // nested scopes. This persistent rail must exit explicitly on TV.
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              _deps.isTelevision() &&
              MainPageBridge.focusTvSidebar != null) {
            if (event is KeyDownEvent) _deps.exitSpotlightSourcesToApp();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
      railSlot: buildSpotlightRail(
        collapsed:
            mode == IptvSpotlightLayoutMode.wide &&
            !_selectionState.spotlightSourcesExpanded,
      ),
      categorySlot: _deps.spotlightControlNavigation(
        SpotlightCategoryControl(
          dense: true,
          categoryLabel: _effectiveCategory ?? 'All channels',
          channelCount: _catalogState.filteredChannels.length,
          loading: _catalogState.isLoading,
          onPressed: showSpotlightCategoryPicker,
          focusNode: _focusState.categoryFilterFocusNode,
          optionsFocusNode: _focusState.spotlightCategoryOptionsFocusNode,
          onOpenOptions: _canShowCategoryOptions && _effectiveCategory != null
              ? () => unawaited(
                  _deps.promptCategoryOptions(_catalogState.selectedCategory!),
                )
              : null,
        ),
      ),
      contentTypeSlot: selected?.isXtreamCodes ?? false
          ? _deps.spotlightControlNavigation(
              SpotlightContentTypeControl(
                dense: true,
                value: _catalogState.selectedContentType,
                onChanged: _deps.onContentTypeChanged,
                firstItemFocusNode: _focusState.contentTypeFocusNode,
              ),
            )
          : null,
      heroSlot: FocusScope(
        node: _focusState.spotlightHeroScope,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowUp => TraversalDirection.up,
            LogicalKeyboardKey.arrowDown => TraversalDirection.down,
            LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
            LogicalKeyboardKey.arrowRight => TraversalDirection.right,
            _ => null,
          };
          if (direction == null) return KeyEventResult.ignored;
          // Traverse all action rows before leaving the hero. Its scope
          // confines spatial traversal to these buttons, including Wrap rows.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary.focusInDirection(direction)) {
            return KeyEventResult.handled;
          }
          switch (direction) {
            case TraversalDirection.down:
              _focusState.categoryFilterFocusNode.requestFocus();
            case TraversalDirection.up:
              _deps.focusSpotlightSearchOrExit();
            case TraversalDirection.left:
              _deps.focusSpotlightSources();
            case TraversalDirection.right:
              break;
          }
          return KeyEventResult.handled;
        },
        child: _deps.buildSpotlightHero(mode),
      ),
      contentSlot: sports
          ? FocusScope(
              node: _focusState.spotlightSportsScope,
              child: _deps.buildSpotlightContent(mode),
            )
          : _deps.buildSpotlightContent(mode),
      contentOnly: sports,
      onOpenSources: showSpotlightSources,
      sourcesExpanded: _selectionState.spotlightSourcesExpanded,
      onToggleSources: () {
        if (_selectionState.spotlightSourcesExpanded) {
          _deps.closeSpotlightSources();
        } else {
          _deps.focusSpotlightSources();
        }
      },
      onCloseSources: _deps.closeSpotlightSources,
      onExitSourcesLeft: _deps.exitSpotlightSourcesToApp,
      onOpenSearch: _deps.openSpotlightSearch,
      compactSourceLabel: selected?.name ?? 'Sources',
      compactSourceCount: _spotlightSelectedSourceCount,
      compactSourceFocusNode: _focusState.playlistFilterFocusNode,
      onSourceDown: _deps.focusSpotlightHero,
      railWidth: 244,
      padding: EdgeInsets.all(mode == IptvSpotlightLayoutMode.wide ? 10 : 8),
    );
  }

  Widget buildSpotlightSearch(IptvSpotlightLayoutMode mode) {
    final search = _deps.searchHeader();
    if (search == null) return const SizedBox.shrink();
    if (search is! BrowseSearchHeader) return search;
    final t = IptvStyleTokens.spotlight;
    return BrowseSearchHeader(
      key: search.key,
      controller: search.controller,
      focusNode: search.focusNode,
      hintText: mode == IptvSpotlightLayoutMode.wide
          ? 'Search'
          : search.hintText,
      onChanged: search.onChanged,
      onSubmitted: (value) {
        search.onSubmitted?.call(value);
        // TV's parent coordinates keyboard dismissal before requesting focus.
        // Desktop and standalone headers can enter results immediately.
        if (!_deps.isTelevision() || search.onSubmitted == null) {
          _deps.focusSpotlightSearchResults();
        }
      },
      onClear: search.onClear,
      onDownArrow: _deps.focusSpotlightSearchResults,
      ink: t.fg,
      fillColor: t.fg.withValues(alpha: 0.055),
      focusedBorderColor: t.accent,
      accent: t.accent,
      keyboardGround: t.panel,
      keyboardInk: t.fg,
      keyboardInkOnAccent: t.focusInk,
      padding: mode == IptvSpotlightLayoutMode.wide
          ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
          : EdgeInsets.zero,
    );
  }

  Widget buildSpotlightRail({
    bool collapsed = false,
    bool autofocusFirstItem = false,
    ValueChanged<IptvPlaylist>? onSelectPlaylist,
    VoidCallback? onOpenRecordings,
    VoidCallback? onNewList,
    VoidCallback? onAddPlaylist,
    VoidCallback? onAddAddon,
    VoidCallback? onManageSources,
  }) {
    return SpotlightRail(
      collapsed: collapsed,
      onEntryFocus: autofocusFirstItem
          ? null
          : () {
              if (_selectionState.spotlightLayoutMode ==
                  IptvSpotlightLayoutMode.wide) {
                _deps.setSpotlightSourcesExpanded(true);
              }
            },
      playlists: _settingsState.playlists,
      selectedPlaylist: _settingsState.selectedPlaylist,
      sourceCounts: _recordingState.sourceCounts,
      customListCounts: {
        for (final list in _customLists)
          'iptv-list-${list.id}': list.channelCount,
      },
      favoritesCount: _membershipState.favoriteUrls.length,
      continueWatchingCount: _recordingState.continueWatchingCount,
      recordingsCount: _recordingState.scheduledCount,
      showRecordings: _recordingState.pageCanRecord,
      recordingActive: _anyRecordingLive,
      onSelectPlaylist:
          onSelectPlaylist ??
          (playlist) {
            _deps.setSpotlightSourcesExpanded(false);
            _deps.onPlaylistChanged(playlist, focusContent: true);
          },
      onOpenRecordings:
          onOpenRecordings ??
          (_recordingState.pageCanRecord
              ? _deps.openScheduledRecordings
              : null),
      onNewList: onNewList ?? () => unawaited(_deps.promptCreateList()),
      onAddPlaylist: onAddPlaylist ?? _deps.navigateToSettings,
      onAddAddon: onAddAddon ?? _deps.navigateToAddons,
      onManageSources: onManageSources ?? _deps.navigateToManageSources,
      firstItemFocusNode: autofocusFirstItem
          ? null
          : _focusState.playlistFilterFocusNode,
      autofocusFirstItem: autofocusFirstItem,
      onUpFromFirstItem: autofocusFirstItem
          ? null
          : _deps.focusSpotlightSearchOrExit,
      onExitRight: autofocusFirstItem ? null : _deps.closeSpotlightSources,
    );
  }

  Future<void> showSpotlightSources() async {
    final size = MediaQuery.sizeOf(_deps.context());
    await showDialog<void>(
      context: _deps.context(),
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_deps.mounted()) action();
          });
        }

        return TvHeldKeyGuard(
          child: Dialog(
            backgroundColor: IptvStyleTokens.spotlight.panel,
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: IptvStyleTokens.spotlight.hairline2),
            ),
            child: SizedBox(
              width: math.min(390, size.width - 32),
              height: math.min(620, size.height - 32),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Sources')),
                        CloseButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: buildSpotlightRail(
                        autofocusFirstItem: true,
                        onSelectPlaylist: (playlist) => closeThen(
                          () => _deps.onPlaylistChanged(
                            playlist,
                            focusContent: true,
                          ),
                        ),
                        onOpenRecordings: _recordingState.pageCanRecord
                            ? () => closeThen(_deps.openScheduledRecordings)
                            : null,
                        onNewList: () => closeThen(
                          () => unawaited(_deps.promptCreateList()),
                        ),
                        onAddPlaylist: () =>
                            closeThen(_deps.navigateToSettings),
                        onAddAddon: () => closeThen(_deps.navigateToAddons),
                        onManageSources: () =>
                            closeThen(_deps.navigateToManageSources),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> showSpotlightCategoryPicker() async {
    final picked = await showDialog<String>(
      context: _deps.context(),
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (_) => SpotlightCategoryPickerDialog(
        categories: List<String>.of(_catalogState.categories, growable: false),
        selectedCategory: _effectiveCategory,
        categoryCounts: Map<String, int>.of(_categoryCounts),
        allChannelCount: _catalogState.allChannels.length,
        showOptionsHint:
            _canShowCategoryOptions && _catalogState.categories.isNotEmpty,
        allCategoryValue: IptvSelectionState.kSpotlightAllCategory,
      ),
    );
    if (!_deps.mounted() || picked == null) return;
    _deps.onCategoryChanged(
      picked == IptvSelectionState.kSpotlightAllCategory ? null : picked,
    );
  }
}
