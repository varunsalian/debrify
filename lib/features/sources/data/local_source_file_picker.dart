import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../models/series_source.dart';
import 'local_source_files.dart';

const List<String> _videoExtensions = [
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

Future<String?> pickLocalDirectory() => FilePicker.platform.getDirectoryPath();

Future<SeriesSource?> pickLocalVideoSource({
  bool Function()? canContinue,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _videoExtensions,
    allowMultiple: false,
    withData: false,
  );
  if (!(canContinue?.call() ?? true)) return null;
  final path = result?.files.single.path;
  if (path == null || path.trim().isEmpty) return null;
  return localSourceFromFile(File(path), canContinue: canContinue);
}
