import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

import '../utils/app_storage.dart';
import 'profiles/privacy_log.dart';

enum DiagnosticLevel { debug, info, warning, error }

/// An explicitly audited, non-content string such as a platform, state, enum,
/// version, or short correlation token. Plain strings passed as fields are
/// rejected so future instrumentation cannot accidentally persist titles,
/// filenames, or other user content.
class DiagnosticLabel {
  const DiagnosticLabel(this.value);

  final String value;
}

class DiagnosticLogExport {
  const DiagnosticLogExport({
    required this.fileName,
    required this.bytes,
    required this.entryCount,
    required this.windowStart,
    required this.windowEnd,
  });

  final String fileName;
  final Uint8List bytes;
  final int entryCount;
  final DateTime windowStart;
  final DateTime windowEnd;
}

/// Privacy-filtered, bounded diagnostics retained independently of console
/// logging. Only explicitly instrumented events and structural values enter
/// this store; general console output and exception bodies are never copied.
/// Release R8 rules are free to remove Log.d/i/v because this sink writes
/// directly to app-private storage.
///
/// Files are split into short time buckets. That makes pruning cheap and
/// avoids rewriting a multi-megabyte active log on every message. Each bucket
/// is independently capped, and exports filter individual records to the
/// requested two-hour window rather than relying only on file timestamps.
class DiagnosticLog {
  DiagnosticLog({
    DateTime Function()? clock,
    this.retention = const Duration(hours: 2),
    this.segmentDuration = const Duration(minutes: 15),
    this.maxSegmentBytes = 256 * 1024,
  }) : _clock = clock ?? DateTime.now;

  static final DiagnosticLog instance = DiagnosticLog();

  static const MethodChannel _nativeChannel = MethodChannel(
    'debrify/native_diagnostics',
  );
  static const String _filePrefix = 'debrify-diagnostics-';
  static const String _fileSuffix = '.jsonl';
  static const int _maxPendingEntries = 2000;
  static const int _maxMemoryEntries = 4000;

  final DateTime Function() _clock;
  final Duration retention;
  final Duration segmentDuration;
  final int maxSegmentBytes;
  final Lock _ioLock = Lock();
  final List<_DiagnosticEntry> _pending = <_DiagnosticEntry>[];
  final List<_DiagnosticEntry> _memoryFallback = <_DiagnosticEntry>[];

  Future<void>? _initializing;
  Directory? _directory;
  Timer? _flushTimer;
  bool _accepting = false;
  bool _memoryOnly = false;
  bool _disabledForDeviceReset = false;
  int _droppedEntries = 0;
  int _writeGeneration = 0;

  bool get isAvailable => _accepting;

  /// [directoryOverride] keeps the storage engine independently testable.
  /// Production callers should omit it.
  Future<void> initialize({@visibleForTesting Directory? directoryOverride}) {
    if (_disabledForDeviceReset) return Future<void>.value();
    return _initializing ??= _initialize(directoryOverride);
  }

  Future<void> _initialize(Directory? directoryOverride) async {
    if (_disabledForDeviceReset) return;
    _accepting = true;
    if (kIsWeb) {
      _memoryOnly = true;
      recordEvent(
        source: 'app',
        event: 'diagnostics_initialized',
        fields: const <String, Object?>{'storage': DiagnosticLabel('memory')},
      );
      return;
    }

    try {
      final root = directoryOverride ?? await AppStorage.support();
      final directory = Directory(path.join(root.path, 'diagnostics'));
      await directory.create(recursive: true);
      _directory = directory;
      await _ioLock.synchronized(() => _pruneExpiredFiles(directory));
      recordEvent(
        source: 'app',
        event: 'diagnostics_initialized',
        fields: const <String, Object?>{'storage': DiagnosticLabel('file')},
      );
    } catch (_) {
      // Diagnostics must never become a startup dependency. Retain a bounded
      // in-memory window so an export can still help when storage is damaged.
      _memoryOnly = true;
      recordEvent(
        source: 'app',
        event: 'diagnostics_storage_unavailable',
        level: DiagnosticLevel.warning,
      );
    }
  }

  void recordEvent({
    required String source,
    required String event,
    DiagnosticLevel level = DiagnosticLevel.info,
    Map<String, Object?> fields = const <String, Object?>{},
    bool flushImmediately = false,
  }) {
    final safeFields = <String, Object?>{};
    for (final entry in fields.entries) {
      final value = _safeField(entry.value);
      if (!identical(value, _unsafeField)) {
        safeFields[_safeLabel(entry.key)] = value;
      }
    }
    _enqueue(
      _DiagnosticEntry(
        timestamp: _clock().toUtc(),
        level: level,
        source: _safeLabel(source),
        event: _safeLabel(event),
        fields: safeFields,
      ),
      flushImmediately: flushImmediately,
    );
  }

  void recordError({
    required String source,
    required String event,
    required Object error,
    required StackTrace stackTrace,
    bool flushImmediately = true,
  }) {
    _enqueue(
      _DiagnosticEntry(
        timestamp: _clock().toUtc(),
        level: DiagnosticLevel.error,
        source: _safeLabel(source),
        event: _safeLabel(event),
        fields: <String, Object?>{
          'errorType': _safeLabel(error.runtimeType.toString()),
          ..._pluginChannelFields(error),
          'stack': _safeStack(stackTrace),
        },
      ),
      flushImmediately: flushImmediately,
    );
  }

  /// A MissingPluginException names a code constant, never data: its message
  /// is the fixed "No implementation found for method X on channel Y". Keep
  /// the channel and method so a platform gap can be located from the log
  /// instead of guessed at from a stack that only shows framework frames.
  static Map<String, Object?> _pluginChannelFields(Object error) {
    if (error is! MissingPluginException) return const <String, Object?>{};
    final match = RegExp(
      r'method ([A-Za-z0-9_.]+) on channel ([A-Za-z0-9_./:-]+)$',
    ).firstMatch(error.message ?? '');
    if (match == null) return const <String, Object?>{};
    return <String, Object?>{
      'method': _safeLabel(match.group(1)!),
      'channel': _safeLabel(match.group(2)!),
    };
  }

  void recordFlutterError(FlutterErrorDetails details) {
    _enqueue(
      _DiagnosticEntry(
        timestamp: _clock().toUtc(),
        level: DiagnosticLevel.error,
        source: 'flutter',
        event: 'framework_error',
        fields: <String, Object?>{
          'errorType': _safeLabel(details.exception.runtimeType.toString()),
          ..._pluginChannelFields(details.exception),
          'stack': _safeStack(details.stack ?? StackTrace.current),
        },
      ),
      flushImmediately: true,
    );
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty && _droppedEntries == 0) return;
    final generation = _writeGeneration;

    final batch = List<_DiagnosticEntry>.of(_pending);
    _pending.clear();
    if (_droppedEntries > 0) {
      batch.add(
        _DiagnosticEntry(
          timestamp: _clock().toUtc(),
          level: DiagnosticLevel.warning,
          source: 'diagnostics',
          event: 'entries_dropped',
          fields: <String, Object?>{'count': _droppedEntries},
        ),
      );
      _droppedEntries = 0;
    }

    final directory = _directory;
    if (_memoryOnly || directory == null) {
      if (_accepting && generation == _writeGeneration) {
        _retainInMemory(batch);
      }
      return;
    }

    await _ioLock.synchronized(() async {
      if (!_accepting || generation != _writeGeneration) return;
      try {
        final grouped = <int, List<_DiagnosticEntry>>{};
        for (final entry in batch) {
          grouped
              .putIfAbsent(_segmentStartMs(entry.timestamp), () => [])
              .add(entry);
        }
        for (final group in grouped.entries) {
          final file = File(
            path.join(
              directory.path,
              '$_filePrefix${group.key}-dart$_fileSuffix',
            ),
          );
          final encoded = StringBuffer();
          for (final entry in group.value) {
            encoded.writeln(jsonEncode(entry.toJson()));
          }
          await file.writeAsString(
            encoded.toString(),
            mode: FileMode.append,
            flush: false,
          );
          await _trimSegment(file);
        }
        await _pruneExpiredFiles(directory);
      } catch (_) {
        if (_accepting && generation == _writeGeneration) {
          _retainInMemory(batch);
        }
      }
    });
  }

  Future<DiagnosticLogExport> exportLastWindow() async {
    await initialize();
    if (!_accepting) {
      throw StateError('Diagnostic logging is unavailable after device reset');
    }
    await _flushNative();
    await flush();

    final now = _clock().toUtc();
    final cutoff = now.subtract(retention);
    final entries = <_DiagnosticExportLine>[];
    final directory = _directory;

    if (directory != null) {
      await _ioLock.synchronized(() async {
        await _pruneExpiredFiles(directory);
        final files = await directory
            .list()
            .where((entity) => entity is File && _isDiagnosticFile(entity))
            .cast<File>()
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          try {
            await for (final line
                in file
                    .openRead()
                    .transform(utf8.decoder)
                    .transform(const LineSplitter())) {
              final decoded = jsonDecode(line);
              if (decoded is! Map<String, dynamic>) continue;
              final timestamp = DateTime.tryParse(
                decoded['timestamp']?.toString() ?? '',
              )?.toUtc();
              if (timestamp == null ||
                  timestamp.isBefore(cutoff) ||
                  timestamp.isAfter(now.add(const Duration(minutes: 1)))) {
                continue;
              }
              entries.add(
                _DiagnosticExportLine(timestamp: timestamp, jsonLine: line),
              );
            }
          } catch (_) {
            // A partial final line after a hard process kill must not prevent
            // the rest of the retained files from being exported.
          }
        }
      });
    }

    for (final entry in _memoryFallback) {
      if (!entry.timestamp.isBefore(cutoff) && !entry.timestamp.isAfter(now)) {
        entries.add(
          _DiagnosticExportLine(
            timestamp: entry.timestamp,
            jsonLine: jsonEncode(entry.toJson()),
          ),
        );
      }
    }
    entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final header = <String, Object?>{
      'timestamp': now.toIso8601String(),
      'level': DiagnosticLevel.info.name,
      'source': 'diagnostics',
      'event': 'export_metadata',
      'fields': <String, Object?>{
        'windowStart': cutoff.toIso8601String(),
        'windowEnd': now.toIso8601String(),
        'entryCount': entries.length,
        'format': 1,
      },
    };
    final output = StringBuffer()..writeln(jsonEncode(header));
    for (final entry in entries) {
      output.writeln(entry.jsonLine);
    }

    return DiagnosticLogExport(
      fileName: 'debrify-diagnostics-${_fileTimestamp(now)}.jsonl',
      bytes: Uint8List.fromList(utf8.encode(output.toString())),
      entryCount: entries.length,
      windowStart: cutoff,
      windowEnd: now,
    );
  }

  @visibleForTesting
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    _accepting = false;
  }

  /// Test-only: returns the singleton to its never-initialized state so a
  /// later [initialize] runs again. [dispose] deliberately keeps the cached
  /// initialization (production never re-initializes in one process), which
  /// makes two diagnostics tests in one file step on each other.
  @visibleForTesting
  Future<void> debugReset() async {
    await dispose();
    _writeGeneration++;
    _pending.clear();
    _memoryFallback.clear();
    _initializing = null;
    _directory = null;
    _memoryOnly = false;
    _disabledForDeviceReset = false;
    _droppedEntries = 0;
    _accepting = false;
  }

  /// Permanently stops this process' diagnostic writers and erases both Dart
  /// and native Android state. Device reset terminates immediately afterwards;
  /// refusing reinitialization closes the gap before that termination lands.
  Future<void> clearForDeviceReset() async {
    _disabledForDeviceReset = true;
    _accepting = false;
    _writeGeneration++;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _memoryFallback.clear();
    _droppedEntries = 0;

    Object? firstFailure;
    StackTrace? firstFailureStack;
    try {
      final initializing = _initializing;
      if (initializing != null) await initializing;
      await _clearNativeForDeviceReset();
    } catch (error, stackTrace) {
      firstFailure = error;
      firstFailureStack = stackTrace;
    }

    try {
      await _ioLock.synchronized(() async {
        var directory = _directory;
        if (directory == null && !kIsWeb) {
          final root = await AppStorage.support();
          directory = Directory(path.join(root.path, 'diagnostics'));
        }
        _directory = null;
        _memoryOnly = false;
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
    } catch (error, stackTrace) {
      firstFailure ??= error;
      firstFailureStack ??= stackTrace;
    }

    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstFailureStack!);
    }
  }

  void _enqueue(_DiagnosticEntry entry, {bool flushImmediately = false}) {
    if (!_accepting) return;
    if (_pending.length >= _maxPendingEntries) {
      const discard = 200;
      _pending.removeRange(0, discard);
      _droppedEntries += discard;
    }
    _pending.add(entry);

    if (flushImmediately) {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(flush());
      return;
    }
    _flushTimer ??= Timer(const Duration(milliseconds: 750), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  void _retainInMemory(List<_DiagnosticEntry> entries) {
    _memoryFallback.addAll(entries);
    final cutoff = _clock().toUtc().subtract(retention);
    _memoryFallback.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    if (_memoryFallback.length > _maxMemoryEntries) {
      _memoryFallback.removeRange(
        0,
        _memoryFallback.length - _maxMemoryEntries,
      );
    }
  }

  Future<void> _flushNative() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _nativeChannel
          .invokeMethod<void>('flush')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _clearNativeForDeviceReset() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _nativeChannel
        .invokeMethod<void>('clearForDeviceReset')
        .timeout(const Duration(seconds: 5));
  }

  Future<void> _pruneExpiredFiles(Directory directory) async {
    final cutoffMs = _clock()
        .toUtc()
        .subtract(retention)
        .millisecondsSinceEpoch;
    await for (final entity in directory.list()) {
      if (entity is! File || !_isDiagnosticFile(entity)) continue;
      final segmentStart = _segmentFromFile(entity);
      if (segmentStart == null) continue;
      if (segmentStart + segmentDuration.inMilliseconds <= cutoffMs) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _trimSegment(File file) async {
    final length = await file.length();
    if (length <= maxSegmentBytes) return;
    final bytes = await file.readAsBytes();
    // Retain half a segment after overflow. Trimming exactly back to the cap
    // would force a full read/rewrite on every subsequent batch while a noisy
    // subsystem is active, which is the worst time to add storage pressure.
    var start = bytes.length - (maxSegmentBytes ~/ 2);
    while (start < bytes.length && bytes[start] != 0x0a) {
      start++;
    }
    if (start < bytes.length) start++;
    final retained = start < bytes.length ? bytes.sublist(start) : Uint8List(0);
    await file.writeAsBytes(retained, flush: true);
  }

  bool _isDiagnosticFile(FileSystemEntity entity) {
    final name = path.basename(entity.path);
    return name.startsWith(_filePrefix) && name.endsWith(_fileSuffix);
  }

  int? _segmentFromFile(File file) {
    final name = path.basename(file.path);
    final match = RegExp(
      '^${RegExp.escape(_filePrefix)}([0-9]+)-.+${RegExp.escape(_fileSuffix)}\$',
    ).firstMatch(name);
    return int.tryParse(match?.group(1) ?? '');
  }

  int _segmentStartMs(DateTime timestamp) {
    final milliseconds = timestamp.millisecondsSinceEpoch;
    return milliseconds - (milliseconds % segmentDuration.inMilliseconds);
  }

  static String _safeLabel(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'unknown';
    return cleaned.length <= 64 ? cleaned : cleaned.substring(0, 64);
  }

  static final Object _unsafeField = Object();
  static final RegExp _structuralString = RegExp(r'^[a-zA-Z0-9_.:+-]{1,80}$');

  static Object? _safeField(Object? value) {
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : _unsafeField;
    if (value is Type) return _safeLabel(value.toString());
    if (value is DiagnosticLabel) {
      final redacted = PrivacyLog.redact(value.value);
      return _structuralString.hasMatch(redacted) ? redacted : _unsafeField;
    }
    if (value is Iterable<Object?>) {
      final safe = <Object?>[];
      for (final item in value.take(32)) {
        final sanitized = _safeField(item);
        if (identical(sanitized, _unsafeField)) return _unsafeField;
        safe.add(sanitized);
      }
      return safe;
    }
    return _unsafeField;
  }

  static List<String> _safeStack(StackTrace stackTrace) {
    return stackTrace
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(24)
        .map(PrivacyLog.redact)
        .toList(growable: false);
  }

  static String _fileTimestamp(DateTime timestamp) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${timestamp.year}${two(timestamp.month)}${two(timestamp.day)}-'
        '${two(timestamp.hour)}${two(timestamp.minute)}${two(timestamp.second)}Z';
  }
}

class _DiagnosticExportLine {
  const _DiagnosticExportLine({
    required this.timestamp,
    required this.jsonLine,
  });

  final DateTime timestamp;
  final String jsonLine;
}

class _DiagnosticEntry {
  const _DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.event,
    this.fields = const <String, Object?>{},
  });

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String source;
  final String event;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => <String, Object?>{
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'source': source,
    'event': event,
    if (fields.isNotEmpty) 'fields': fields,
  };
}
