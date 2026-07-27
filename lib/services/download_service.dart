import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'debrid_service.dart';
import 'torbox_service.dart';
import 'pikpak_api_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';
import 'android_native_downloader.dart';
import 'android_download_history.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

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
  const AndroidBytesProgress({
    required this.taskId,
    required this.bytes,
    required this.total,
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
  final StreamController<AndroidBytesProgress> _bytesController =
      StreamController.broadcast();
  final Map<String, (String contentUri, String mimeType)?> _lastFileByTaskId =
      {};

  Stream<TaskProgressUpdate> get progressStream => _progressController.stream;
  Stream<TaskStatusUpdate> get statusStream => _statusController.stream;
  Stream<MoveProgressUpdate> get moveProgressStream => _moveController.stream;
  Stream<AndroidBytesProgress> get bytesProgressStream =>
      _bytesController.stream;

  bool _started = false;
  bool _initializing = false;
  StreamSubscription<Map<String, dynamic>>? _androidEventsSub;
  bool _batteryCheckShown = false;
  ConnectivityResult _net = ConnectivityResult.wifi; // default optimistic
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  ConnectivityResult _computeEffectiveNet(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityResult.none;
    if (results.contains(ConnectivityResult.none))
      return ConnectivityResult.none;
    // Treat ethernet/wired/vpn as acceptable like Wi-Fi for large downloads
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn)) {
      return ConnectivityResult.wifi;
    }
    if (results.contains(ConnectivityResult.mobile))
      return ConnectivityResult.mobile;
    // Fallback to the first known state
    return results.first;
  }

  // Queuing
  final List<_PendingRequest> _pending = [];
  final Map<String, _PendingRequest> _pendingById = {};
  final Map<String, _PendingRequest> _pausedPending = {};
  final Map<String, TaskRecord> _nonAndroidQueuedRecords = {};
  // Resumes awaiting capacity
  final Set<String> _pendingResumeAndroid = {};
  final Map<String, DownloadTask> _pendingResumeNonAndroid = {};
  final Set<String> _nonAndroidResumeQueuedOverlay = {};
  final Set<String> _canceledDuringStart = {};
  bool _reevaluating = false;
  bool _reevaluateScheduled = false;
  // Monotonic suffix so two enqueues in the same millisecond can't mint the
  // same record id (which used to silently overwrite the earlier record).
  int _idSeq = 0;
  // Per-task debrid-link refresh attempts; caps the error→refresh→error loop
  // for genuinely dead content. Reset only by FRESH progress: byte count at
  // the last error is the baseline, because progress events carry cumulative
  // bytes and any partially-downloaded task would otherwise reset the budget
  // on its first tick after every restart.
  final Map<String, int> _linkRefreshAttempts = {};
  final Map<String, int> _bytesAtLastError = {};
  static const int _maxLinkRefreshAttempts = 2;
  static const int _refreshResetFreshBytes = 1024 * 1024;

  // Persistence for pending queue (crash-safe, survives restarts)
  static const String _pendingKey = 'pending_download_queue_v1';
  static const String _pausedKey = 'paused_download_queue_v1';
  static const String _recordsFile = 'downloads_db_v1.json';

  Map<String, Map<String, dynamic>> _records = {}; // recordId -> record map

  DownloadRecordDetails? recordDetailsForTaskId(String taskId) {
    final recId = _resolveRecordIdForTaskId(taskId);
    if (recId == null) return null;
    final data = _records[recId];
    if (data == null) return null;
    return DownloadRecordDetails.fromMap(recId, data);
  }

  DownloadRecordDetails? recordDetailsForRecordId(String recordId) {
    final data = _records[recordId];
    if (data == null) return null;
    return DownloadRecordDetails.fromMap(recordId, data);
  }

  Map<String, DownloadRecordDetails> allRecordDetailsSnapshot() {
    final Map<String, DownloadRecordDetails> result = {};
    for (final entry in _records.entries) {
      result[entry.key] = DownloadRecordDetails.fromMap(entry.key, entry.value);
    }
    return result;
  }

  bool isPausedQueuedTask(String taskId) => _pausedPending.containsKey(taskId);

  Future<void> pauseQueuedTasksByIds(Iterable<String> taskIds) async {
    final ids = taskIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    bool changedPending = false;
    bool changedPaused = false;

    Future<void> updateRecordState(String recordId) async {
      if (recordId.isEmpty) return;
      _upsertRecord(recordId, {'state': 'paused'});
    }

    for (final id in ids) {
      final pending = _pendingById.remove(id);
      if (pending != null) {
        pending.canceled = true;
        _pending.remove(pending);
        _pausedPending[pending.queuedId] = pending;
        changedPending = true;
        changedPaused = true;
        _canceledDuringStart.add(pending.queuedId);

        await updateRecordState(pending.queuedId);

        final downloadTask = DownloadTask(
          taskId: pending.queuedId,
          url: pending.url,
          filename: (pending.providedFileName?.isNotEmpty ?? false)
              ? pending.providedFileName!
              : 'download',
        );

        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance.upsert(
            downloadTask,
            TaskStatus.paused,
            -5.0,
          );
        } else {
          _nonAndroidQueuedRecords[pending.queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.paused,
            -5.0,
            -1,
          );
        }

        _statusController.add(
          TaskStatusUpdate(downloadTask, TaskStatus.paused),
        );
      } else {
        _canceledDuringStart.add(id);
        final recId = _resolveRecordIdForTaskId(id);
        if (recId != null) {
          await updateRecordState(recId);
          final rec = _records[recId];
          final reconstructed = rec != null
              ? _pendingFromRecordData(recId, rec)
              : null;
          if (reconstructed != null && !_pausedPending.containsKey(recId)) {
            reconstructed.canceled = true;
            _pausedPending[recId] = reconstructed;
            changedPaused = true;
            final downloadTask = DownloadTask(
              taskId: recId,
              url: reconstructed.url,
              filename: reconstructed.providedFileName ?? 'download',
            );
            if (Platform.isAndroid) {
              AndroidDownloadHistory.instance.upsert(
                downloadTask,
                TaskStatus.paused,
                -5.0,
              );
            } else {
              _nonAndroidQueuedRecords[recId] = TaskRecord(
                downloadTask,
                TaskStatus.paused,
                -5.0,
                -1,
              );
            }
            _statusController.add(
              TaskStatusUpdate(downloadTask, TaskStatus.paused),
            );
          }
        }
      }
    }

    if (changedPending) {
      await _persistPending();
    }
    if (changedPaused) {
      await _persistPaused();
    }
  }

  Future<void> resumeQueuedTasksByIds(Iterable<String> taskIds) async {
    final ids = taskIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    bool changedPending = false;
    bool changedPaused = false;

    for (final id in ids) {
      final paused = _pausedPending.remove(id);
      if (paused != null) {
        paused.canceled = false;
        _addPendingRequest(_pending, _pendingById, paused, atFront: true);
        changedPending = true;
        changedPaused = true;
        _canceledDuringStart.remove(paused.queuedId);

        _upsertRecord(paused.queuedId, {'state': 'queued'});

        final downloadTask = DownloadTask(
          taskId: paused.queuedId,
          url: paused.url,
          filename: (paused.providedFileName?.isNotEmpty ?? false)
              ? paused.providedFileName!
              : 'download',
        );

        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance.upsert(
            downloadTask,
            TaskStatus.enqueued,
            0.0,
          );
        } else {
          _nonAndroidQueuedRecords[paused.queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.enqueued,
            0.0,
            -1,
          );
        }

        _statusController.add(
          TaskStatusUpdate(downloadTask, TaskStatus.enqueued),
        );
      } else {
        _canceledDuringStart.remove(id);
        final recId = _resolveRecordIdForTaskId(id);
        if (recId != null) {
          final rec = _records[recId];
          if (rec != null) {
            final reconstructed = _pendingFromRecordData(recId, rec);
            if (reconstructed != null) {
              reconstructed.canceled = false;
              _addPendingRequest(
                _pending,
                _pendingById,
                reconstructed,
                atFront: true,
              );
              changedPending = true;
              _upsertRecord(reconstructed.queuedId, {'state': 'queued'});

              final downloadTask = DownloadTask(
                taskId: reconstructed.queuedId,
                url: reconstructed.url,
                filename: reconstructed.providedFileName ?? 'download',
              );
              if (Platform.isAndroid) {
                AndroidDownloadHistory.instance.upsert(
                  downloadTask,
                  TaskStatus.enqueued,
                  0.0,
                );
              } else {
                _nonAndroidQueuedRecords[reconstructed.queuedId] = TaskRecord(
                  downloadTask,
                  TaskStatus.enqueued,
                  0.0,
                  -1,
                );
              }
              _statusController.add(
                TaskStatusUpdate(downloadTask, TaskStatus.enqueued),
              );
            }
          }
        }
      }
    }

    if (changedPaused) {
      await _persistPaused();
    }
    if (changedPending) {
      await _persistPending();
      unawaited(_reevaluateQueue());
    }
  }

  String? _resolveRecordIdForTaskId(String taskId) {
    // If the taskId itself is a known record key (queued placeholder), return it
    if (_records.containsKey(taskId)) return taskId;
    // Otherwise, search by pluginTaskId → queued record id
    for (final e in _records.entries) {
      final pid = (e.value['pluginTaskId'] ?? '').toString();
      if (pid == taskId && pid.isNotEmpty) {
        return e.key;
      }
    }
    return null;
  }

  Future<String> _recordsFilePath() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(path.join(dir.path, _recordsFile));
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('{}');
    }
    return file.path;
  }

  Future<void> _loadRecords() async {
    try {
      final path = await _recordsFilePath();
      final raw = await File(path).readAsString();
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        _records = data.map(
          (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
        );
      }
    } catch (_) {
      _records = {};
    }
  }

  Future<void> _saveRecords() async {
    try {
      final path = await _recordsFilePath();
      await File(path).writeAsString(jsonEncode(_records));
    } catch (_) {}
  }

  void _upsertRecord(String recordId, Map<String, dynamic> patch) {
    final existing = _records[recordId] ?? <String, dynamic>{};
    existing.addAll(patch);
    existing['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    _records[recordId] = existing;
    unawaited(_saveRecords());
  }

  Map<String, String> _buildResumeHeaders(
    String finalPath,
    Map<String, String>? baseHeaders,
    Map<String, dynamic>? rec,
  ) {
    final Map<String, String> headers = {};
    if (baseHeaders != null) headers.addAll(baseHeaders);
    try {
      final file = File(finalPath);
      if (file.existsSync()) {
        final partial = file.lengthSync();
        if (partial > 0) {
          headers['Range'] = 'bytes=$partial-';
          final etag = rec != null ? (rec['etag'] as String?) : null;
          final lastMod = rec != null ? (rec['lastModified'] as String?) : null;
          if (etag != null && etag.isNotEmpty) {
            headers['If-Range'] = etag;
          } else if (lastMod != null && lastMod.isNotEmpty) {
            headers['If-Range'] = lastMod;
          }
          debugPrint(
            'DL RESUME: path=$finalPath partial=$partial rangeSet=true ifRange=' +
                (headers['If-Range'] ?? ''),
          );
        }
      }
    } catch (_) {}
    return headers;
  }

  String _computeContentKey(
    String? meta,
    String url,
    String? fileName,
    String? torrentName,
  ) {
    try {
      // Prefer stable identifiers from meta if present
      if (meta != null && meta.isNotEmpty) {
        // Expecting JSON meta with fields like restrictedLink or (torrentHash,fileIndex)
        final m = jsonDecode(meta);
        if (m is Map) {
          // PikPak pattern: pp:${fileId} (check BEFORE Torbox)
          final isPikPak = m['pikpakDownload'] == true;
          if (isPikPak) {
            final fileId = (m['pikpakFileId'] ?? '').toString();
            if (fileId.isNotEmpty) {
              return 'pp:$fileId';
            }
          }
          final isWebDav = m['webdavDownload'] == true;
          if (isWebDav) {
            final webdavPath = (m['webdavPath'] ?? '').toString();
            if (webdavPath.isNotEmpty) {
              return 'wd:${webdavPath.hashCode}';
            }
          }
          // Torbox pattern: tb:${torrentId}:${fileId} or tb-zip:${torrentId}
          final isTorbox = m['torboxDownload'] == true;
          if (isTorbox) {
            final torrentId = (m['torboxTorrentId'] ?? '').toString();
            final isZip = m['torboxZip'] == true;
            if (isZip && torrentId.isNotEmpty) {
              return 'tb-zip:$torrentId';
            }
            final fileId = (m['torboxFileId'] ?? '').toString();
            if (torrentId.isNotEmpty && fileId.isNotEmpty) {
              return 'tb:$torrentId:$fileId';
            }
          }
          // RealDebrid patterns (keep existing logic)
          final hash = (m['torrentHash'] ?? '').toString();
          final idx = (m['fileIndex'] ?? '').toString();
          if (hash.isNotEmpty && idx.isNotEmpty) return 'th:$hash:$idx';
          final restricted = (m['restrictedLink'] ?? '').toString();
          if (restricted.isNotEmpty) return 'rl:${restricted.hashCode}';
        }
      }
      // Fallback: torrent folder + sanitized fileName
      final n = (fileName ?? '').isNotEmpty
          ? fileName!
          : Uri.parse(url).pathSegments.lastOrNull ?? 'file';
      final t = (torrentName ?? '').trim();
      return 'nf:${t}_${_sanitizeName(n)}';
    } catch (_) {
      final n = (fileName ?? '').isNotEmpty ? fileName! : 'file';
      return 'nf:${(torrentName ?? '').trim()}_${_sanitizeName(n)}';
    }
  }

  Future<void> _captureValidatorsAndSave(String recordId, String url) async {
    try {
      final resp = await http.head(Uri.parse(url));
      final etag = resp.headers['etag'];
      final lastMod = resp.headers['last-modified'];
      final acceptRanges = resp.headers['accept-ranges'];
      _upsertRecord(recordId, {
        'etag': etag,
        'lastModified': lastMod,
        'acceptRanges': acceptRanges,
      });
    } catch (_) {}
  }

  Future<void> retryAllFailed() async {
    await _loadRecords();
    // Snapshot: _queueFromRecord mutates bookkeeping while we iterate, and
    // re-queue the SAME record (same id) — a retry must never mint a ghost
    // duplicate or be swallowed by content-key dedup.
    final failedIds = _records.entries
        .where((e) => (e.value['state'] == 'failed'))
        .map((e) => e.key)
        .toList(growable: false);
    for (final recordId in failedIds) {
      final requeued = await _queueFromRecord(recordId, paused: false);
      if (!requeued) {
        debugPrint('DL RETRY-ALL: could not re-queue $recordId');
      }
    }
    if (failedIds.isNotEmpty) {
      unawaited(_reevaluateQueue());
    }
  }

  Future<void> clearDownloadDatabase() async {
    // Clear durable records
    _records = {};
    await _saveRecords();
    // Clear in-memory queues so cleared items can't be revived by a later pass
    _pending.clear();
    _pendingById.clear();
    _pausedPending.clear();
    _pendingResumeAndroid.clear();
    _canceledDuringStart.clear();
    _linkRefreshAttempts.clear();
    // Clear persisted pending queue
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
      await prefs.remove(_pausedKey);
    } catch (_) {}
    if (Platform.isAndroid) {
      // A "clear" must clear ALL Android stores: the UI history and the
      // native service's persistent task store. Running tasks are CANCELED
      // (not just forgotten) — a live worker would otherwise keep streaming
      // and its next event/persist would resurrect the entry just cleared.
      try {
        final tasks = await AndroidNativeDownloader.queryTasks();
        for (final t in tasks) {
          final id = (t['taskId'] ?? '').toString();
          if (id.isEmpty) continue;
          if ((t['status'] ?? '').toString() == 'running') {
            await AndroidNativeDownloader.cancel(id);
          } else {
            await AndroidNativeDownloader.forgetTask(id);
          }
        }
      } catch (_) {}
      AndroidDownloadHistory.instance.clearAll();
    } else {
      // Best-effort clear of non-Android plugin DB
      try {
        final all = await FileDownloader().database.allRecords();
        for (final r in all) {
          await FileDownloader().database.deleteRecordWithId(r.taskId);
        }
      } catch (_) {}
    }
  }

  Future<void> _persistPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _pending
          .map(
            (p) => {
              'queuedId': p.queuedId,
              'url': p.url,
              'providedFileName': p.providedFileName,
              'headers': p.headers,
              'wifiOnly': p.wifiOnly,
              'retries': p.retries,
              'meta': p.meta,
              'torrentName': p.torrentName,
              'contentKey': p.contentKey,
              'destPath': p.destPath,
              'relativeSubDir': p.relativeSubDir,
              'treeUri': p.treeUri,
            },
          )
          .toList();
      await prefs.setString(_pendingKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _persistPaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pausedPending.isEmpty) {
        await prefs.remove(_pausedKey);
        return;
      }
      final data = _pausedPending.values
          .map(
            (p) => {
              'queuedId': p.queuedId,
              'url': p.url,
              'providedFileName': p.providedFileName,
              'headers': p.headers,
              'wifiOnly': p.wifiOnly,
              'retries': p.retries,
              'meta': p.meta,
              'torrentName': p.torrentName,
              'contentKey': p.contentKey,
              'destPath': p.destPath,
              'relativeSubDir': p.relativeSubDir,
              'treeUri': p.treeUri,
            },
          )
          .toList();
      await prefs.setString(_pausedKey, jsonEncode(data));
    } catch (_) {}
  }

  _PendingRequest? _pendingFromStoredMap(Map<String, dynamic> item) {
    final queuedId = (item['queuedId'] ?? '') as String;
    final url = (item['url'] ?? '') as String;
    if (queuedId.isEmpty || url.isEmpty) return null;
    final providedFileName = item['providedFileName'] as String?;
    final meta = item['meta'] as String?;
    final torrentName = item['torrentName'] as String?;
    final headers = (item['headers'] as Map?)?.cast<String, String>();
    final wifiOnly = (item['wifiOnly'] as bool?) ?? false;
    final retries = (item['retries'] as int?) ?? 3;
    final contentKey =
        (item['contentKey'] as String?) ??
        _computeContentKey(meta, url, providedFileName, torrentName);
    return _PendingRequest(
      queuedId: queuedId,
      url: url,
      providedFileName: providedFileName,
      headers: headers,
      wifiOnly: wifiOnly,
      retries: retries,
      meta: meta,
      context: null,
      torrentName: torrentName,
      contentKey: contentKey,
      destPath: item['destPath'] as String?,
      relativeSubDir: item['relativeSubDir'] as String?,
      treeUri: item['treeUri'] as String?,
    );
  }

  _PendingRequest? _pendingFromRecordData(
    String recordId,
    Map<String, dynamic> rec,
  ) {
    final url = (rec['url'] ?? '') as String;
    if (url.isEmpty) return null;
    final displayName = rec['displayName'] as String?;
    final meta = rec['meta'] as String?;
    final torrentName = rec['torrentName'] as String?;
    final headers = (rec['headers'] as Map?)?.cast<String, String>();
    final wifiOnly = (rec['wifiOnly'] as bool?) ?? false;
    final retries = (rec['retries'] as int?) ?? 3;
    final contentKey =
        (rec['contentKey'] as String?) ??
        _computeContentKey(meta, url, displayName, torrentName);
    return _PendingRequest(
      queuedId: recordId,
      url: url,
      providedFileName: displayName,
      headers: headers,
      wifiOnly: wifiOnly,
      retries: retries,
      meta: meta,
      context: null,
      torrentName: torrentName,
      contentKey: contentKey,
      destPath: rec['destPath'] as String?,
      relativeSubDir: rec['relativeSubDir'] as String?,
      treeUri: rec['treeUri'] as String?,
    );
  }

  Future<bool> _queueFromRecord(
    String recordId, {
    required bool paused,
    bool insertFront = true,
  }) async {
    final rec = _records[recordId];
    if (rec == null) return false;
    final pending = _pendingFromRecordData(recordId, rec);
    if (pending == null) return false;

    if (paused) {
      if (_pausedPending.containsKey(recordId)) return true;
      pending.canceled = true;
      _pausedPending[recordId] = pending;
      _upsertRecord(recordId, {'state': 'paused'});

      final downloadTask = DownloadTask(
        taskId: recordId,
        url: pending.url,
        filename: pending.providedFileName ?? 'download',
      );
      if (Platform.isAndroid) {
        AndroidDownloadHistory.instance.upsert(
          downloadTask,
          TaskStatus.paused,
          -5.0,
        );
      } else {
        _nonAndroidQueuedRecords[recordId] = TaskRecord(
          downloadTask,
          TaskStatus.paused,
          -5.0,
          -1,
        );
      }
      _statusController.add(TaskStatusUpdate(downloadTask, TaskStatus.paused));
      await _persistPaused();
      return true;
    }

    if (_pendingById.containsKey(recordId)) return true;
    pending.canceled = false;
    _canceledDuringStart.remove(recordId);
    // Internal re-queue of an existing record: bypass content-key dedup so a
    // retry/resume-fallback can never be silently swallowed.
    final added = _addPendingRequest(
      _pending,
      _pendingById,
      pending,
      atFront: insertFront,
      allowDuplicate: true,
    );
    if (!added) return true; // already queued under this id
    _upsertRecord(recordId, {'state': 'queued'});

    // Visibility: the re-queued item must show up as enqueued in the UI.
    final downloadTask = DownloadTask(
      taskId: recordId,
      url: pending.url,
      filename: pending.providedFileName ?? 'download',
    );
    if (Platform.isAndroid) {
      AndroidDownloadHistory.instance.upsert(
        downloadTask,
        TaskStatus.enqueued,
        0.0,
      );
    } else {
      _nonAndroidQueuedRecords[recordId] = TaskRecord(
        downloadTask,
        TaskStatus.enqueued,
        0.0,
        -1,
      );
    }
    _statusController.add(TaskStatusUpdate(downloadTask, TaskStatus.enqueued));
    await _persistPending();
    return true;
  }

  Future<void> _restorePaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pausedKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      _pausedPending.clear();
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final pending = _pendingFromStoredMap(item);
        if (pending == null) continue;
        final rec = _records[pending.queuedId];
        if (rec != null && rec['state'] == 'canceled') {
          continue;
        }
        _pausedPending[pending.queuedId] = pending;
        final downloadTask = DownloadTask(
          taskId: pending.queuedId,
          url: pending.url,
          filename: pending.providedFileName ?? 'download',
        );
        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance.upsert(
            downloadTask,
            TaskStatus.paused,
            -5.0,
          );
        } else {
          _nonAndroidQueuedRecords[pending.queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.paused,
            -5.0,
            -1,
          );
        }
        _statusController.add(
          TaskStatusUpdate(downloadTask, TaskStatus.paused),
        );
      }
      await _persistPaused();
    } catch (_) {}
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return;
      debugPrint('DL INIT: restoring pending queue from prefs');
      final list = jsonDecode(raw);
      if (list is! List) return;
      debugPrint('DL INIT: pending entries found=${list.length}');
      final Set<String> seenKeys = {};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final pending = _pendingFromStoredMap(item);
        if (pending == null) continue;
        final queuedId = pending.queuedId;
        if (_pausedPending.containsKey(queuedId)) {
          continue;
        }
        final rec = _records[queuedId];
        if (rec != null && rec['state'] == 'canceled') {
          debugPrint('DL INIT: skipping canceled pending queuedId=$queuedId');
          continue;
        }
        if (pending.contentKey.isNotEmpty &&
            seenKeys.contains(pending.contentKey)) {
          debugPrint(
            'DL INIT: skipping duplicate pending contentKey=${pending.contentKey}',
          );
          continue;
        }
        final downloadTask = DownloadTask(
          taskId: queuedId,
          url: pending.url,
          filename: pending.providedFileName ?? 'download',
        );
        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance.upsert(
            downloadTask,
            TaskStatus.enqueued,
            0.0,
          );
        } else {
          _nonAndroidQueuedRecords[queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.enqueued,
            0.0,
            -1,
          );
        }
        _statusController.add(
          TaskStatusUpdate(downloadTask, TaskStatus.enqueued),
        );
        _addPendingRequest(_pending, _pendingById, pending, atFront: false);
        if (pending.contentKey.isNotEmpty) {
          seenKeys.add(pending.contentKey);
        }
        debugPrint(
          'DL INIT: restored pending queuedId=$queuedId name=${pending.providedFileName ?? 'download'}',
        );
      }
      await _persistPending();
    } catch (_) {}
  }

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
        proceed =
            await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: const Color(0xFF0B1220),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (ctx) {
                final kb = MediaQuery.of(ctx).viewInsets.bottom;
                return Padding(
                  padding: EdgeInsets.only(bottom: kb),
                  child: SafeArea(
                    top: false,
                    child: StatefulBuilder(
                      builder: (ctx2, setLocal) {
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
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.battery_saver,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Allow background downloads',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'To keep downloads running reliably in the background, allow the app to ignore battery optimizations.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Keeps long downloads alive',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'You can change this later in system settings',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Checkbox(
                                    value: dontAskAgain,
                                    onChanged: (v) => setLocal(
                                      () => dontAskAgain = v ?? false,
                                    ),
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
                                        choice = dontAskAgain
                                            ? 'never'
                                            : 'denied';
                                        Navigator.of(ctx2).pop(false);
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0xFF334155),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
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
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        backgroundColor: const Color(
                                          0xFF6366F1,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        elevation: 2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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
      final ok =
          await AndroidNativeDownloader.requestIgnoreBatteryOptimizationsForApp();
      if (ok) {
        await StorageService.setBatteryOptimizationStatus('granted');
        return true;
      } else {
        await StorageService.setBatteryOptimizationStatus('denied');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You can enable background downloads later in Settings.',
              ),
            ),
          );
        }
        return true; // do not block downloads
      }
    } catch (_) {
      return true; // don't block if something goes wrong
    }
  }

  Future<void> initialize() async {
    if (_started) return;
    if (_initializing) return;
    _initializing = true;

    await _ensureNotificationPermission();
    // Track connectivity for transient handling and auto-resume
    final initial = await Connectivity().checkConnectivity();
    _net = _computeEffectiveNet(initial);
    _netSub ??= Connectivity().onConnectivityChanged.listen((results) async {
      _net = _computeEffectiveNet(results);
      // On valid connectivity, nudge scheduler to resume paused items
      if (_net != ConnectivityResult.none) {
        if (Platform.isAndroid) {
          final paused = AndroidDownloadHistory.instance
              .all()
              .where((r) => r.status == TaskStatus.paused)
              .map((r) => r.taskId)
              // Queue-managed entries (pending/paused-queued placeholders)
              // are owned by the scheduler, not the native resume path.
              .where(
                (id) =>
                    !_pendingById.containsKey(id) &&
                    !_pausedPending.containsKey(id),
              )
              .toList(growable: false);
          int scheduled = 0;
          for (final id in paused) {
            if (!_pendingResumeAndroid.contains(id)) {
              _pendingResumeAndroid.add(id);
              scheduled++;
            }
          }
          debugPrint('NET OK → scheduled resume $scheduled tasks');
        }
        unawaited(_reevaluateQueue());
      }
    });

    if (Platform.isAndroid) {
      await AndroidDownloadHistory.instance.initialize();
      _androidEventsSub = AndroidNativeDownloader.events.listen((event) async {
        final type = event['type'] as String?;
        final String taskId = (event['taskId'] ?? '').toString();
        if (taskId.startsWith(AndroidNativeDownloader.updateTaskPrefix)) {
          return;
        }
        final task = DownloadTask(
          taskId: taskId,
          url: event['url'] ?? '',
          filename: event['fileName'] ?? 'download',
        );
        final String? recId = _resolveRecordIdForTaskId(taskId);
        switch (type) {
          case 'started':
            // Never regress progress: an out-of-order 'started' (or an
            // adopt-restart of a partially downloaded task) must not clobber
            // a known progress value back to 0.
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.running,
              _preservedProgress(taskId),
            );
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            if (recId != null)
              _upsertRecord(recId, {
                'state': 'running',
                'pluginTaskId': taskId,
              });
            break;
          case 'progress':
            final total = (event['total'] as num?)?.toInt() ?? 0;
            final bytes = (event['bytes'] as num?)?.toInt() ?? 0;
            // Fresh progress past the last-error baseline means the refreshed
            // link genuinely works — only then reset the refresh budget.
            final baseline = _bytesAtLastError[taskId];
            if (baseline != null && bytes > baseline + _refreshResetFreshBytes) {
              _linkRefreshAttempts.remove(taskId);
              _bytesAtLastError.remove(taskId);
            }
            final prog = total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.running,
              prog,
              expectedFileSize: total,
            );
            _progressController.add(TaskProgressUpdate(task, prog));
            _bytesController.add(
              AndroidBytesProgress(
                taskId: taskId,
                bytes: bytes,
                total: total > 0 ? total : -1,
              ),
            );
            break;
          case 'paused':
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.paused,
              -5.0,
            );
            _statusController.add(TaskStatusUpdate(task, TaskStatus.paused));
            if (recId != null) _upsertRecord(recId, {'state': 'paused'});
            // Paused frees a slot; try to start next
            _reevaluateQueue();
            break;
          case 'resumed':
            // A revive-from-store resume is exactly the partial-bytes case —
            // keep the known progress instead of flashing back to 0%.
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.running,
              _preservedProgress(taskId),
            );
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            if (recId != null) _upsertRecord(recId, {'state': 'running'});
            break;
          case 'canceled':
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.canceled,
              -2.0,
            );
            _statusController.add(TaskStatusUpdate(task, TaskStatus.canceled));
            _lastFileByTaskId.remove(taskId);
            if (recId != null) _upsertRecord(recId, {'state': 'canceled'});
            _reevaluateQueue();
            break;
          case 'complete':
            AndroidDownloadHistory.instance.upsert(
              task,
              TaskStatus.complete,
              1.0,
            );
            _statusController.add(TaskStatusUpdate(task, TaskStatus.complete));
            final uri = (event['contentUri'] ?? '').toString();
            final mime = (event['mimeType'] ?? 'application/octet-stream')
                .toString();
            if (uri.isNotEmpty) {
              _lastFileByTaskId[taskId] = (uri, mime);
            }
            if (recId != null) _upsertRecord(recId, {'state': 'complete'});
            _reevaluateQueue();
            break;
          case 'error':
            // Classify with immediate connectivity read; be transient-default safe
            ConnectivityResult nowNet;
            try {
              final nowList = await Connectivity().checkConnectivity();
              nowNet = _computeEffectiveNet(nowList);
            } catch (_) {
              nowNet = _net; // fallback to cached
            }
            final bool cachedNone = _net == ConnectivityResult.none;
            final bool nowNone = nowNet == ConnectivityResult.none;
            if (nowNone || cachedNone) {
              debugPrint(
                'ANDR ERR net=${nowNone ? 'none' : _net.name} → paused',
              );
              AndroidDownloadHistory.instance.upsert(
                task,
                TaskStatus.paused,
                -5.0,
              );
              _statusController.add(TaskStatusUpdate(task, TaskStatus.paused));
              if (recId != null) _upsertRecord(recId, {'state': 'paused'});
              _lastFileByTaskId.remove(taskId);
              _reevaluateQueue();
            } else {
              // Network is online: the native side already retried transient
              // errors, so this is usually an expired debrid link. Refresh it
              // (RD/Torbox/PikPak) and restart under the SAME task id so the
              // partial bytes on disk are resumed.
              _lastFileByTaskId.remove(taskId);
              final httpCode = (event['httpCode'] as num?)?.toInt();
              final errorBytes = (event['bytes'] as num?)?.toInt() ?? 0;
              unawaited(() async {
                final retried = await _handleAndroidErrorRetry(
                  recId,
                  taskId,
                  httpCode,
                  errorBytes,
                );
                if (!retried) {
                  debugPrint('ANDR ERR net=${nowNet.name} → failed');
                  AndroidDownloadHistory.instance.upsert(
                    task,
                    TaskStatus.failed,
                    -1.0,
                  );
                  _statusController.add(
                    TaskStatusUpdate(task, TaskStatus.failed),
                  );
                  if (recId != null) _upsertRecord(recId, {'state': 'failed'});
                }
                _reevaluateQueue();
              }());
            }
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
                await FileDownloader().database.deleteRecordWithId(
                  update.task.taskId,
                );
              } catch (_) {}
            }
            if (update.status == TaskStatus.failed) {
              // Try PikPak cold storage retry before giving up
              final recId = _resolveRecordIdForTaskId(update.task.taskId);
              unawaited(() async {
                final retried = await _handlePikPakFailedRetry(recId);
                if (retried) {
                  // Clean up the failed task record from plugin
                  try {
                    await FileDownloader().database.deleteRecordWithId(
                      update.task.taskId,
                    );
                  } catch (_) {}
                }
                _reevaluateQueue();
              }());
            } else if (update.status == TaskStatus.complete ||
                update.status == TaskStatus.canceled ||
                update.status == TaskStatus.paused) {
              _reevaluateQueue();
            }
        }
      });
      await FileDownloader().trackTasks();
      await FileDownloader().resumeFromBackground();
    }

    // Restore any pending queue persisted from a previous run
    await _loadRecords();
    await _restorePaused();
    await _restorePending();
    debugPrint('DL INIT: loaded records count=${_records.length}');
    // On non-Android: try to resume tasks on startup
    if (!Platform.isAndroid) {
      final records = await FileDownloader().database.allRecords();
      debugPrint('DL INIT: plugin records count=${records.length}');
      // Build reverse map: pluginTaskId -> recordId
      final Map<String, String> recordIdByPluginId = {};
      for (final e in _records.entries) {
        final pluginId = (e.value['pluginTaskId'] ?? '') as String;
        if (pluginId.isNotEmpty) recordIdByPluginId[pluginId] = e.key;
      }
      for (final r in records) {
        final task = r.task as DownloadTask;
        final recordId = recordIdByPluginId[task.taskId] ?? task.taskId;
        final rec = _records[recordId];
        final String? meta = rec != null ? (rec['meta'] as String?) : null;
        final String? displayName = rec != null
            ? (rec['displayName'] as String?)
            : null;
        final String? url = rec != null ? (rec['url'] as String?) : null;
        final String? torrentName = rec != null
            ? (rec['torrentName'] as String?)
            : null;

        Future<void> reenqueueFromMeta({bool insertFront = true}) async {
          debugPrint(
            'DL INIT: re-enqueue from meta for taskId=${task.taskId} name=$displayName',
          );
          if (await _queueFromRecord(
            recordId,
            paused: false,
            insertFront: insertFront,
          )) {
            return;
          }
          if (meta != null) {
            final ck = _computeContentKey(
              meta,
              url ?? '',
              displayName,
              torrentName,
            );
            final bool dup = _pending.any((p) => p.contentKey == ck);
            if (!dup) {
              await enqueueDownload(
                url: url ?? '',
                fileName: displayName,
                meta: meta,
                torrentName: torrentName,
                insertAtFront: insertFront,
                destPath: rec?['destPath'] as String?,
                relativeSubDir: rec?['relativeSubDir'] as String?,
              );
            } else {
              debugPrint('DL INIT: skip re-enqueue duplicate contentKey=$ck');
            }
          }
        }

        if (r.status == TaskStatus.paused || r.status == TaskStatus.enqueued) {
          final canResume = await FileDownloader().taskCanResume(task);
          debugPrint(
            'DL INIT: taskId=${task.taskId} status=${r.status} canResume=$canResume',
          );
          bool resumed = false;
          if (canResume) {
            try {
              await FileDownloader().resume(task);
              debugPrint('DL INIT: resumed taskId=${task.taskId}');
              resumed = true;
            } catch (e) {
              debugPrint(
                'DL INIT: resume failed for taskId=${task.taskId} error=$e',
              );
            }
          }
          if (!resumed) {
            // Cancel and delete stale record to free capacity
            try {
              await FileDownloader().cancel(task);
            } catch (_) {}
            try {
              await FileDownloader().database.deleteRecordWithId(task.taskId);
            } catch (_) {}
            final queued = await _queueFromRecord(
              recordId,
              paused: r.status == TaskStatus.paused,
              insertFront: true,
            );
            if (!queued) {
              await reenqueueFromMeta(insertFront: true);
            }
          }
        } else if (r.status == TaskStatus.running) {
          // Nudge running tasks to ensure the plugin is actually progressing; if not resumable, re-enqueue
          final canResume = await FileDownloader().taskCanResume(task);
          debugPrint(
            'DL INIT: running taskId=${task.taskId} canResume=$canResume',
          );
          bool resumed = false;
          if (canResume) {
            try {
              await FileDownloader().resume(task);
              debugPrint('DL INIT: resumed running taskId=${task.taskId}');
              resumed = true;
            } catch (e) {
              debugPrint(
                'DL INIT: resume running failed taskId=${task.taskId} error=$e',
              );
            }
          }
          if (!resumed) {
            // Cancel and delete stale record to free capacity
            try {
              await FileDownloader().cancel(task);
            } catch (_) {}
            try {
              await FileDownloader().database.deleteRecordWithId(task.taskId);
            } catch (_) {}
            final queued = await _queueFromRecord(
              recordId,
              paused: false,
              insertFront: true,
            );
            if (!queued) {
              await reenqueueFromMeta(insertFront: true);
            }
          }
        }
      }
    }
    // On Android: reconcile Dart records/history against native truth (the
    // service's persistent store + live registry) — adopts survivors of
    // process death into the SAME records instead of re-enqueueing ghosts —
    // then seed resumable tasks into the scheduler.
    if (Platform.isAndroid) {
      await _reconcileWithNative();
      final hist = AndroidDownloadHistory.instance.all();
      int seeded = 0;
      for (final r in hist) {
        if (r.status == TaskStatus.paused || r.status == TaskStatus.enqueued) {
          if (!_pendingById.containsKey(r.taskId) &&
              !_pausedPending.containsKey(r.taskId) &&
              !_pendingResumeAndroid.contains(r.taskId)) {
            _pendingResumeAndroid.add(r.taskId);
            seeded++;
          }
        }
      }
      if (seeded > 0)
        debugPrint('DL INIT: android seeded $seeded tasks for resume');
    }
    _started = true;
    _initializing = false;
    // Kick the scheduler once at startup in case capacity is free
    unawaited(_reevaluateQueue());
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
    final String dir = path.join(downloadsRoot, folder);
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
    bool insertAtFront = false,
    String? destPath,
    String? relativeSubDir,
  }) async {
    await initialize();

    // Always queue first, then start based on concurrency limit
    final providedName = (fileName?.trim().isNotEmpty ?? false)
        ? _sanitizeName(fileName!.trim())
        : null;

    // One identity end-to-end: this id is the durable record key AND the
    // native task id (start-or-adopt on the service side), so reconciliation
    // never has to correlate two id spaces. The monotonic suffix prevents
    // same-millisecond collisions that used to silently overwrite records.
    final String queuedId =
        'dl-${DateTime.now().millisecondsSinceEpoch}-${_idSeq++}';

    // Custom download location (SAF): captured at enqueue time and persisted
    // per-download, so in-flight downloads keep their original destination
    // even if the preference changes later.
    String? treeUri;
    if (Platform.isAndroid) {
      try {
        final saved = await StorageService.getDownloadTreeUri();
        if (saved != null && saved.isNotEmpty) {
          if (await _validateTreeUriCached(saved)) {
            treeUri = saved;
          } else {
            // Grant lost (SD card ejected/reformatted, folder deleted):
            // fall back to the default location and clear the stale pref.
            debugPrint(
              'DL: custom download folder grant lost; falling back to default',
            );
            await StorageService.clearDownloadTreeUri();
          }
        }
      } catch (_) {}
    }
    final String displayName =
        providedName ??
        (() {
          try {
            final uri = Uri.parse(url);
            return _sanitizeName(
              uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file',
            );
          } catch (_) {
            return 'file';
          }
        })();

    final queuedTask = DownloadTask(
      taskId: queuedId,
      url: url,
      filename: displayName,
    );

    if (Platform.isAndroid) {
      AndroidDownloadHistory.instance.upsert(
        queuedTask,
        TaskStatus.enqueued,
        0.0,
      );
    } else {
      _nonAndroidQueuedRecords[queuedId] = TaskRecord(
        queuedTask,
        TaskStatus.enqueued,
        0.0,
        -1,
      );
    }
    _statusController.add(TaskStatusUpdate(queuedTask, TaskStatus.enqueued));

    // Persist a durable record for richer recovery
    final contentKey = _computeContentKey(meta, url, displayName, torrentName);
    _upsertRecord(queuedId, {
      'id': queuedId,
      'url': url,
      'displayName': displayName,
      'state': 'queued',
      'meta': meta,
      'torrentName': torrentName,
      'contentKey': contentKey,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'wifiOnly': wifiOnly,
      'retries': retries,
      'headers': headers,
      if (destPath != null) 'destPath': destPath,
      if (relativeSubDir != null) 'relativeSubDir': relativeSubDir,
      if (treeUri != null) 'treeUri': treeUri,
    });

    // Add to in-memory pending queue (prevent duplicates by contentKey)
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
      contentKey: contentKey,
      destPath: destPath,
      relativeSubDir: relativeSubDir,
      treeUri: treeUri,
    );
    final added = _addPendingRequest(
      _pending,
      _pendingById,
      pending,
      atFront: insertAtFront,
    );
    if (!added) {
      // Dedup suppressed the enqueue (same content already queued): roll back
      // the record and placeholder created above, or they'd sit as a
      // permanent "queued" ghost no scheduler entry ever starts.
      _records.remove(queuedId);
      unawaited(_saveRecords());
      if (Platform.isAndroid) {
        AndroidDownloadHistory.instance.removeById(queuedId);
      } else {
        _nonAndroidQueuedRecords.remove(queuedId);
      }
      _statusController.add(TaskStatusUpdate(queuedTask, TaskStatus.canceled));
      return DownloadEntry(
        task: queuedTask,
        displayName: displayName,
        directory: '',
      );
    }
    await _persistPending();

    // Try to start if capacity allows
    unawaited(_reevaluateQueue());

    return DownloadEntry(
      task: queuedTask,
      displayName: displayName,
      directory: '',
    );
  }

  Future<void> pause(Task task) async {
    // A queued item (not yet started) has no native task — pausing it means
    // parking it in the paused queue, or it would start anyway moments later.
    if (_pendingById.containsKey(task.taskId)) {
      await pauseQueuedTasksByIds([task.taskId]);
      return;
    }
    if (_pausedPending.containsKey(task.taskId)) return; // already paused
    if (Platform.isAndroid) {
      // The native channel can't report "unknown task" (the intent dispatch
      // always succeeds), so ownership is decided HERE: a record still in
      // 'queued' state is scheduler-owned — possibly mid-start inside the
      // drain's multi-second link refresh — and must be parked in the paused
      // queue, or the drain would start it anyway and ignore the pause.
      final recId = _resolveRecordIdForTaskId(task.taskId);
      final recState = recId != null
          ? (_records[recId]?['state'] ?? '').toString()
          : '';
      if (recState == 'queued') {
        _canceledDuringStart.add(task.taskId);
        await _queueFromRecord(recId!, paused: true);
        return;
      }
      // Native-owned (running, or persisted from a killed process): the
      // service pauses it (reconstructing from its store when needed) and
      // confirms with a 'paused' event.
      await AndroidNativeDownloader.pause(task.taskId);
      return;
    }
    if (task is DownloadTask) {
      await FileDownloader().pause(task);
    }
  }

  Future<bool> resume(Task task) async {
    // A paused-queued item resumes by rejoining the queue, not via native.
    if (_pausedPending.containsKey(task.taskId)) {
      await resumeQueuedTasksByIds([task.taskId]);
      return true;
    }
    _canceledDuringStart.remove(task.taskId);
    // Enforce concurrency: if at capacity, queue the resume
    final int maxParallel = await StorageService.getMaxParallelDownloads();
    int runningCount;
    if (Platform.isAndroid) {
      final list = AndroidDownloadHistory.instance.all();
      runningCount = list.where((r) => r.status == TaskStatus.running).length;
      if (runningCount >= maxParallel) {
        _pendingResumeAndroid.add(task.taskId);
        // Show as queued
        AndroidDownloadHistory.instance.upsert(
          task as DownloadTask,
          TaskStatus.enqueued,
          0.0,
        );
        _statusController.add(TaskStatusUpdate(task, TaskStatus.enqueued));
        unawaited(_reevaluateQueue());
        return true;
      }
      // Plain native resume first (cheap: uses the stored URL; the service
      // reconstructs from its persistent store if its memory is gone). If the
      // stored link has expired, the resulting error event goes through
      // _handleAndroidErrorRetry which refreshes the link and re-adopts.
      bool ok = await AndroidNativeDownloader.resume(task.taskId);
      if (!ok) {
        // Native knows nothing about this task at all. Try a link-refresh
        // start-or-adopt (same id, resumes on-disk bytes); as a last resort
        // hand it to the scheduler's resume set so SOMETHING owns it instead
        // of it stranding as "enqueued" forever.
        final recId = _resolveRecordIdForTaskId(task.taskId);
        final metaStr = recId != null
            ? (_records[recId]?['meta'] as String?)
            : null;
        final fresh = await _refreshUrlFromMeta(metaStr);
        if (fresh != null) {
          ok = await _startAdoptAndroid(task.taskId, url: fresh.url);
        }
        if (!ok) {
          _pendingResumeAndroid.add(task.taskId);
          AndroidDownloadHistory.instance.upsert(
            task as DownloadTask,
            TaskStatus.enqueued,
            0.0,
          );
          _statusController.add(TaskStatusUpdate(task, TaskStatus.enqueued));
          unawaited(_reevaluateQueue());
        }
      }
      return ok;
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
      // Not resumable (no resume data): don't dead-end the tap — restart the
      // download from its durable record instead of silently doing nothing.
      final recId = _resolveRecordIdForTaskId(task.taskId);
      if (recId != null && await _queueFromRecord(recId, paused: false)) {
        try {
          await FileDownloader().database.deleteRecordWithId(task.taskId);
        } catch (_) {}
        unawaited(_reevaluateQueue());
        return true;
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
        _upsertRecord(pending.queuedId, {'state': 'canceled'});
        _canceledDuringStart.add(pending.queuedId);
      } else {
        _upsertRecord(task.taskId, {'state': 'canceled'});
      }
      if (Platform.isAndroid) {
        AndroidDownloadHistory.instance.removeById(task.taskId);
        _statusController.add(
          TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled),
        );
      } else {
        _nonAndroidQueuedRecords.remove(task.taskId);
        _statusController.add(
          TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled),
        );
      }
      unawaited(_reevaluateQueue());
      await _persistPending();
      return;
    }

    final pausedPending = _pausedPending.remove(task.taskId);
    if (pausedPending != null) {
      final canceledTask = DownloadTask(
        taskId: pausedPending.queuedId,
        url: pausedPending.url,
        filename: (pausedPending.providedFileName?.isNotEmpty ?? false)
            ? pausedPending.providedFileName!
            : 'download',
      );

      if (Platform.isAndroid) {
        AndroidDownloadHistory.instance.removeById(pausedPending.queuedId);
      } else {
        _nonAndroidQueuedRecords.remove(pausedPending.queuedId);
      }

      _statusController.add(
        TaskStatusUpdate(canceledTask, TaskStatus.canceled),
      );
      _upsertRecord(pausedPending.queuedId, {'state': 'canceled'});
      _canceledDuringStart.remove(pausedPending.queuedId);
      await _persistPaused();
      return;
    }

    if (Platform.isAndroid) {
      // If already canceled/complete/failed in history, avoid native calls
      final hist = AndroidDownloadHistory.instance.all().firstWhere(
        (r) => r.taskId == task.taskId,
        orElse: () =>
            TaskRecord(task as DownloadTask, TaskStatus.notFound, 0.0, -1),
      );
      if (hist.status == TaskStatus.canceled ||
          hist.status == TaskStatus.complete ||
          hist.status == TaskStatus.failed) {
        AndroidDownloadHistory.instance.removeById(task.taskId);
        _statusController.add(
          TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled),
        );
        final recId = _resolveRecordIdForTaskId(task.taskId);
        if (recId != null) _upsertRecord(recId, {'state': 'canceled'});
        // Failed tasks keep a native store entry (for resume); a cancel is
        // the user saying "let it go" — purge it so it can't be adopted.
        unawaited(AndroidNativeDownloader.forgetTask(task.taskId));
        return;
      }
      bool ok = false;
      try {
        ok = await AndroidNativeDownloader.cancel(task.taskId);
      } catch (_) {}
      if (!ok) {
        // The cancel command never reached the service. Check native truth:
        // if the task is still alive there, retry once rather than locally
        // marking canceled while native keeps downloading (resurrection).
        try {
          final tasks = await AndroidNativeDownloader.queryTasks();
          final alive = tasks.any(
            (t) => (t['taskId'] ?? '').toString() == task.taskId,
          );
          if (alive) {
            await AndroidNativeDownloader.cancel(task.taskId);
          }
        } catch (_) {}
      }
      _canceledDuringStart.add(task.taskId);
      AndroidDownloadHistory.instance.removeById(task.taskId);
      _statusController.add(
        TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled),
      );
      final recId = _resolveRecordIdForTaskId(task.taskId);
      if (recId != null) {
        _upsertRecord(recId, {'state': 'canceled'});
      } else {
        _upsertRecord(task.taskId, {'state': 'canceled'});
      }
      return;
    }
    await FileDownloader().cancel(task as DownloadTask);
    try {
      await FileDownloader().database.deleteRecordWithId(task.taskId);
    } catch (_) {}
    _upsertRecord(task.taskId, {'state': 'canceled'});
  }

  // For backward UI compatibility; on Android, we don’t maintain a DB of records
  Future<List<TaskRecord>> allRecords() async {
    if (Platform.isAndroid) {
      return AndroidDownloadHistory.instance.all();
    }
    final dbRecords = await FileDownloader().database.allRecords();
    // Overlay queued placeholders and queued-resume status
    if (_nonAndroidQueuedRecords.isEmpty &&
        _nonAndroidResumeQueuedOverlay.isEmpty)
      return dbRecords;
    final List<TaskRecord> adjusted = dbRecords.map((r) {
      if (_nonAndroidResumeQueuedOverlay.contains(r.taskId)) {
        return TaskRecord(
          r.task,
          TaskStatus.enqueued,
          r.progress,
          r.expectedFileSize,
        );
      }
      return r;
    }).toList();
    int rank(TaskStatus s) {
      switch (s) {
        case TaskStatus.running:
          return 0;
        case TaskStatus.enqueued:
          return 1;
        case TaskStatus.paused:
          return 2;
        case TaskStatus.waitingToRetry:
          return 3;
        case TaskStatus.complete:
          return 4;
        case TaskStatus.canceled:
          return 5;
        case TaskStatus.failed:
          return 6;
        case TaskStatus.notFound:
          return 7;
      }
    }

    final merged = [..._nonAndroidQueuedRecords.values, ...adjusted];
    merged.sort((a, b) {
      final ranked = rank(a.status).compareTo(rank(b.status));
      if (ranked != 0) return ranked;
      return b.task.creationTime.compareTo(a.task.creationTime);
    });
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
    if (Platform.isWindows || Platform.isMacOS) {
      // On macOS, use the user's actual Downloads folder
      try {
        final Directory? downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          if (Platform.isWindows) {
            final Directory appDownloadsDir = Directory(
              path.join(downloadsDir.path, 'Debrify'),
            );
            if (!await appDownloadsDir.exists()) {
              await appDownloadsDir.create(recursive: true);
            }
            return appDownloadsDir;
          }
          return downloadsDir;
        }
      } catch (e) {
        // Fallback to app documents if Downloads directory is not accessible
      }
    }
    return Directory((await getApplicationDocumentsDirectory()).path);
  }

  Future<String> _appDownloadsSubdir() async {
    if (Platform.isWindows || Platform.isMacOS) {
      // On macOS, use the user's actual Downloads folder
      try {
        final Directory? downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          // Create a subfolder for the app to organize downloads
          final Directory appDownloadsDir = Directory(
            path.join(downloadsDir.path, 'Debrify'),
          );
          if (!await appDownloadsDir.exists()) {
            await appDownloadsDir.create(recursive: true);
          }
          return appDownloadsDir.path;
        }
      } catch (e) {
        // Fallback to app documents if Downloads directory is not accessible
      }
    }

    // Fallback: Use a stable, app-specific downloads directory under Documents
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dlDir = Directory(path.join(docs.path, 'downloads'));
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

  static String _sanitizeRelativePath(String value) {
    return value
        .split(RegExp(r'[\\/]'))
        .map((segment) => _sanitizeName(segment.trim()))
        .where((segment) => segment.isNotEmpty && segment != '.')
        .where((segment) => segment != '..')
        .join(path.separator);
  }

  (String contentUri, String mimeType)? getLastFileForTask(String taskId) =>
      _lastFileByTaskId[taskId];

  /// Handles PikPak cold storage retry for failed downloads.
  /// Returns true if retry was initiated, false if not applicable or max retries exceeded.
  Future<bool> _handlePikPakFailedRetry(String? recId) async {
    if (recId == null) return false;

    final rec = _records[recId];
    if (rec == null) return false;

    final String? metaStr = rec['meta'] as String?;
    if (metaStr == null || metaStr.isEmpty) return false;

    try {
      final meta = jsonDecode(metaStr);
      final isPikPak = meta['pikpakDownload'] == true;
      if (!isPikPak) return false;

      final fileId = meta['pikpakFileId'] as String?;
      if (fileId == null || fileId.isEmpty) return false;

      // PikPak cold storage retry with exponential backoff
      // Same constants as in catch block during start
      const int pikpakMaxColdRetries = 5;
      const int pikpakBaseDelaySeconds = 5;
      const int pikpakMaxDelaySeconds = 30;

      final int coldAttempt = (meta['_pikpakColdAttempt'] as int?) ?? 0;

      if (coldAttempt >= pikpakMaxColdRetries) {
        debugPrint(
          'DL RETRY PIKPAK FAILED: Max cold storage retries ($pikpakMaxColdRetries) exceeded for file $fileId',
        );
        return false;
      }

      // Calculate delay with exponential backoff (capped)
      final int delaySeconds = (pikpakBaseDelaySeconds * (1 << coldAttempt))
          .clamp(pikpakBaseDelaySeconds, pikpakMaxDelaySeconds);

      debugPrint(
        'DL RETRY PIKPAK FAILED: Cold storage attempt ${coldAttempt + 1}/$pikpakMaxColdRetries, waiting ${delaySeconds}s for file $fileId',
      );

      // Wait for cold storage to potentially warm up
      await Future.delayed(Duration(seconds: delaySeconds));

      debugPrint('DL RETRY PIKPAK FAILED: Refreshing URL for file $fileId');

      // Get fresh file details
      final freshData = await PikPakApiService.instance.getFileDetails(fileId);
      final freshUrl = PikPakApiService.instance.getStreamingUrl(freshData);

      if (freshUrl == null || freshUrl.isEmpty) {
        debugPrint('DL RETRY PIKPAK FAILED: Failed to get fresh URL');
        return false;
      }

      // Update meta with incremented cold attempt count
      final updatedMeta = Map<String, dynamic>.from(meta);
      updatedMeta['_pikpakColdAttempt'] = coldAttempt + 1;

      // Re-queue the download
      final displayName = rec['displayName'] as String?;
      final torrentName = rec['torrentName'] as String?;
      final destPath = rec['destPath'] as String?;
      final wifiOnly = rec['wifiOnly'] as bool? ?? false;
      final retries = rec['retries'] as int? ?? 3;

      // Remove old record
      _records.remove(recId);
      await _saveRecords();

      // Enqueue with fresh URL
      await enqueueDownload(
        url: freshUrl,
        fileName: displayName,
        meta: jsonEncode(updatedMeta),
        torrentName: torrentName,
        destPath: destPath,
        relativeSubDir: rec['relativeSubDir'] as String?,
        wifiOnly: wifiOnly,
        retries: retries,
        insertAtFront: true,
      );

      debugPrint(
        'DL RETRY PIKPAK FAILED: Re-queued with fresh URL (attempt ${coldAttempt + 1})',
      );
      return true;
    } catch (e) {
      debugPrint('DL RETRY PIKPAK FAILED: Error during retry: $e');
      return false;
    }
  }

  /// Refreshes an expired debrid link from the record's meta. Returns the
  /// fresh URL (and, when the provider reports one, the real filename), or
  /// null when meta is absent/unsupported or the refresh failed.
  ///
  /// Debrid links expire — this is the URL-level recovery half of the retry
  /// split: native retries transient network errors on the SAME url; Dart owns
  /// getting a NEW url (needs API credentials).
  Future<({String url, String? fileName})?> _refreshUrlFromMeta(
    String? metaStr,
  ) async {
    if (metaStr == null || metaStr.isEmpty) return null;
    try {
      final meta = jsonDecode(metaStr);
      if (meta is! Map) return null;

      if (meta['pikpakDownload'] == true) {
        final fileId = (meta['pikpakFileId'] ?? '').toString();
        if (fileId.isEmpty) return null;
        final freshData = await PikPakApiService.instance.getFileDetails(
          fileId,
        );
        final freshUrl = PikPakApiService.instance.getStreamingUrl(freshData);
        if (freshUrl == null || freshUrl.isEmpty) return null;
        return (url: freshUrl, fileName: null);
      }

      final apiKey = (meta['apiKey'] ?? '').toString();
      if (meta['torboxWebDownload'] == true) {
        final webDownloadId = meta['torboxWebDownloadId'] as int?;
        final fileId = meta['torboxFileId'] as int?;
        if (apiKey.isEmpty) return null;
        if (meta['torboxZip'] == true && webDownloadId != null) {
          return (
            url: TorboxService.createWebDownloadZipPermalink(
              apiKey,
              webDownloadId,
            ),
            fileName: null,
          );
        }
        if (webDownloadId != null && fileId != null) {
          final fresh = await TorboxService.requestWebDownloadFileLink(
            apiKey: apiKey,
            webId: webDownloadId,
            fileId: fileId,
          );
          if (fresh.isEmpty) return null;
          return (url: fresh, fileName: null);
        }
        return null;
      }
      if (meta['torboxDownload'] == true) {
        final torrentId = meta['torboxTorrentId'] as int?;
        final fileId = meta['torboxFileId'] as int?;
        if (apiKey.isEmpty) return null;
        if (meta['torboxZip'] == true && torrentId != null) {
          return (
            url: TorboxService.createZipPermalink(apiKey, torrentId),
            fileName: null,
          );
        }
        if (torrentId != null && fileId != null) {
          final fresh = await TorboxService.requestFileDownloadLink(
            apiKey: apiKey,
            torrentId: torrentId,
            fileId: fileId,
          );
          if (fresh.isEmpty) return null;
          return (url: fresh, fileName: null);
        }
        return null;
      }

      // RealDebrid
      final restricted = (meta['restrictedLink'] ?? '').toString();
      if (restricted.isEmpty || apiKey.isEmpty) return null;
      final fresh = await DebridService.unrestrictLink(apiKey, restricted);
      final freshUrl = (fresh['download'] ?? '').toString();
      if (freshUrl.isEmpty) return null;
      final rdName = (fresh['filename'] ?? '').toString();
      return (url: freshUrl, fileName: rdName.isEmpty ? null : rdName);
    } catch (e) {
      debugPrint('DL REFRESH: link refresh failed: $e');
      return null;
    }
  }

  // Short-lived cache for the SAF grant check: bulk-adding a torrent's files
  // must not run one cross-process DocumentsProvider query per file.
  String? _validatedTreeUri;
  DateTime? _validatedTreeUriAt;

  Future<bool> _validateTreeUriCached(String treeUri) async {
    final at = _validatedTreeUriAt;
    if (_validatedTreeUri == treeUri &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 30)) {
      return true;
    }
    final ok = await AndroidNativeDownloader.validateDownloadDirectory(treeUri);
    if (ok) {
      _validatedTreeUri = treeUri;
      _validatedTreeUriAt = DateTime.now();
    } else {
      _validatedTreeUri = null;
      _validatedTreeUriAt = null;
    }
    return ok;
  }

  /// Progress currently shown for [taskId], if any — used so restart/resume
  /// events never regress a partially-downloaded task's bar back to 0%.
  double _preservedProgress(String taskId) {
    final existing = AndroidDownloadHistory.instance.byId(taskId);
    if (existing != null &&
        existing.progress > 0.0 &&
        existing.progress <= 1.0) {
      return existing.progress;
    }
    return 0.0;
  }

  /// The MediaStore-relative folder a record's download belongs in — the same
  /// shape the scheduler's start path computes.
  String _subDirForRecord(Map<String, dynamic>? rec) {
    final torrentName = (rec?['torrentName'] as String?)?.trim() ?? '';
    if (torrentName.isEmpty) return 'Debrify';
    final rel = (rec?['relativeSubDir'] as String?)?.trim() ?? '';
    final sanitizedRel = rel.isNotEmpty ? _sanitizeRelativePath(rel) : '';
    final parts = sanitizedRel.isNotEmpty
        ? ['Debrify', _sanitizeName(torrentName), sanitizedRel]
        : ['Debrify', _sanitizeName(torrentName)];
    return parts.join('/').replaceAll(r'\', '/');
  }

  /// Restart an existing native task under its SAME id with a fresh URL. The
  /// service adopts its persisted state (destination uri, validators) and
  /// resumes from the bytes on disk — no new record, no ghost duplicate.
  Future<bool> _startAdoptAndroid(String taskId, {required String url}) async {
    final recId = _resolveRecordIdForTaskId(taskId);
    final rec = recId != null ? _records[recId] : null;
    final name = (rec?['displayName'] ?? 'download').toString();
    final res = await AndroidNativeDownloader.start(
      taskId: taskId,
      url: url,
      fileName: name,
      // Only consulted when the native store has nothing to adopt (fresh
      // destination) — without it the file would land in the Debrify root
      // instead of its torrent subfolder.
      subDir: _subDirForRecord(rec),
      headers: (rec?['headers'] as Map?)?.cast<String, String>(),
      treeUri: rec?['treeUri'] as String?,
    );
    if (!res.ok) {
      debugPrint(
        'DL ADOPT: start failed for $taskId: ${res.errorCode} ${res.errorMessage}',
      );
      return false;
    }
    final task = DownloadTask(taskId: taskId, url: url, filename: name);
    AndroidDownloadHistory.instance.upsert(
      task,
      TaskStatus.running,
      _preservedProgress(taskId),
    );
    _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
    if (recId != null) {
      _upsertRecord(recId, {
        'state': 'running',
        'pluginTaskId': taskId,
        'url': url,
      });
    }
    return true;
  }

  /// Error-path recovery for a native task that failed while online: refresh
  /// the debrid link and restart under the same task id (resuming the partial
  /// bytes). Returns true when a retry was started.
  Future<bool> _handleAndroidErrorRetry(
    String? recId,
    String taskId,
    int? httpCode,
    int errorBytes,
  ) async {
    // PikPak keeps its dedicated cold-storage ladder.
    if (await _handlePikPakFailedRetry(recId)) return true;
    if (recId == null) return false;
    final rec = _records[recId];
    final metaStr = rec?['meta'] as String?;
    if (metaStr == null || metaStr.isEmpty) return false;
    // Native already retried transient errors, so a refresh only helps when
    // the URL itself is dead: a 4xx (expired debrid link) or a non-HTTP
    // failure. A 5xx that exhausted native retries is a server problem a new
    // link won't fix.
    if (httpCode != null && (httpCode < 400 || httpCode >= 500)) {
      return false;
    }
    final attempts = _linkRefreshAttempts[taskId] ?? 0;
    if (attempts >= _maxLinkRefreshAttempts) {
      debugPrint('DL REFRESH: attempts exhausted for $taskId');
      return false;
    }
    _linkRefreshAttempts[taskId] = attempts + 1;
    // Baseline for the budget reset: only bytes downloaded BEYOND this point
    // prove the refreshed link works.
    _bytesAtLastError[taskId] = errorBytes;
    final fresh = await _refreshUrlFromMeta(metaStr);
    if (fresh == null) return false;
    debugPrint(
      'DL REFRESH: restarting $taskId with fresh link (attempt ${attempts + 1}, httpCode=$httpCode)',
    );
    return _startAdoptAndroid(taskId, url: fresh.url);
  }

  /// Startup reconciliation: adopt native truth (persistent store + live
  /// registry) into history/records, and settle Dart-side entries whose
  /// native task is gone — same record, never a re-enqueued duplicate.
  Future<void> _reconcileWithNative() async {
    if (!Platform.isAndroid) return;
    List<Map<String, dynamic>> tasks;
    try {
      tasks = await AndroidNativeDownloader.queryTasks();
    } catch (_) {
      return;
    }
    final Map<String, Map<String, dynamic>> byId = {
      for (final t in tasks) (t['taskId'] ?? '').toString(): t,
    };
    byId.remove('');

    // 1) Native tasks -> adopt status/bytes into history + records.
    for (final entry in byId.entries) {
      final id = entry.key;
      if (id.startsWith(AndroidNativeDownloader.updateTaskPrefix)) continue;
      final t = entry.value;
      final status = (t['status'] ?? '').toString();
      final bytes = (t['bytes'] as num?)?.toInt() ?? 0;
      final total = (t['total'] as num?)?.toInt() ?? 0;
      final task = DownloadTask(
        taskId: id,
        url: (t['url'] ?? '').toString(),
        filename: (t['fileName'] ?? 'download').toString(),
      );
      final prog = total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0;
      final recId = _resolveRecordIdForTaskId(id);
      switch (status) {
        case 'running':
          AndroidDownloadHistory.instance.upsert(
            task,
            TaskStatus.running,
            prog,
            expectedFileSize: total,
          );
          if (recId != null) _upsertRecord(recId, {'state': 'running'});
          break;
        case 'failed':
          AndroidDownloadHistory.instance.upsert(task, TaskStatus.failed, -1.0);
          if (recId != null) _upsertRecord(recId, {'state': 'failed'});
          break;
        default: // paused (incl. stored-running with no live worker)
          AndroidDownloadHistory.instance.upsert(task, TaskStatus.paused, -5.0);
          if (recId != null) _upsertRecord(recId, {'state': 'paused'});
          break;
      }
      debugPrint('DL RECONCILE: adopted $id status=$status bytes=$bytes');
    }

    // 2) History entries claiming active work that native doesn't know about
    //    (and that aren't queue-managed placeholders) are dead: settle them on
    //    the SAME record — paused when resumable, failed otherwise.
    for (final r in AndroidDownloadHistory.instance.all()) {
      final id = r.taskId;
      if (byId.containsKey(id)) continue;
      if (_pendingById.containsKey(id) ||
          _pausedPending.containsKey(id) ||
          id.startsWith(AndroidNativeDownloader.updateTaskPrefix)) {
        continue;
      }
      if (r.status == TaskStatus.running || r.status == TaskStatus.enqueued) {
        final recId = _resolveRecordIdForTaskId(id);
        final rec = recId != null ? _records[recId] : null;
        final recState = (rec?['state'] ?? '').toString();
        if (recState == 'queued') {
          // Queue-managed; the scheduler owns it.
          continue;
        }
        final hasMeta = ((rec?['meta'] as String?) ?? '').isNotEmpty;
        final settled = hasMeta ? TaskStatus.paused : TaskStatus.failed;
        AndroidDownloadHistory.instance.upsert(
          r.task,
          settled,
          settled == TaskStatus.paused ? -5.0 : -1.0,
        );
        if (recId != null) {
          _upsertRecord(recId, {
            'state': settled == TaskStatus.paused ? 'paused' : 'failed',
          });
        }
        debugPrint('DL RECONCILE: settled dead $id -> ${settled.name}');
      }
    }
  }

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

    // First, process pending resumes up to capacity. One failed resume must
    // NOT abort the drain — each item is handled (resumed, re-queued on its
    // own record, or settled as failed) and the loop continues.
    while (runningCount < maxParallel) {
      if (Platform.isAndroid && _pendingResumeAndroid.isNotEmpty) {
        final taskId = _pendingResumeAndroid.first;
        _pendingResumeAndroid.remove(taskId);
        // Skip if already running (or canceled while waiting)
        final hist = AndroidDownloadHistory.instance.all().firstWhere(
          (r) => r.taskId == taskId,
          orElse: () => TaskRecord(
            DownloadTask(taskId: taskId, url: '', filename: 'download'),
            TaskStatus.notFound,
            0.0,
            -1,
          ),
        );
        if (hist.status == TaskStatus.running ||
            hist.status == TaskStatus.canceled ||
            hist.status == TaskStatus.complete) {
          continue;
        }
        bool ok = false;
        try {
          ok = await AndroidNativeDownloader.resume(taskId);
        } catch (_) {
          ok = false;
        }
        if (!ok) {
          // Native has nothing to adopt. Refresh the link and re-adopt under
          // the same id; else re-queue the SAME record (never a new ghost).
          final recId = _resolveRecordIdForTaskId(taskId);
          final metaStr = recId != null
              ? (_records[recId]?['meta'] as String?)
              : null;
          try {
            final fresh = await _refreshUrlFromMeta(metaStr);
            if (fresh != null) {
              ok = await _startAdoptAndroid(taskId, url: fresh.url);
            }
          } catch (_) {}
          if (!ok && recId != null) {
            if (await _queueFromRecord(recId, paused: false)) {
              debugPrint('DL RESUME-DRAIN: re-queued record $recId');
              continue; // started by the pending drain below
            }
          }
          if (!ok) {
            debugPrint('DL RESUME-DRAIN: could not revive $taskId → failed');
            final failTask = DownloadTask(
              taskId: taskId,
              url: '',
              filename: hist.task.filename,
            );
            AndroidDownloadHistory.instance.upsert(
              failTask,
              TaskStatus.failed,
              -1.0,
            );
            _statusController.add(
              TaskStatusUpdate(failTask, TaskStatus.failed),
            );
            if (recId != null) _upsertRecord(recId, {'state': 'failed'});
            continue;
          }
        }
        runningCount += 1;
        continue;
      } else if (!Platform.isAndroid && _pendingResumeNonAndroid.isNotEmpty) {
        final entry = _pendingResumeNonAndroid.entries.first;
        _pendingResumeNonAndroid.remove(entry.key);
        _nonAndroidResumeQueuedOverlay.remove(entry.key);
        final DownloadTask task = entry.value;
        bool ok = false;
        if (await FileDownloader().taskCanResume(task)) {
          ok = await FileDownloader().resume(task);
        }
        if (ok) {
          runningCount += 1;
        } else {
          // Not resumable: restart from the durable record instead of
          // silently dropping the task from every queue.
          final recId = _resolveRecordIdForTaskId(task.taskId);
          if (recId != null) {
            await _queueFromRecord(recId, paused: false);
          }
        }
        continue;
      }
      break;
    }

    // Start as many as possible
    while (runningCount < maxParallel && _pending.isNotEmpty) {
      var p = _pending.removeAt(0);
      _pendingById.remove(p.queuedId);
      final bool wasCanceled =
          p.canceled || _canceledDuringStart.remove(p.queuedId);
      await _persistPending();
      if (wasCanceled) {
        debugPrint('DL START: skipped canceled pending queuedId=${p.queuedId}');
        continue;
      }
      try {
        // On-demand unrestriction: if URL is restricted, unrestrict it first
        String finalUrl = p.url;
        String finalFileName = p.providedFileName ?? 'download';

        debugPrint('DL START: url=${p.url}, meta=${p.meta}');

        if (p.meta != null && p.meta!.isNotEmpty) {
          try {
            final meta = jsonDecode(p.meta!) as Map<String, dynamic>;

            // CHECK PIKPAK FIRST (before Torbox)
            final isPikPak = meta['pikpakDownload'] == true;
            if (isPikPak) {
              // PikPak: URL already pre-signed, use directly
              finalUrl = p.url;
              finalFileName =
                  (meta['pikpakFileName'] as String?) ??
                  p.providedFileName ??
                  'download';
              debugPrint('DL PIKPAK: Using pre-signed URL');
            } else {
              // EXISTING TORBOX/REALDEBRID LOGIC
              final isTorbox = meta['torboxDownload'] == true;
              final isTorboxWebDownload = meta['torboxWebDownload'] == true;

              if (isTorboxWebDownload) {
                // Torbox web download path
                final apiKey = meta['apiKey'] as String?;
                final webDownloadId = meta['torboxWebDownloadId'] as int?;
                final fileId = meta['torboxFileId'] as int?;
                final isZip = meta['torboxZip'] == true;

                debugPrint(
                  'DL TORBOX WEB: webDownloadId=$webDownloadId, fileId=$fileId, isZip=$isZip, apiKey=${apiKey?.isNotEmpty ?? false ? "present" : "missing"}',
                );

                if (apiKey == null || apiKey.isEmpty) {
                  debugPrint('DL ERROR: Torbox web download missing API key');
                  throw Exception('Torbox web download missing API key');
                }

                if (isZip) {
                  // ZIP download - use permalink
                  if (webDownloadId == null) {
                    debugPrint(
                      'DL ERROR: Torbox web download ZIP missing webDownloadId',
                    );
                    throw Exception(
                      'Torbox web download ZIP missing webDownloadId',
                    );
                  }
                  finalUrl = TorboxService.createWebDownloadZipPermalink(
                    apiKey,
                    webDownloadId,
                  );
                  debugPrint(
                    'DL TORBOX WEB ZIP: Generated permalink: $finalUrl',
                  );
                } else {
                  // Regular file download
                  if (webDownloadId == null || fileId == null) {
                    debugPrint(
                      'DL ERROR: Torbox web download missing webDownloadId or fileId',
                    );
                    throw Exception(
                      'Torbox web download missing webDownloadId or fileId',
                    );
                  }
                  debugPrint(
                    'DL TORBOX WEB: Requesting download link for file $fileId in web download $webDownloadId',
                  );
                  finalUrl = await TorboxService.requestWebDownloadFileLink(
                    apiKey: apiKey,
                    webId: webDownloadId,
                    fileId: fileId,
                  );
                  debugPrint(
                    'DL TORBOX WEB SUCCESS: Got download URL: ${finalUrl.substring(0, finalUrl.length > 50 ? 50 : finalUrl.length)}...',
                  );
                }

                if (finalUrl.isEmpty) {
                  debugPrint(
                    'DL ERROR: Torbox web download returned empty download URL',
                  );
                  throw Exception(
                    'Torbox web download returned empty download URL',
                  );
                }
              } else if (isTorbox) {
                // Torbox torrent download path
                final apiKey = meta['apiKey'] as String?;
                final torrentId = meta['torboxTorrentId'] as int?;
                final fileId = meta['torboxFileId'] as int?;
                final isZip = meta['torboxZip'] == true;

                debugPrint(
                  'DL TORBOX: torrentId=$torrentId, fileId=$fileId, isZip=$isZip, apiKey=${apiKey?.isNotEmpty ?? false ? "present" : "missing"}',
                );

                if (apiKey == null || apiKey.isEmpty) {
                  debugPrint('DL ERROR: Torbox download missing API key');
                  throw Exception('Torbox download missing API key');
                }

                if (isZip) {
                  // ZIP download - use permalink
                  if (torrentId == null) {
                    debugPrint(
                      'DL ERROR: Torbox ZIP download missing torrentId',
                    );
                    throw Exception('Torbox ZIP download missing torrentId');
                  }
                  finalUrl = TorboxService.createZipPermalink(
                    apiKey,
                    torrentId,
                  );
                  debugPrint('DL TORBOX ZIP: Generated permalink: $finalUrl');
                } else {
                  // Regular file download
                  if (torrentId == null || fileId == null) {
                    debugPrint(
                      'DL ERROR: Torbox download missing torrentId or fileId',
                    );
                    throw Exception(
                      'Torbox download missing torrentId or fileId',
                    );
                  }
                  debugPrint(
                    'DL TORBOX: Requesting download link for file $fileId in torrent $torrentId',
                  );
                  finalUrl = await TorboxService.requestFileDownloadLink(
                    apiKey: apiKey,
                    torrentId: torrentId,
                    fileId: fileId,
                  );
                  debugPrint(
                    'DL TORBOX SUCCESS: Got download URL: ${finalUrl.substring(0, finalUrl.length > 50 ? 50 : finalUrl.length)}...',
                  );
                }

                if (finalUrl.isEmpty) {
                  debugPrint('DL ERROR: Torbox returned empty download URL');
                  throw Exception('Torbox returned empty download URL');
                }
              } else {
                // RealDebrid download path (existing logic)
                final restrictedLink = (meta['restrictedLink'] ?? '') as String;
                final apiKey = (meta['apiKey'] ?? '') as String;

                debugPrint(
                  'DL META: restrictedLink=$restrictedLink, apiKey=${apiKey.isNotEmpty ? "present" : "missing"}',
                );
                debugPrint(
                  'DL COMPARE: p.url=${p.url} == restrictedLink=$restrictedLink ? ${p.url == restrictedLink}',
                );

                // If we have meta with restricted link info, always unrestrict
                // This handles the case where we pass restricted links directly as URLs
                if (restrictedLink.isNotEmpty && apiKey.isNotEmpty) {
                  debugPrint(
                    'DL UNRESTRICT: Starting unrestriction for: $finalFileName',
                  );
                  final unrestrictResult = await DebridService.unrestrictLink(
                    apiKey,
                    restrictedLink,
                  );
                  final unrestrictedUrl = (unrestrictResult['download'] ?? '')
                      .toString();
                  final rdFileName = (unrestrictResult['filename'] ?? '')
                      .toString();

                  debugPrint(
                    'DL UNRESTRICT RESULT: url=$unrestrictedUrl, filename=$rdFileName',
                  );

                  if (unrestrictedUrl.isNotEmpty) {
                    finalUrl = unrestrictedUrl;
                    if (rdFileName.isNotEmpty) {
                      finalFileName = rdFileName;
                    }
                    debugPrint(
                      'DL SUCCESS: Unrestricted to $finalUrl with filename $finalFileName',
                    );
                  } else {
                    debugPrint('DL ERROR: Unrestriction returned empty URL');
                    throw Exception(
                      'Failed to unrestrict link - empty URL returned',
                    );
                  }
                } else {
                  debugPrint(
                    'DL SKIP: Not unrestricting - restrictedLink empty: ${restrictedLink.isEmpty}, apiKey empty: ${apiKey.isEmpty}',
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('DL ERROR: On-demand unrestriction failed: $e');
            throw Exception('Failed to unrestrict link: $e');
          }
        } else {
          debugPrint('DL SKIP: No meta information provided');
        }

        // The link refresh above can take seconds — a pause/cancel that
        // landed during those awaits must win, or the download starts anyway
        // and desyncs from the paused/canceled bookkeeping.
        if (p.canceled ||
            _canceledDuringStart.remove(p.queuedId) ||
            _pausedPending.containsKey(p.queuedId)) {
          debugPrint(
            'DL START: ${p.queuedId} paused/canceled during link refresh; skipping',
          );
          continue;
        }

        // Fresh-link policy: if start fails due to expired URL, we'll refresh below in catch
        if (Platform.isAndroid) {
          // Remove queued placeholder
          AndroidDownloadHistory.instance.removeById(p.queuedId);

          // Ensure battery exemptions (non-blocking by policy)
          await _ensureBatteryExemptions(p.context);

          final String name;
          if (finalFileName.isNotEmpty) {
            name = finalFileName;
          } else {
            final (_dir, fn) = await _smartLocationFor(
              finalUrl,
              null,
              p.torrentName,
            );
            name = fn;
          }

          final sanitizedRelativeDir =
              p.relativeSubDir != null && p.relativeSubDir!.trim().isNotEmpty
              ? _sanitizeRelativePath(p.relativeSubDir!)
              : '';
          final String subDir =
              p.torrentName != null && p.torrentName!.trim().isNotEmpty
              ? (sanitizedRelativeDir.isNotEmpty
                        ? path.join(
                            'Debrify',
                            _sanitizeName(p.torrentName!.trim()),
                            sanitizedRelativeDir,
                          )
                        : path.join(
                            'Debrify',
                            _sanitizeName(p.torrentName!.trim()),
                          ))
                    .replaceAll(r'\', '/')
              : 'Debrify';

          final startRes = await AndroidNativeDownloader.start(
            // Same id as the durable record: the service adopts persisted
            // state under this id, and reconciliation never has to correlate
            // two id spaces.
            taskId: p.queuedId,
            url: finalUrl,
            fileName: name,
            subDir: subDir,
            headers: p.headers,
            treeUri: p.treeUri,
          );
          if (!startRes.ok) {
            if (startRes.errorCode == 'fgs_not_allowed') {
              // Android 12+ refused a foreground-service start from the
              // background. The link is fine — put the item back at the front
              // and stop draining; the next reevaluation (app foregrounded,
              // event, connectivity) will start it. NOT a failure.
              debugPrint(
                'DL START: fgs_not_allowed — requeueing ${p.queuedId} until app is foregrounded',
              );
              _pending.insert(0, p);
              _pendingById[p.queuedId] = p;
              await _persistPending();
              final queuedTask = DownloadTask(
                taskId: p.queuedId,
                url: p.url,
                filename: name,
              );
              AndroidDownloadHistory.instance.upsert(
                queuedTask,
                TaskStatus.enqueued,
                0.0,
              );
              _statusController.add(
                TaskStatusUpdate(queuedTask, TaskStatus.enqueued),
              );
              break;
            }
            throw Exception(
              'Failed to start download: ${startRes.errorCode ?? ''} ${startRes.errorMessage ?? ''}',
            );
          }
          final taskId = startRes.taskId!;
          final task = DownloadTask(
            taskId: taskId,
            url: finalUrl,
            filename: name,
          );
          AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
          _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
          _upsertRecord(p.queuedId, {
            'state': 'running',
            'pluginTaskId': taskId,
            'url': finalUrl,
            'displayName': name,
          });
          // Last un-guarded window: a pause/cancel that landed while the
          // native start round-trip itself was in flight (the pre-start check
          // above had already passed). Forward it to the now-live task.
          if (p.canceled || _canceledDuringStart.remove(p.queuedId)) {
            unawaited(AndroidNativeDownloader.cancel(taskId));
          } else if (_pausedPending.remove(p.queuedId) != null) {
            // Native owns the paused state from here on; its 'paused' event
            // settles history/record.
            await _persistPaused();
            unawaited(AndroidNativeDownloader.pause(taskId));
          }
        } else {
          // Remove queued placeholder from our in-memory list
          _nonAndroidQueuedRecords.remove(p.queuedId);

          // Prefer persisted destination path for resume capability
          String finalPath;
          final rec = _records[p.queuedId];
          if (p.destPath != null &&
              p.destPath!.isNotEmpty &&
              File(p.destPath!).existsSync()) {
            finalPath = p.destPath!;
          } else if (rec != null &&
              (rec['destPath'] as String?) != null &&
              (rec['destPath'] as String).isNotEmpty) {
            finalPath = rec['destPath'] as String;
          } else {
            final (dirAbsPath, filenamePart) = await _smartLocationFor(
              finalUrl,
              finalFileName,
              p.torrentName,
            );
            final sanitizedRelativeDir =
                p.relativeSubDir != null && p.relativeSubDir!.trim().isNotEmpty
                ? _sanitizeRelativePath(p.relativeSubDir!)
                : '';
            finalPath = sanitizedRelativeDir.isNotEmpty
                ? path.join(dirAbsPath, sanitizedRelativeDir, filenamePart)
                : path.join(dirAbsPath, filenamePart);
            _upsertRecord(p.queuedId, {'destPath': finalPath});
            p.destPath = finalPath;
          }
          try {
            final d = Directory(finalPath).parent;
            if (!await d.exists()) {
              await d.create(recursive: true);
            }
          } catch (_) {}

          // Build headers for Range resume based on partial size and validators
          Map<String, String> headers = _buildResumeHeaders(
            finalPath,
            p.headers,
            rec,
          );

          // On Windows, Task.split() strips the drive letter when falling back to BaseDirectory.root,
          // causing the file to be saved to a relative path instead of the absolute path.
          // We bypass Task.split() on Windows and manually use BaseDirectory.root with the full path.
          final DownloadTask task;
          if (Platform.isWindows) {
            final directory = path.dirname(finalPath);
            final filename = path.basename(finalPath);
            task = DownloadTask(
              url: finalUrl,
              headers: headers.isEmpty ? null : headers,
              filename: filename,
              directory: directory,
              baseDirectory: BaseDirectory.root,
              updates: Updates.statusAndProgress,
              requiresWiFi: p.wifiOnly,
              retries: p.retries,
              allowPause: true,
            );
          } else {
            final (
              BaseDirectory baseDir,
              String relativeDir,
              String relFilename,
            ) = await Task.split(
              filePath: finalPath,
            );
            task = DownloadTask(
              url: finalUrl,
              headers: headers.isEmpty ? null : headers,
              filename: relFilename,
              directory: relativeDir,
              baseDirectory: baseDir,
              updates: Updates.statusAndProgress,
              requiresWiFi: p.wifiOnly,
              retries: p.retries,
              allowPause: true,
            );
          }
          final bool ok = await FileDownloader().enqueue(task);
          if (!ok) {
            throw Exception('Failed to enqueue download');
          }
          _upsertRecord(p.queuedId, {
            'state': 'running',
            'pluginTaskId': task.taskId,
            'url': finalUrl,
            'displayName': task.filename,
          });
          // capture validators for the refreshed URL
          unawaited(_captureValidatorsAndSave(p.queuedId, finalUrl));
        }
        runningCount += 1;
      } catch (e) {
        // Attempt fresh-link refresh once if we have meta
        bool retried = false;
        try {
          if (p.meta != null && p.meta!.isNotEmpty) {
            final meta = jsonDecode(p.meta!);

            // CHECK PIKPAK FIRST (before Torbox)
            final isPikPak = meta['pikpakDownload'] == true;
            if (isPikPak) {
              final fileId = meta['pikpakFileId'] as String?;
              if (fileId != null && fileId.isNotEmpty) {
                try {
                  // PikPak cold storage retry with exponential backoff
                  // Files in cold storage need 10-30s to reactivate
                  // Total worst case: 5 + 10 + 20 + 30 + 30 = 95 seconds
                  const int pikpakMaxColdRetries = 5;
                  const int pikpakBaseDelaySeconds = 5;
                  const int pikpakMaxDelaySeconds = 30;

                  final int coldAttempt =
                      (meta['_pikpakColdAttempt'] as int?) ?? 0;

                  if (coldAttempt >= pikpakMaxColdRetries) {
                    debugPrint(
                      'DL RETRY PIKPAK: Max cold storage retries ($pikpakMaxColdRetries) exceeded for file $fileId',
                    );
                    // Don't retry anymore, let it fail
                  } else {
                    // Calculate delay with exponential backoff (capped)
                    final int delaySeconds =
                        (pikpakBaseDelaySeconds * (1 << coldAttempt)).clamp(
                          pikpakBaseDelaySeconds,
                          pikpakMaxDelaySeconds,
                        );

                    debugPrint(
                      'DL RETRY PIKPAK: Cold storage attempt ${coldAttempt + 1}/$pikpakMaxColdRetries, waiting ${delaySeconds}s before retry for file $fileId',
                    );

                    // Wait for cold storage to potentially warm up
                    await Future.delayed(Duration(seconds: delaySeconds));

                    debugPrint(
                      'DL RETRY PIKPAK: Refreshing URL for file $fileId',
                    );

                    // Get fresh file details
                    final freshData = await PikPakApiService.instance
                        .getFileDetails(fileId);
                    final freshUrl = PikPakApiService.instance.getStreamingUrl(
                      freshData,
                    );

                    if (freshUrl != null && freshUrl.isNotEmpty) {
                      // Update meta with incremented cold attempt count
                      final updatedMeta = Map<String, dynamic>.from(meta);
                      updatedMeta['_pikpakColdAttempt'] = coldAttempt + 1;

                      // Create new pending request with fresh URL and updated meta
                      final refreshed = _PendingRequest(
                        queuedId: p.queuedId,
                        url: freshUrl,
                        providedFileName: p.providedFileName,
                        headers: p.headers,
                        wifiOnly: p.wifiOnly,
                        retries: p.retries,
                        meta: jsonEncode(updatedMeta),
                        context: p.context,
                        torrentName: p.torrentName,
                        contentKey: p.contentKey,
                        destPath: p.destPath,
                        relativeSubDir: p.relativeSubDir,
                        treeUri: p.treeUri,
                      );
                      _pending.insert(0, refreshed);
                      _pendingById[refreshed.queuedId] = refreshed;
                      await _persistPending();
                      retried = true;
                      debugPrint(
                        'DL RETRY PIKPAK: Re-queued with fresh URL (attempt ${coldAttempt + 1})',
                      );
                      continue; // try scheduling the refreshed entry immediately
                    } else {
                      debugPrint('DL RETRY PIKPAK: Failed to get fresh URL');
                    }
                  }
                } catch (e) {
                  debugPrint('DL RETRY PIKPAK: Error refreshing URL: $e');
                }
              }
            } else {
              // EXISTING TORBOX/REALDEBRID RETRY LOGIC (keep exactly as is)
              final isTorbox = meta['torboxDownload'] == true;
              final isTorboxWebDownload = meta['torboxWebDownload'] == true;

              if (isTorboxWebDownload) {
                // Torbox web download retry path
                final apiKey = meta['apiKey'] as String?;
                final webDownloadId = meta['torboxWebDownloadId'] as int?;
                final fileId = meta['torboxFileId'] as int?;
                final isZip = meta['torboxZip'] == true;

                if (apiKey != null && apiKey.isNotEmpty) {
                  String freshUrl = '';

                  if (isZip && webDownloadId != null) {
                    // Regenerate ZIP permalink
                    freshUrl = TorboxService.createWebDownloadZipPermalink(
                      apiKey,
                      webDownloadId,
                    );
                    debugPrint(
                      'DL RETRY TORBOX WEB ZIP: Regenerated permalink',
                    );
                  } else if (webDownloadId != null && fileId != null) {
                    // Re-request file download link
                    freshUrl = await TorboxService.requestWebDownloadFileLink(
                      apiKey: apiKey,
                      webId: webDownloadId,
                      fileId: fileId,
                    );
                    debugPrint('DL RETRY TORBOX WEB: Got fresh download URL');
                  }

                  if (freshUrl.isNotEmpty) {
                    final refreshed = _PendingRequest(
                      queuedId: p.queuedId,
                      url: freshUrl,
                      providedFileName: p.providedFileName,
                      headers: p.headers,
                      wifiOnly: p.wifiOnly,
                      retries: p.retries,
                      meta: p.meta,
                      context: p.context,
                      torrentName: p.torrentName,
                      contentKey: p.contentKey,
                      destPath: p.destPath,
                      relativeSubDir: p.relativeSubDir,
                      treeUri: p.treeUri,
                    );
                    _pending.insert(0, refreshed);
                    _pendingById[refreshed.queuedId] = refreshed;
                    await _persistPending();
                    retried = true;
                    debugPrint('DL RETRY TORBOX WEB: Re-queued with fresh URL');
                    continue; // try scheduling the refreshed entry immediately
                  }
                }
              } else if (isTorbox) {
                // Torbox torrent retry path
                final apiKey = meta['apiKey'] as String?;
                final torrentId = meta['torboxTorrentId'] as int?;
                final fileId = meta['torboxFileId'] as int?;
                final isZip = meta['torboxZip'] == true;

                if (apiKey != null && apiKey.isNotEmpty) {
                  String freshUrl = '';

                  if (isZip && torrentId != null) {
                    // Regenerate ZIP permalink
                    freshUrl = TorboxService.createZipPermalink(
                      apiKey,
                      torrentId,
                    );
                    debugPrint('DL RETRY TORBOX ZIP: Regenerated permalink');
                  } else if (torrentId != null && fileId != null) {
                    // Re-request file download link
                    freshUrl = await TorboxService.requestFileDownloadLink(
                      apiKey: apiKey,
                      torrentId: torrentId,
                      fileId: fileId,
                    );
                    debugPrint('DL RETRY TORBOX: Got fresh download URL');
                  }

                  if (freshUrl.isNotEmpty) {
                    final refreshed = _PendingRequest(
                      queuedId: p.queuedId,
                      url: freshUrl,
                      providedFileName: p.providedFileName,
                      headers: p.headers,
                      wifiOnly: p.wifiOnly,
                      retries: p.retries,
                      meta: p.meta,
                      context: p.context,
                      torrentName: p.torrentName,
                      contentKey: p.contentKey,
                      destPath: p.destPath,
                      relativeSubDir: p.relativeSubDir,
                      treeUri: p.treeUri,
                    );
                    _pending.insert(0, refreshed);
                    _pendingById[refreshed.queuedId] = refreshed;
                    await _persistPending();
                    retried = true;
                    debugPrint('DL RETRY TORBOX: Re-queued with fresh URL');
                    continue; // try scheduling the refreshed entry immediately
                  }
                }
              } else {
                // RealDebrid retry path (existing logic)
                final restricted = (meta['restrictedLink'] ?? '') as String;
                final apiKey = (meta['apiKey'] ?? '') as String;
                if (restricted.isNotEmpty && apiKey.isNotEmpty) {
                  final fresh = await DebridService.unrestrictLink(
                    apiKey,
                    restricted,
                  );
                  final freshUrl = (fresh['download'] ?? '').toString();
                  final rdName = (fresh['filename'] ?? '').toString();
                  if (freshUrl.isNotEmpty) {
                    final refreshed = _PendingRequest(
                      queuedId: p.queuedId,
                      url: freshUrl,
                      providedFileName: (rdName.isNotEmpty
                          ? rdName
                          : p.providedFileName),
                      headers: p.headers,
                      wifiOnly: p.wifiOnly,
                      retries: p.retries,
                      meta: p.meta,
                      context: p.context,
                      torrentName: p.torrentName,
                      contentKey: p.contentKey,
                      destPath: p.destPath,
                      relativeSubDir: p.relativeSubDir,
                      treeUri: p.treeUri,
                    );
                    _pending.insert(0, refreshed);
                    _pendingById[refreshed.queuedId] = refreshed;
                    await _persistPending();
                    retried = true;
                    continue; // try scheduling the refreshed entry immediately
                  }
                }
              }
            }
          }
        } catch (_) {}

        if (!retried) {
          // Mark failed
          if (Platform.isAndroid) {
            final failTask = DownloadTask(
              taskId: p.queuedId,
              url: p.url,
              filename: p.providedFileName ?? 'download',
            );
            AndroidDownloadHistory.instance.upsert(
              failTask,
              TaskStatus.failed,
              -1.0,
            );
            _statusController.add(
              TaskStatusUpdate(failTask, TaskStatus.failed),
            );
          } else {
            final failTask = DownloadTask(
              taskId: p.queuedId,
              url: p.url,
              filename: p.providedFileName ?? 'download',
            );
            _nonAndroidQueuedRecords[p.queuedId] = TaskRecord(
              failTask,
              TaskStatus.failed,
              -1.0,
              -1,
            );
            _statusController.add(
              TaskStatusUpdate(failTask, TaskStatus.failed),
            );
          }
          _upsertRecord(p.queuedId, {
            'state': 'failed',
            'lastError': e.toString(),
          });
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

class DownloadRecordDetails {
  final String recordId;
  final String? url;
  final String? displayName;
  final String? state;
  final String? meta;
  final String? torrentName;
  final String? contentKey;
  final String? destPath;
  final String? pluginTaskId;
  final int? createdAt;
  final int? updatedAt;

  const DownloadRecordDetails({
    required this.recordId,
    this.url,
    this.displayName,
    this.state,
    this.meta,
    this.torrentName,
    this.contentKey,
    this.destPath,
    this.pluginTaskId,
    this.createdAt,
    this.updatedAt,
  });

  factory DownloadRecordDetails.fromMap(
    String recordId,
    Map<String, dynamic> map,
  ) {
    return DownloadRecordDetails(
      recordId: recordId,
      url: _maybeString(map['url']),
      displayName: _maybeString(map['displayName']),
      state: _maybeString(map['state']),
      meta: _maybeString(map['meta']),
      torrentName: _maybeString(map['torrentName']),
      contentKey: _maybeString(map['contentKey']),
      destPath: _maybeString(map['destPath']),
      pluginTaskId: _maybeString(map['pluginTaskId']),
      createdAt: (map['createdAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }

  DownloadRecordDetails copyWith({
    String? url,
    String? displayName,
    String? state,
    String? meta,
    String? torrentName,
    String? contentKey,
    String? destPath,
    String? pluginTaskId,
    int? createdAt,
    int? updatedAt,
  }) {
    return DownloadRecordDetails(
      recordId: recordId,
      url: url ?? this.url,
      displayName: displayName ?? this.displayName,
      state: state ?? this.state,
      meta: meta ?? this.meta,
      torrentName: torrentName ?? this.torrentName,
      contentKey: contentKey ?? this.contentKey,
      destPath: destPath ?? this.destPath,
      pluginTaskId: pluginTaskId ?? this.pluginTaskId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _maybeString(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    return str.isEmpty ? null : str;
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
  final String contentKey;
  bool canceled;
  String? destPath;
  final String? relativeSubDir;
  final String? treeUri;

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
    required this.contentKey,
    this.canceled = false,
    this.destPath,
    this.relativeSubDir,
    this.treeUri,
  });
}

/// Returns true when the request joined the queue. Duplicate suppression only
/// applies to fresh user-initiated enqueues against LIVE entries — internal
/// re-queues of an existing record (retry, resume fallback) pass
/// [allowDuplicate] so a retry can never be silently swallowed.
bool _addPendingRequest(
  List<_PendingRequest> pendingList,
  Map<String, _PendingRequest> pendingById,
  _PendingRequest request, {
  bool atFront = false,
  bool allowDuplicate = false,
}) {
  if (pendingById.containsKey(request.queuedId)) {
    // Same record already queued — nothing to add.
    return false;
  }
  if (!allowDuplicate &&
      pendingList.any(
        (p) => !p.canceled && p.contentKey == request.contentKey,
      )) {
    debugPrint('DL: skip enqueue duplicate contentKey=${request.contentKey}');
    return false;
  }
  if (atFront) {
    pendingList.insert(0, request);
  } else {
    pendingList.add(request);
  }
  pendingById[request.queuedId] = request;
  return true;
}
