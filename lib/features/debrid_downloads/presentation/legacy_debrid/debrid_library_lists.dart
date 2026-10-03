import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_navigation_state.dart';
import 'debrid_selection_state.dart';
import 'debrid_torrent_search_state.dart';

typedef DebridLibraryListsDeps = ({
  DebridCatalogState catalogState,
  Future<void> Function(String apiKey, {bool reset}) fetchTorrents,
  DebridFocusState focusState,
  Widget Function(RDTorrent torrent, int index) buildTorrentCard,
  Widget Function() buildTorrentToolbar,
  Widget Function() buildViewSelectorBar,
  DebridTorrentSearchState torrentSearchState,
  Widget Function() buildTorrentSearchBar,
  DebridSelectionState selectionState,
  Widget Function() buildSelectionBar,
  DebridNavigationState navigationState,
  Widget Function() buildFolderLoadingView,
  Widget Function() buildTorrentSearchResults,
  bool Function() selectSourceMode,
  DebridDownloadState downloadState,
  Future<void> Function(String apiKey, {bool reset}) fetchDownloads,
  Widget Function(DebridDownload download, int index) buildDownloadCard,
  Widget Function() buildDownloadToolbar,
});

class DebridLibraryLists {
  DebridLibraryLists(this._deps);
  final DebridLibraryListsDeps _deps;

  Widget buildTorrentContent() {
    Widget body;

    if (_deps.catalogState.isLoadingTorrents &&
        _deps.catalogState.torrents.isEmpty) {
      body = const CloudRowSkeletonList();
    } else if (_deps.catalogState.torrentErrorMessage.isNotEmpty &&
        _deps.catalogState.torrents.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading Torrent Downloads',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _deps.catalogState.torrentErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                autofocus: true,
                onPressed: () => _deps.fetchTorrents(
                  _deps.catalogState.apiKey!,
                  reset: true,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_deps.catalogState.torrents.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No torrent downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your downloaded torrents will appear here',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () async {
          if (_deps.catalogState.apiKey != null) {
            await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
          }
        },
        color: Colors.white,
        backgroundColor: const Color(0xFF1E293B),
        strokeWidth: 3,
        child: ListView.builder(
          controller: _deps.focusState.torrentScrollController,
          padding: const EdgeInsets.all(16),
          itemCount:
              _deps.catalogState.torrents.length +
              (_deps.catalogState.hasMoreTorrents ? 1 : 0),
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _deps.catalogState.torrents.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final torrent = _deps.catalogState.torrents[index];
            return KeyedSubtree(
              key: ValueKey(torrent.id),
              child: _deps.buildTorrentCard(torrent, index),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        if (!_deps.selectSourceMode()) _deps.buildTorrentToolbar(),
        _deps.buildViewSelectorBar(),
        if (_deps.torrentSearchState.isTorrentSearchActive)
          _deps.buildTorrentSearchBar(),
        if (_deps.selectionState.isSelectionMode) _deps.buildSelectionBar(),
        Expanded(
          child: _deps.navigationState.isLoadingFolder
              ? _deps.buildFolderLoadingView()
              : _deps.torrentSearchState.isTorrentSearchActive
              ? _deps.buildTorrentSearchResults()
              : body,
        ),
      ],
    );
  }

  Widget buildDownloadContent() {
    Widget body;

    if (_deps.downloadState.isLoadingDownloads &&
        _deps.downloadState.downloads.isEmpty) {
      body = const CloudRowSkeletonList();
    } else if (_deps.downloadState.downloadErrorMessage.isNotEmpty &&
        _deps.downloadState.downloads.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading DDL Downloads',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _deps.downloadState.downloadErrorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                autofocus: true,
                onPressed: () => _deps.fetchDownloads(
                  _deps.catalogState.apiKey!,
                  reset: true,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_deps.downloadState.downloads.isEmpty) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No DDL downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your DDL downloads will appear here',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () async {
          if (_deps.catalogState.apiKey != null) {
            await _deps.fetchDownloads(_deps.catalogState.apiKey!, reset: true);
          }
        },
        color: Colors.white,
        backgroundColor: const Color(0xFF1E293B),
        strokeWidth: 3,
        child: ListView.builder(
          controller: _deps.focusState.downloadScrollController,
          padding: const EdgeInsets.all(16),
          itemCount:
              _deps.downloadState.downloads.length +
              (_deps.downloadState.hasMoreDownloads ? 1 : 0),
          cacheExtent: 200.0, // Pre-cache items for smoother scrolling
          addRepaintBoundaries: true, // Optimize repainting
          itemBuilder: (context, index) {
            if (index == _deps.downloadState.downloads.length) {
              // Loading more indicator
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final download = _deps.downloadState.downloads[index];
            return KeyedSubtree(
              key: ValueKey(download.id),
              child: _deps.buildDownloadCard(download, index),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        if (!_deps.selectSourceMode()) _deps.buildDownloadToolbar(),
        _deps.buildViewSelectorBar(),
        if (_deps.selectionState.isSelectionMode) _deps.buildSelectionBar(),
        Expanded(child: body),
      ],
    );
  }
}
