import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentFileListDeps = ({
  PlaylistContentCatalogState catalogState,
  Future<void> Function() loadContent,
  PlaylistContentNavigationState navigationState,
  Widget Function() buildOTTView,
  BuildContext Function() context,
  Map<String, dynamic>? Function(RDFileNode file) getProgressForFile,
  void Function(RDFileNode folder) navigateIntoFolder,
  Future<void> Function(RDFileNode file) playFile,
});

class PlaylistContentFileList {
  PlaylistContentFileList(this._deps);
  final PlaylistContentFileListDeps _deps;

  Widget buildContent() {
    if (_deps.catalogState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_deps.catalogState.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _deps.catalogState.errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _deps.loadContent,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_deps.navigationState.currentViewNodes == null ||
        _deps.navigationState.currentViewNodes!.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    // For Series Arrange mode, show OTT-style view
    if (_deps.navigationState.currentViewMode == FolderViewMode.seriesArrange) {
      return _deps.buildOTTView();
    }

    // For Raw and Sort modes, show file browser
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deps.navigationState.currentViewNodes!.length,
      itemBuilder: (context, index) {
        final node = _deps.navigationState.currentViewNodes![index];
        return buildFileCard(node);
      },
    );
  }

  Widget buildFileCard(RDFileNode node) {
    final app = AppThemeScope.of(_deps.context());
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    // Get progress for this file (if it's a video)
    double progress = 0.0;
    bool isFinished = false;
    if (isVideo) {
      // Try to get progress from cache
      // For series, use season/episode key; for others use filename
      final progressData = _deps.getProgressForFile(node);
      if (progressData != null) {
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Consider finished if 90%+ watched or less than 2 minutes remaining
          isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
        }
      }
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            if (isFolder) {
              _deps.navigateIntoFolder(node);
            } else if (isVideo) {
              _deps.playFile(node);
            }
            return null;
          },
        ),
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: app.playlist.card,
        child: InkWell(
          onTap: () {
            if (isFolder) {
              _deps.navigateIntoFolder(node);
            } else if (isVideo) {
              _deps.playFile(node);
            }
          },
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Icon
                    Icon(
                      isFolder
                          ? Icons.folder
                          : isVideo
                          ? Icons.play_circle_outline
                          : Icons.insert_drive_file,
                      color: isFolder ? Colors.amber : Colors.blue,
                      size: 32,
                    ),
                    const SizedBox(width: 12),

                    // File info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFolder
                                ? '${node.fileCount} files • ${Formatters.formatFileSize(node.totalBytes)}'
                                : Formatters.formatFileSize(node.bytes ?? 0),
                            style: TextStyle(
                              color: app.playlist.ink2,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Arrow for folders or progress indicator for videos
                    if (isFolder)
                      Icon(
                        Icons.chevron_right,
                        // Colors.white54 at its exact alpha, off the page ink.
                        color: app.core.tx.withValues(alpha: 0x8A / 255),
                      )
                    else if (isVideo && progress > 0.0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isFinished
                              ? app.playlist.statusWatched
                              : app.playlist.progressPlayed,
                          borderRadius: app.shape.br(4),
                        ),
                        child: Text(
                          isFinished ? 'DONE' : '${(progress * 100).round()}%',
                          style: TextStyle(
                            // Legacy keeps its shipped WHITE explicitly. It
                            // cannot be left to inkOn: white scores 3.77 on
                            // legacy's #059669 and 3.12 on Colors.blue, both
                            // under the 4.0 threshold, so inkOn returns
                            // core.ground and the badge would flip to
                            // near-black — a visible change to today's app.
                            //
                            // Every other theme scores, because white on a
                            // DERIVED success green is ~1.9:1 and unreadable.
                            color: app.isLegacy
                                ? app.core.tx
                                : app.inkOn(
                                    isFinished
                                        ? app.playlist.statusWatched
                                        : app.playlist.progressPlayed,
                                  ),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Progress bar overlay for videos
              if (isVideo && progress > 0.0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isFinished
                              ? app.playlist.statusWatched
                              : app.playlist.progressPlayed,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
