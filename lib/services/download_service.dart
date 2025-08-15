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
  final Map<String, (String contentUri, String mimeType)?> _lastFileByTaskId = {};

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
    // Respect saved preference first
    final saved = await StorageService.getBatteryOptimizationStatus();
    if (saved == 'granted') return true;
    if (saved == 'never') return true; // user opted out

    if (_batteryCheckShown) return true;
    _batteryCheckShown = true;
    try {
      bool proceed = true;
      String choice = 'denied';
      if (context != null) {
        bool dontAskAgain = false;
        proceed = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: const Color(0xFF0B1220),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (ctx) {
                final kb = MediaQuery.of(ctx).viewInsets.bottom;
                return Padding(
                  padding: EdgeInsets.only(bottom: kb),
                  child: SafeArea(
                    top: false,
                    child: StatefulBuilder(builder: (ctx2, setLocal) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF334155),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.battery_saver, color: Colors.white),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text('Allow background downloads',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'To keep downloads running reliably in the background, allow the app to ignore battery optimizations.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.check_circle, size: 18, color: const Color(0xFF10B981).withValues(alpha: 0.9)),
                                const SizedBox(width: 8),
                                Text('Keeps long downloads alive', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.check_circle, size: 18, color: const Color(0xFF10B981).withValues(alpha: 0.9)),
                                const SizedBox(width: 8),
                                Text('You can change this later in system settings', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Checkbox(
                                  value: dontAskAgain,
                                  onChanged: (v) => setLocal(() => dontAskAgain = v ?? false),
                                ),
                                const SizedBox(width: 4),
                                const Text("Don't ask again"),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      choice = dontAskAgain ? 'never' : 'denied';
                                      Navigator.of(ctx2).pop(false);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFF334155)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text('Not now'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      choice = 'granted';
                                      Navigator.of(ctx2).pop(true);
                                    },
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text('Allow'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                );
              },
            ) ??
            false;
      }
      if (!proceed) {
        await StorageService.setBatteryOptimizationStatus(choice);
        return true; // do not block downloads
      }

      // System dialog
      final ok = await AndroidNativeDownloader.requestIgnoreBatteryOptimizationsForApp();
      if (ok) {
        await StorageService.setBatteryOptimizationStatus('granted');
        return true;
      } else {
        await StorageService.setBatteryOptimizationStatus('denied');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can enable background downloads later in Settings.')),
          );
        }
        return true; // do not block downloads
      }
    } catch (_) {
      return true; // don't block if something goes wrong
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
            _lastFileByTaskId.remove(taskId);
            break;
          case 'complete':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.complete, 1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.complete));
            final uri = (event['contentUri'] ?? '').toString();
            final mime = (event['mimeType'] ?? 'application/octet-stream').toString();
            if (uri.isNotEmpty) {
              _lastFileByTaskId[taskId] = (uri, mime);
            }
            break;
          case 'error':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.failed, -1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.failed));
            _lastFileByTaskId.remove(taskId);
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
    String? torrentName,
  ) async {
    // Determine file name: provided > last path segment
    String filename = (providedFileName?.trim().isNotEmpty ?? false)
        ? providedFileName!.trim()
        : Uri.parse(url).pathSegments.isNotEmpty
            ? Uri.parse(url).pathSegments.last
            : 'file';

    filename = _sanitizeName(filename);

    // Use torrent name for folder if provided, otherwise use base name of file
    String folder;
    if (torrentName != null && torrentName.trim().isNotEmpty) {
      folder = _sanitizeName(torrentName.trim());
    } else {
      // Make a folder from base name (without extension)
      final int dot = filename.lastIndexOf('.');
      final String baseName = dot > 0 ? filename.substring(0, dot) : filename;
      folder = _sanitizeName(baseName);
    }

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
    String? torrentName,
  }) async {
    await initialize();

    final (dirAbsPath, filename) = await _smartLocationFor(url, fileName, torrentName);

    if (Platform.isAndroid) {
      final ok = await _ensureBatteryExemptions(context);
      if (!ok) {
        throw Exception('battery_optimization_not_granted');
      }
      final String name = filename;
      // Use torrent name for subdirectory if provided, otherwise use 'Debrify'
      final String subDir = torrentName != null && torrentName.trim().isNotEmpty 
          ? 'Debrify/${_sanitizeName(torrentName.trim())}'
          : 'Debrify';
      final taskId = await AndroidNativeDownloader.start(
        url: url,
        fileName: name,
        subDir: subDir,
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

  (String contentUri, String mimeType)? getLastFileForTask(String taskId) => _lastFileByTaskId[taskId];
} 