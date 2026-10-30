// Pushes finished recordings to an SMB share: connect, reserve a remote name,
// stream the local bytes through a `.part` file, verify sizes, then rename.
// Depends only on the SMB contracts so tests can drive it with fakes.

import 'dart:async';
import 'dart:typed_data';

import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';
import 'smb_contracts.dart';

/// Result of one upload attempt.
sealed class SmbUploadOutcome {
  const SmbUploadOutcome();
}

/// The recording reached the share under [remotePath].
final class SmbUploaded extends SmbUploadOutcome {
  const SmbUploaded(this.remotePath);

  final String remotePath;
}

/// The attempt failed with [kind] and a human-readable [message].
final class SmbUploadFailed extends SmbUploadOutcome {
  const SmbUploadFailed(this.kind, this.message);

  final SmbFailureKind kind;
  final String message;
}

/// One-shot uploader: every [upload] opens its own session and always closes
/// it. No state is kept between calls, so concurrent uploads never share a
/// connection or a writer.
final class SmbUploader {
  SmbUploader({
    required SmbConnector connector,
    required RecordingByteSource source,
  }) : _connector = connector,
       _source = source;

  /// Bytes handed to the writer per call; the last chunk may be shorter.
  static const chunkBytes = 1024 * 1024;

  static const _probeName = '.debrify_probe';
  static const _maxNameSuffix = 99;

  /// Characters SMB forbids plus every control char, replaced by `_`.
  static final _illegalName = RegExp(r'[/\\:*?"<>|\x00-\x1f]');

  final SmbConnector _connector;
  final RecordingByteSource _source;

  Future<SmbUploadOutcome> upload({
    required SmbTarget target,
    required String? password,
    required SmbLocalRecording recording,
    SmbCancelToken? cancel,
    void Function(int sent, int total)? onProgress,
  }) async {
    final SmbConnection connection;
    try {
      connection = await _connector.connect(target, password);
    } catch (error) {
      // A failed connect owns no session, so there is nothing to close.
      return _failureFrom(error);
    }
    try {
      return await _uploadOn(connection, target, recording, cancel, onProgress);
    } finally {
      await _quietlyClose(connection);
    }
  }

  /// Settings check: connect, ensureDirectory(folderSegments), write a
  /// 2-byte file `<folder>/.debrify_probe` ('ok'), delete it, close.
  /// null = works, else the failure.
  Future<SmbUploadFailed?> probe({
    required SmbTarget target,
    required String? password,
  }) async {
    final SmbConnection connection;
    try {
      connection = await _connector.connect(target, password);
    } catch (error) {
      return _failureFrom(error);
    }
    try {
      final probePath = target.remotePathFor(_probeName);
      await connection.ensureDirectory(target.folderSegments);
      final writer = await connection.openWrite(probePath);
      await writer.write(Uint8List.fromList(const [0x6f, 0x6b])); // 'ok'
      await writer.close();
      await connection.delete(probePath);
      return null;
    } catch (error) {
      return _failureFrom(error);
    } finally {
      await _quietlyClose(connection);
    }
  }

  Future<SmbUploadOutcome> _uploadOn(
    SmbConnection connection,
    SmbTarget target,
    SmbLocalRecording recording,
    SmbCancelToken? cancel,
    void Function(int sent, int total)? onProgress,
  ) async {
    String? part;
    SmbWriter? writer;
    try {
      await connection.ensureDirectory(target.folderSegments);
      final remote = await reserveRemoteName(
        connection,
        target,
        recording.name,
      );
      if (remote == null) {
        return const SmbUploadFailed(SmbFailureKind.other, 'no free file name');
      }
      part = '$remote.part';
      if (await connection.exists(part)) {
        // A leftover from an earlier crash would poison openWrite.
        await connection.delete(part);
      }
      if (cancel?.isCancelled ?? false) {
        return const SmbUploadFailed(SmbFailureKind.cancelled, 'cancelled');
      }
      final openWriter = await connection.openWrite(part);
      writer = openWriter;
      final transfer = await _sendBytes(
        writer: openWriter,
        recording: recording,
        cancel: cancel,
        onProgress: onProgress,
      );
      // Cleanup = close the writer if open (ignore errors) + delete the part.
      await openWriter.close();
      switch (transfer) {
        case _TransferFailed(:final failure):
          await _discardPart(connection, part);
          return failure;
        case _TransferOk(:final bytes):
          if (bytes != recording.bytes) {
            await _discardPart(connection, part);
            return SmbUploadFailed(
              SmbFailureKind.sizeMismatch,
              'size mismatch: sent $bytes of ${recording.bytes}',
            );
          }
          final remoteSize = await connection.sizeOf(part);
          if (remoteSize != bytes) {
            await _discardPart(connection, part);
            return SmbUploadFailed(
              SmbFailureKind.sizeMismatch,
              'size mismatch: remote $remoteSize, sent $bytes',
            );
          }
          try {
            await connection.rename(part, remote);
          } catch (_) {
            // dart_smb2 replays a rename after a dropped connection; when the
            // first one landed, the replay fails although the file is there.
            if (await _landed(connection, remote, bytes)) {
              return SmbUploaded(remote);
            }
            rethrow;
          }
          return SmbUploaded(remote);
      }
    } catch (error) {
      if (part != null) {
        await _cleanup(connection, writer, part);
      }
      return _failureFrom(error);
    }
  }

  static Future<bool> _landed(
    SmbConnection connection,
    String remote,
    int bytes,
  ) async {
    try {
      return await connection.exists(remote) &&
          await connection.sizeOf(remote) == bytes;
    } catch (_) {
      return false;
    }
  }

  /// Re-chunks the source stream into [chunkBytes] writes. Checks [cancel]
  /// before every write; a source stream error becomes `readFailed` while a
  /// writer error propagates so the caller maps its own failure kind.
  Future<_TransferResult> _sendBytes({
    required SmbWriter writer,
    required SmbLocalRecording recording,
    required SmbCancelToken? cancel,
    required void Function(int sent, int total)? onProgress,
  }) async {
    var sent = 0;
    final chunk = Uint8List(chunkBytes);
    var filled = 0;
    final pieces = StreamIterator<Uint8List>(_source(recording.uri));
    var drained = false;
    try {
      while (true) {
        final bool hasNext;
        try {
          hasNext = await pieces.moveNext();
        } catch (_) {
          return _readFailed;
        }
        if (!hasNext) {
          drained = true;
          break;
        }
        final piece = pieces.current;
        var offset = 0;
        while (offset < piece.length) {
          if (cancel?.isCancelled ?? false) return _cancelled;
          final space = chunkBytes - filled;
          final remaining = piece.length - offset;
          final count = space < remaining ? space : remaining;
          chunk.setRange(filled, filled + count, piece, offset);
          filled += count;
          offset += count;
          if (filled < chunkBytes) continue;
          if (cancel?.isCancelled ?? false) return _cancelled;
          await writer.write(Uint8List.fromList(chunk));
          sent += chunkBytes;
          onProgress?.call(sent, recording.bytes);
          filled = 0;
        }
      }
      if (filled > 0) {
        if (cancel?.isCancelled ?? false) return _cancelled;
        final tail = Uint8List.fromList(chunk.sublist(0, filled));
        await writer.write(tail);
        sent += tail.length;
        onProgress?.call(sent, recording.bytes);
      }
      return _TransferOk(sent);
    } finally {
      // Only an early exit holds a live subscription. A drained iterator's
      // cancel() returns a root-zone future, which fake clocks never complete.
      if (!drained) await pieces.cancel();
    }
  }

  /// The full remote path (folder-qualified) for a new file called
  /// [fileName]: SMB-illegal characters become `_`, and a taken name gets
  /// ` (2)`, ` (3)`… before its extension. Null when every suffix is taken.
  static Future<String?> reserveRemoteName(
    SmbConnection connection,
    SmbTarget target,
    String fileName,
  ) async {
    var name = fileName.replaceAll(_illegalName, '_');
    if (name.isEmpty) name = 'recording.ts';
    if (!await connection.exists(target.remotePathFor(name))) {
      return target.remotePathFor(name);
    }
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i <= _maxNameSuffix; i++) {
      final candidate = '$stem ($i)$ext';
      if (!await connection.exists(target.remotePathFor(candidate))) {
        return target.remotePathFor(candidate);
      }
    }
    return null;
  }

  Future<void> _discardPart(SmbConnection connection, String part) async {
    try {
      await connection.delete(part);
    } catch (_) {
      // Best effort: the part is never renamed, so a later attempt retries
      // the delete instead of writing onto a broken file.
    }
  }

  /// Cleanup for the exception path: close the writer (ignore errors), then
  /// drop the unfinished part.
  Future<void> _cleanup(
    SmbConnection connection,
    SmbWriter? writer,
    String part,
  ) async {
    if (writer != null) {
      try {
        await writer.close();
      } catch (_) {
        // The part is deleted next; a failed close changes nothing.
      }
    }
    await _discardPart(connection, part);
  }

  SmbUploadFailed _failureFrom(Object error) {
    if (error is SmbException) {
      return SmbUploadFailed(error.kind, error.message);
    }
    return SmbUploadFailed(SmbFailureKind.other, '$error');
  }

  Future<void> _quietlyClose(SmbConnection connection) async {
    try {
      await connection.close();
    } catch (_) {
      // Closing never decides the upload outcome.
    }
  }
}

const _cancelled = _TransferFailed(
  SmbUploadFailed(SmbFailureKind.cancelled, 'cancelled'),
);

const _readFailed = _TransferFailed(
  SmbUploadFailed(
    SmbFailureKind.readFailed,
    'could not read the local recording',
  ),
);

/// One byte-transfer attempt (no remote work yet).
sealed class _TransferResult {
  const _TransferResult();
}

final class _TransferOk extends _TransferResult {
  const _TransferOk(this.bytes);

  final int bytes;
}

final class _TransferFailed extends _TransferResult {
  const _TransferFailed(this.failure);

  final SmbUploadFailed failure;
}
