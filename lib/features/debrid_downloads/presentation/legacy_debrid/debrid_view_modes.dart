import 'package:debrify/features/debrid_downloads/application/debrid_folder_policy.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:flutter/material.dart';

import 'debrid_navigation_state.dart';
import 'debrid_view_state.dart';

typedef DebridViewModesDeps = ({
  DebridNavigationState navigationState,
  DebridViewState viewState,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
});

class DebridViewModes {
  DebridViewModes(this._deps);
  final DebridViewModesDeps _deps;

  /// Get current view mode for active torrent
  FolderViewMode getCurrentViewMode() {
    if (_deps.navigationState.currentTorrentId == null) {
      return FolderViewMode.raw;
    }
    return _deps.viewState.torrentViewModes[_deps
            .navigationState
            .currentTorrentId] ??
        FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void setViewMode(FolderViewMode mode) {
    if (_deps.navigationState.currentTorrentId == null ||
        _deps.navigationState.currentViewNodes == null) {
      return;
    }

    // Get raw nodes based on current path
    List<RDFileNode> rawNodes;
    if (_deps.navigationState.folderPath.isEmpty &&
        _deps.navigationState.currentFolderTree != null) {
      rawNodes = RDFolderTreeBuilder.getRootLevelNodes(
        _deps.navigationState.currentFolderTree!,
      );
    } else if (_deps.navigationState.currentFolderTree != null) {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = _deps.navigationState.currentFolderTree!;
      for (final folderName in _deps.navigationState.folderPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          _deps.setState(() {
            _deps.navigationState.currentViewNodes = [];
          });
          return;
        }
      }
      rawNodes = currentNode.children;
    } else {
      return;
    }

    // If user selected Series Arrange, detect if content is actually a series
    if (mode == FolderViewMode.seriesArrange) {
      final isSeries = detectSeriesPattern(rawNodes);

      if (!isSeries) {
        // Not a series - show snackbar and fallback to sorted view
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: const Text(
              'No series detected in this folder. Switching to Sort (A-Z) view.',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: AppThemeScope.of(
              _deps.context(),
            ).cloud.dialogSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to sorted view instead
        _deps.setState(() {
          _deps.viewState.torrentViewModes[_deps
                  .navigationState
                  .currentTorrentId!] =
              FolderViewMode.sortedAZ;
          _deps.navigationState.currentViewNodes = applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    _deps.setState(() {
      _deps.viewState.torrentViewModes[_deps
              .navigationState
              .currentTorrentId!] =
          mode;

      switch (mode) {
        case FolderViewMode.raw:
          _deps.navigationState.currentViewNodes = rawNodes;
          break;
        case FolderViewMode.sortedAZ:
          _deps.navigationState.currentViewNodes = applySortedView(rawNodes);
          break;
        case FolderViewMode.seriesArrange:
          _deps.navigationState.currentViewNodes = applySeriesArrangedView(
            rawNodes,
          );
          break;
      }
    });
  }
}
