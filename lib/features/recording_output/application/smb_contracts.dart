// Boundaries of the SMB recording upload. The uploader and coordinator depend
// only on these; the dart_smb2 adapter, the local file readers and the
// settings store implement them.

import 'dart:typed_data';

import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';

/// Opens a session on [SmbTarget]'s share.
abstract interface class SmbConnector {
  /// Throws [SmbException] when the server, share or login fails.
  Future<SmbConnection> connect(SmbTarget target, String? password);
}

/// One logged-on session. Paths are relative to the share root and use '/'.
/// Every method throws [SmbException] on failure.
abstract interface class SmbConnection {
  /// Creates each missing level of [segments] (`['a', 'b']` makes `a`, `a/b`).
  Future<void> ensureDirectory(List<String> segments);
  Future<bool> exists(String path);

  /// Creates or empties [path] for writing from offset 0.
  Future<SmbWriter> openWrite(String path);

  /// The entries directly inside [folder] ('' is the share root).
  Future<List<SmbEntry>> list(String folder);

  /// Opens [path] for reading at any offset.
  Future<SmbReader> openRead(String path);
  Future<int> sizeOf(String path);
  Future<void> rename(String from, String to);
  Future<void> delete(String path);

  /// Logs off. Safe to call more than once.
  Future<void> close();
}

/// One entry of [SmbConnection.list].
final class SmbEntry {
  const SmbEntry({
    required this.name,
    required this.isFile,
    required this.bytes,
    required this.modified,
  });

  final String name;
  final bool isFile;
  final int bytes;
  final DateTime modified;
}

/// Random-access reader returned by [SmbConnection.openRead].
abstract interface class SmbReader {
  /// The file's size when it was opened.
  int get size;

  /// Up to [length] bytes from [offset]; fewer only at the end of the file.
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}

/// Sequential writer returned by [SmbConnection.openWrite].
abstract interface class SmbWriter {
  Future<void> write(Uint8List chunk);
  Future<void> close();
}

final class SmbException implements Exception {
  const SmbException(this.kind, this.message);

  final SmbFailureKind kind;
  final String message;

  @override
  String toString() => 'SmbException(${kind.name}): $message';
}

/// Cooperative cancellation for one upload.
final class SmbCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Reads a finished local recording by its library uri (`content://`,
/// `file://` or a plain path).
typedef RecordingByteSource = Stream<Uint8List> Function(String uri);

/// What the upload coordinator needs from settings storage.
abstract interface class SmbUploadSettings {
  Future<SmbTarget> readTarget();
  Future<String?> readPassword();
  Future<SmbUploadLedger> readLedger();
  Future<void> writeLedger(SmbUploadLedger ledger);
}
