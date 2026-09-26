import 'dart:io';

import 'package:flutter/material.dart';

import '../features/sources/data/local_source_file_picker.dart';
import '../features/sources/data/local_source_file_rules.dart';
import '../features/sources/data/local_source_files.dart';
import '../features/sources/models/local_source_file.dart';
import '../features/sources/presentation/android_local_source_picker.dart';
import '../features/sources/presentation/local_movie_pick_mode_sheet.dart';
import '../features/sources/presentation/local_source_choice_dialogs.dart';
import '../features/sources/presentation/local_series_folder_help.dart';
import '../models/series_source.dart';
import '../utils/file_utils.dart';
import 'android_local_source_service.dart';

export '../features/sources/models/local_source_file.dart'
    show LocalSeriesEpisodeFile;

class LocalBoundSourceService {
  static final _androidPicker = AndroidLocalSourcePicker(
    pick: AndroidLocalSourceService.pick,
    scan: AndroidLocalSourceService.videos,
    isVideoFile: FileUtils.isVideoFile,
    episodeCount: (documents) =>
        AndroidLocalSourceService.episodes(documents).length,
  );

  static const String mobileDisabledReason =
      'Local source binding is not supported on iOS yet.';

  static Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (isLocalBindingDisabled) {
      _showSnack(context, mobileDisabledReason, isError: true);
      return null;
    }

    final mode = await showLocalMoviePickMode(
      context,
      androidFolderSelection: Platform.isAndroid,
    );

    if (mode == null || !context.mounted || !active()) return null;

    return switch (mode) {
      LocalMoviePickMode.file => _pickFile(context, canContinue: canContinue),
      LocalMoviePickMode.folder => _pickFromFolder(
        context,
        title: title,
        year: year,
        canContinue: canContinue,
      ),
    };
  }

  static Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (isLocalBindingDisabled) {
      _showSnack(context, mobileDisabledReason, isError: true);
      return null;
    }

    if (Platform.isAndroid) {
      return _androidPicker.pickSeries(
        context,
        title,
        canContinue: canContinue,
      );
    }

    final path = await pickLocalDirectory();
    if (path == null || path.trim().isEmpty) return null;
    if (!context.mounted || !active()) return null;

    final seriesFolder = await _resolveSeriesFolder(
      context,
      path,
      title: title,
      canContinue: canContinue,
    );
    if (seriesFolder == null || !active()) return null;

    final resolvedPath = seriesFolder.path;
    final episodes = await scanLocalSeriesFolder(
      resolvedPath,
      canContinue: canContinue,
    );
    if (!active()) return null;
    if (episodes.isEmpty) {
      if (context.mounted) {
        _showSnack(context, 'No episodes found in that folder', isError: true);
      }
      return null;
    }

    return localSourceFromSeriesFolder(
      seriesFolder,
      title: title,
      episodeCount: episodes.length,
      canContinue: canContinue,
    );
  }

  static Future<List<LocalSeriesEpisodeFile>> scanSeriesFolder(
    String path,
  ) async => (await scanLocalSeriesFolder(path)).toList();

  static bool get isLocalBindingDisabled => Platform.isIOS;

  static String? get localDisabledReason =>
      isLocalBindingDisabled ? mobileDisabledReason : null;

  static Future<SeriesSource?> _pickFile(
    BuildContext context, {
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (Platform.isAndroid) {
      return _androidPicker.pickMovie(
        context,
        folder: false,
        canContinue: canContinue,
      );
    }
    return pickLocalVideoSource(canContinue: canContinue);
  }

  static Future<SeriesSource?> _pickFromFolder(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (Platform.isAndroid) {
      return _androidPicker.pickMovie(
        context,
        folder: true,
        canContinue: canContinue,
      );
    }
    final path = await pickLocalDirectory();
    if (!active()) return null;
    if (path == null || path.trim().isEmpty) return null;

    final candidates = await scanLocalVideoFolder(
      path,
      canContinue: canContinue,
    );
    if (!active()) return null;
    if (candidates.isEmpty) {
      if (context.mounted) {
        _showSnack(
          context,
          'No video files found in that folder',
          isError: true,
        );
      }
      return null;
    }

    final matched = matchLocalMovieFiles(candidates, title: title, year: year);
    if (matched != null) {
      return localSourceFromFile(matched.file, canContinue: canContinue);
    }

    if (!context.mounted) return null;
    final selected = await showLocalFileChoice(context, candidates);
    if (!active()) return null;
    return selected == null
        ? null
        : localSourceFromFile(selected.file, canContinue: canContinue);
  }

  static Future<Directory?> _resolveSeriesFolder(
    BuildContext context,
    String pickedPath, {
    required String title,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    final pickedFolder = Directory(pickedPath);
    if (!await pickedFolder.exists()) return null;
    if (!active()) return null;

    if (localSeriesFolderMatchScore(localPathName(pickedPath), title) > 0) {
      return pickedFolder;
    }

    final matches = await matchingLocalSeriesFolders(
      pickedPath,
      title: title,
      canContinue: canContinue,
    );
    if (!active()) return null;
    if (matches.isEmpty) {
      if (context.mounted) {
        await showLocalSeriesFolderHelp(
          context,
          title: title,
          pickedFolderName: localPathName(pickedPath),
        );
      }
      return null;
    }

    if (matches.length == 1) {
      return matches.single.directory;
    }

    if (!context.mounted) return null;
    final selected = await showLocalSeriesFolderChoice(
      context,
      title: title,
      candidates: matches,
    );
    if (!active()) return null;
    return selected?.directory;
  }

  static void _showSnack(
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
