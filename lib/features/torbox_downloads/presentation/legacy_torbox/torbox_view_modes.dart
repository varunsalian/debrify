import 'package:debrify/features/torbox_downloads/application/torbox_folder_policy.dart';
import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_focus_state.dart';
import 'torbox_navigation_state.dart';
import 'torbox_view_state.dart';

typedef TorboxViewModesDeps = ({
  TorboxNavigationState navigationState,
  TorboxViewState viewState,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  TorboxFocusState focusState,
});

class TorboxViewModes {
  TorboxViewModes(this._deps);
  final TorboxViewModesDeps _deps;

  /// Get current view mode for active torrent/web download
  FolderViewMode getCurrentViewMode() {
    if (_deps.navigationState.currentTorrent != null) {
      return _deps.viewState.torrentViewModes[_deps
              .navigationState
              .currentTorrent!
              .id] ??
          FolderViewMode.raw;
    }
    if (_deps.navigationState.currentWebDownload != null) {
      return _deps.viewState.webDownloadViewModes[_deps
              .navigationState
              .currentWebDownload!
              .id] ??
          FolderViewMode.raw;
    }
    return FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void setViewMode(FolderViewMode mode) {
    if ((_deps.navigationState.currentTorrent == null &&
            _deps.navigationState.currentWebDownload == null) ||
        _deps.navigationState.currentFolderNode == null) {
      return;
    }

    // Get raw nodes based on current path
    // Always rebuild tree from scratch to handle virtual folders
    final files =
        _deps.navigationState.currentTorrent?.files ??
        _deps.navigationState.currentWebDownload?.files ??
        [];
    final tree = TorboxFolderTreeBuilder.buildTree(files);
    List<RDFileNode> rawNodes;

    if (_deps.navigationState.currentPath.isEmpty) {
      // At torrent/web download root
      rawNodes = tree.children;
    } else {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = tree;
      bool pathValid = true;

      for (final folderName in _deps.navigationState.currentPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          // Path not found in raw tree (likely inside virtual folder)
          // Fall back to root level
          pathValid = false;
          break;
        }
      }

      if (pathValid) {
        // Successfully navigated to the path
        rawNodes = currentNode.children;
      } else {
        // Path invalid (e.g., inside virtual Season folder) - reset to root
        rawNodes = tree.children;
        _deps.navigationState.currentPath.clear();
        _deps.navigationState.currentFolderNode = tree;
      }
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
          if (_deps.navigationState.currentTorrent != null) {
            _deps.viewState.torrentViewModes[_deps
                    .navigationState
                    .currentTorrent!
                    .id] =
                FolderViewMode.sortedAZ;
          } else if (_deps.navigationState.currentWebDownload != null) {
            _deps.viewState.webDownloadViewModes[_deps
                    .navigationState
                    .currentWebDownload!
                    .id] =
                FolderViewMode.sortedAZ;
          }
          _deps.viewState.currentViewNodes = applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    _deps.setState(() {
      if (_deps.navigationState.currentTorrent != null) {
        _deps.viewState.torrentViewModes[_deps
                .navigationState
                .currentTorrent!
                .id] =
            mode;
      } else if (_deps.navigationState.currentWebDownload != null) {
        _deps.viewState.webDownloadViewModes[_deps
                .navigationState
                .currentWebDownload!
                .id] =
            mode;
      }

      switch (mode) {
        case FolderViewMode.raw:
          _deps.viewState.currentViewNodes = rawNodes;
          break;
        case FolderViewMode.sortedAZ:
          _deps.viewState.currentViewNodes = applySortedView(rawNodes);
          break;
        case FolderViewMode.seriesArrange:
          _deps.viewState.currentViewNodes = applySeriesArrangedView(rawNodes);
          break;
      }
    });
  }

  Widget buildViewModeDropdown() {
    final theme = Theme.of(_deps.context());
    final mode = getCurrentViewMode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _deps.focusState.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<FolderViewMode>(
          focusNode: _deps.focusState.viewModeDropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == FolderViewMode.raw
                  ? Icons.view_list
                  : mode == FolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(value: FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
              value: FolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setViewMode(value);
          },
        ),
      ),
    );
  }
}
