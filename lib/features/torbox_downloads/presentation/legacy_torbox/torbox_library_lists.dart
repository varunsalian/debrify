import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_web_state.dart';

typedef TorboxLibraryListsDeps = ({
  bool Function() isAtRoot,
  TorboxCatalogState catalogState,
  List<dynamic> Function() currentItems,
  BuildContext Function() context,
  void Function() openSettings,
  TorboxFocusState focusState,
  Widget Function(TorboxTorrent torrent, int index) buildTorrentFolderCard,
  Widget Function(RDFileNode node, int index) buildFileOrFolderCard,
  TorboxWebState webState,
  Widget Function(TorboxWebDownload webDownload, int index)
  buildWebDownloadCard,
});

class TorboxLibraryLists {
  TorboxLibraryLists(this._deps);
  final TorboxLibraryListsDeps _deps;

  Widget buildFilesFoldersList() {
    // Check if we're showing web downloads view at root level
    final isWebDownloadsView =
        _deps.isAtRoot() &&
        _deps.catalogState.selectedView == TorboxDownloadsView.webDownloads;

    if (isWebDownloadsView) {
      return buildWebDownloadsList();
    }

    // Loading state
    if (_deps.catalogState.isLoading && _deps.currentItems().isEmpty) {
      return const CloudRowSkeletonList();
    }

    // Error state
    if (_deps.catalogState.errorMessage.isNotEmpty &&
        _deps.currentItems().isEmpty &&
        !_deps.catalogState.initialLoad) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 48,
            color: Theme.of(_deps.context()).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _deps.catalogState.errorMessage,
            style: Theme.of(_deps.context()).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_deps.catalogState.apiKey == null ||
              _deps.catalogState.apiKey!.isEmpty)
            FilledButton(
              onPressed: _deps.openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_deps.currentItems().isEmpty && !_deps.catalogState.isLoading) {
      final isRoot = _deps.isAtRoot();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRoot ? Icons.inbox_outlined : Icons.folder_open,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                isRoot ? 'No Torrents Yet' : 'Folder is Empty',
                style: Theme.of(_deps.context()).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                isRoot
                    ? 'Add torrents via Torbox to see them here.'
                    : 'This folder doesn\'t contain any files or subfolders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of items (torrents or files/folders)
    return ListView.builder(
      controller: _deps.focusState.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount:
          _deps.currentItems().length +
          (_deps.catalogState.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _deps.currentItems().length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = _deps.currentItems()[index];

        if (_deps.isAtRoot()) {
          // Show torrent as a folder
          return _deps.buildTorrentFolderCard(item as TorboxTorrent, index);
        } else {
          // Show file or folder node
          return _deps.buildFileOrFolderCard(item as RDFileNode, index);
        }
      },
    );
  }

  Widget buildWebDownloadsList() {
    // Loading state
    if (_deps.webState.isLoadingWebDownloads &&
        _deps.webState.webDownloads.isEmpty) {
      return const CloudRowSkeletonList();
    }

    // Error state
    if (_deps.webState.webDownloadErrorMessage.isNotEmpty &&
        _deps.webState.webDownloads.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.link_rounded,
            size: 48,
            color: Theme.of(_deps.context()).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _deps.webState.webDownloadErrorMessage,
            style: Theme.of(_deps.context()).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_deps.catalogState.apiKey == null ||
              _deps.catalogState.apiKey!.isEmpty)
            FilledButton(
              onPressed: _deps.openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_deps.webState.webDownloads.isEmpty &&
        !_deps.webState.isLoadingWebDownloads) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              Text(
                'No Web Downloads Yet',
                style: Theme.of(_deps.context()).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Add web downloads from YouTube, file hosts, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of web downloads
    return ListView.builder(
      controller: _deps.focusState.webDownloadScrollController,
      padding: const EdgeInsets.all(16),
      itemCount:
          _deps.webState.webDownloads.length +
          (_deps.webState.isLoadingMoreWebDownloads ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _deps.webState.webDownloads.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _deps.buildWebDownloadCard(
          _deps.webState.webDownloads[index],
          index,
        );
      },
    );
  }
}
