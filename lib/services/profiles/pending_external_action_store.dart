import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../utils/app_storage.dart';
import 'device_key_provider.dart';

/// Device-level, sealed holding area for links received before a local profile
/// is unlocked. Pairing or an OS launch intent never chooses a profile; the
/// payload is consumed only after ProfileGate has authorized a local session.
class PendingExternalActionStore {
  PendingExternalActionStore._();

  static const String fileName = 'pending-external-actions-v1.json';
  static const int _version = 1;
  static const int _maxEntries = 32;
  static const int _maxValueBytes = 16 * 1024;
  static const int _maxFileBytes = 1024 * 1024;
  static const Duration _lifetime = Duration(hours: 24);
  static final Lock _lock = Lock();

  static Future<void> enqueueAll(Iterable<String> values) => _lock.synchronized(
    () async {
      if (!DeviceKeyProvider.isUnlocked) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      var entries = <_PendingExternalAction>[];
      try {
        entries = await _readEntries();
      } catch (_) {
        // A tampered/corrupt holding file contains no trusted action. Replace
        // it instead of turning a non-critical launch intent into a boot loop.
      }
      entries.removeWhere((entry) => entry.expiresAtMs <= now);
      for (final raw in values) {
        final value = raw.trim();
        if (value.isEmpty || utf8.encode(value).length > _maxValueBytes) {
          continue;
        }
        final id = _newId();
        final expiresAt = now + _lifetime.inMilliseconds;
        final envelope = await DeviceKeyProvider.cipher.seal(
          utf8.encode(value),
          associatedData: _aad(id, now, expiresAt),
        );
        entries.add(
          _PendingExternalAction(
            id: id,
            createdAtMs: now,
            expiresAtMs: expiresAt,
            envelope: envelope,
          ),
        );
        while (entries.length > _maxEntries) {
          entries.removeAt(0);
        }
      }
      await _writeEntries(entries);
    },
  );

  /// Atomically consumes every currently valid action before decrypting it.
  /// A crash can therefore lose an already-authorized action but can never
  /// replay it into a later profile session.
  static Future<List<String>> take() => _lock.synchronized(() async {
    if (!DeviceKeyProvider.isUnlocked) return const <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<_PendingExternalAction> entries;
    try {
      entries = (await _readEntries())
          .where((entry) => entry.expiresAtMs > now)
          .toList(growable: false);
    } catch (_) {
      await _writeEntries(const <_PendingExternalAction>[]);
      return const <String>[];
    }
    await _writeEntries(const <_PendingExternalAction>[]);
    final result = <String>[];
    for (final entry in entries) {
      try {
        final opened = await DeviceKeyProvider.cipher.open(
          entry.envelope,
          associatedData: _aad(entry.id, entry.createdAtMs, entry.expiresAtMs),
        );
        if (opened.length <= _maxValueBytes) result.add(utf8.decode(opened));
      } catch (_) {
        // Key loss, corruption, or tampering drops the action fail-closed.
      }
    }
    return result;
  });

  static Future<void> clear() => _lock.synchronized(() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  });

  static Future<List<_PendingExternalAction>> _readEntries() async {
    final file = await _file();
    if (!await file.exists()) return <_PendingExternalAction>[];
    if (await file.length() > _maxFileBytes) {
      throw const FormatException('Pending external action store is oversized');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _version ||
        decoded['entries'] is! List) {
      throw const FormatException('Pending external action store is corrupt');
    }
    final source = decoded['entries']! as List;
    if (source.length > _maxEntries) {
      throw const FormatException('Too many pending external actions');
    }
    return source
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending external action');
          }
          return _PendingExternalAction.fromJson(value);
        })
        .toList(growable: true);
  }

  static Future<void> _writeEntries(
    List<_PendingExternalAction> entries,
  ) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.next');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': _version,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      }),
      flush: true,
    );
    if (Platform.isWindows && await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<File> _file() async =>
      File(p.join((await AppStorage.support()).path, fileName));

  static List<int> _aad(
    String id,
    int createdAtMs,
    int expiresAtMs,
  ) => utf8.encode(
    'debrify-pending-action-v1|id=$id|created=$createdAtMs|expires=$expiresAtMs',
  );

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _PendingExternalAction {
  final String id;
  final int createdAtMs;
  final int expiresAtMs;
  final String envelope;

  const _PendingExternalAction({
    required this.id,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.envelope,
  });

  factory _PendingExternalAction.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAtMs = json['createdAtMs'];
    final expiresAtMs = json['expiresAtMs'];
    final envelope = json['envelope'];
    if (id is! String ||
        id.length < 16 ||
        id.length > 64 ||
        createdAtMs is! int ||
        expiresAtMs is! int ||
        createdAtMs < 0 ||
        expiresAtMs <= createdAtMs ||
        envelope is! String ||
        envelope.length > 128 * 1024) {
      throw const FormatException('Invalid pending external action');
    }
    return _PendingExternalAction(
      id: id,
      createdAtMs: createdAtMs,
      expiresAtMs: expiresAtMs,
      envelope: envelope,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'createdAtMs': createdAtMs,
    'expiresAtMs': expiresAtMs,
    'envelope': envelope,
  };
}
