import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'debrid_service.dart';
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
  bool _initializing = false;
  StreamSubscription<Map<String, dynamic>>? _androidEventsSub;
  bool _batteryCheckShown = false;
  ConnectivityResult _net = ConnectivityResult.wifi; // default optimistic
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  ConnectivityResult _computeEffectiveNet(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityResult.none;
    if (results.contains(ConnectivityResult.none)) return ConnectivityResult.none;
    // Treat ethernet/wired/vpn as acceptable like Wi-Fi for large downloads
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn)) {
      return ConnectivityResult.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) return ConnectivityResult.mobile;
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
  bool _reevaluating = false;
  bool _reevaluateScheduled = false;

  // Persistence for pending queue (crash-safe, survives restarts)
  static const String _pendingKey = 'pending_download_queue_v1';
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

    Future<void> updateRecordState(String recordId) async {
      if (recordId.isEmpty) return;
      _upsertRecord(recordId, {'state': 'paused'});
    }

    for (final id in ids) {
      final pending = _pendingById.remove(id);
      if (pending != null) {
        _pending.remove(pending);
        _pausedPending[pending.queuedId] = pending;
        changedPending = true;

        await updateRecordState(pending.queuedId);

        final downloadTask = DownloadTask(
          taskId: pending.queuedId,
          url: pending.url,
          filename: (pending.providedFileName?.isNotEmpty ?? false)
              ? pending.providedFileName!
              : 'download',
        );

        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance
              .upsert(downloadTask, TaskStatus.paused, -5.0);
        } else {
          _nonAndroidQueuedRecords[pending.queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.paused,
            -5.0,
            -1,
          );
        }

        _statusController.add(TaskStatusUpdate(downloadTask, TaskStatus.paused));
      } else {
        final recId = _resolveRecordIdForTaskId(id);
        if (recId != null) {
          await updateRecordState(recId);
        }
      }
    }

    if (changedPending) {
      await _persistPending();
    }
  }

  Future<void> resumeQueuedTasksByIds(Iterable<String> taskIds) async {
    final ids = taskIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    bool changedPending = false;

    for (final id in ids) {
      final paused = _pausedPending.remove(id);
      if (paused != null) {
        _pending.add(paused);
        _pendingById[paused.queuedId] = paused;
        changedPending = true;

        _upsertRecord(paused.queuedId, {'state': 'queued'});

        final downloadTask = DownloadTask(
          taskId: paused.queuedId,
          url: paused.url,
          filename: (paused.providedFileName?.isNotEmpty ?? false)
              ? paused.providedFileName!
              : 'download',
        );

        if (Platform.isAndroid) {
          AndroidDownloadHistory.instance
              .upsert(downloadTask, TaskStatus.enqueued, 0.0);
        } else {
          _nonAndroidQueuedRecords[paused.queuedId] = TaskRecord(
            downloadTask,
            TaskStatus.enqueued,
            0.0,
            -1,
          );
        }

        _statusController.add(TaskStatusUpdate(downloadTask, TaskStatus.enqueued));
      }
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
    final file = File('${dir.path}/$_recordsFile');
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
        _records = data.map((k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()));
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

  Map<String, String> _buildResumeHeaders(String finalPath, Map<String, String>? baseHeaders, Map<String, dynamic>? rec) {
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
          debugPrint('DL RESUME: path=$finalPath partial=$partial rangeSet=true ifRange=' + (headers['If-Range'] ?? ''));
        }
      }
    } catch (_) {}
    return headers;
  }

  String _computeContentKey(String? meta, String url, String? fileName, String? torrentName) {
    try {
      // Prefer stable identifiers from meta if present
      if (meta != null && meta.isNotEmpty) {
        // Expecting JSON meta with fields like restrictedLink or (torrentHash,fileIndex)
        final m = jsonDecode(meta);
        if (m is Map) {
          final hash = (m['torrentHash'] ?? '').toString();
          final idx = (m['fileIndex'] ?? '').toString();
          if (hash.isNotEmpty && idx.isNotEmpty) return 'th:$hash:$idx';
          final restricted = (m['restrictedLink'] ?? '').toString();
          if (restricted.isNotEmpty) return 'rl:${restricted.hashCode}';
        }
      }
      // Fallback: torrent folder + sanitized fileName
      final n = (fileName ?? '').isNotEmpty ? fileName! : Uri.parse(url).pathSegments.lastOrNull ?? 'file';
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
    final failed = _records.entries.where((e) => (e.value['state'] == 'failed'));
    for (final e in failed) {
      final rec = e.value;
      final meta = rec['meta'] as String?;
      final url = rec['url'] as String?;
      final fileName = rec['displayName'] as String?;
      final torrentName = rec['torrentName'] as String?;
      if (meta != null && meta.isNotEmpty) {
        await enqueueDownload(url: url ?? '', fileName: fileName, meta: meta, torrentName: torrentName);
      } else if (url != null && url.isNotEmpty) {
        await enqueueDownload(url: url, fileName: fileName, torrentName: torrentName);
      }
      _upsertRecord(e.key, {'state': 'queued'});
    }
  }

  Future<void> clearDownloadDatabase() async {
    // Clear durable records
    _records = {};
    await _saveRecords();
    // Clear persisted pending queue
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
    } catch (_) {}
    // Best-effort clear of non-Android plugin DB (Android handled via native history elsewhere)
    if (!Platform.isAndroid) {
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
          .map((p) => {
                'queuedId': p.queuedId,
                'url': p.url,
                'providedFileName': p.providedFileName,
                'headers': p.headers,
                'wifiOnly': p.wifiOnly,
                'retries': p.retries,
                'meta': p.meta,
                'torrentName': p.torrentName,
                'contentKey': p.contentKey,
              })
          .toList();
      await prefs.setString(_pendingKey, jsonEncode(data));
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
      await _loadRecords();
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final queuedId = (item['queuedId'] ?? '') as String;
          final url = (item['url'] ?? '') as String;
          if (queuedId.isEmpty || url.isEmpty) continue;
          // Skip if this task was canceled previously (persisted in records)
          final rec = _records[queuedId];
          if (rec != null && rec['state'] == 'canceled') {
            debugPrint('DL INIT: skipping canceled pending queuedId=$queuedId');
            continue;
          }
          final providedFileName = (item['providedFileName'] as String?);
          final meta = (item['meta'] as String?);
          final torrentName = (item['torrentName'] as String?);
          final contentKey = (item['contentKey'] as String?) ?? _computeContentKey(meta, url, providedFileName, torrentName);
          if (contentKey.isNotEmpty && seenKeys.contains(contentKey)) {
            debugPrint('DL INIT: skipping duplicate pending contentKey=$contentKey');
            continue;
          }
          final p = _PendingRequest(
            queuedId: queuedId,
            url: url,
            providedFileName: providedFileName,
            headers: (item['headers'] as Map?)?.cast<String, String>(),
            wifiOnly: (item['wifiOnly'] as bool?) ?? false,
            retries: (item['retries'] as int?) ?? 3,
            meta: meta,
            context: null,
            torrentName: torrentName,
            contentKey: contentKey,
          );
          // Recreate placeholder queued record for UI continuity
          if (Platform.isAndroid) {
            final t = DownloadTask(taskId: queuedId, url: url, filename: p.providedFileName ?? 'download');
            AndroidDownloadHistory.instance.upsert(t, TaskStatus.enqueued, 0.0);
            _statusController.add(TaskStatusUpdate(t, TaskStatus.enqueued));
          } else {
            _nonAndroidQueuedRecords[queuedId] = TaskRecord(DownloadTask(taskId: queuedId, url: url, filename: p.providedFileName ?? 'download'), TaskStatus.enqueued, 0.0, -1);
            _statusController.add(TaskStatusUpdate(_nonAndroidQueuedRecords[queuedId]!.task, TaskStatus.enqueued));
          }
          _pending.add(p);
          _pendingById[queuedId] = p;
          if (contentKey.isNotEmpty) seenKeys.add(contentKey);
          debugPrint('DL INIT: restored pending queuedId=$queuedId name=${p.providedFileName ?? 'download'}');
        }
      }
      // Prevent re-importing the same set on next launch
      await prefs.remove(_pendingKey);
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
              .where((id) => !id.startsWith('queued-'))
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
        final task = DownloadTask(
          taskId: taskId,
          url: event['url'] ?? '',
          filename: event['fileName'] ?? 'download',
        );
        final String? recId = _resolveRecordIdForTaskId(taskId);
        switch (type) {
          case 'started':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            if (recId != null) _upsertRecord(recId, {'state': 'running', 'pluginTaskId': taskId});
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
            if (recId != null) _upsertRecord(recId, {'state': 'paused'});
            // Paused frees a slot; try to start next
            _reevaluateQueue();
            break;
          case 'resumed':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
            if (recId != null) _upsertRecord(recId, {'state': 'running'});
            break;
          case 'canceled':
            AndroidDownloadHistory.instance.upsert(task, TaskStatus.canceled, -2.0);
            _statusController.add(TaskStatusUpdate(task, TaskStatus.canceled));
            _lastFileByTaskId.remove(taskId);
            if (recId != null) _upsertRecord(recId, {'state': 'canceled'});
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
              debugPrint('ANDR ERR net=${nowNone ? 'none' : _net.name} → paused');
              AndroidDownloadHistory.instance.upsert(task, TaskStatus.paused, -5.0);
              _statusController.add(TaskStatusUpdate(task, TaskStatus.paused));
              if (recId != null) _upsertRecord(recId, {'state': 'paused'});
            } else {
              debugPrint('ANDR ERR net=${nowNet.name} → failed');
              AndroidDownloadHistory.instance.upsert(task, TaskStatus.failed, -1.0);
              _statusController.add(TaskStatusUpdate(task, TaskStatus.failed));
              if (recId != null) _upsertRecord(recId, {'state': 'failed'});
            }
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

    // Restore any pending queue persisted from a previous run
    await _restorePending();
    await _loadRecords();
    debugPrint('DL INIT: loaded records count=${_records.length}');
    // On non-Android: try to resume tasks on startup
    if (!Platform.isAndroid) {
      final records = await FileDownloader().database.allRecords();
      debugPrint('DL INIT: plugin records count=${records.length}');
      // Build reverse map: pluginTaskId -> record
      Map<String, Map<String, dynamic>> byPluginId = {};
      for (final e in _records.entries) {
        final pluginId = (e.value['pluginTaskId'] ?? '') as String;
        if (pluginId.isNotEmpty) byPluginId[pluginId] = e.value;
      }
      for (final r in records) {
        final task = r.task as DownloadTask;
        final rec = byPluginId[task.taskId] ?? _records[task.taskId];
        final String? meta = rec != null ? (rec['meta'] as String?) : null;
        final String? displayName = rec != null ? (rec['displayName'] as String?) : null;
        final String? url = rec != null ? (rec['url'] as String?) : null;
        final String? torrentName = rec != null ? (rec['torrentName'] as String?) : null;

        Future<void> reenqueueFromMeta() async {
          debugPrint('DL INIT: re-enqueue from meta for taskId=${task.taskId} name=$displayName');
          if (meta != null) {
            final ck = _computeContentKey(meta, url ?? '', displayName, torrentName);
            final bool dup = _pending.any((p) => p.contentKey == ck);
            if (!dup) {
              await enqueueDownload(url: url ?? '', fileName: displayName, meta: meta, torrentName: torrentName);
            } else {
              debugPrint('DL INIT: skip re-enqueue duplicate contentKey=$ck');
            }
          }
        }

        if (r.status == TaskStatus.paused || r.status == TaskStatus.enqueued) {
          final canResume = await FileDownloader().taskCanResume(task);
          debugPrint('DL INIT: taskId=${task.taskId} status=${r.status} canResume=$canResume');
          if (canResume) {
            try { await FileDownloader().resume(task); debugPrint('DL INIT: resumed taskId=${task.taskId}'); } catch (_) { await reenqueueFromMeta(); }
          } else {
            // Cancel and delete stale record to free capacity
            try { await FileDownloader().cancel(task); } catch (_) {}
            try { await FileDownloader().database.deleteRecordWithId(task.taskId); } catch (_) {}
            await reenqueueFromMeta();
          }
        } else if (r.status == TaskStatus.running) {
          // Nudge running tasks to ensure the plugin is actually progressing; if not resumable, re-enqueue
          final canResume = await FileDownloader().taskCanResume(task);
          debugPrint('DL INIT: running taskId=${task.taskId} canResume=$canResume');
          if (!canResume) {
            // Cancel and delete stale record to free capacity
            try { await FileDownloader().cancel(task); } catch (_) {}
            try { await FileDownloader().database.deleteRecordWithId(task.taskId); } catch (_) {}
            await reenqueueFromMeta();
          }
        }
      }
    }
    // On Android: seed paused/enqueued/running tasks into pending resume to let scheduler handle capacity
    if (Platform.isAndroid) {
      final hist = AndroidDownloadHistory.instance.all();
      int seeded = 0;
      for (final r in hist) {
        if (r.status == TaskStatus.paused || r.status == TaskStatus.enqueued || r.status == TaskStatus.running) {
          if (!r.taskId.startsWith('queued-') && !_pendingResumeAndroid.contains(r.taskId)) {
            _pendingResumeAndroid.add(r.taskId);
            seeded++;
          }
        }
      }
      if (seeded > 0) debugPrint('DL INIT: android seeded $seeded tasks for resume');
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
    );
    if (_pending.any((p) => p.contentKey == contentKey)) {
      debugPrint('DL: skip enqueue duplicate contentKey=$contentKey');
    } else {
      _pending.add(pending);
    }
    _pendingById[queuedId] = pending;
    await _persistPending();

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
      try {
        return await AndroidNativeDownloader.resume(task.taskId);
      } catch (_) {
        // If native resume fails (unknown id or already resumed), downgrade to enqueued and let reevaluator proceed
        AndroidDownloadHistory.instance.upsert(task as DownloadTask, TaskStatus.enqueued, 0.0);
        _statusController.add(TaskStatusUpdate(task, TaskStatus.enqueued));
        unawaited(_reevaluateQueue());
        return false;
      }
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
      return;
    }

    if (Platform.isAndroid) {
      // If already canceled/complete/failed in history, avoid native calls
      final hist = AndroidDownloadHistory.instance.all().firstWhere(
        (r) => r.taskId == task.taskId,
        orElse: () => TaskRecord(task as DownloadTask, TaskStatus.notFound, 0.0, -1),
      );
      if (hist.status == TaskStatus.canceled || hist.status == TaskStatus.complete || hist.status == TaskStatus.failed) {
        AndroidDownloadHistory.instance.removeById(task.taskId);
        _statusController.add(TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled));
        final recId = _resolveRecordIdForTaskId(task.taskId);
        if (recId != null) _upsertRecord(recId, {'state': 'canceled'});
        return;
      }
      try {
        await AndroidNativeDownloader.cancel(task.taskId);
      } catch (_) {}
      AndroidDownloadHistory.instance.removeById(task.taskId);
      _statusController.add(TaskStatusUpdate(task as DownloadTask, TaskStatus.canceled));
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
    if (_nonAndroidQueuedRecords.isEmpty && _nonAndroidResumeQueuedOverlay.isEmpty) return dbRecords;
    final List<TaskRecord> adjusted = dbRecords.map((r) {
      if (_nonAndroidResumeQueuedOverlay.contains(r.taskId)) {
        return TaskRecord(r.task, TaskStatus.enqueued, r.progress, r.expectedFileSize);
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
    if (Platform.isMacOS) {
      // On macOS, use the user's actual Downloads folder
      try {
        final Directory? downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          return downloadsDir;
        }
      } catch (e) {
        // Fallback to app documents if Downloads directory is not accessible
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
        // Skip if already running/enqueued
        final hist = AndroidDownloadHistory.instance.all().firstWhere(
          (r) => r.taskId == taskId,
          orElse: () => TaskRecord(DownloadTask(taskId: taskId, url: '', filename: 'download'), TaskStatus.notFound, 0.0, -1),
        );
        if (hist.status == TaskStatus.running || hist.status == TaskStatus.enqueued) {
          continue;
        }
        bool ok = false;
        try { ok = await AndroidNativeDownloader.resume(taskId); } catch (_) { ok = false; }
        if (ok) {
          resumedSomeone = true;
          runningCount += 1;
        } else {
          // Resume failed: fall back to re-enqueue based on durable record
          final recId = _resolveRecordIdForTaskId(taskId);
          if (recId != null) {
            final rec = _records[recId];
            if (rec != null) {
              final url = (rec['url'] ?? '').toString();
              final name = (rec['displayName'] ?? 'download').toString();
              final meta = rec['meta'] as String?;
              final tname = rec['torrentName'] as String?;
              if (url.isNotEmpty || (meta != null && meta.isNotEmpty)) {
                unawaited(enqueueDownload(url: url, fileName: name, meta: meta, torrentName: tname));
              }
            }
          }
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
      var p = _pending.removeAt(0);
      _pendingById.remove(p.queuedId);
      await _persistPending();
      try {
        // On-demand unrestriction: if URL is restricted, unrestrict it first
        String finalUrl = p.url;
        String finalFileName = p.providedFileName ?? 'download';
        
        debugPrint('DL START: url=${p.url}, meta=${p.meta}');
        
        if (p.meta != null && p.meta!.isNotEmpty) {
          try {
            final meta = jsonDecode(p.meta!);
            final restrictedLink = (meta['restrictedLink'] ?? '') as String;
            final apiKey = (meta['apiKey'] ?? '') as String;
            
            debugPrint('DL META: restrictedLink=$restrictedLink, apiKey=${apiKey.isNotEmpty ? "present" : "missing"}');
            debugPrint('DL COMPARE: p.url=${p.url} == restrictedLink=$restrictedLink ? ${p.url == restrictedLink}');
            
            // If we have meta with restricted link info, always unrestrict
            // This handles the case where we pass restricted links directly as URLs
            if (restrictedLink.isNotEmpty && apiKey.isNotEmpty) {
              debugPrint('DL UNRESTRICT: Starting unrestriction for: $finalFileName');
              final unrestrictResult = await DebridService.unrestrictLink(apiKey, restrictedLink);
              final unrestrictedUrl = (unrestrictResult['download'] ?? '').toString();
              final rdFileName = (unrestrictResult['filename'] ?? '').toString();
              
              debugPrint('DL UNRESTRICT RESULT: url=$unrestrictedUrl, filename=$rdFileName');
              
              if (unrestrictedUrl.isNotEmpty) {
                finalUrl = unrestrictedUrl;
                if (rdFileName.isNotEmpty) {
                  finalFileName = rdFileName;
                }
                debugPrint('DL SUCCESS: Unrestricted to $finalUrl with filename $finalFileName');
              } else {
                debugPrint('DL ERROR: Unrestriction returned empty URL');
                throw Exception('Failed to unrestrict link - empty URL returned');
              }
            } else {
              debugPrint('DL SKIP: Not unrestricting - restrictedLink empty: ${restrictedLink.isEmpty}, apiKey empty: ${apiKey.isEmpty}');
            }
          } catch (e) {
            debugPrint('DL ERROR: On-demand unrestriction failed: $e');
            throw Exception('Failed to unrestrict link: $e');
          }
        } else {
          debugPrint('DL SKIP: No meta information provided');
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
            final (_dir, fn) = await _smartLocationFor(finalUrl, null, p.torrentName);
            name = fn;
          }

          final String subDir = p.torrentName != null && p.torrentName!.trim().isNotEmpty 
              ? 'Debrify/${_sanitizeName(p.torrentName!.trim())}'
              : 'Debrify';

          final taskId = await AndroidNativeDownloader.start(
            url: finalUrl,
            fileName: name,
            subDir: subDir,
            headers: p.headers,
          );
          if (taskId == null) {
            throw Exception('Failed to start download');
          }
          final task = DownloadTask(taskId: taskId, url: finalUrl, filename: name);
          AndroidDownloadHistory.instance.upsert(task, TaskStatus.running, 0.0);
          _statusController.add(TaskStatusUpdate(task, TaskStatus.running));
          _upsertRecord(p.queuedId, {
            'state': 'running',
            'pluginTaskId': taskId,
            'url': finalUrl,
            'displayName': name,
          });
        } else {
          // Remove queued placeholder from our in-memory list
          _nonAndroidQueuedRecords.remove(p.queuedId);

          // Prefer persisted destination path for resume capability
          String finalPath;
          final rec = _records[p.queuedId];
          if (rec != null && (rec['destPath'] as String?) != null && (rec['destPath'] as String).isNotEmpty) {
            finalPath = rec['destPath'] as String;
          } else {
            final (dirAbsPath, filename) = await _smartLocationFor(finalUrl, finalFileName, p.torrentName);
            finalPath = '$dirAbsPath/$filename';
            _upsertRecord(p.queuedId, {'destPath': finalPath});
          }
          try { final d = Directory(finalPath).parent; if (!await d.exists()) { await d.create(recursive: true); } } catch (_) {}

          // Build headers for Range resume based on partial size and validators
          Map<String, String> headers = _buildResumeHeaders(finalPath, p.headers, rec);

          final (BaseDirectory baseDir, String relativeDir, String relFilename) = await Task.split(filePath: finalPath);
          final task = DownloadTask(
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
          final bool ok = await FileDownloader().enqueue(task);
          if (!ok) {
            throw Exception('Failed to enqueue download');
          }
          _upsertRecord(p.queuedId, {
            'state': 'running',
            'pluginTaskId': task.taskId,
            'url': finalUrl,
            'displayName': relFilename,
          });
          // capture validators for the refreshed URL
          unawaited(_captureValidatorsAndSave(p.queuedId, finalUrl));
        }
        runningCount += 1;
      } catch (e) {
        // Attempt fresh-link refresh once if we have restricted link meta
        bool retried = false;
        try {
          if (p.meta != null && p.meta!.isNotEmpty) {
            final meta = jsonDecode(p.meta!);
            final restricted = (meta['restrictedLink'] ?? '') as String;
            final apiKey = (meta['apiKey'] ?? '') as String;
            if (restricted.isNotEmpty && apiKey.isNotEmpty) {
              final fresh = await DebridService.unrestrictLink(apiKey, restricted);
              final freshUrl = (fresh['download'] ?? '').toString();
              final rdName = (fresh['filename'] ?? '').toString();
              if (freshUrl.isNotEmpty) {
                final refreshed = _PendingRequest(
                  queuedId: p.queuedId,
                  url: freshUrl,
                  providedFileName: (rdName.isNotEmpty ? rdName : p.providedFileName),
                  headers: p.headers,
                  wifiOnly: p.wifiOnly,
                  retries: p.retries,
                  meta: p.meta,
                  context: p.context,
                  torrentName: p.torrentName,
                  contentKey: p.contentKey,
                );
                _pending.insert(0, refreshed);
                _pendingById[refreshed.queuedId] = refreshed;
                await _persistPending();
                retried = true;
                continue; // try scheduling the refreshed entry immediately
              }
            }
          }
        } catch (_) {}

        if (!retried) {
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
          _upsertRecord(p.queuedId, {'state': 'failed', 'lastError': e.toString()});
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

  factory DownloadRecordDetails.fromMap(String recordId, Map<String, dynamic> map) {
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
  });
} 
