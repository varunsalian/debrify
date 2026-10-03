import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_navigation_state.dart';

typedef PikpakCatalogLoadingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PikpakCatalogState catalogState,
  PikpakNavigationState navigationState,
  String? Function() initialFolderId,
  String? Function() initialFolderName,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>> files)
  filterFiles,
  FolderViewMode Function() getCurrentViewMode,
  List<Map<String, dynamic>> Function(
    FolderViewMode mode,
    List<Map<String, dynamic>> items,
  )
  applyViewMode,
  void Function() focusFirstItemOrFallback,
  PikpakFocusState focusState,
});

class PikpakCatalogLoading {
  PikpakCatalogLoading(this._deps);
  final PikpakCatalogLoadingDeps _deps;

  String? _email;

  Future<void> loadSettings() async {
    final enabled = await PikpakStorage.getPikPakEnabled();
    final showVideosOnly = await PikpakStorage.getPikPakShowVideosOnly();
    final ignoreSmallVideos = await PikpakStorage.getPikPakIgnoreSmallVideos();
    final email = await PikPakApiService.instance.getEmail();
    final restrictedId = await PikpakStorage.getPikPakRestrictedFolderId();
    final restrictedName = await PikpakStorage.getPikPakRestrictedFolderName();

    if (!_deps.mounted()) return;

    // If enabled and has a restricted folder, verify it still exists
    if (enabled && restrictedId != null && restrictedId.isNotEmpty) {
      final folderExists = await PikPakApiService.instance
          .verifyRestrictedFolderExists();
      if (!folderExists) {
        // Restricted folder was deleted externally
        await handleRestrictedFolderDeleted();
        return;
      }
    }

    _deps.setState(() {
      _deps.catalogState.pikpakEnabled = enabled;
      _deps.catalogState.showVideosOnly = showVideosOnly;
      _deps.catalogState.ignoreSmallVideos = ignoreSmallVideos;
      _email = email;
      _deps.navigationState.restrictedFolderId = restrictedId;
      _deps.navigationState.restrictedFolderName = restrictedName;

      // If initial folder is provided, navigate to it
      if (_deps.initialFolderId() != null &&
          _deps.initialFolderName() != null) {
        _deps.navigationState.currentFolderId = _deps.initialFolderId();
        _deps.navigationState.currentFolderName = _deps.initialFolderName()!;
        _deps.navigationState.isAtRestrictedRoot = false;
      }
      // Otherwise, initialize at restricted folder instead of root
      else if (restrictedId != null) {
        _deps.navigationState.currentFolderId = restrictedId;
        _deps.navigationState.currentFolderName =
            restrictedName ?? 'Restricted Folder';
        _deps.navigationState.isAtRestrictedRoot = true;
      }
    });

    if (enabled) {
      loadFiles();
    }
  }

  /// Handle the case when the restricted folder has been deleted externally
  Future<void> handleRestrictedFolderDeleted() async {
    print(
      'PikPak: Restricted folder was deleted externally, logging out user...',
    );

    // A shared owner must resolve borrower impact before this local account
    // can be removed. Do not claim logout or clear the screen on failure.
    try {
      await PikPakApiService.instance.logout();
    } catch (_) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar(
        'This connection is shared. Manage profile access before disconnecting.',
        isError: true,
      );
      return;
    }

    if (!_deps.mounted()) return;

    // Update state
    _deps.setState(() {
      _deps.catalogState.pikpakEnabled = false;
      _deps.navigationState.restrictedFolderId = null;
      _deps.navigationState.restrictedFolderName = null;
      _deps.catalogState.isLoading = false;
      _deps.catalogState.initialLoad = false;
      _deps.catalogState.errorMessage = '';
    });

    // Show snackbar
    _deps.showSnackBar(
      'Restricted folder was deleted. You have been logged out.',
      isError: true,
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> loadFiles() async {
    if (_deps.catalogState.isLoading) return;

    _deps.setState(() {
      _deps.catalogState.isLoading = true;
      _deps.catalogState.errorMessage = '';
      // Reset pagination state for fresh load
      _deps.catalogState.nextPageToken = null;
      _deps.catalogState.hasMore = true;
    });

    try {
      final result = await PikPakApiService.instance.listFiles(
        parentId: _deps.navigationState.currentFolderId,
      );

      if (!_deps.mounted()) return;

      // Filter files based on settings
      final filteredFiles = _deps.filterFiles(result.files);

      // Apply current view mode transformation
      final mode = _deps.getCurrentViewMode();
      final transformedFiles = mode == FolderViewMode.seriesArrange
          ? filteredFiles // Series Arrange is handled separately in _setViewMode
          : _deps.applyViewMode(mode, filteredFiles);

      _deps.setState(() {
        _deps.catalogState.files.clear();
        _deps.catalogState.files.addAll(transformedFiles);
        _deps.catalogState.nextPageToken = result.nextPageToken;
        _deps.catalogState.hasMore =
            result.nextPageToken != null && result.nextPageToken!.isNotEmpty;
        _deps.catalogState.isLoading = false;
        _deps.catalogState.initialLoad = false;
      });

      // Focus first item if navigated from sidebar
      _deps.focusFirstItemOrFallback();
    } catch (e) {
      print('Error loading PikPak files: $e');
      if (!_deps.mounted()) return;

      // Check if the restricted folder has been deleted externally
      if (_deps.navigationState.restrictedFolderId != null &&
          _deps.navigationState.currentFolderId ==
              _deps.navigationState.restrictedFolderId) {
        // The error is likely because the restricted folder was deleted
        // Auto-logout the user
        await handleRestrictedFolderDeleted();
        return;
      }

      _deps.setState(() {
        _deps.catalogState.errorMessage = e.toString();
        _deps.catalogState.isLoading = false;
        _deps.catalogState.initialLoad = false;
      });
    }
  }

  Future<void> loadMoreFiles() async {
    // Don't load more if already loading, no more pages, or no page token
    if (_deps.catalogState.isLoadingMore ||
        !_deps.catalogState.hasMore ||
        _deps.catalogState.nextPageToken == null) {
      return;
    }

    _deps.setState(() {
      _deps.catalogState.isLoadingMore = true;
    });

    try {
      final result = await PikPakApiService.instance.listFiles(
        parentId: _deps.navigationState.currentFolderId,
        pageToken: _deps.catalogState.nextPageToken,
      );

      if (!_deps.mounted()) return;

      // Filter files based on settings
      final filteredFiles = _deps.filterFiles(result.files);

      _deps.setState(() {
        _deps.catalogState.files.addAll(filteredFiles);
        _deps.catalogState.nextPageToken = result.nextPageToken;
        _deps.catalogState.hasMore =
            result.nextPageToken != null && result.nextPageToken!.isNotEmpty;

        // Re-apply current view mode to maintain consistency
        final mode = _deps.getCurrentViewMode();
        if (mode != FolderViewMode.raw &&
            mode != FolderViewMode.seriesArrange) {
          final transformed = _deps.applyViewMode(
            mode,
            _deps.catalogState.files,
          );
          _deps.catalogState.files.clear();
          _deps.catalogState.files.addAll(transformed);
        }

        _deps.catalogState.isLoadingMore = false;
      });
    } catch (e) {
      print('Error loading more PikPak files: $e');
      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.catalogState.isLoadingMore = false;
      });

      _deps.showSnackBar('Failed to load more files: $e');
    }
  }

  void onScroll() {
    // Load more when user scrolls near the bottom (200px threshold)
    if (_deps.focusState.scrollController.position.pixels >=
        _deps.focusState.scrollController.position.maxScrollExtent - 200) {
      loadMoreFiles();
    }
  }

  /// Reset scroll while the outgoing list is still attached, so the next
  /// listing never inherits the old offset. The load-more listener is
  /// detached around the jump — otherwise jumpTo(0) can fire _onScroll while
  /// the OLD folder's pagination state is still live and append its next
  /// page into the new folder's list.
  void resetListScroll() {
    if (!_deps.focusState.scrollController.hasClients) return;
    _deps.focusState.scrollController.removeListener(onScroll);
    _deps.focusState.scrollController.jumpTo(0);
    _deps.focusState.scrollController.addListener(onScroll);
  }
}
