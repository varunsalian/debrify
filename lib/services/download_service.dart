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

  // Queuing
  final List<_PendingRequest> _pending = [];
  final Map<String, _PendingRequest> _pendingById = {};
  final Map<String, TaskRecord> _nonAndroidQueuedRecords = {};
  // Resumes awaiting capacity
  final Set<String> _pendingResumeAndroid = {};
  final Map<String, DownloadTask> _pendingResumeNonAndroid = {};
  final Set<String> _nonAndroidResumeQueuedOverlay = {};
  bool _reevaluating = false;
  bool _reevaluateScheduled = false;

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
            // Paused frees a slot; try to start next
            _reevaluateQueue();
            break;
          case 'resumed':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            break;
          case 'canceled':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.canceled, -2.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.canceled));
            _lastFileByTaskId.remove(taskId);
            _reevaluateQueue();
            break;
          case 'complete':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.complete, 1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.complete));
            final uri = (event['contentUri'] ?? '').toString();
            final mime = (event['mimeType'] ?? 'application/octet-stream').toString();
            if (uri.isNotEmpty) {
              _lastFileByTaskId[taskId] = (uri, mime);
            }
            _reevaluateQueue();
            break;
          case 'error':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.failed, -1.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.failed));
            _lastFileByTaskId.remove(taskId);
            _reevaluateQueue();
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
            if (update.status == TaskStatus.complete ||
                update.status == TaskStatus.failed ||
                update.status == TaskStatus.canceled ||
                update.status == TaskStatus.paused) {
              _reevaluateQueue();
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

    // Always queue first, then start based on concurrency limit
    final providedName = (fileName?.trim().isNotEmpty ?? false) ? _sanitizeName(fileName!.trim()) : null;

    // Create a queued placeholder task/record for visibility
    final String queuedId = 'queued-${DateTime.now().millisecondsSinceEpoch}-${url.hashCode}';
    final String displayName = providedName ?? (() {
      try {
        final uri = Uri.parse(url);
        return _sanitizeName(uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file');
      } catch (_) {
        return 'file';
      }
    })();

    final queuedTask = DownloadTask(taskId: queuedId, url: url, filename: displayName);

    if (Platform.isAndroid) {
      AndroidDownloadHistory.instance.upsert(queuedTask, TaskStatus.enqueued, 0.0);
    } else {
      _nonAndroidQueuedRecords[queuedId] = TaskRecord(queuedTask, TaskStatus.enqueued, 0.0, -1);
    }
    _statusController.add(TaskStatusUpdate(queuedTask, TaskStatus.enqueued));

    // Add to in-memory pending queue
    final pending = _PendingRequest(
      queuedId: queuedId,
      url: url,
      providedFileName: providedName,
      headers: headers,
      wifiOnly: wifiOnly,
      retries: retries,
      meta: meta,
      context: context,
      torrentName: torrentName,
    );
    _pending.add(pending);
    _pendingById[queuedId] = pending;

    // Try to start if capacity allows
    unawaited(_reevaluateQueue());

    return DownloadEntry(task: queuedTask, displayName: displayName, directory: '');
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
    // Enforce concurrency: if at capacity, queue the resume
    final int maxParallel = await StorageService.getMaxParallelDownloads();
    int runningCount;
    if (Platform.isAndroid) {
      final list = AndroidDownloadHistory.instance.all();
      runningCount = list.where((r) => r.status == TaskStatus.running).length;
      if (runningCount >= maxParallel) {
        _pendingResumeAndroid.add(task.taskId);
        // Show as queued
        AndroidDownloadHistory.instance.upsert(task as DownloadTask, TaskStatus.enqueued, 0.0);
        _statusController.add(TaskStatusUpdate(task, TaskStatus.enqueued));
        unawaited(_reevaluateQueue());
        return true;
      }
      return AndroidNativeDownloader.resume(task.taskId);
    } else {
      final dbList = await FileDownloader().database.allRecords();
      runningCount = dbList.where((r) => r.status == TaskStatus.running).length;
      if (runningCount >= maxParallel) {
        if (task is DownloadTask) {
          _pendingResumeNonAndroid[task.taskId] = task;
          _nonAndroidResumeQueuedOverlay.add(task.taskId);
          _statusController.add(TaskStatusUpdate(task, TaskStatus.enqueued));
          unawaited(_reevaluateQueue());
          return true;
        }
        return false;
      }
      if (task is DownloadTask && await FileDownloader().taskCanResume(task)) {
        return FileDownloader().resume(task);
      }
      return false;
    }
  }

  Future<void> cancel(Task task) async {
    // If it's a queued placeholder, remove from our queue and history without touching platform
    if (_pendingById.containsKey(task.taskId)) {
      final pending = _pendingById.remove(task.taskId);
      if (pending != null) {
        _pending.remove(pending);
      }
      if (Platform.isAndroid) {
        AndroidDownloadHistory.instance.removeById(task.taskId);
        _statusController.add(TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled));
      } else {
        _nonAndroidQueuedRecords.remove(task.taskId);
        _statusController.add(TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled));
      }
      unawaited(_reevaluateQueue());
      return;
    }

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
    final dbRecords = await FileDownloader().database.allRecords();
    // Overlay queued placeholders and queued-resume status
    if (_nonAndroidQueuedRecords.isEmpty && _nonAndroidResumeQueuedOverlay.isEmpty) return dbRecords;
    final List<TaskRecord> adjusted = dbRecords.map((r) {
      if (_nonAndroidResumeQueuedOverlay.contains(r.taskId)) {
        return TaskRecord(r.task, TaskStatus.enqueued, r.progress, r.expectedFileSize);
      }
      return r;
    }).toList();
    final merged = [..._nonAndroidQueuedRecords.values, ...adjusted];
    merged.sort((a, b) => a.task.creationTime.compareTo(b.task.creationTime));
    return merged;
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
    if (Platform.isMacOS) {
      // On macOS, use the user's actual Downloads folder
      try {
        final Directory? downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          return downloadsDir;
        }
      } catch (e) {
        // Fallback to app documents if Downloads directory is not accessible
        print('Could not access Downloads directory: $e');
      }
    }
    return Directory((await getApplicationDocumentsDirectory()).path);
  }

  Future<String> _appDownloadsSubdir() async {
    if (Platform.isMacOS) {
      // On macOS, use the user's actual Downloads folder
      try {
        final Directory? downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          // Create a subfolder for the app to organize downloads
          final Directory appDownloadsDir = Directory('${downloadsDir.path}/Debrify');
          if (!await appDownloadsDir.exists()) {
            await appDownloadsDir.create(recursive: true);
          }
          return appDownloadsDir.path;
        }
      } catch (e) {
        // Fallback to app documents if Downloads directory is not accessible
        print('Could not access Downloads directory: $e');
      }
    }
    
    // Fallback: Use a stable, app-specific downloads directory under Documents
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

  Future<void> _reevaluateQueue() async {
    if (_reevaluating) {
      _reevaluateScheduled = true;
      return;
    }
    _reevaluating = true;
    // Determine capacity
    final int maxParallel = await StorageService.getMaxParallelDownloads();

    int runningCount = 0;
    if (Platform.isAndroid) {
      final list = AndroidDownloadHistory.instance.all();
      runningCount = list.where((r) => r.status == TaskStatus.running).length;
    } else {
      final list = await FileDownloader().database.allRecords();
      runningCount = list.where((r) => r.status == TaskStatus.running).length;
    }

    // First, process pending resumes up to capacity
    while (runningCount < maxParallel) {
      bool resumedSomeone = false;
      if (Platform.isAndroid && _pendingResumeAndroid.isNotEmpty) {
        final taskId = _pendingResumeAndroid.first;
        _pendingResumeAndroid.remove(taskId);
        final ok = await AndroidNativeDownloader.resume(taskId);
        if (ok) {
          resumedSomeone = true;
          runningCount += 1;
        }
      } else if (!Platform.isAndroid && _pendingResumeNonAndroid.isNotEmpty) {
        final entry = _pendingResumeNonAndroid.entries.first;
        _pendingResumeNonAndroid.remove(entry.key);
        _nonAndroidResumeQueuedOverlay.remove(entry.key);
        final DownloadTask task = entry.value;
        if (await FileDownloader().taskCanResume(task)) {
          final ok = await FileDownloader().resume(task);
          if (ok) {
            resumedSomeone = true;
            runningCount += 1;
          }
        }
      }
      if (!resumedSomeone) break;
    }

    // Start as many as possible
    while (runningCount < maxParallel && _pending.isNotEmpty) {
      final p = _pending.removeAt(0);
      _pendingById.remove(p.queuedId);
      try {
        if (Platform.isAndroid) {
          // Remove queued placeholder
          AndroidDownloadHistory.instance.removeById(p.queuedId);

          // Ensure battery exemptions (non-blocking by policy)
          await _ensureBatteryExemptions(p.context);

          final String name;
          if (p.providedFileName != null && p.providedFileName!.isNotEmpty) {
            name = p.providedFileName!;
          } else {
            final (_dir, fn) = await _smartLocationFor(p.url, null, p.torrentName);
            name = fn;
          }

          final String subDir = p.torrentName != null && p.torrentName!.trim().isNotEmpty 
              ? 'Debrify/${_sanitizeName(p.torrentName!.trim())}'
              : 'Debrify';

          final taskId = await AndroidNativeDownloader.start(
            url: p.url,
            fileName: name,
            subDir: subDir,
            headers: p.headers,
          );
          if (taskId == null) {
            throw Exception('Failed to start download');
          }
          final task = DownloadTask(taskId: taskId, url: p.url, filename: name);
          AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
          _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
        } else {
          // Remove queued placeholder from our in-memory list
          _nonAndroidQueuedRecords.remove(p.queuedId);

          final (dirAbsPath, filename) = await _smartLocationFor(p.url, p.providedFileName, p.torrentName);
          final (BaseDirectory baseDir, String relativeDir, String relFilename) = await Task.split(
            filePath: '$dirAbsPath/$filename',
          );
          final task = DownloadTask(
            url: p.url,
            headers: p.headers,
            filename: relFilename,
            directory: relativeDir,
            baseDirectory: baseDir,
            updates: Updates.statusAndProgress,
            requiresWiFi: p.wifiOnly,
            retries: p.retries,
            allowPause: true,
          );
          final bool ok = await FileDownloader().enqueue(task);
          if (!ok) {
            throw Exception('Failed to enqueue download');
          }
        }
        runningCount += 1;
      } catch (e) {
        // Mark failed
        if (Platform.isAndroid) {
          final failTask = DownloadTask(taskId: p.queuedId, url: p.url, filename: p.providedFileName ?? 'download');
          AndroidDownloadHistory.instance.upsert(failTask, TaskStatus.failed, -1.0);
          _statusController.add(TaskStatusUpdate(failTask, TaskStatus.failed));
        } else {
          final failTask = DownloadTask(taskId: p.queuedId, url: p.url, filename: p.providedFileName ?? 'download');
          _nonAndroidQueuedRecords[p.queuedId] = TaskRecord(failTask, TaskStatus.failed, -1.0, -1);
          _statusController.add(TaskStatusUpdate(failTask, TaskStatus.failed));
        }
      }
    }
    _reevaluating = false;
    if (_reevaluateScheduled) {
      _reevaluateScheduled = false;
      // Schedule a new pass
      unawaited(_reevaluateQueue());
    }
  }
}

class _PendingRequest {
  final String queuedId;
  final String url;
  final String? providedFileName;
  final Map<String, String>? headers;
  final bool wifiOnly;
  final int retries;
  final String? meta;
  final BuildContext? context;
  final String? torrentName;

  _PendingRequest({
    required this.queuedId,
    required this.url,
    required this.providedFileName,
    required this.headers,
    required this.wifiOnly,
    required this.retries,
    required this.meta,
    required this.context,
    required this.torrentName,
  });
} 