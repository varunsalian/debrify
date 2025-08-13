import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';
import 'package:saf_stream/saf_stream.dart';
import 'android_native_downloader.dart';
import 'android_download_history.dart';
import 'package:flutter/material.dart';

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

class AndroidBytesProgress {
  final String taskId;
  final int bytes;
  final int total; // -1 if unknown
  const AndroidBytesProgress({required this.taskId, required this.bytes, required this.total});
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
  final StreamController<AndroidBytesProgress> _bytesController =
      StreamController.broadcast();

  Stream<TaskProgressUpdate> get progressStream => _progressController.stream;
  Stream<TaskStatusUpdate> get statusStream => _statusController.stream;
  Stream<MoveProgressUpdate> get moveProgressStream => _moveController.stream;
  Stream<AndroidBytesProgress> get bytesProgressStream => _bytesController.stream;

  bool _started = false;
  StreamSubscription<Map<String, dynamic>>? _androidEventsSub;
  bool _batteryCheckShown = false;

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<bool> _ensureBatteryExemptions(BuildContext? context) async {
    if (!Platform.isAndroid) return true;
    if (_batteryCheckShown) return true;
    _batteryCheckShown = true;
    try {
      bool proceed = true;
      if (context != null) {
        proceed = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Allow background downloads'),
                content: const Text(
                    'To keep downloads running reliably in the background, please allow the app to ignore battery optimizations. You can change this later in system settings.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!proceed) return false;

      // First, request ignore battery optimizations for this app via system dialog
      final ok = await AndroidNativeDownloader.requestIgnoreBatteryOptimizationsForApp();
      if (!ok) {
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please allow “Ignore battery optimizations” to start downloads.')),
          );
        }
        return false;
      }
      // Optionally open the settings list page so users can confirm/verify
      await AndroidNativeDownloader.openBatteryOptimizationSettings();
    } catch (_) {
      return true; // don't block if something goes wrong
    }
    return true;
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

  String _withSuffix(String filename, int attempt) {
    if (attempt <= 0) return filename;
    final dot = filename.lastIndexOf('.');
    final name = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    return '$name ($attempt)$ext';
  }

  Future<void> initialize() async {
    if (_started) return;

    await _ensureNotificationPermission();

    if (Platform.isAndroid) {
      await AndroidDownloadHistory.instance.initialize();
      _androidEventsSub = AndroidNativeDownloader.events.listen((event) {
        final type = event['type'] as String?;
        final String taskId = (event['taskId'] ?? '').toString();
        final task = DownloadTask(
          taskId: taskId,
          url: event['url'] ?? '',
          filename: event['fileName'] ?? 'download',
        );
        switch (type) {
          case 'started':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            break;
          case 'progress':
            final total = (event['total'] as num?)?.toInt() ?? 0;
            final bytes = (event['bytes'] as num?)?.toInt() ?? 0;
            final prog = total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, prog, expectedFileSize: total);
            _progressController.add(TaskProgressUpdate(task, prog));
            _bytesController.add(AndroidBytesProgress(taskId: taskId, bytes: bytes, total: total > 0 ? total : -1));
            break;
          case 'paused':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.paused, -5.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.paused));
            break;
          case 'resumed':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            break;
          case 'canceled':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.canceled, -2.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.canceled));
            break;
          case 'complete':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.complete, 1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.complete));
            break;
          case 'error':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.failed, -1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.failed));
            break;
        }
      });
    } else {
      // Non-Android: keep plugin notification configuration
      FileDownloader().configureNotification(
        running: const TaskNotification('Downloading', '{filename}'),
        complete: const TaskNotification('Download complete', '{filename}'),
        error: const TaskNotification('Download failed', '{filename}'),
        paused: const TaskNotification('Download paused', '{filename}'),
        progressBar: true,
      );

      FileDownloader().updates.listen((update) async {
        switch (update) {
          case TaskProgressUpdate():
            _progressController.add(update);
          case TaskStatusUpdate():
            _statusController.add(update);
            if (update.status == TaskStatus.canceled) {
              try {
                await FileDownloader().database.deleteRecordWithId(update.task.taskId);
              } catch (_) {}
            }
        }
      });
      await FileDownloader().trackTasks();
      await FileDownloader().resumeFromBackground();
    }

    _started = true;
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
    BuildContext? context,
  }) async {
    await initialize();

    final (dirAbsPath, filename) = await _smartLocationFor(url, fileName);

    if (Platform.isAndroid) {
      final ok = await _ensureBatteryExemptions(context);
      if (!ok) {
        throw Exception('battery_optimization_not_granted');
      }
      final String name = filename;
      final taskId = await AndroidNativeDownloader.start(
        url: url,
        fileName: name,
        subDir: 'Debrify',
        headers: headers,
      );
      if (taskId == null) {
        throw Exception('Failed to start download');
      }
      final task = DownloadTask(taskId: taskId, url: url, filename: name);
      // Optimistically add to history as enqueued/running
      AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
      return DownloadEntry(task: task, displayName: name, directory: '');
    }

    // Non-Android: existing plugin flow
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
    if (Platform.isAndroid) {
      await AndroidNativeDownloader.pause(task.taskId);
      return;
    }
    if (task is DownloadTask) {
      await FileDownloader().pause(task);
    }
  }

  Future<bool> resume(Task task) async {
    if (Platform.isAndroid) {
      return AndroidNativeDownloader.resume(task.taskId);
    }
    if (task is DownloadTask && await FileDownloader().taskCanResume(task)) {
      return FileDownloader().resume(task);
    }
    return false;
  }

  Future<void> cancel(Task task) async {
    if (Platform.isAndroid) {
      await AndroidNativeDownloader.cancel(task.taskId);
      AndroidDownloadHistory.instance.removeById(task.taskId);
      _statusController.add(TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled));
      return;
    }
    await FileDownloader().cancel(task as DownloadTask);
    try {
      await FileDownloader().database.deleteRecordWithId(task.taskId);
    } catch (_) {}
  }

  // For backward UI compatibility; on Android, we don’t maintain a DB of records
  Future<List<TaskRecord>> allRecords() async {
    if (Platform.isAndroid) {
      return AndroidDownloadHistory.instance.all();
    }
    return FileDownloader().database.allRecords();
  }

  Future<void> deleteRecord(TaskRecord record) async {
    if (Platform.isAndroid) {
      AndroidDownloadHistory.instance.removeById(record.taskId);
      return;
    }
    await FileDownloader().database.deleteRecordWithId(record.taskId);
  }

  Future<Directory> getDownloadsRoot() async {
    if (Platform.isAndroid) {
      // Public Downloads is not directly accessible; keep using app docs for any local-only ops
      return Directory((await getApplicationDocumentsDirectory()).path);
    }
    return Directory((await getApplicationDocumentsDirectory()).path);
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
} 