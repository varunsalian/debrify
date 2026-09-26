import '../models/pikpak_prepared_source.dart';

class PikPakSourceFailed implements Exception {
  const PikPakSourceFailed();
}

class PikPakSourceStillProcessing implements Exception {
  const PikPakSourceStillProcessing();
}

class PikPakSourceRetired implements Exception {
  const PikPakSourceRetired();
}

/// Decode only the fields needed for playlist construction at the API boundary.
PikPakSourceVideo pikPakSourceVideoFromJson(
  Map<String, dynamic> file, {
  String? nameOverride,
}) => PikPakSourceVideo(
  id: file['id']?.toString(),
  name: nameOverride ?? file['name']?.toString(),
  relativePath: file['_fullPath'] as String?,
  sizeBytes: int.tryParse(file['size']?.toString() ?? '0'),
);

/// Preserve the existing two-stage readiness polling and partial folder listing.
/// Each reader owns authentication. A retired action must not start another read
/// that could capture a different profile; already-issued requests may complete.
Future<PikPakPreparedSource> preparePikPakSource({
  required String magnet,
  required Future<Map<String, dynamic>> Function(String) addDownload,
  required Future<Map<String, dynamic>> Function(String) readTask,
  required Future<Map<String, dynamic>> Function(String) readFile,
  required Future<List<Map<String, dynamic>>> Function(String) listFolder,
  Future<void> Function(Duration)? delay,
  bool Function()? canContinue,
}) async {
  void checkCurrent() {
    if (canContinue?.call() == false) throw const PikPakSourceRetired();
  }

  Future<void> wait() async {
    checkCurrent();
    await (delay ?? Future<void>.delayed)(const Duration(seconds: 2));
    checkCurrent();
  }

  Future<List<PikPakSourceVideo>> folderVideos(
    String folderId, {
    int depth = 0,
    String path = '',
  }) async {
    checkCurrent();
    if (depth >= 5) return [];
    final videos = <PikPakSourceVideo>[];
    try {
      final files = await listFolder(folderId);
      checkCurrent();
      for (final file in files) {
        final kind = file['kind'] ?? '';
        final mime = (file['mime_type'] ?? '').toString();
        final name = (file['name'] ?? 'unknown').toString();
        if (kind == 'drive#folder') {
          videos.addAll(
            await folderVideos(
              file['id'].toString(),
              depth: depth + 1,
              path: path.isEmpty ? name : '$path/$name',
            ),
          );
          checkCurrent();
        } else if (mime.startsWith('video/')) {
          videos.add(
            pikPakSourceVideoFromJson(
              file,
              nameOverride: path.isEmpty ? null : '$path/$name',
            ),
          );
        }
      }
    } on PikPakSourceRetired {
      rethrow;
    } catch (_) {
      checkCurrent();
      // The legacy listing keeps files collected before a folder read fails.
    }
    videos.sort(
      (a, b) =>
          (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()),
    );
    return videos;
  }

  checkCurrent();
  final add = await addDownload(magnet);
  checkCurrent();
  String? fileId;
  String? taskId;
  if (add['file'] != null) {
    fileId = add['file']['id']?.toString();
  } else if (add['task'] != null) {
    fileId = add['task']['file_id']?.toString();
    taskId = add['task']['id']?.toString();
  } else if (add['id'] != null) {
    fileId = add['id']?.toString();
  }
  if (fileId == null) throw Exception('PikPak: no file id returned');

  var taskReady = false;
  if (taskId != null) {
    for (var attempt = 0; attempt < 7; attempt++) {
      if (attempt > 0) await wait();
      checkCurrent();
      try {
        final task = await readTask(taskId);
        checkCurrent();
        if (task['phase'] == 'PHASE_TYPE_COMPLETE') {
          taskReady = true;
          break;
        }
        if (task['phase'] == 'PHASE_TYPE_ERROR') {
          throw const PikPakSourceFailed();
        }
        final raw = task['progress'];
        if (raw != null) {
          final progress = raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
          if (progress >= 90) {
            taskReady = true;
            break;
          }
        }
      } on PikPakSourceFailed {
        rethrow;
      } on PikPakSourceRetired {
        rethrow;
      } catch (_) {
        checkCurrent();
        break;
      }
    }
  }

  List<PikPakSourceVideo> videos = const [];
  for (var attempt = 0; attempt < 5; attempt++) {
    if (attempt > 0 || !taskReady) await wait();
    checkCurrent();
    try {
      final file = await readFile(fileId);
      checkCurrent();
      if (file['phase'] == 'PHASE_TYPE_COMPLETE') {
        if (file['kind'] == 'drive#folder') {
          videos = await folderVideos(fileId);
          checkCurrent();
        } else if ((file['mime_type'] ?? '').toString().startsWith('video/')) {
          videos = [pikPakSourceVideoFromJson(file)];
        }
        break;
      }
      if (file['phase'] == 'PHASE_TYPE_ERROR') {
        throw const PikPakSourceFailed();
      }
    } on PikPakSourceFailed {
      rethrow;
    } on PikPakSourceRetired {
      rethrow;
    } catch (_) {
      checkCurrent();
    }
  }
  if (videos.isEmpty) throw const PikPakSourceStillProcessing();
  return PikPakPreparedSource(fileId: fileId, videos: videos);
}
