import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidDownloadHistory {
  AndroidDownloadHistory._internal();
  static final AndroidDownloadHistory _instance = AndroidDownloadHistory._internal();
  static AndroidDownloadHistory get instance => _instance;

  static const String _prefsKey = 'android_download_history_v1';

  final Map<String, TaskRecord> _recordsById = {};
  SharedPreferences? _prefs;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        for (final item in list) {
          final rec = TaskRecord.fromJson(Map<String, dynamic>.from(item));
          _recordsById[rec.taskId] = rec;
        }
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    final List<Map<String, dynamic>> list = _recordsById.values.map((e) => e.toJson()).toList();
    await _prefs!.setString(_prefsKey, jsonEncode(list));
  }

  void upsert(Task task, TaskStatus status, double progress, {int expectedFileSize = -1}) {
    final rec = TaskRecord(task, status, progress, expectedFileSize);
    _recordsById[task.taskId] = rec;
    _persist();
  }

  void removeById(String taskId) {
    _recordsById.remove(taskId);
    _persist();
  }

  List<TaskRecord> all() {
    final list = _recordsById.values.toList(growable: false);
    list.sort((a, b) {
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

      final r = rank(a.status).compareTo(rank(b.status));
      if (r != 0) return r;
      return b.task.creationTime.compareTo(a.task.creationTime);
    });
    return list;
  }
}
