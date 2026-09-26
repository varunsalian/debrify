import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/local_source_document.dart';
import '../../../models/series_source.dart';
import 'android_local_source_dialogs.dart';
import 'local_folder_scan_progress.dart';

/// Presents document selection; native access and classification are injected.
class AndroidLocalSourcePicker {
  const AndroidLocalSourcePicker({
    required this.pick,
    required this.scan,
    required this.isVideoFile,
    required this.episodeCount,
  });

  final Future<LocalSourceDocument?> Function({required bool directory}) pick;
  final Future<List<LocalSourceDocument>> Function(String uri) scan;
  final bool Function(String name) isVideoFile;
  final int Function(List<LocalSourceDocument> documents) episodeCount;

  Future<List<LocalSourceDocument>> _scanFolder(
    BuildContext context,
    String uri, {
    bool Function()? canContinue,
  }) => readLocalFolderWithProgress(
    context,
    scan: () => scan(uri),
    canContinue: canContinue,
  );

  Future<SeriesSource?> pickMovie(
    BuildContext context, {
    required bool folder,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    try {
      final picked = await pick(directory: folder);
      if (picked == null || !context.mounted || !active()) return null;
      if (!folder) {
        if (picked.isDirectory || !isVideoFile(picked.name)) {
          _showSnack(context, 'Please select a video file.', isError: true);
          return null;
        }
        return picked.toSource();
      }
      final videos = await _scanFolder(
        context,
        picked.uri,
        canContinue: canContinue,
      );
      if (!context.mounted || !active()) return null;
      if (videos.isEmpty) {
        _showSnack(
          context,
          'No video files found in that folder.',
          isError: true,
        );
        return null;
      }
      videos.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      final selected = await showAndroidLocalMovieChoice(context, videos);
      if (!active()) return null;
      return selected?.toSource();
    } on PlatformException catch (error) {
      if (context.mounted && active()) {
        _showSnack(
          context,
          error.message ?? 'Local source could not be opened.',
          isError: true,
        );
      }
    } on LocalSourceUnavailable catch (error) {
      if (context.mounted && active()) {
        _showSnack(context, error.message, isError: true);
      }
    }
    return null;
  }

  Future<SeriesSource?> pickSeries(
    BuildContext context,
    String title, {
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    try {
      final folder = await pick(directory: true);
      if (folder == null || !context.mounted || !active()) return null;
      final videos = await _scanFolder(
        context,
        folder.uri,
        canContinue: canContinue,
      );
      if (!active()) return null;
      final count = episodeCount(videos);
      if (!context.mounted || !active()) return null;
      if (count == 0) {
        _showSnack(
          context,
          'No episodes found. Select this show’s folder with episode filenames such as S01E01.',
          isError: true,
        );
        return null;
      }
      final confirmed = await showAndroidLocalSeriesConfirmation(
        context,
        title: title,
        folderName: folder.name,
        episodeCount: count,
      );
      if (!active()) return null;
      return confirmed == true ? folder.toSource() : null;
    } on PlatformException catch (error) {
      if (context.mounted && active()) {
        _showSnack(
          context,
          error.message ?? 'Local folder could not be opened.',
          isError: true,
        );
      }
    } on LocalSourceUnavailable catch (error) {
      if (context.mounted && active()) {
        _showSnack(context, error.message, isError: true);
      }
    }
    return null;
  }

  void _showSnack(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
      ),
    );
  }
}
