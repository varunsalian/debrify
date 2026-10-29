// dart_smb2 adapter for the SMB recording upload.
//
// One single-worker pool per session: uploads are sequential, and a pool
// keeps libsmb2's blocking calls on its worker isolate, off the UI isolate.

import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import '../application/smb_contracts.dart';
import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';

final class DartSmb2Connector implements SmbConnector {
  const DartSmb2Connector({this.timeoutSeconds = 20});

  final int timeoutSeconds;

  @override
  Future<SmbConnection> connect(SmbTarget target, String? password) async {
    final user = target.user.trim();
    final domain = target.domain.trim();
    final pool = await _guard(
      () => Smb2Pool.connect(
        host: target.host.trim(),
        share: target.share.trim(),
        user: user.isEmpty ? null : user,
        // Without a user the logon is anonymous; libsmb2 then ignores it.
        password: user.isEmpty ? null : (password ?? ''),
        domain: domain.isEmpty ? null : domain,
        workers: 1,
        timeoutSeconds: timeoutSeconds,
      ),
    );
    return _Connection(pool);
  }
}

final class _Connection implements SmbConnection {
  _Connection(this._pool);

  final Smb2Pool _pool;
  bool _closed = false;

  @override
  Future<void> ensureDirectory(List<String> segments) async {
    for (var i = 1; i <= segments.length; i++) {
      final path = segments.take(i).join('/');
      if (await exists(path)) continue;
      try {
        await _guard(() => _pool.mkdir(path));
      } on SmbException {
        // Another client may have created it in between.
        if (!await exists(path)) rethrow;
      }
    }
  }

  @override
  Future<bool> exists(String path) => _guard(() => _pool.exists(path));

  @override
  Future<SmbWriter> openWrite(String path) async {
    final handle = await _guard(() => _pool.openFileWrite(path));
    // openFileWrite creates but does not empty an existing file.
    await _guard(() => _pool.ftruncateHandle(handle, 0));
    return _Writer(_pool, handle);
  }

  @override
  Future<int> sizeOf(String path) => _guard(() => _pool.fileSize(path));

  @override
  Future<void> rename(String from, String to) =>
      _guard(() => _pool.rename(from, to));

  @override
  Future<void> delete(String path) => _guard(() => _pool.deleteFile(path));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pool.disconnect();
  }
}

final class _Writer implements SmbWriter {
  _Writer(this._pool, this._handle);

  final Smb2Pool _pool;
  final Smb2PoolHandle _handle;
  int _offset = 0;

  @override
  Future<void> write(Uint8List chunk) async {
    await _guard(() => _pool.writeToHandle(_handle, chunk, offset: _offset));
    _offset += chunk.length;
  }

  @override
  Future<void> close() => _guard(() => _pool.closeHandle(_handle));
}

Future<T> _guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on Smb2Exception catch (e) {
    throw SmbException(smbFailureKindOf(e.type), e.message);
  }
}

/// How the uploader should treat a dart_smb2 error.
SmbFailureKind smbFailureKindOf(Smb2ErrorType type) => switch (type) {
  Smb2ErrorType.auth => SmbFailureKind.auth,
  Smb2ErrorType.fileNotFound ||
  Smb2ErrorType.notADirectory => SmbFailureKind.notFound,
  Smb2ErrorType.accessDenied => SmbFailureKind.accessDenied,
  Smb2ErrorType.diskFull => SmbFailureKind.noSpace,
  Smb2ErrorType.connection || Smb2ErrorType.timeout => SmbFailureKind.network,
  _ => SmbFailureKind.other,
};
