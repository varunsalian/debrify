import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';
import 'package:saf_stream/saf_stream.dart';

class DownloadEntry {
  final Task task;
  final String displayName;
  final String directory; // relative to base directory
  final int? expectedFileSize;

  const DownloadEntry({
    required this.task,
    required this.displayName,
    required this.directory,
    this.expectedFileSize,
  });
}

class MoveProgressUpdate {
  final String taskId;
  final double progress; // 0.0..1.0
  final bool done;
  final bool failed;
  const MoveProgressUpdate({
    required this.taskId,
    required this.progress,
    this.done = false,
    this.failed = false,
  });
}

class DownloadService {
  DownloadService._internal();
  static final DownloadService _instance = DownloadService._internal();
  static DownloadService get instance => _instance;

  final StreamController<TaskProgressUpdate> _progressController =
      StreamController.broadcast();
  final StreamController<TaskStatusUpdate> _statusController =
      StreamController.broadcast();
  final StreamController<MoveProgressUpdate> _moveController =
      StreamController.broadcast();

  Stream<TaskProgressUpdate> get progressStream => _progressController.stream;
  Stream<TaskStatusUpdate> get statusStream => _statusController.stream;
  Stream<MoveProgressUpdate> get moveProgressStream => _moveController.stream;

  bool _started = false;

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<String> _resolveAbsolutePathForTask(Task task) async {
    // We only construct paths for tasks we created with BaseDirectory.applicationDocuments
    // and a relative 'directory'
    Directory docs = await getApplicationDocumentsDirectory();
    final String dir = (task is DownloadTask) ? (task.directory ?? '') : '';
    final String filename = task.filename;
    final String normalizedDir = dir.isEmpty
        ? docs.path
        : '${docs.path}/${dir.replaceAll('\\', '/')}';
    return '$normalizedDir/$filename';
  }

  Future<void> _moveToSafIfConfigured(TaskStatusUpdate update) async {
    if (!Platform.isAndroid) return;
    if (update.status != TaskStatus.complete) return;
    final String? targetDirUri = await StorageService.getDefaultDownloadUri();
    if (targetDirUri == null || targetDirUri.isEmpty) return;
    try {
      final String absPath = await _resolveAbsolutePathForTask(update.task);
      final file = File(absPath);
      if (!await file.exists()) return;

      final saf = SafStream();
      final int total = await file.length();

      String baseName = update.task.filename;
      String name = baseName;
      bool moved = false;

      // Try up to 4 attempts with suffixes to avoid name collisions
      for (int attempt = 0; attempt < 4 && !moved; attempt++) {
        name = attempt == 0 ? baseName : _withSuffix(baseName, attempt);
        try {
          // First try streamed copy to show progress
          final info = await saf.startWriteStream(
            targetDirUri,
            name,
            'application/octet-stream',
          );
          final sessionId = info.session;
          int written = 0;
          await for (final chunk in file.openRead()) {
            final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
            await saf.writeChunk(sessionId, data);
            written += chunk.length;
            _moveController.add(MoveProgressUpdate(
              taskId: update.task.taskId,
              progress: total > 0 ? (written / total).clamp(0.0, 1.0) : 0.0,
            ));
          }
          await saf.endWriteStream(sessionId);
          moved = true;
        } catch (_) {
          // Fallback to paste for this attempt (no progress but more robust)
          try {
            await saf.pasteLocalFile(
              targetDirUri,
              absPath,
              name,
              'application/octet-stream',
            );
            moved = true;
          } catch (_) {
            // try next suffix
            moved = false;
          }
        }
      }

      if (moved) {
        _moveController.add(MoveProgressUpdate(
          taskId: update.task.taskId,
          progress: 1.0,
          done: true,
        ));
        await file.delete();
      } else {
        _moveController.add(MoveProgressUpdate(
          taskId: update.task.taskId,
          progress: 0.0,
          failed: true,
        ));
      }
    } catch (_) {
      // Report failure; local app copy remains available
      _moveController.add(MoveProgressUpdate(
        taskId: update.task.taskId,
        progress: 0.0,
        failed: true,
      ));
    }
  }

  String _withSuffix(String filename, int attempt) {
    if (attempt <= 0) return filename;
    final dot = filename.lastIndexOf('.');
    final name = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    return '$name ($attempt)$ext';
  }

  Future<void> initialize() async {
    if (_started) return;

    // Request notification permission on Android 13+
    await _ensureNotificationPermission();

    // Configure notifications (Android)
    FileDownloader().configureNotification(
      running: const TaskNotification('Downloading', '{filename}'),
      complete: const TaskNotification('Download complete', '{filename}'),
      error: const TaskNotification('Download failed', '{filename}'),
      paused: const TaskNotification('Download paused', '{filename}'),
      progressBar: true,
    );

    // Listen for updates centrally
    FileDownloader().updates.listen((update) async {
      switch (update) {
        case TaskProgressUpdate():
          _progressController.add(update);
        case TaskStatusUpdate():
          _statusController.add(update);
          if (update.status == TaskStatus.canceled) {
            // Purge canceled tasks from DB so they don't show up anywhere
            try {
              await FileDownloader().database.deleteRecordWithId(update.task.taskId);
            } catch (_) {}
          }
          if (update.status == TaskStatus.complete) {
            await _moveToSafIfConfigured(update);
          }
      }
    });

    // Track tasks and resume events that happened in background
    await FileDownloader().trackTasks();
    await FileDownloader().resumeFromBackground();

    _started = true;
  }

  Future<String> _appDownloadsSubdir() async {
    // Use a stable, app-specific downloads directory under Documents
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dlDir = Directory('${docs.path}/downloads');
    if (!await dlDir.exists()) {
      await dlDir.create(recursive: true);
    }
    return dlDir.path;
  }

  static String _sanitizeName(String name) {
    // Remove problematic characters and trim
    final String cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  Future<(String directory, String filename)> _smartLocationFor(
    String url,
    String? providedFileName,
  ) async {
    // Determine file name: provided > last path segment
    String filename = (providedFileName?.trim().isNotEmpty ?? false)
        ? providedFileName!.trim()
        : Uri.parse(url).pathSegments.isNotEmpty
            ? Uri.parse(url).pathSegments.last
            : 'file';

    filename = _sanitizeName(filename);

    // Make a folder from base name (without extension)
    final int dot = filename.lastIndexOf('.');
    final String baseName = dot > 0 ? filename.substring(0, dot) : filename;
    final String folder = _sanitizeName(baseName);

    // Place under downloads/<folder>
    final String downloadsRoot = await _appDownloadsSubdir();
    final String dir = '$downloadsRoot/$folder';
    final Directory d = Directory(dir);
    if (!await d.exists()) {
      await d.create(recursive: true);
    }

    return (dir, filename);
  }

  Future<DownloadEntry> enqueueDownload({
    required String url,
    String? fileName,
    Map<String, String>? headers,
    bool wifiOnly = false,
    int retries = 3,
    String? meta,
  }) async {
    await initialize();

    final (dirAbsPath, filename) = await _smartLocationFor(url, fileName);

    // Convert absolute path to baseDirectory + relative directory
    final (BaseDirectory baseDir, String relativeDir, String relFilename) =
        await Task.split(
      filePath: '$dirAbsPath/$filename',
    );

    final task = DownloadTask(
      url: url,
      headers: headers,
      filename: relFilename,
      directory: relativeDir,
      baseDirectory: baseDir,
      updates: Updates.statusAndProgress,
      requiresWiFi: wifiOnly,
      retries: retries,
      allowPause: true,
    );

    final bool ok = await FileDownloader().enqueue(task);
    if (!ok) {
      throw Exception('Failed to enqueue download');
    }

    return DownloadEntry(
      task: task,
      displayName: filename,
      directory: relativeDir,
    );
  }

  Future<void> pause(Task task) async {
    if (task is DownloadTask) {
      await FileDownloader().pause(task);
    }
  }

  Future<bool> resume(Task task) async {
    if (task is DownloadTask && await FileDownloader().taskCanResume(task)) {
      return FileDownloader().resume(task);
    }
    return false;
  }

  Future<void> cancel(Task task) async {
    await FileDownloader().cancel(task as DownloadTask);
    try {
      await FileDownloader().database.deleteRecordWithId(task.taskId);
    } catch (_) {}
  }

  Future<List<TaskRecord>> allRecords() async {
    return FileDownloader().database.allRecords();
  }

  Future<void> deleteRecord(TaskRecord record) async {
    await FileDownloader().database.deleteRecordWithId(record.taskId);
  }

  Future<Directory> getDownloadsRoot() async {
    return Directory(await _appDownloadsSubdir());
  }
} 