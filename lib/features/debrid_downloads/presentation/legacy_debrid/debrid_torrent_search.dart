import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_torrent_search_state.dart';

typedef DebridTorrentSearchDeps = ({
  void Function(VoidCallback) setState,
  DebridTorrentSearchState torrentSearchState,
  bool Function() selectSourceMode,
  String? Function() initialSearchQuery,
  DebridFocusState focusState,
  BuildContext Function() context,
  bool Function() mounted,
  DebridCatalogState catalogState,
});

// Torrent list search methods
class DebridTorrentSearch {
  DebridTorrentSearch(this._deps);
  final DebridTorrentSearchDeps _deps;

  void toggleTorrentSearch() {
    if (_deps.selectSourceMode()) return;
    _deps.setState(() {
      _deps.torrentSearchState.isTorrentSearchActive =
          !_deps.torrentSearchState.isTorrentSearchActive;
      if (!_deps.torrentSearchState.isTorrentSearchActive) {
        _deps.torrentSearchState.torrentSearchController.clear();
        _deps.torrentSearchState.torrentSearchQuery = '';
        _deps.torrentSearchState.allTorrentsForSearch.clear();
      }
    });
  }

  bool queryMatchesInitialTitle(String query) {
    final title = _deps.initialSearchQuery();
    if (title == null || title.isEmpty) return true;
    const stopwords = {'the', 'a', 'an'};
    final rawTokens = title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final filtered = rawTokens
        .where((t) => !stopwords.contains(t) && t.length >= 2)
        .toList();
    final effectiveTokens = filtered.isEmpty ? rawTokens : filtered;
    if (effectiveTokens.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    return effectiveTokens.any((t) => normalizedQuery.contains(t));
  }

  void submitTorrentSearch() {
    final query = _deps.torrentSearchState.torrentSearchController.text.trim();
    if (query.isEmpty) {
      _deps.focusState.torrentSearchSubmitFocus.cancel();
      return;
    }
    if (_deps.selectSourceMode() &&
        _deps.torrentSearchState.hiddenFromNav &&
        !queryMatchesInitialTitle(query)) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text(
            'Search must include part of "${_deps.initialSearchQuery()}"',
          ),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 3),
        ),
      );
      _deps.focusState.torrentSearchSubmitFocus.cancel();
      return;
    }
    _deps.focusState.torrentSearchSubmitFocus.arm(
      enabled: PlatformUtil.isTelevision,
    );
    _deps.setState(() => _deps.torrentSearchState.torrentSearchQuery = query);
    if (_deps.torrentSearchState.allTorrentsForSearch.isEmpty) {
      if (!_deps.torrentSearchState.isLoadingSearch) {
        fetchAllTorrentsForSearch();
      }
    } else {
      _deps.setState(() {}); // Trigger rebuild with new query
      completeTorrentSearchSubmitFocus();
    }
  }

  void completeTorrentSearchSubmitFocus() {
    if (filteredSearchTorrents.isEmpty) {
      _deps.focusState.torrentSearchSubmitFocus.cancel();
      return;
    }
    _deps.focusState.torrentSearchSubmitFocus.complete(
      field: _deps.focusState.torrentSearchFocusNode,
      isMounted: () => _deps.mounted(),
      requestFocus: _deps.focusState.firstItemFocusNode.requestFocus,
      targetHasFocus: () => _deps.focusState.firstItemFocusNode.hasFocus,
    );
  }

  Future<void> fetchAllTorrentsForSearch() async {
    if (_deps.catalogState.apiKey == null) {
      _deps.focusState.torrentSearchSubmitFocus.cancel();
      return;
    }
    _deps.setState(() => _deps.torrentSearchState.isLoadingSearch = true);

    try {
      final List<RDTorrent> allTorrents = [];
      int page = 1;
      bool hasMore = true;

      while (hasMore) {
        final result = await DebridService.getTorrents(
          _deps.catalogState.apiKey!,
          page: page,
          limit: 2000,
        );
        final List<RDTorrent> batch = result['torrents'];
        allTorrents.addAll(batch);
        hasMore = result['hasMore'] && batch.isNotEmpty;
        page++;
        // Safety cap at 3 pages (6000 torrents max)
        if (page > 3) break;
      }

      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.torrentSearchState.allTorrentsForSearch = allTorrents;
          _deps.torrentSearchState.isLoadingSearch = false;
        });
        completeTorrentSearchSubmitFocus();
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.focusState.torrentSearchSubmitFocus.cancel();
        _deps.setState(() => _deps.torrentSearchState.isLoadingSearch = false);
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load torrents for search: ${e.toString()}',
            ),
          ),
        );
      }
    }
  }

  List<RDTorrent> get filteredSearchTorrents {
    if (_deps.selectSourceMode() &&
        _deps.torrentSearchState.torrentSearchQuery.isEmpty) {
      return [];
    }
    final downloaded = _deps.torrentSearchState.allTorrentsForSearch.where(
      (t) => t.isDownloaded,
    );
    if (_deps.torrentSearchState.torrentSearchQuery.isEmpty) {
      return downloaded.toList();
    }
    final query = _deps.torrentSearchState.torrentSearchQuery.toLowerCase();
    return downloaded
        .where((t) => t.filename.toLowerCase().contains(query))
        .toList();
  }
}
