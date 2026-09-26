import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  static const List<String> _videoExtensions = [
    'mp4',
    'avi',
    'mkv',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    '3gp',
    'ts',
    'mts',
    'm2ts',
  ];

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

    final path = await FilePicker.platform.getDirectoryPath();
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

    final stat = await seriesFolder.stat();
    if (!active()) return null;
    final folderName = localPathName(resolvedPath).isNotEmpty
        ? localPathName(resolvedPath)
        : title;
    return SeriesSource(
      torrentHash: SeriesSource.localSourceHash(resolvedPath),
      torrentName: folderName,
      debridService: SeriesSource.localService,
      debridTorrentId: resolvedPath,
      boundAt: DateTime.now().millisecondsSinceEpoch,
      localPath: resolvedPath,
      localUri: Uri.directory(resolvedPath).toString(),
      localKind: SeriesSource.localKindSeriesFolder,
      localSizeBytes: episodes.length,
      localModifiedAt: stat.modified.millisecondsSinceEpoch,
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _videoExtensions,
      allowMultiple: false,
      withData: false,
    );
    if (!active()) return null;
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    return localSourceFromFile(File(path), canContinue: canContinue);
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
    final path = await FilePicker.platform.getDirectoryPath();
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
