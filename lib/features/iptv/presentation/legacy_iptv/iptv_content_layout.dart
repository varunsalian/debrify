import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/widgets/iptv/iptv_channel_row.dart';
import 'package:debrify/widgets/iptv/iptv_empty_state.dart';
import 'package:debrify/widgets/iptv/sports/iptv_sports_board.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

typedef IptvContentLayoutDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvMembershipState membershipState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  Widget Function(BuildContext context) buildLoadingState,
  Widget Function(
    List<IptvChannel> channels, {
    required double rowExtent,
    required bool epgRows,
  })
  buildTabletCenteredSelector,
  BuildContext Function() context,
  List<IptvListMeta> Function() customLists,
  bool Function() epgRowsActive,
  FocusNode Function(IptvChannel channel) focusNodeFor,
  bool Function() isTelevision,
  void Function({bool openAddSource}) navigateToSettings,
  void Function(IptvChannel channel, {bool fromPointer}) onChannelFocused,
  void Function(IptvChannel channel) onRowDetached,
  Future<void> Function(IptvChannel channel) openListPicker,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  Future<void> Function() retryLoad,
  VoidCallback? Function(IptvChannel channel, {bool inPlace}) scheduleActionFor,
  String Function() searchQuery,
  Future<void> Function(IptvChannel channel) showContinueWatchingActions,
  bool Function() showsPosterRows,
  Future<void> Function(IptvChannel channel, bool isFavorited) toggleFavorite,
});

class IptvContentLayout {
  final IptvContentLayoutDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvMembershipState _membershipState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvContentLayout(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _membershipState = _deps.membershipState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  bool get _epgRowsActive => _deps.epgRowsActive();

  bool get _showsPosterRows => _deps.showsPosterRows();

  Widget buildContent({
    bool tvPane = false,
    bool touchSelector = false,
    bool cockpit = false,
  }) {
    // Empty state when no playlists
    if (_settingsState.playlists.isEmpty) {
      return IptvEmptyState(
        hasPlaylists: false,
        onAddPlaylist: _deps.navigateToSettings,
      );
    }

    // Empty state when no playlist selected
    if (_settingsState.selectedPlaylist == null) {
      return const IptvEmptyState(hasPlaylists: true);
    }

    // The Sports shelf renders its own board instead of a channel list.
    if (_settingsState.selectedPlaylist!.isSports) {
      return SportsIptvBoard(onPlay: (channel) => _deps.playChannel(channel));
    }

    // Loading
    if (_catalogState.isLoading) {
      return _deps.buildLoadingState(_deps.context());
    }

    // Error
    if (_catalogState.errorMessage != null &&
        _catalogState.allChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(_deps.context()).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load playlist',
                style: Theme.of(_deps.context()).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _catalogState.errorMessage!,
                style: Theme.of(_deps.context()).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(_deps.context()).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _deps.retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No channels matched. While a progressive load is still streaming in,
    // a definitive "No channels found" would be a lie — matches may simply
    // not have arrived yet, so say that instead.
    if (_catalogState.filteredChannels.isEmpty) {
      if (_catalogState.isLoadingMore) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                _deps.searchQuery().isNotEmpty
                    ? 'No matches yet — channels are still loading'
                    : _catalogState.selectedCategory != null
                    ? 'Nothing in this category yet — still loading'
                    : 'Loading channels…',
                style: Theme.of(_deps.context()).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_catalogState.allChannels.length} channel'
                '${_catalogState.allChannels.length == 1 ? '' : 's'} loaded so far',
                style: Theme.of(_deps.context()).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(_deps.context()).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      final isFavoritesView =
          _settingsState.selectedPlaylist?.isFavorites ?? false;
      final isListView = _settingsState.selectedPlaylist?.isCustomList ?? false;
      final isContinueView =
          _settingsState.selectedPlaylist?.isContinueWatching ?? false;
      final unfiltered =
          _deps.searchQuery().isEmpty && _catalogState.selectedCategory == null;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !unfiltered
                  ? Icons.live_tv_outlined
                  : isContinueView
                  ? Icons.history_rounded
                  : isFavoritesView
                  ? Icons.star_border
                  : isListView
                  ? Icons.playlist_add_rounded
                  : Icons.live_tv_outlined,
              size: 64,
              color: Theme.of(_deps.context()).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              !unfiltered
                  ? 'No channels found'
                  : isContinueView
                  ? 'Nothing in progress'
                  : isFavoritesView
                  ? 'No favorites yet'
                  : isListView
                  ? 'Nothing in ${_settingsState.selectedPlaylist?.name ?? 'this list'} yet'
                  : 'No channels found',
              style: Theme.of(_deps.context()).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _deps.searchQuery().isNotEmpty
                  ? 'Try a different search term'
                  : _catalogState.selectedCategory != null
                  ? 'Try a different category'
                  : isContinueView
                  ? 'Movies you start but do not finish show up here'
                  : isFavoritesView || isListView
                  ? (_deps.isTelevision()
                        ? 'Hold OK on any channel to add it here'
                        : 'Long-press any channel to add it here')
                  : 'This playlist appears to be empty',
              style: Theme.of(_deps.context()).textTheme.bodyMedium?.copyWith(
                color: Theme.of(_deps.context()).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Results — a compact, guide-style list. Multi-column on wide screens so
    // the horizontal space isn't wasted; a single column on phones and in the
    // TV two-pane's guide column (which is roughly phone-width anyway).
    final w = MediaQuery.of(_deps.context()).size.width;
    final narrowRows = !_deps.isTelevision() && w < 600;
    final hPadding = tvPane ? 10.0 : (w >= 900 ? 28.0 : 12.0);
    final maxCrossAxisExtent = tvPane ? 720.0 : 440.0;
    const crossAxisSpacing = 12.0;
    final padRight = tvPane ? 24.0 : hPadding;

    // Resolved ONCE per build, not per row: the getter probes channels with
    // IptvEpgService.isEpgCapable, which parses a URL per probe (one for a
    // capable list, up to ten when the leading channels aren't) — reading it
    // from the item builder repeated that for every row the grid materialized.
    // It is constant for the whole list anyway, and the grid gives every tile
    // ONE height, so hoisting also makes the delegate and the rows agree by
    // construction instead of by coincidence.
    final epgRows = _epgRowsActive;
    final rowExtent = _showsPosterRows
        ? kIptvPosterRowExtent
        : epgRows
        ? (cockpit ? kIptvEpgRowTallExtent : kIptvEpgRowExtent)
        : cockpit
        ? kIptvRowTallExtent
        : narrowRows
        ? kIptvNarrowRowExtent
        : kIptvRowExtent;

    final Widget channelBrowser = touchSelector
        ? _deps.buildTabletCenteredSelector(
            _catalogState.filteredChannels,
            rowExtent: rowExtent,
            epgRows: epgRows,
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              // The delegate's own column math, replicated so rows can know
              // whether they sit on the grid's right edge (those get the
              // RIGHT-opens-schedule key; the rest keep plain traversal).
              final crossExtent = (constraints.maxWidth - hPadding - padRight)
                  .clamp(1.0, double.infinity);
              final columns =
                  (crossExtent / (maxCrossAxisExtent + crossAxisSpacing))
                      .ceil()
                      .clamp(1, 100);
              // Captured together so itemCount and the list the delegate indexes
              // can never disagree: a RangeError in itemBuilder is exactly what a
              // count-from-one-variable / rows-from-another split produces the
              // day someone assigns _filteredChannels outside setState.
              final channelList = _catalogState.filteredChannels;
              final itemCount = channelList.length;
              // Published for the startup-channel launch, which must scroll to
              // a row that has never been built (so it has no focus node and
              // no ensureVisible of its own). These are LayoutBuilder locals —
              // unreachable from outside without stashing them.
              _selectionState.gridColumns = columns;
              _selectionState.gridRowExtent = rowExtent;

              // NOT wrapped in TvFocusScrollWrapper: this subtree has no ancestor
              // Scrollable, so the wrapper's ensureVisible walk was a silent no-op
              // — and each row already runs its own ensureVisible on focus, so the
              // wrapper only ever risked a second, competing scroll animation.
              return FocusTraversalGroup(
                child: GridView.builder(
                  controller: _focusState.scrollController,
                  padding: EdgeInsets.fromLTRB(hPadding, 8, padRight, 24),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxCrossAxisExtent,
                    mainAxisExtent: rowExtent,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: crossAxisSpacing,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    final channel = channelList[index];
                    // Right edge = last column, or the final item of a partial
                    // last row (nothing exists to its right either way).
                    final rightEdge =
                        index % columns == columns - 1 ||
                        index == itemCount - 1;
                    return IptvChannelRow(
                      // ObjectKey, not ValueKey(url): duplicate URLs are legal
                      // in a playlist and must keep independent row state.
                      key: ObjectKey(channel),
                      channel: channel,
                      isTelevision: _deps.isTelevision(),
                      onTap: () => _deps.playChannel(channel),
                      onLongPress:
                          (_settingsState
                                  .selectedPlaylist
                                  ?.isContinueWatching ??
                              false)
                          ? () => _deps.showContinueWatchingActions(channel)
                          : null,
                      focusNode: _deps.focusNodeFor(channel),
                      isFavorited: _membershipState.favoriteUrls.contains(
                        channel.url,
                      ),
                      inAnyList:
                          _membershipState
                              .membership[channel.url]
                              ?.isNotEmpty ??
                          false,
                      onFavoriteToggle: channel.contentType == 'series'
                          ? null
                          : (isFavorited) =>
                                _deps.toggleFavorite(channel, isFavorited),
                      onOpenListPicker: channel.contentType == 'series'
                          ? null
                          : () => _deps.openListPicker(channel),
                      hasCustomLists: _customLists.isNotEmpty,
                      onFocused: tvPane
                          ? () => _deps.onChannelFocused(channel)
                          : null,
                      onPointerRest: tvPane
                          ? () => _deps.onChannelFocused(
                              channel,
                              fromPointer: true,
                            )
                          : null,
                      onDetached: () => _deps.onRowDetached(channel),
                      onSchedule: _deps.scheduleActionFor(
                        channel,
                        inPlace: _deps.isTelevision() && tvPane,
                      ),
                      // Cockpit: RIGHT walks into the stage's actions by
                      // geometry instead; the full schedule pane stays
                      // reachable from the stage's Guide button.
                      scheduleOnRightKey: rightEdge && !cockpit,
                      progress: _membershipState.progressByUrl[channel.url],
                      poster: _showsPosterRows,
                      epg: epgRows,
                      twoLineName: cockpit && !_showsPosterRows,
                      // Styled looks exist only in the cockpit, and only for
                      // live/EPG rows — VOD/series posters keep the shipped
                      // layout in every style (plan: posters are untouched).
                      style: cockpit && !_showsPosterRows
                          ? _settingsState.iptvStyle
                          : IptvStyle.command,
                      tileWidth:
                          (crossExtent - (columns - 1) * crossAxisSpacing) /
                          columns,
                    );
                  },
                ),
              );
            },
          );
    // Streamed load still running: a quiet, non-focusable line keeps the
    // visible (possibly filtered) rows honest about being a partial list.
    final subtle = Theme.of(_deps.context()).colorScheme.onSurfaceVariant;
    Widget buildProgressiveStatus() => Padding(
      padding: EdgeInsets.fromLTRB(hPadding + 4, 6, hPadding, 0),
      child: Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: subtle.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _deps.searchQuery().isNotEmpty
                  ? 'Still loading (${_catalogState.allChannels.length} so far) — '
                        'search results may be incomplete'
                  : 'Still loading channels — '
                        '${_catalogState.allChannels.length} so far',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtle,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (touchSelector) {
      // Keep this parent chain stable when the final progressive result hides
      // the status line. Moving the selector from inside a Column to the root
      // would dispose it even with a stable key and reset its scroll state.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _catalogState.isLoadingMore
              ? buildProgressiveStatus()
              : const SizedBox.shrink(),
          Expanded(
            key: const ValueKey('iptv-tablet-selector-slot'),
            child: channelBrowser,
          ),
        ],
      );
    }

    if (!_catalogState.isLoadingMore) return channelBrowser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildProgressiveStatus(),
        Expanded(child: channelBrowser),
      ],
    );
  }
}
