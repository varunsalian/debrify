import 'package:debrify/features/debrid_downloads/application/debrid_folder_policy.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_navigation_state.dart';
import 'debrid_view_state.dart';

typedef DebridFolderNavigationDeps = ({
  DebridCatalogState catalogState,
  void Function() exitSelectionMode,
  DebridFocusState focusState,
  void Function() resetListScroll,
  void Function(VoidCallback) setState,
  DebridNavigationState navigationState,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String text) copyToClipboard,
  void Function(String message) showError,
  DebridViewState viewState,
  void Function() focusFirstItemOrFallback,
  FolderViewMode Function() getCurrentViewMode,
});

// ========== Folder Navigation Methods ==========
class DebridFolderNavigation {
  DebridFolderNavigation(this._deps);
  final DebridFolderNavigationDeps _deps;

  Future<void> navigateIntoTorrent(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

    _deps.exitSelectionMode();

    // Focus first item after folder contents load
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();

    _deps.setState(() {
      _deps.navigationState.isLoadingFolder = true;
    });

    try {
      // Get torrent info to check for RAR archives
      final torrentInfo = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        torrent.id,
      );
      final files =
          (torrentInfo['files'] as List<dynamic>?)
              ?.map((f) => f as Map<String, dynamic>)
              .toList() ??
          [];
      final links = (torrentInfo['links'] as List<dynamic>?) ?? [];

      // Check if this is a RAR archive
      final isRarArchive = RDFolderTreeBuilder.isRarArchive(files, links);

      if (isRarArchive) {
        // Show a message that this cannot be browsed
        _deps.setState(() {
          _deps.navigationState.isLoadingFolder = false;
        });

        // Show dialog explaining RAR archives and offering to download
        if (_deps.mounted()) {
          await showDialog(
            context: _deps.context(),
            builder: (ctx) => AlertDialog(
              backgroundColor: AppThemeScope.of(ctx).cloud.dialogSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.archive,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'RAR Archive Detected',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(
                'This is a RAR archive that Real-Debrid has not extracted yet. '
                'The folder structure shown represents the archive contents, but only the RAR file itself can be downloaded.\n\n'
                'You can download the RAR archive to extract it locally.',
                style: const TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Download the single RAR file
                    if (links.isNotEmpty) {
                      try {
                        final unrestrictResult =
                            await DebridService.unrestrictLink(
                              _deps.catalogState.apiKey!,
                              links[0],
                            );
                        final downloadUrl =
                            unrestrictResult['download'] as String?;
                        if (downloadUrl != null) {
                          _deps.copyToClipboard(downloadUrl);
                        }
                      } catch (e) {
                        _deps.showError(
                          'Failed to get download link: ${e.toString()}',
                        );
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF60A5FA),
                  ),
                  child: const Text('Copy Download Link'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Not a RAR archive - proceed with normal folder navigation
      // Get the folder tree for this torrent
      final folderTree = await DebridService.getTorrentFolderTree(
        _deps.catalogState.apiKey!,
        torrent.id,
      );
      final rootNodes = RDFolderTreeBuilder.getRootLevelNodes(folderTree);

      // Initialize view mode for this torrent if not already set
      _deps.viewState.torrentViewModes.putIfAbsent(
        torrent.id,
        () => FolderViewMode.raw,
      );

      // Apply view mode transformation to root nodes
      final mode = _deps.viewState.torrentViewModes[torrent.id]!;
      List<RDFileNode> transformedNodes;
      switch (mode) {
        case FolderViewMode.raw:
          transformedNodes = rootNodes;
          break;
        case FolderViewMode.sortedAZ:
          transformedNodes = applySortedView(rootNodes);
          break;
        case FolderViewMode.seriesArrange:
          transformedNodes = applySeriesArrangedView(rootNodes);
          break;
      }

      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.navigationState.currentTorrentId = torrent.id;
        _deps.navigationState.currentTorrent = torrent;
        _deps.navigationState.currentFolderTree = folderTree;
        _deps.navigationState.currentViewNodes = transformedNodes;
        _deps.navigationState.folderPath = [];
        _deps.navigationState.isLoadingFolder = false;
      });

      // Focus first item after folder contents load
      _deps.focusFirstItemOrFallback();
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.navigationState.isLoadingFolder = false;
      });
      _deps.showError('Failed to load torrent contents: ${e.toString()}');
    }
  }

  /// Navigate into a folder
  void navigateIntoFolder(RDFileNode folder) {
    if (!folder.isFolder) return;

    // Focus first item after navigation
    _deps.focusState.shouldFocusOnLoad = true;

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _deps.getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    if (mode == FolderViewMode.seriesArrange) {
      // Inside a folder with Series Arrange mode: show files sorted by name
      transformedChildren = applySortedView(folder.children);
    } else {
      switch (mode) {
        case FolderViewMode.raw:
          transformedChildren = folder.children;
          break;
        case FolderViewMode.sortedAZ:
          transformedChildren = applySortedView(folder.children);
          break;
        case FolderViewMode.seriesArrange:
          // Should never reach here
          transformedChildren = folder.children;
          break;
      }
    }

    _deps.setState(() {
      _deps.navigationState.folderPath.add(folder.name);
      _deps.navigationState.currentViewNodes = transformedChildren;
    });

    // Focus first item after navigation
    _deps.focusFirstItemOrFallback();
  }

  /// Navigate up one level
  void navigateUp() {
    // Refocus the first row once the previous listing shows — the focused
    // row is disposed by the swap and nothing else reclaims DPAD focus.
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();
    if (_deps.navigationState.folderPath.isEmpty &&
        _deps.navigationState.currentTorrentId != null) {
      // Go back to torrents list
      _deps.setState(() {
        _deps.navigationState.currentTorrentId = null;
        _deps.navigationState.currentTorrent = null;
        _deps.navigationState.currentFolderTree = null;
        _deps.navigationState.currentViewNodes = null;
        _deps.navigationState.folderPath = [];
      });
      _deps.focusFirstItemOrFallback();
    } else if (_deps.navigationState.folderPath.isNotEmpty &&
        _deps.navigationState.currentFolderTree != null) {
      // Go up one folder level
      _deps.navigationState.folderPath.removeLast();

      // Get raw nodes at the new path
      List<RDFileNode> rawNodes;
      if (_deps.navigationState.folderPath.isEmpty) {
        rawNodes = RDFolderTreeBuilder.getRootLevelNodes(
          _deps.navigationState.currentFolderTree!,
        );
      } else {
        // Find the folder node at the current path
        RDFileNode currentNode = _deps.navigationState.currentFolderTree!;
        for (final folderName in _deps.navigationState.folderPath) {
          final childFolder = currentNode.children
              .cast<RDFileNode?>()
              .firstWhere(
                (node) => node?.name == folderName && node?.isFolder == true,
                orElse: () => null,
              );
          if (childFolder != null) {
            currentNode = childFolder;
          } else {
            // Folder not found - reset to root
            _deps.navigationState.folderPath.clear();
            rawNodes = RDFolderTreeBuilder.getRootLevelNodes(
              _deps.navigationState.currentFolderTree!,
            );
            // Apply view mode and set state
            final mode = _deps.getCurrentViewMode();
            List<RDFileNode> transformedNodes;
            switch (mode) {
              case FolderViewMode.raw:
                transformedNodes = rawNodes;
                break;
              case FolderViewMode.sortedAZ:
                transformedNodes = applySortedView(rawNodes);
                break;
              case FolderViewMode.seriesArrange:
                transformedNodes = applySeriesArrangedView(rawNodes);
                break;
            }
            _deps.setState(() {
              _deps.navigationState.currentViewNodes = transformedNodes;
            });
            _deps.focusFirstItemOrFallback();
            return;
          }
        }
        rawNodes = currentNode.children;
      }

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      final mode = _deps.getCurrentViewMode();
      List<RDFileNode> transformedNodes;

      if (mode == FolderViewMode.seriesArrange &&
          _deps.navigationState.folderPath.isNotEmpty) {
        // Still inside a folder after going up - use sorted view
        transformedNodes = applySortedView(rawNodes);
      } else {
        switch (mode) {
          case FolderViewMode.raw:
            transformedNodes = rawNodes;
            break;
          case FolderViewMode.sortedAZ:
            transformedNodes = applySortedView(rawNodes);
            break;
          case FolderViewMode.seriesArrange:
            transformedNodes = applySeriesArrangedView(rawNodes);
            break;
        }
      }

      _deps.setState(() {
        _deps.navigationState.currentViewNodes = transformedNodes;
      });
      _deps.focusFirstItemOrFallback();
    }
  }

  String getCurrentFolderTitle() {
    if (_deps.navigationState.currentTorrentId == null) return '';
    if (_deps.navigationState.folderPath.isEmpty) {
      return _deps.navigationState.currentTorrent?.filename ?? 'Torrent Files';
    }
    return _deps.navigationState.folderPath.last;
  }
}
