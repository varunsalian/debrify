import 'dart:ui';

import 'package:debrify/features/torbox_downloads/application/torbox_folder_policy.dart';
import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_focus_state.dart';
import 'torbox_navigation_state.dart';
import 'torbox_view_state.dart';

typedef TorboxFolderNavigationDeps = ({
  void Function() exitSelectionMode,
  TorboxFocusState focusState,
  void Function() resetListScroll,
  TorboxViewState viewState,
  void Function(VoidCallback) setState,
  TorboxNavigationState navigationState,
  void Function() focusFirstItemOrFallback,
  FolderViewMode Function() getCurrentViewMode,
});

class TorboxFolderNavigation {
  TorboxFolderNavigation(this._deps);
  final TorboxFolderNavigationDeps _deps;

  /// Navigate into a torrent (show its folder structure)
  void navigateIntoTorrent(TorboxTorrent torrent) {
    _deps.exitSelectionMode();
    // Focus first item after navigation
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();

    print('🔍 Navigating into torrent: id=${torrent.id}, name=${torrent.name}');
    print('   Files count: ${torrent.files.length}');
    print('   Sample files:');
    for (
      int i = 0;
      i < (torrent.files.length < 5 ? torrent.files.length : 5);
      i++
    ) {
      print(
        '     [$i] id=${torrent.files[i].id}, name=${torrent.files[i].name}',
      );
    }

    // Build folder tree for this torrent
    print('   Building folder tree...');
    final tree = TorboxFolderTreeBuilder.buildTree(torrent.files);
    print('   Tree built: root has ${tree.children.length} children');

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
        transformedNodes = tree.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedNodes = applySortedView(tree.children);
        break;
      case FolderViewMode.seriesArrange:
        transformedNodes = applySeriesArrangedView(tree.children);
        break;
    }

    _deps.setState(() {
      // Push current state to navigation stack
      _deps.navigationState.navigationStack.add((
        torrent: _deps.navigationState.currentTorrent,
        webDownload: _deps.navigationState.currentWebDownload,
        path: List.from(_deps.navigationState.currentPath),
        node: _deps.navigationState.currentFolderNode,
      ));

      // Navigate to torrent root
      _deps.navigationState.currentTorrent = torrent;
      _deps.navigationState.currentWebDownload = null;
      _deps.navigationState.currentPath = [];
      _deps.navigationState.currentFolderNode = tree;
      _deps.viewState.currentViewNodes = transformedNodes;
    });

    // Focus first item after navigation
    _deps.focusFirstItemOrFallback();
  }

  /// Navigate into a web download (show its folder structure)
  void navigateIntoWebDownload(TorboxWebDownload webDownload) {
    _deps.exitSelectionMode();
    // Focus first item after navigation
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();

    // Build folder tree for this web download
    final tree = TorboxFolderTreeBuilder.buildTree(webDownload.files);

    // Initialize view mode for this web download if not already set
    _deps.viewState.webDownloadViewModes.putIfAbsent(
      webDownload.id,
      () => FolderViewMode.raw,
    );

    // Apply view mode transformation to root nodes
    final mode = _deps.viewState.webDownloadViewModes[webDownload.id]!;
    List<RDFileNode> transformedNodes;
    switch (mode) {
      case FolderViewMode.raw:
        transformedNodes = tree.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedNodes = applySortedView(tree.children);
        break;
      case FolderViewMode.seriesArrange:
        transformedNodes = applySeriesArrangedView(tree.children);
        break;
    }

    _deps.setState(() {
      // Push current state to navigation stack
      _deps.navigationState.navigationStack.add((
        torrent: _deps.navigationState.currentTorrent,
        webDownload: _deps.navigationState.currentWebDownload,
        path: List.from(_deps.navigationState.currentPath),
        node: _deps.navigationState.currentFolderNode,
      ));

      // Navigate to web download root
      _deps.navigationState.currentTorrent = null;
      _deps.navigationState.currentWebDownload = webDownload;
      _deps.navigationState.currentPath = [];
      _deps.navigationState.currentFolderNode = tree;
      _deps.viewState.currentViewNodes = transformedNodes;
    });

    // Focus first item after navigation
    _deps.focusFirstItemOrFallback();
  }

  /// Navigate into a subfolder within current torrent/web download
  void navigateIntoFolder(RDFileNode folderNode) {
    if (!folderNode.isFolder) return;

    // Focus first item after navigation
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _deps.getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    switch (mode) {
      case FolderViewMode.raw:
        transformedChildren = folderNode.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedChildren = applySortedView(folderNode.children);
        break;
      case FolderViewMode.seriesArrange:
        // Inside a folder with Series Arrange mode: show files sorted by name
        transformedChildren = applySortedView(folderNode.children);
        break;
    }

    _deps.setState(() {
      // Push current state to navigation stack
      _deps.navigationState.navigationStack.add((
        torrent: _deps.navigationState.currentTorrent,
        webDownload: _deps.navigationState.currentWebDownload,
        path: List.from(_deps.navigationState.currentPath),
        node: _deps.navigationState.currentFolderNode,
      ));

      // Navigate into folder
      _deps.navigationState.currentPath.add(folderNode.name);
      _deps.navigationState.currentFolderNode = folderNode;
      _deps.viewState.currentViewNodes = transformedChildren;
    });

    // Focus first item after navigation
    _deps.focusFirstItemOrFallback();
  }

  /// Navigate up one level (back button)
  void navigateUp() {
    if (_deps.navigationState.navigationStack.isEmpty) return;

    // Refocus the first row once the previous listing shows — the focused
    // row is disposed by the swap and nothing else reclaims DPAD focus.
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();
    final previous = _deps.navigationState.navigationStack.removeLast();

    // Reapply view mode transformation after navigation
    List<RDFileNode>? transformedNodes;
    if (previous.node != null &&
        (previous.torrent != null || previous.webDownload != null)) {
      FolderViewMode mode;
      if (previous.torrent != null) {
        mode =
            _deps.viewState.torrentViewModes[previous.torrent!.id] ??
            FolderViewMode.raw;
      } else {
        mode =
            _deps.viewState.webDownloadViewModes[previous.webDownload!.id] ??
            FolderViewMode.raw;
      }
      final rawNodes = previous.node!.children;

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      if (mode == FolderViewMode.seriesArrange && previous.path.isNotEmpty) {
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
    }

    _deps.setState(() {
      _deps.navigationState.currentTorrent = previous.torrent;
      _deps.navigationState.currentWebDownload = previous.webDownload;
      _deps.navigationState.currentPath = previous.path;
      _deps.navigationState.currentFolderNode = previous.node;
      _deps.viewState.currentViewNodes = transformedNodes;
    });
  }

  /// Check if we're at root level (torrent/web download list)
  bool get isAtRoot =>
      _deps.navigationState.currentTorrent == null &&
      _deps.navigationState.currentWebDownload == null;

  /// Get current folder/torrent/web download name for display
  String get currentFolderName {
    if (isAtRoot) return 'Torbox Files';
    if (_deps.navigationState.currentPath.isEmpty) {
      return _deps.navigationState.currentTorrent?.name ??
          _deps.navigationState.currentWebDownload?.name ??
          'Download';
    }
    return _deps.navigationState.currentPath.last;
  }
}
