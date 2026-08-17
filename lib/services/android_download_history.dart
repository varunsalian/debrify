import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_storage.dart';
import 'profiles/device_key_provider.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

/// Owner-filtered view over Android's device-wide download history.
///
/// Legacy mode retains the original SharedPreferences shape. Committed mode
/// uses one encrypted device store so native jobs can continue while another
/// profile is active without placing job state in a profile generation.
class AndroidDownloadHistory {
  AndroidDownloadHistory._internal();

  static final AndroidDownloadHistory _instance =
      AndroidDownloadHistory._internal();
  static AndroidDownloadHistory get instance => _instance;

  static const String _legacyPrefsKey = 'android_download_history_v1';
  static const String _deviceFileName = 'android_download_history_v2.json';
  static final List<int> _deviceAad = utf8.encode(
    'debrify-android-download-history-v2',
  );
  static const int _maxRecordsPerOwner = 20000;
  static const int _maxFileBytes = 16 * 1024 * 1024;

  final Map<String, TaskRecord> _recordsById = <String, TaskRecord>{};
  ProfilePreferences? _legacyPrefs;
  String? _loadedOwner;
  bool _committed = false;

  // Serializes read/merge/write operations across rapid task callbacks and
  // profile switches. Each write captures its owner and view before waiting.
  Future<void> _persistChain = Future<void>.value();
  bool _persistQueued = false;
  Object? _persistError;

  String get _currentOwner => ProfileRuntime.isProfileCommitted
      ? ProfileRuntime.capture().profileId
      : 'legacy-admin-v1';

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    final committed = ProfileRuntime.isProfileCommitted;
    final owner = _currentOwner;
    if (_loadedOwner == owner && _committed == committed) return;
    await _persistChain;
    _recordsById.clear();
    _committed = committed;
    _loadedOwner = owner;

    if (!committed) {
      _legacyPrefs = await ProfilePreferences.instance();
      try {
        _decodeRecords(_legacyPrefs!.getString(_legacyPrefsKey));
      } catch (_) {
        // Preserve the legacy behavior of treating malformed history as empty.
        _recordsById.clear();
      }
      return;
    }

    _legacyPrefs = null;
    final all = await _readDeviceOwners();
    final stored = all[owner];
    if (stored != null) {
      _decodeRecordList(stored);
      return;
    }

    // The old job history remains untouched for downgrade safety. Import it
    // exactly once into the migrated Admin's owner bucket.
    if (owner == 'legacy-admin-v1') {
      final prefs = await SharedPreferences.getInstance();
      try {
        _decodeRecords(prefs.getString(_legacyPrefsKey));
      } catch (_) {
        _recordsById.clear();
      }
      if (_recordsById.isNotEmpty) {
        await _persistCommittedSnapshot(owner, _snapshot());
      }
    }
  }

  void _decodeRecords(String? raw) {
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid Android download history');
    }
    _decodeRecordList(decoded);
  }

  void _decodeRecordList(List<dynamic> values) {
    if (values.length > _maxRecordsPerOwner) {
      throw const FormatException('Android download history exceeds limit');
    }
    for (final item in values) {
      if (item is! Map) {
        throw const FormatException('Invalid Android download record');
      }
      final record = TaskRecord.fromJson(Map<String, dynamic>.from(item));
      _recordsById[record.taskId] = record;
    }
  }

  List<Map<String, dynamic>> _snapshot() => _recordsById.values
      .map((record) => Map<String, dynamic>.from(record.toJson()))
      .toList(growable: false);

  void _persist() {
    final owner = _loadedOwner;
    if (owner == null || _persistQueued) return;
    _persistQueued = true;
    _persistChain = _persistChain
        .then((_) async {
          _persistQueued = false;
          final snapshot = _snapshot();
          if (_committed) {
            await _persistCommittedSnapshot(owner, snapshot);
          } else {
            final prefs = _legacyPrefs;
            if (prefs != null &&
                !await prefs.setString(_legacyPrefsKey, jsonEncode(snapshot))) {
              throw StateError('Could not persist Android download history');
            }
          }
        })
        .catchError((Object error) {
          _persistError = error;
        });
  }

  Future<Map<String, List<dynamic>>> _readDeviceOwners() async {
    final file = File(await _deviceFilePath());
    if (!await file.exists()) return <String, List<dynamic>>{};
    if (await file.length() > _maxFileBytes) {
      throw const FormatException('Android download history exceeds limit');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['version'] != 2 ||
        decoded['sealed'] is! String) {
      throw const FormatException('Invalid Android download history envelope');
    }
    final clear = await DeviceKeyProvider.cipher.open(
      decoded['sealed'] as String,
      associatedData: _deviceAad,
    );
    if (clear.length > _maxFileBytes) {
      throw const FormatException('Android download history exceeds limit');
    }
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map ||
        payload['version'] != 1 ||
        payload['owners'] is! Map) {
      throw const FormatException('Invalid Android download history payload');
    }
    final owners = <String, List<dynamic>>{};
    for (final entry in (payload['owners'] as Map).entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).length > _maxRecordsPerOwner) {
        throw const FormatException('Invalid Android history owner bucket');
      }
      owners[entry.key as String] = List<dynamic>.from(entry.value as List);
    }
    return owners;
  }

  Future<void> _persistCommittedSnapshot(
    String owner,
    List<Map<String, dynamic>> snapshot,
  ) async {
    final owners = await _readDeviceOwners();
    if (snapshot.isEmpty) {
      owners.remove(owner);
    } else {
      owners[owner] = snapshot;
    }
    final sealed = await DeviceKeyProvider.cipher.seal(
      utf8.encode(
        jsonEncode(<String, Object?>{'version': 1, 'owners': owners}),
      ),
      associatedData: _deviceAad,
    );
    final encoded = jsonEncode(<String, Object>{
      'version': 2,
      'sealed': sealed,
    });
    if (utf8.encode(encoded).length > _maxFileBytes) {
      throw StateError('Android download history exceeds limit');
    }
    final file = File(await _deviceFilePath());
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(encoded, flush: true);
    await temporary.rename(file.path);
  }

  Future<String> _deviceFilePath() async =>
      p.join((await AppStorage.support()).path, _deviceFileName);

  /// Flushes and drops only the active owner projection. Native work and the
  /// other owner buckets stay intact.
  Future<void> prepareProfileSwitch() async {
    await _persistChain;
    final error = _persistError;
    _persistError = null;
    if (error != null) {
      throw StateError('Could not persist Android download history: $error');
    }
    _recordsById.clear();
    _legacyPrefs = null;
    _loadedOwner = null;
  }

  /// Device-reset-only cleanup. Ordinary profile clear/reset never calls it.
  Future<void> clearDeviceState() async {
    await _persistChain;
    _persistError = null;
    _recordsById.clear();
    _legacyPrefs = null;
    _loadedOwner = null;
    final file = File(await _deviceFilePath());
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }

  void upsert(
    Task task,
    TaskStatus status,
    double progress, {
    int expectedFileSize = -1,
  }) {
    _recordsById[task.taskId] = TaskRecord(
      task,
      status,
      progress,
      expectedFileSize,
    );
    _persist();
  }

  void removeById(String taskId) {
    _recordsById.remove(taskId);
    _persist();
  }

  TaskRecord? byId(String taskId) => _recordsById[taskId];

  void clearAll() {
    _recordsById.clear();
    _persist();
  }

  List<TaskRecord> all() {
    final list = _recordsById.values.toList(growable: false);
    list.sort((a, b) {
      int rank(TaskStatus status) {
        switch (status) {
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

      final status = rank(a.status).compareTo(rank(b.status));
      if (status != 0) return status;
      return b.task.creationTime.compareTo(a.task.creationTime);
    });
    return list;
  }
}
