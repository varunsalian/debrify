import 'dart:ui';

import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_torrent_search_state.dart';
import 'torbox_web_state.dart';

typedef TorboxCatalogLoadingDeps = ({
  TorboxFocusState focusState,
  TorboxCatalogState catalogState,
  TorboxWebState webState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  // TEMP(torbox): submitTorrentSearch -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search.dart at step 5.
  void Function() submitTorrentSearch,
  String? Function() initialSearchQuery,
  TorboxTorrentSearchState torrentSearchState,
  void Function() focusFirstItemOrFallback,
  // TEMP(torbox): maybeTriggerInitialAction -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_initial_action.dart at step 4.
  void Function() maybeTriggerInitialAction,
});

class TorboxCatalogLoading {
  TorboxCatalogLoading(this._deps);
  final TorboxCatalogLoadingDeps _deps;

  void onScroll() {
    if (_deps.focusState.scrollController.position.pixels >=
            _deps.focusState.scrollController.position.maxScrollExtent - 200 &&
        !_deps.catalogState.isLoadingMore &&
        _deps.catalogState.hasMore &&
        !_deps.catalogState.isLoading) {
      loadMore();
    }
  }

  void onWebDownloadScroll() {
    if (_deps.focusState.webDownloadScrollController.position.pixels >=
            _deps
                    .focusState
                    .webDownloadScrollController
                    .position
                    .maxScrollExtent -
                200 &&
        !_deps.webState.isLoadingMoreWebDownloads &&
        _deps.webState.hasMoreWebDownloads &&
        !_deps.webState.isLoadingWebDownloads) {
      loadMoreWebDownloads();
    }
  }

  Future<void> loadApiKeyAndTorrents() async {
    final key = await TorboxStorage.getTorboxApiKey();
    if (!_deps.mounted()) return;

    _deps.setState(() {
      _deps.catalogState.apiKey = key;
    });

    if (key == null || key.isEmpty) {
      _deps.setState(() {
        _deps.catalogState.initialLoad = false;
        _deps.catalogState.errorMessage =
            'Add your Torbox API key in Settings to view cached torrents.';
        _deps.webState.webDownloadErrorMessage =
            'Add your Torbox API key in Settings to view web downloads.';
      });
      return;
    }

    await Future.wait([
      fetchTorrents(reset: true),
      fetchWebDownloads(reset: true),
    ]);

    if (_deps.initialSearchQuery() != null &&
        _deps.initialSearchQuery()!.isNotEmpty) {
      _deps.submitTorrentSearch();
    }
  }

  Future<void> fetchTorrents({bool reset = false}) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) return;

    if (reset) {
      _deps.setState(() {
        _deps.catalogState.isLoading = true;
        _deps.catalogState.initialLoad = true;
        _deps.catalogState.errorMessage = '';
        _deps.catalogState.offset = 0;
        _deps.catalogState.hasMore = true;
        _deps.catalogState.torrents.clear();
        _deps.torrentSearchState.allTorrentsForSearch.clear();
      });
    } else {
      _deps.setState(() {
        _deps.catalogState.isLoadingMore = true;
      });
    }

    try {
      final result = await TorboxService.getTorrents(
        key,
        offset: _deps.catalogState.offset,
        limit: TorboxCatalogState.limit,
      );
      final List<TorboxTorrent> fetched = (result['torrents'] as List)
          .cast<TorboxTorrent>();
      final bool hasMore = result['hasMore'] as bool? ?? false;
      final bool shouldFetchMore = fetched.isEmpty && hasMore;

      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.catalogState.torrents.addAll(fetched);
        _deps.catalogState.hasMore = hasMore;
        _deps.catalogState.offset += TorboxCatalogState.limit;
        _deps.catalogState.isLoading = false;
        _deps.catalogState.isLoadingMore = false;
        _deps.catalogState.initialLoad = false;
        if (_deps.catalogState.torrents.isNotEmpty) {
          _deps.catalogState.errorMessage = '';
        } else if (!hasMore) {
          _deps.catalogState.errorMessage =
              'No cached torrents found yet. Add torrents via Torbox to see them here.';
        }
      });

      // Focus first item if navigated from sidebar
      _deps.focusFirstItemOrFallback();

      _deps.maybeTriggerInitialAction();

      if (shouldFetchMore) {
        await fetchTorrents();
      }
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.catalogState.errorMessage = e.toString().replaceFirst(
          'Exception: ',
          '',
        );
        _deps.catalogState.isLoading = false;
        _deps.catalogState.isLoadingMore = false;
        _deps.catalogState.initialLoad = false;
      });
    }
  }

  Future<void> loadMore() async {
    if (_deps.catalogState.isLoadingMore || !_deps.catalogState.hasMore) return;
    await fetchTorrents();
  }

  Future<void> refresh() async {
    if (_deps.catalogState.selectedView == TorboxDownloadsView.torrents) {
      await fetchTorrents(reset: true);
    } else {
      await fetchWebDownloads(reset: true);
    }
  }

  Future<void> fetchWebDownloads({bool reset = false}) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) return;

    if (reset) {
      _deps.setState(() {
        _deps.webState.isLoadingWebDownloads = true;
        _deps.webState.webDownloadErrorMessage = '';
        _deps.webState.webDownloadOffset = 0;
        _deps.webState.hasMoreWebDownloads = true;
        _deps.webState.webDownloads.clear();
      });
    } else {
      _deps.setState(() {
        _deps.webState.isLoadingMoreWebDownloads = true;
      });
    }

    try {
      final result = await TorboxService.getWebDownloads(
        key,
        offset: _deps.webState.webDownloadOffset,
        limit: TorboxCatalogState.limit,
      );

      if (!_deps.mounted()) return;

      final webDownloads = result['webDownloads'] as List<TorboxWebDownload>;
      final hasMore = result['hasMore'] as bool;

      _deps.setState(() {
        _deps.webState.webDownloads.addAll(webDownloads);
        // Advance by the page size, not the filtered count — the service
        // drops non-completed items, so filtered.length under-counts and
        // would make the next page overlap this one (duplicate rows).
        _deps.webState.webDownloadOffset += TorboxCatalogState.limit;
        _deps.webState.hasMoreWebDownloads = hasMore;
        _deps.webState.isLoadingWebDownloads = false;
        _deps.webState.isLoadingMoreWebDownloads = false;
      });

      // Focus first item if navigated from sidebar
      _deps.focusFirstItemOrFallback();
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.webState.webDownloadErrorMessage = e.toString().replaceFirst(
          'Exception: ',
          '',
        );
        _deps.webState.isLoadingWebDownloads = false;
        _deps.webState.isLoadingMoreWebDownloads = false;
      });
    }
  }

  Future<void> loadMoreWebDownloads() async {
    if (_deps.webState.isLoadingMoreWebDownloads ||
        !_deps.webState.hasMoreWebDownloads) {
      return;
    }
    await fetchWebDownloads();
  }

  /// Reset scroll while the outgoing list is still attached, so the next
  /// listing never inherits the old offset (the torrent and node lists share
  /// one controller). Load-more listeners are detached around the jump —
  /// otherwise jumpTo(0) can fire them while the OLD view's pagination state
  /// is still live and append its next page into the new listing.
  void resetListScroll() {
    if (_deps.focusState.scrollController.hasClients) {
      _deps.focusState.scrollController.removeListener(onScroll);
      _deps.focusState.scrollController.jumpTo(0);
      _deps.focusState.scrollController.addListener(onScroll);
    }
    if (_deps.focusState.webDownloadScrollController.hasClients) {
      _deps.focusState.webDownloadScrollController.removeListener(
        onWebDownloadScroll,
      );
      _deps.focusState.webDownloadScrollController.jumpTo(0);
      _deps.focusState.webDownloadScrollController.addListener(
        onWebDownloadScroll,
      );
    }
  }
}
