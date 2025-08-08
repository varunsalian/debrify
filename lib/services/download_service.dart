import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';

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

class DownloadService {
  DownloadService._internal();
  static final DownloadService _instance = DownloadService._internal();
  static DownloadService get instance => _instance;

  final StreamController<TaskProgressUpdate> _progressController =
      StreamController.broadcast();
  final StreamController<TaskStatusUpdate> _statusController =
      StreamController.broadcast();

  Stream<TaskProgressUpdate> get progressStream => _progressController.stream;
  Stream<TaskStatusUpdate> get statusStream => _statusController.stream;

  bool _started = false;

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
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

    // If user selected a default SAF directory (Android), use a Uri-based task
    final String? defaultUri = await StorageService.getDefaultDownloadUri();

    if (Platform.isAndroid && defaultUri != null && defaultUri.isNotEmpty) {
      // Determine filename
      String filename = (fileName?.trim().isNotEmpty ?? false)
          ? fileName!.trim()
          : (Uri.tryParse(url)?.pathSegments.isNotEmpty ?? false)
              ? Uri.parse(url).pathSegments.last
              : 'file';
      filename = _sanitizeName(filename);

      final task = UriDownloadTask(
        url: url,
        headers: headers,
        filename: filename,
        directoryUri: Uri.parse(defaultUri),
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
        directory: '',
      );
    }

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
    await FileDownloader().pause(task as DownloadTask);
  }

  Future<bool> resume(Task task) async {
    if (await FileDownloader().taskCanResume(task as DownloadTask)) {
      return FileDownloader().resume(task as DownloadTask);
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