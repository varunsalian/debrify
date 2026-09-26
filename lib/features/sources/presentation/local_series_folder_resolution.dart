import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/local_source_file.dart';
import 'local_series_folder_help.dart';
import 'local_source_choice_dialogs.dart';

Future<Directory?> resolveLocalSeriesFolder(
  BuildContext context, {
  required String title,
  required String pickedFolderName,
  required Future<LocalSeriesFolderLookup?> Function() lookup,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return null;
  final result = await lookup();
  if (result == null || !active()) return null;
  if (result.direct != null) return result.direct;
  final matches = result.candidates;
  if (matches.isEmpty) {
    if (context.mounted) {
      await showLocalSeriesFolderHelp(
        context,
        title: title,
        pickedFolderName: pickedFolderName,
      );
    }
    return null;
  }
  if (matches.length == 1) return matches.single.directory;
  if (!context.mounted) return null;
  final selected = await showLocalSeriesFolderChoice(
    context,
    title: title,
    candidates: matches,
  );
  if (!active()) return null;
  return selected?.directory;
}
