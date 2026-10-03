import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_navigation_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakFolderNavigationDeps = ({
  PikpakCatalogState catalogState,
  void Function() exitSelectionMode,
  PikpakFocusState focusState,
  void Function() resetListScroll,
  void Function(VoidCallback) setState,
  PikpakNavigationState navigationState,
  Future<void> Function() loadFiles,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  PikpakViewState viewState,
  FolderViewMode Function() getCurrentViewMode,
  Future<void> Function(FolderViewMode mode) setViewMode,
  void Function() focusFirstItemOrFallback,
});

class PikpakFolderNavigation {
  PikpakFolderNavigation(this._deps);
  final PikpakFolderNavigationDeps _deps;

  /// Filter files based on user settings (videos only, ignore small videos)
  List<Map<String, dynamic>> filterFiles(List<Map<String, dynamic>> files) {
    List<Map<String, dynamic>> filteredFiles = files;

    // Filter by file type (videos only)
    if (_deps.catalogState.showVideosOnly) {
      filteredFiles = filteredFiles.where((file) {
        final kind = file['kind'] ?? '';
        final mimeType = file['mime_type'] ?? '';
        // Always show folders, only filter non-folder items
        return kind == 'drive#folder' || mimeType.startsWith('video/');
      }).toList();
    }

    // Filter by size (ignore videos under 100MB)
    if (_deps.catalogState.ignoreSmallVideos) {
      filteredFiles = filteredFiles.where((file) {
        final kind = file['kind'] ?? '';
        final mimeType = file['mime_type'] ?? '';
        final size = file['size'];

        // Always show folders
        if (kind == 'drive#folder') return true;

        // For videos, check size
        if (mimeType.startsWith('video/')) {
          if (size == null) return true; // Show if size is unknown
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100; // Only show videos 100MB or larger
        }

        // Show non-video files if videos-only filter is off
        return true;
      }).toList();
    }

    return filteredFiles;
  }

  void navigateIntoFolder(String folderId, String folderName) {
    _deps.exitSelectionMode();
    // Focus first item after folder contents load
    _deps.focusState.shouldFocusOnLoad = true;

    _deps.resetListScroll();
    _deps.setState(() {
      // Push current folder to stack before navigating
      _deps.navigationState.navigationStack.add((
        id: _deps.navigationState.currentFolderId,
        name: _deps.navigationState.currentFolderName,
      ));
      _deps.navigationState.currentFolderId = folderId;
      _deps.navigationState.currentFolderName = folderName;
      // Clear stale rows so the loading skeleton shows instead of the
      // outgoing folder's contents sitting frozen while the fetch runs.
      _deps.catalogState.files.clear();
      // We're navigating into a subfolder, so we're no longer at restricted root
      _deps.navigationState.isAtRestrictedRoot = false;
    });
    _deps.loadFiles();
  }

  void navigateUp() {
    _deps.exitSelectionMode();
    // Don't navigate above restricted folder
    if (_deps.navigationState.restrictedFolderId != null &&
        _deps.navigationState.currentFolderId ==
            _deps.navigationState.restrictedFolderId) {
      _deps.showSnackBar('Already at restricted folder root', isError: false);
      return;
    }

    // Refocus the first row once the parent listing loads — clearing _files
    // disposes the focused row and nothing else reclaims DPAD focus.
    _deps.focusState.shouldFocusOnLoad = true;
    _deps.resetListScroll();
    _deps.setState(() {
      _deps.catalogState.files.clear();
      // Pop from stack to go back one level
      if (_deps.navigationState.navigationStack.isNotEmpty) {
        final previous = _deps.navigationState.navigationStack.removeLast();
        _deps.navigationState.currentFolderId = previous.id;
        _deps.navigationState.currentFolderName = previous.name;

        // Check if we're back at the restricted root
        _deps.navigationState.isAtRestrictedRoot =
            (_deps.navigationState.restrictedFolderId != null &&
            _deps.navigationState.currentFolderId ==
                _deps.navigationState.restrictedFolderId);
      } else {
        // Already at root (or restricted root)
        if (_deps.navigationState.restrictedFolderId != null) {
          _deps.navigationState.currentFolderId =
              _deps.navigationState.restrictedFolderId;
          _deps.navigationState.currentFolderName =
              _deps.navigationState.restrictedFolderName ?? 'Restricted Folder';
          _deps.navigationState.isAtRestrictedRoot = true;
        } else {
          _deps.navigationState.currentFolderId = null;
          _deps.navigationState.currentFolderName = 'My Files';
        }
      }
    });
    _deps.loadFiles();
  }

  /// Navigate up with virtual folder support
  /// If in virtual folder, exit virtual folder first before navigating real folders
  void navigateUpWithVirtual() {
    if (_deps.viewState.isInVirtualFolder) {
      // Exit virtual folder, go back to transformed view
      _deps.focusState.shouldFocusOnLoad = true;
      _deps.resetListScroll();
      _deps.setState(() {
        _deps.viewState.isInVirtualFolder = false;
        _deps.viewState.virtualFolderName = null;
        _deps.viewState.virtualFolderFiles.clear();
      });

      // Re-apply current view mode to show the season folders again
      final mode = _deps.getCurrentViewMode();
      _deps.setViewMode(mode);
      _deps.focusFirstItemOrFallback();
    } else {
      // Normal navigation up real folders
      navigateUp();
    }
  }

  /// Navigate into a virtual Season folder
  void navigateIntoVirtualFolder(Map<String, dynamic> virtualFolder) {
    _deps.exitSelectionMode();
    final seasonName = virtualFolder['name'] as String? ?? 'Virtual Folder';
    final virtualFiles = virtualFolder['virtual_files'] as List<dynamic>? ?? [];

    // Validate virtual files exist
    if (virtualFiles.isEmpty) {
      _deps.showSnackBar('Virtual folder is empty', isError: true);
      return;
    }

    // Focus first item after navigation
    _deps.focusState.shouldFocusOnLoad = true;

    _deps.resetListScroll();
    try {
      final typedFiles = virtualFiles.cast<Map<String, dynamic>>();
      _deps.setState(() {
        _deps.viewState.isInVirtualFolder = true;
        _deps.viewState.virtualFolderName = seasonName;
        _deps.viewState.virtualFolderFiles = typedFiles;
        _deps.catalogState.files.clear();
        _deps.catalogState.files.addAll(_deps.viewState.virtualFolderFiles);
      });

      // Focus first item after navigation
      _deps.focusFirstItemOrFallback();
    } catch (e) {
      print('Error navigating into virtual folder: $e');
      _deps.showSnackBar('Failed to open virtual folder: $e', isError: true);
    }
  }
}
