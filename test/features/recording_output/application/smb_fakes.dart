// In-memory SMB share for uploader/coordinator tests.

import 'dart:async';
import 'dart:typed_data';

import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';

final class FakeShare implements SmbConnector {
  final Map<String, List<int>> files = {};
  final Set<String> dirs = {};
  final List<String> log = [];

  /// Thrown by connect when set.
  SmbException? connectError;

  /// Thrown by the next writer.write when set (then cleared).
  Object? writeError;

  /// Added to sizeOf results (simulates a short remote file).
  int sizeSkew = 0;

  /// Paths whose rename fails.
  final Set<String> renameFails = {};

  /// With [renameFails]: the rename happens, then its reply is lost.
  bool renameLandsThenFails = false;

  /// Called before each write; lets a test cancel mid-upload.
  void Function(String path, int writes)? beforeWrite;

  /// Modification times for [files]; unset ones read as 2026-01-01.
  final Map<String, DateTime> modified = {};

  /// Thrown by list when set.
  SmbException? listError;

  int connects = 0;
  int closes = 0;
  int writes = 0;
  int reads = 0;
  SmbTarget? lastTarget;
  String? lastPassword;

  @override
  Future<SmbConnection> connect(SmbTarget target, String? password) async {
    connects++;
    lastTarget = target;
    lastPassword = password;
    log.add('connect');
    if (connectError != null) throw connectError!;
    return _FakeConnection(this);
  }
}

final class _FakeConnection implements SmbConnection {
  _FakeConnection(this.share);
  final FakeShare share;

  @override
  Future<void> ensureDirectory(List<String> segments) async {
    share.log.add('mkdir ${segments.join('/')}');
    for (var i = 1; i <= segments.length; i++) {
      share.dirs.add(segments.take(i).join('/'));
    }
  }

  @override
  Future<bool> exists(String path) async =>
      share.files.containsKey(path) || share.dirs.contains(path);

  @override
  Future<SmbWriter> openWrite(String path) async {
    share.log.add('open $path');
    share.files[path] = <int>[];
    return _FakeWriter(share, path);
  }

  @override
  Future<List<SmbEntry>> list(String folder) async {
    if (share.listError != null) throw share.listError!;
    final prefix = folder.isEmpty ? '' : '$folder/';
    final names = <String, bool>{};
    for (final path in [...share.files.keys, ...share.dirs]) {
      if (!path.startsWith(prefix) || path == folder) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      final isFile = slash < 0 && share.files.containsKey(path);
      names[name] = (names[name] ?? false) || isFile;
    }
    return [
      for (final MapEntry(key: name, value: isFile) in names.entries)
        SmbEntry(
          name: name,
          isFile: isFile,
          bytes: isFile ? share.files['$prefix$name']!.length : 0,
          modified: share.modified['$prefix$name'] ?? DateTime.utc(2026),
        ),
    ];
  }

  @override
  Future<SmbReader> openRead(String path) async {
    final data = share.files[path];
    if (data == null) {
      throw SmbException(SmbFailureKind.notFound, 'no $path');
    }
    return _FakeReader(share, data);
  }

  @override
  Future<int> sizeOf(String path) async {
    final f = share.files[path];
    if (f == null) {
      throw SmbException(SmbFailureKind.notFound, 'no $path');
    }
    return f.length + share.sizeSkew;
  }

  @override
  Future<void> rename(String from, String to) async {
    share.log.add('rename $from -> $to');
    if (share.renameFails.contains(from)) {
      if (share.renameLandsThenFails) {
        share.files[to] = share.files.remove(from)!;
        throw const SmbException(SmbFailureKind.notFound, 'reply lost');
      }
      throw const SmbException(SmbFailureKind.accessDenied, 'rename refused');
    }
    share.files[to] = share.files.remove(from)!;
  }

  @override
  Future<void> delete(String path) async {
    share.log.add('delete $path');
    share.files.remove(path);
  }

  @override
  Future<void> close() async {
    share.closes++;
    share.log.add('close');
  }
}

final class _FakeReader implements SmbReader {
  _FakeReader(this.share, this.data);
  final FakeShare share;
  final List<int> data;

  @override
  int get size => data.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    share.reads++;
    final end = (offset + length).clamp(0, data.length);
    return Uint8List.fromList(data.sublist(offset.clamp(0, end), end));
  }

  @override
  Future<void> close() async => share.log.add('closer');
}

final class _FakeWriter implements SmbWriter {
  _FakeWriter(this.share, this.path);
  final FakeShare share;
  final String path;
  int _writes = 0;

  @override
  Future<void> write(Uint8List chunk) async {
    share.beforeWrite?.call(path, _writes);
    _writes++;
    share.writes++;
    final error = share.writeError;
    if (error != null) {
      share.writeError = null;
      throw error;
    }
    share.files[path]!.addAll(chunk);
  }

  @override
  Future<void> close() async => share.log.add('closew $path');
}

/// A byte source over in-memory files, emitting [pieceBytes]-sized pieces.
RecordingByteSource memorySource(
  Map<String, List<int>> files, {
  int pieceBytes = 1000,
  Set<String> failing = const {},
}) {
  return (uri) async* {
    if (failing.contains(uri)) {
      throw StateError('unreadable $uri');
    }
    final data = files[uri]!;
    for (var i = 0; i < data.length; i += pieceBytes) {
      final end = i + pieceBytes < data.length ? i + pieceBytes : data.length;
      yield Uint8List.fromList(data.sublist(i, end));
    }
  };
}

List<int> bytesOf(int n) => List<int>.generate(n, (i) => i % 251);

/// Settings with a fixed target and password, for code that only reads them.
final class FakeSettings implements SmbUploadSettings {
  FakeSettings({required this.target, this.password});

  SmbTarget target;
  String? password;
  SmbUploadLedger ledger = const SmbUploadLedger();

  @override
  Future<SmbTarget> readTarget() async => target;
  @override
  Future<String?> readPassword() async => password;
  @override
  Future<SmbUploadLedger> readLedger() async => ledger;
  @override
  Future<void> writeLedger(SmbUploadLedger value) async => ledger = value;
}
