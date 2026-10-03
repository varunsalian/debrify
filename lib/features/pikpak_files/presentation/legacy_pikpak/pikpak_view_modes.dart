import 'package:debrify/features/pikpak_files/application/pikpak_sort_policy.dart';
import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_navigation_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakViewModesDeps = ({
  PikpakViewState viewState,
  PikpakNavigationState navigationState,
  void Function(VoidCallback) setState,
  PikpakCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
});

class PikpakViewModes {
  PikpakViewModes(this._deps);
  final PikpakViewModesDeps _deps;

  /// Get current view mode for the active folder
  FolderViewMode getCurrentViewMode() {
    // Virtual folders don't have their own view modes
    if (_deps.viewState.isInVirtualFolder) return FolderViewMode.seriesArrange;

    // Root level (no folder selected) defaults to Raw
    if (_deps.navigationState.currentFolderId == null) {
      return FolderViewMode.raw;
    }

    return _deps.viewState.folderViewModes[_deps
            .navigationState
            .currentFolderId!] ??
        FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  Future<void> setViewMode(FolderViewMode mode) async {
    if (_deps.navigationState.currentFolderId == null) return;

    // If user selected Series Arrange, we need to fetch all files recursively
    if (mode == FolderViewMode.seriesArrange) {
      // Show loading indicator
      _deps.setState(() {
        _deps.catalogState.isLoading = true;
      });

      try {
        // Fetch all files recursively from this folder
        List<Map<String, dynamic>> allFiles;
        if (_deps.viewState.recursiveFileCache.containsKey(
          _deps.navigationState.currentFolderId!,
        )) {
          allFiles = _deps
              .viewState
              .recursiveFileCache[_deps.navigationState.currentFolderId!]!;
        } else {
          allFiles = await PikPakApiService.instance.listFilesRecursive(
            folderId: _deps.navigationState.currentFolderId!,
          );
          _deps.viewState.recursiveFileCache[_deps
                  .navigationState
                  .currentFolderId!] =
              allFiles;
        }

        // Filter for video files only
        final videoFiles = allFiles.where((file) {
          final kind = file['kind'] ?? '';
          final mimeType = file['mime_type'] ?? '';
          return kind != 'drive#folder' && mimeType.startsWith('video/');
        }).toList();

        // Detect if it's actually a series
        if (videoFiles.length < 3) {
          showFallbackToSorted(
            'Not enough video files for series detection',
            allFiles,
          );
          return;
        }

        final filenames = videoFiles
            .map((f) => f['name'] as String? ?? '')
            .toList();
        final isSeries = SeriesParser.isSeriesPlaylist(filenames);

        if (!isSeries) {
          showFallbackToSorted('No series detected in this folder', allFiles);
          return;
        }

        // It's a series! Apply Series Arrange view
        _deps.setState(() {
          _deps.viewState.folderViewModes[_deps
                  .navigationState
                  .currentFolderId!] =
              mode;
          final transformed = applySeriesArrangeView(allFiles);
          _deps.catalogState.files.clear();
          _deps.catalogState.files.addAll(transformed);
          _deps.catalogState.isLoading = false;
        });
      } catch (e) {
        print('Error applying Series Arrange view: $e');
        showFallbackToSorted('Failed to load series view', null);
      }
    } else {
      // For Raw and Sort modes, work with current page files
      _deps.setState(() {
        _deps.viewState.folderViewModes[_deps
                .navigationState
                .currentFolderId!] =
            mode;
        final transformed = applyViewMode(mode, _deps.catalogState.files);
        _deps.catalogState.files.clear();
        _deps.catalogState.files.addAll(transformed);
        // Reset pagination when transforming (can't mix transformed/raw data)
        _deps.catalogState.nextPageToken = null;
        _deps.catalogState.hasMore = false;
      });
    }
  }

  /// Show snackbar and fallback to sorted view
  /// If allFiles is provided (from recursive fetch), use those instead of _files
  void showFallbackToSorted(
    String reason,
    List<Map<String, dynamic>>? allFiles,
  ) {
    if (!_deps.mounted()) return;

    final app = AppThemeScope.of(_deps.context());
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: const Text(
          'No series detected in this folder. Switching to Sort (A-Z) view.',
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );

    _deps.setState(() {
      _deps.viewState.folderViewModes[_deps.navigationState.currentFolderId!] =
          FolderViewMode.sortedAZ;
      // Use allFiles if provided (preserves full recursive fetch), otherwise use _files
      final filesToTransform = allFiles ?? _deps.catalogState.files;
      final transformed = applySortedView(filesToTransform);
      _deps.catalogState.files.clear();
      _deps.catalogState.files.addAll(transformed);
      _deps.catalogState.isLoading = false;
    });
  }

  /// Apply view mode transformation to a list of files
  List<Map<String, dynamic>> applyViewMode(
    FolderViewMode mode,
    List<Map<String, dynamic>> items,
  ) {
    switch (mode) {
      case FolderViewMode.raw:
        return items;
      case FolderViewMode.sortedAZ:
        return applySortedView(items);
      case FolderViewMode.seriesArrange:
        return applySeriesArrangeView(items);
    }
  }

  /// Apply series arranged view (create virtual Season folders)
  List<Map<String, dynamic>> applySeriesArrangeView(
    List<Map<String, dynamic>> items,
  ) {
    // Separate folders and files
    final folders = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind == 'drive#folder';
    }).toList();

    final files = items.where((item) {
      final kind = item['kind'] ?? '';
      return kind != 'drive#folder';
    }).toList();

    // Filter for video files only
    final videoFiles = files.where((file) {
      final mimeType = file['mime_type'] ?? '';
      return mimeType.startsWith('video/');
    }).toList();

    final nonVideoFiles = files.where((file) {
      final mimeType = file['mime_type'] ?? '';
      return !mimeType.startsWith('video/');
    }).toList();

    if (videoFiles.isEmpty) return items;

    final filenames = videoFiles
        .map((f) => f['name'] as String? ?? '')
        .toList();

    try {
      final parsedInfos = SeriesParser.parsePlaylist(filenames);

      // Group by season
      final Map<int, List<Map<String, dynamic>>> seasonMap = {};
      for (int i = 0; i < videoFiles.length; i++) {
        final info = parsedInfos[i];
        if (info.isSeries && info.season != null) {
          seasonMap.putIfAbsent(info.season!, () => []);
          seasonMap[info.season!]!.add(videoFiles[i]);
        } else {
          // If not parsed as series, default to Season 1
          seasonMap.putIfAbsent(1, () => []);
          seasonMap[1]!.add(videoFiles[i]);
        }
      }

      // Create virtual season folders
      final seasonFolders = seasonMap.entries.map((entry) {
        final seasonNum = entry.key;
        final seasonFiles = entry.value;

        // Sort episodes within season by episode number
        seasonFiles.sort((a, b) {
          final aInfo = SeriesParser.parseFilename(a['name'] as String? ?? '');
          final bInfo = SeriesParser.parseFilename(b['name'] as String? ?? '');
          final aEp = aInfo.episode ?? 0;
          final bEp = bInfo.episode ?? 0;
          return aEp.compareTo(bEp);
        });

        // Create virtual folder (marked with special kind)
        return {
          'id': 'virtual_season_$seasonNum',
          'kind': 'virtual#season',
          'name': seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
          'season_number': seasonNum,
          'virtual_files': seasonFiles, // Store the files inside
          'size': seasonFiles.fold<int>(
            0,
            (sum, f) => sum + (int.tryParse(f['size']?.toString() ?? '0') ?? 0),
          ),
          'created_time': DateTime.now().toIso8601String(),
        };
      }).toList();

      // Sort season folders by season number
      seasonFolders.sort((a, b) {
        final aNum = a['season_number'] as int? ?? 0;
        final bNum = b['season_number'] as int? ?? 0;
        return aNum.compareTo(bNum);
      });

      return [...folders, ...seasonFolders, ...nonVideoFiles];
    } catch (e) {
      print('Series arrangement failed: $e');
      return applySortedView(items); // Fallback to sorted view
    }
  }
}
