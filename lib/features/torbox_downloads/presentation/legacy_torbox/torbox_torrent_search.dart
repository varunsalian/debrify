import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_torrent_search_state.dart';

typedef TorboxTorrentSearchDeps = ({
  void Function(VoidCallback) setState,
  TorboxTorrentSearchState torrentSearchState,
  TorboxFocusState focusState,
  bool Function() selectSourceMode,
  String? Function() initialSearchQuery,
  BuildContext Function() context,
  bool Function() mounted,
  TorboxCatalogState catalogState,
});

class TorboxTorrentSearch {
  TorboxTorrentSearch(this._deps);
  final TorboxTorrentSearchDeps _deps;

  void toggleTorrentSearch() {
    if (_deps.selectSourceMode()) return;
    _deps.setState(() {
      _deps.torrentSearchState.isTorrentSearchActive =
          !_deps.torrentSearchState.isTorrentSearchActive;
      if (!_deps.torrentSearchState.isTorrentSearchActive) {
        _deps.torrentSearchState.torrentSearchController.clear();
        _deps.torrentSearchState.torrentSearchQuery = '';
        _deps.torrentSearchState.allTorrentsForSearch.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deps.focusState.torrentSearchFocusNode.requestFocus();
        });
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
    if (_deps.torrentSearchState.allTorrentsForSearch.isEmpty) {
      _deps.setState(() => _deps.torrentSearchState.torrentSearchQuery = query);
      if (!_deps.torrentSearchState.isLoadingTorrentSearch) {
        _deps.setState(
          () => _deps.torrentSearchState.isLoadingTorrentSearch = true,
        );
        fetchAllTorrentsForSearch();
      }
    } else {
      _deps.setState(() => _deps.torrentSearchState.torrentSearchQuery = query);
      completeTorrentSearchSubmitFocus();
    }
  }

  void completeTorrentSearchSubmitFocus() {
    if (filteredTorrentSearchResults.isEmpty) {
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
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.focusState.torrentSearchSubmitFocus.cancel();
      return;
    }

    try {
      final List<TorboxTorrent> allTorrents = [];
      int offset = 0;
      const limit = 1000;
      bool hasMore = true;

      while (hasMore) {
        final result = await TorboxService.getTorrents(
          key,
          offset: offset,
          limit: limit,
        );
        final List<TorboxTorrent> batch = (result['torrents'] as List)
            .cast<TorboxTorrent>();
        allTorrents.addAll(batch);
        hasMore = result['hasMore'] as bool? ?? false;
        offset += limit;
        if (offset > 5000) break; // Safety cap
      }

      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.torrentSearchState.allTorrentsForSearch = allTorrents;
          _deps.torrentSearchState.isLoadingTorrentSearch = false;
        });
        completeTorrentSearchSubmitFocus();
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.focusState.torrentSearchSubmitFocus.cancel();
        _deps.setState(
          () => _deps.torrentSearchState.isLoadingTorrentSearch = false,
        );
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

  List<TorboxTorrent> get filteredTorrentSearchResults {
    final source = _deps.torrentSearchState.allTorrentsForSearch.isNotEmpty
        ? _deps.torrentSearchState.allTorrentsForSearch
        : _deps.catalogState.torrents;
    if (_deps.torrentSearchState.torrentSearchQuery.isEmpty) return [];
    final query = _deps.torrentSearchState.torrentSearchQuery.toLowerCase();
    return source.where((t) => t.name.toLowerCase().contains(query)).toList();
  }
}
