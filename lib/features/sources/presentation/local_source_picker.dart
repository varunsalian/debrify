import 'package:flutter/material.dart';

import '../../../models/series_source.dart';
import 'local_movie_pick_mode_sheet.dart';

/// Stateless mode selection and feedback, with platform operations supplied by
/// composition. The calling action retains ownership of its continuation guard.
class LocalSourcePicker {
  const LocalSourcePicker({
    required this.androidFolderSelection,
    required this.disabledReason,
    required this.file,
    required this.movieFolder,
    required this.seriesFolder,
  });

  final bool androidFolderSelection;
  final String? disabledReason;
  final Future<SeriesSource?> Function(
    BuildContext context, {
    bool Function()? canContinue,
  })
  file;
  final Future<SeriesSource?> Function(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  })
  movieFolder;
  final Future<SeriesSource?> Function(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  })
  seriesFolder;

  Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (_showDisabled(context)) return null;
    final mode = await showLocalMoviePickMode(
      context,
      androidFolderSelection: androidFolderSelection,
    );
    if (mode == null || !context.mounted || !active()) return null;
    return _pickMovieSelection(
      context,
      mode,
      title: title,
      year: year,
      canContinue: canContinue,
    );
  }

  // Keep the legacy file/folder asynchronous completion boundary and entry guard.
  Future<SeriesSource?> _pickMovieSelection(
    BuildContext context,
    LocalMoviePickMode mode, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    return switch (mode) {
      LocalMoviePickMode.file => file(context, canContinue: canContinue),
      LocalMoviePickMode.folder => movieFolder(
        context,
        title: title,
        year: year,
        canContinue: canContinue,
      ),
    };
  }

  Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  }) async {
    bool active() => canContinue?.call() ?? true;
    if (canContinue != null && (!context.mounted || !active())) return null;
    if (_showDisabled(context)) return null;
    return seriesFolder(context, title: title, canContinue: canContinue);
  }

  bool _showDisabled(BuildContext context) {
    final reason = disabledReason;
    if (reason == null) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(reason), backgroundColor: const Color(0xFFEF4444)),
    );
    return true;
  }
}
