// Streams one live recording straight to the SMB share, so a long capture
// never has to fit on this device first. The capture loop owns the writer:
// it adds bytes as they arrive and, when a write fails, takes the bytes the
// share never received and carries on in a local file.

import 'dart:async';
import 'dart:typed_data';

import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';
import 'smb_contracts.dart';
import 'smb_uploader.dart';

final class SmbDirectWriter {
  SmbDirectWriter._(
    this._connection,
    this._writer,
    this.remotePath,
    this.label,
  );

  /// Bytes gathered before each write: the stream arrives in small pieces,
  /// and one round trip per piece would cap the share's throughput.
  static const flushBytes = 1024 * 1024;

  /// Connects, creates the folder and opens a new file named after
  /// [fileName] (suffixed when taken). Throws [SmbException] when the share
  /// cannot be used; the session is closed again on any failure.
  static Future<SmbDirectWriter> open({
    required SmbConnector connector,
    required SmbTarget target,
    required String? password,
    required String fileName,
  }) async {
    final connection = await connector.connect(target, password);
    try {
      await connection.ensureDirectory(target.folderSegments);
      final remote = await SmbUploader.reserveRemoteName(
        connection,
        target,
        fileName,
      );
      if (remote == null) {
        throw const SmbException(SmbFailureKind.other, 'no free file name');
      }
      final writer = await connection.openWrite(remote);
      final name = remote.split('/').last;
      final folder = target.displayAddress;
      return SmbDirectWriter._(connection, writer, remote, '$folder\\$name');
    } catch (_) {
      await _quietly(connection.close);
      rethrow;
    }
  }

  final SmbConnection _connection;
  final SmbWriter _writer;

  /// Share-relative path of the recording.
  final String remotePath;

  /// `\\host\share\folder\file.ts`, for messages.
  final String label;

  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _written = 0;
  bool _closed = false;

  /// Bytes the share has acknowledged.
  int get bytesWritten => _written;

  /// Buffers [chunk] and writes once [flushBytes] have gathered. Throws
  /// [SmbException] when the write fails; the unsent bytes stay available
  /// through [takeUnsent].
  Future<void> add(Uint8List chunk) async {
    _pending.add(chunk);
    if (_pending.length >= flushBytes) await _flush();
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final bytes = _pending.takeBytes();
    try {
      await _writer.write(bytes);
    } catch (_) {
      // Keep them for the local fallback: the share may hold none of them.
      _pending.add(bytes);
      rethrow;
    }
    _written += bytes.length;
  }

  /// The bytes the share never received, removed from this writer.
  Uint8List takeUnsent() => _pending.takeBytes();

  /// Writes what is buffered, closes the file and logs off. A recording that
  /// never got a byte is deleted rather than left as an empty file. Throws
  /// [SmbException] when the last write fails (see [takeUnsent]); the
  /// session is closed either way.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _flush();
    } finally {
      await _quietly(_writer.close);
      if (_written == 0) await _quietly(() => _connection.delete(remotePath));
      await _quietly(_connection.close);
    }
  }

  /// Gives up on the share after a failed write, sending nothing more. The
  /// teardown is started, not awaited: on a server that stopped answering
  /// each step waits out its timeout, and the capture cannot pause that long.
  Future<void> abandon() async {
    if (_closed) return;
    _closed = true;
    unawaited(() async {
      await _quietly(_writer.close);
      if (_written == 0) await _quietly(() => _connection.delete(remotePath));
      await _quietly(_connection.close);
    }());
  }

  static Future<void> _quietly(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      // Cleanup never decides what happens to the recording.
    }
  }
}
