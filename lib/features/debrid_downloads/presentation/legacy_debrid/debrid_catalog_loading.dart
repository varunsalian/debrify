import 'package:debrify/features/debrid_downloads/application/debrid_error_policy.dart';
import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';
import 'debrid_focus_state.dart';

typedef DebridCatalogLoadingDeps = ({
  DebridFocusState focusState,
  DebridCatalogState catalogState,
  DebridDownloadState downloadState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  // TEMP(debrid): submitTorrentSearch -> lib/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search.dart at step 4.
  void Function() submitTorrentSearch,
  String? Function() initialSearchQuery,
  void Function() focusFirstItemOrFallback,
});

class DebridCatalogLoading {
  DebridCatalogLoading(this._deps);
  final DebridCatalogLoadingDeps _deps;

  void onTorrentScroll() {
    if (_deps.focusState.torrentScrollController.position.pixels >=
        _deps.focusState.torrentScrollController.position.maxScrollExtent -
            200) {
      if (!_deps.catalogState.isLoadingMoreTorrents &&
          _deps.catalogState.hasMoreTorrents) {
        loadMoreTorrents();
      }
    }
  }

  void onDownloadScroll() {
    if (_deps.focusState.downloadScrollController.position.pixels >=
        _deps.focusState.downloadScrollController.position.maxScrollExtent -
            200) {
      if (!_deps.downloadState.isLoadingMoreDownloads &&
          _deps.downloadState.hasMoreDownloads) {
        loadMoreDownloads();
      }
    }
  }

  Future<void> loadApiKeyAndData() async {
    final apiKey = await RealDebridStorage.getApiKey();

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.catalogState.apiKey = apiKey;
      });
    }

    if (apiKey != null) {
      await fetchTorrents(apiKey, reset: true);
      await fetchDownloads(apiKey, reset: true);
    } else {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.catalogState.torrentErrorMessage =
              'No API key configured. Please add your Real Debrid API key in Settings.';
          _deps.downloadState.downloadErrorMessage =
              'No API key configured. Please add your Real Debrid API key in Settings.';
        });
      }
    }

    if (_deps.initialSearchQuery() != null &&
        _deps.initialSearchQuery()!.isNotEmpty) {
      _deps.submitTorrentSearch();
    }
  }

  Future<void> fetchTorrents(String apiKey, {bool reset = false}) async {
    if (reset) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.catalogState.torrentPage = 1;
          _deps.catalogState.hasMoreTorrents = true;
          _deps.catalogState.torrents.clear();
        });
      }
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.catalogState.isLoadingTorrents = true;
        _deps.catalogState.torrentErrorMessage = '';
      });
    }

    try {
      final result = await DebridService.getTorrents(
        apiKey,
        page: _deps.catalogState.torrentPage,
        limit: DebridCatalogState.limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      if (_deps.mounted()) {
        _deps.setState(() {
          if (reset) {
            _deps.catalogState.torrents.clear();
          }
          // Filter to show only downloaded torrents
          final downloadedTorrents = newTorrents
              .where((torrent) => torrent.isDownloaded)
              .toList();
          _deps.catalogState.torrents.addAll(downloadedTorrents);
          _deps.catalogState.hasMoreTorrents = hasMore;
          _deps.catalogState.torrentPage++;
          _deps.catalogState.isLoadingTorrents = false;
        });
        // Focus first item if navigated from sidebar
        _deps.focusFirstItemOrFallback();
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.catalogState.torrentErrorMessage = getUserFriendlyErrorMessage(
            e,
          );
          _deps.catalogState.isLoadingTorrents = false;
        });
      }
    }
  }

  Future<void> loadMoreTorrents() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.catalogState.isLoadingMoreTorrents ||
        !_deps.catalogState.hasMoreTorrents) {
      return;
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.catalogState.isLoadingMoreTorrents = true;
      });
    }

    try {
      final result = await DebridService.getTorrents(
        _deps.catalogState.apiKey!,
        page: _deps.catalogState.torrentPage,
        limit: DebridCatalogState.limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      if (_deps.mounted()) {
        _deps.setState(() {
          // Filter to show only downloaded torrents
          final downloadedTorrents = newTorrents
              .where((torrent) => torrent.isDownloaded)
              .toList();
          _deps.catalogState.torrents.addAll(downloadedTorrents);
          _deps.catalogState.hasMoreTorrents = hasMore;
          _deps.catalogState.torrentPage++;
          _deps.catalogState.isLoadingMoreTorrents = false;
        });
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.catalogState.torrentErrorMessage = getUserFriendlyErrorMessage(
            e,
          );
          _deps.catalogState.isLoadingMoreTorrents = false;
        });
      }
    }
  }

  Future<void> fetchDownloads(String apiKey, {bool reset = false}) async {
    if (reset) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.downloadState.downloadPage = 1;
          _deps.downloadState.hasMoreDownloads = true;
          _deps.downloadState.downloads.clear();
        });
      }
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.downloadState.isLoadingDownloads = true;
        _deps.downloadState.downloadErrorMessage = '';
      });
    }

    try {
      final result = await DebridService.getDownloads(
        apiKey,
        page: _deps.downloadState.downloadPage,
        limit: DebridCatalogState.limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      if (_deps.mounted()) {
        _deps.setState(() {
          if (reset) {
            _deps.downloadState.downloads.clear();
          }
          _deps.downloadState.downloads.addAll(newDownloads);
          _deps.downloadState.hasMoreDownloads = hasMore;
          _deps.downloadState.downloadPage++;
          _deps.downloadState.isLoadingDownloads = false;
        });
        // Focus first item if navigated from sidebar
        _deps.focusFirstItemOrFallback();
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.downloadState.downloadErrorMessage =
              getUserFriendlyErrorMessage(e);
          _deps.downloadState.isLoadingDownloads = false;
        });
      }
    }
  }

  Future<void> loadMoreDownloads() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.downloadState.isLoadingMoreDownloads ||
        !_deps.downloadState.hasMoreDownloads) {
      return;
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _deps.downloadState.isLoadingMoreDownloads = true;
      });
    }

    try {
      final result = await DebridService.getDownloads(
        _deps.catalogState.apiKey!,
        page: _deps.downloadState.downloadPage,
        limit: DebridCatalogState.limit,
      );

      final List<DebridDownload> newDownloads = result['downloads'];
      final bool hasMore = result['hasMore'];

      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.downloadState.downloads.addAll(newDownloads);
          _deps.downloadState.hasMoreDownloads = hasMore;
          _deps.downloadState.downloadPage++;
          _deps.downloadState.isLoadingMoreDownloads = false;
        });
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.downloadState.downloadErrorMessage =
              getUserFriendlyErrorMessage(e);
          _deps.downloadState.isLoadingMoreDownloads = false;
        });
      }
    }
  }

  /// Navigate into a torrent (shows root level folders/files)
  /// Reset scroll while the outgoing list is still attached, so the next
  /// listing never inherits the old offset. Listeners are detached around the
  /// jump so it can't trigger a stale load-more at the navigation boundary.
  void resetListScroll() {
    if (_deps.focusState.torrentScrollController.hasClients) {
      _deps.focusState.torrentScrollController.removeListener(onTorrentScroll);
      _deps.focusState.torrentScrollController.jumpTo(0);
      _deps.focusState.torrentScrollController.addListener(onTorrentScroll);
    }
    if (_deps.focusState.downloadScrollController.hasClients) {
      _deps.focusState.downloadScrollController.removeListener(
        onDownloadScroll,
      );
      _deps.focusState.downloadScrollController.jumpTo(0);
      _deps.focusState.downloadScrollController.addListener(onDownloadScroll);
    }
  }
}
