import 'dart:io';

import 'package:flutter/material.dart';

import '../features/sources/data/local_source_file_picker.dart';
import '../features/sources/data/local_source_file_rules.dart';
import '../features/sources/data/local_source_files.dart';
import '../features/sources/models/local_source_file.dart';
import '../features/sources/presentation/android_local_source_picker.dart';
import '../features/sources/presentation/local_movie_pick_mode_sheet.dart';
import '../features/sources/presentation/desktop_local_source_picker.dart';
import '../features/sources/presentation/local_series_folder_resolution.dart';
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

    return pickDesktopSeriesFolder(
      context,
      pickDirectory: pickLocalDirectory,
      resolve: (path) => resolveLocalSeriesFolder(
        context,
        title: title,
        pickedFolderName: localPathName(path),
        lookup: () => lookupLocalSeriesFolders(
          path,
          title: title,
          canContinue: canContinue,
        ),
        canContinue: canContinue,
      ),
      scan: (path) => scanLocalSeriesFolder(path, canContinue: canContinue),
      describe: (folder, count) => localSourceFromSeriesFolder(
        folder,
        title: title,
        episodeCount: count,
        canContinue: canContinue,
      ),
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
    return pickDesktopMovieFolder(
      context,
      pickDirectory: pickLocalDirectory,
      scan: (path) => scanLocalVideoFolder(path, canContinue: canContinue),
      match: (candidates) =>
          matchLocalMovieFiles(candidates, title: title, year: year),
      describe: (candidate) =>
          localSourceFromFile(candidate.file, canContinue: canContinue),
      canContinue: canContinue,
    );
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
