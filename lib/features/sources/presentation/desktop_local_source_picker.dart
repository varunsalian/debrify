import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/series_source.dart';
import '../models/local_source_file.dart';
import 'local_source_choice_dialogs.dart';

Future<SeriesSource?> pickDesktopMovieFolder(
  BuildContext context, {
  required Future<String?> Function() pickDirectory,
  required Future<List<LocalVideoCandidate>> Function(String path) scan,
  required LocalVideoCandidate? Function(List<LocalVideoCandidate>) match,
  required Future<SeriesSource?> Function(LocalVideoCandidate) describe,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return null;
  final path = await pickDirectory();
  if (!active()) return null;
  if (path == null || path.trim().isEmpty) return null;
  final candidates = await scan(path);
  if (!active()) return null;
  if (candidates.isEmpty) {
    if (context.mounted) {
      _showError(context, 'No video files found in that folder');
    }
    return null;
  }
  final matched = match(candidates);
  if (matched != null) return describe(matched);
  if (!context.mounted) return null;
  final selected = await showLocalFileChoice(context, candidates);
  if (!active()) return null;
  return selected == null ? null : describe(selected);
}

Future<SeriesSource?> pickDesktopSeriesFolder(
  BuildContext context, {
  required Future<String?> Function() pickDirectory,
  required Future<Directory?> Function(String path) resolve,
  required Future<List<LocalSeriesEpisodeFile>> Function(String path) scan,
  required Future<SeriesSource?> Function(Directory folder, int count) describe,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return null;
  final path = await pickDirectory();
  if (path == null || path.trim().isEmpty) return null;
  if (!context.mounted || !active()) return null;
  final seriesFolder = await resolve(path);
  if (seriesFolder == null || !active()) return null;
  final resolvedPath = seriesFolder.path;
  final episodes = await scan(resolvedPath);
  if (!active()) return null;
  if (episodes.isEmpty) {
    if (context.mounted) {
      _showError(context, 'No episodes found in that folder');
    }
    return null;
  }
  return describe(seriesFolder, episodes.length);
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: const Color(0xFFEF4444)),
  );
}
