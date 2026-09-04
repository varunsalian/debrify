import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../utils/app_storage.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_transport.dart';

typedef WebDavSyncStagingDirectoryProvider = Future<Directory> Function();
typedef WebDavSyncScratchCleaner = Future<void> Function(Directory directory);

final class WebDavSyncLargeSectionIo {
  WebDavSyncLargeSectionIo({
    required WebDavSyncCodec codec,
    WebDavSyncStagingDirectoryProvider? stagingDirectoryProvider,
    WebDavSyncScratchCleaner? scratchCleaner,
  }) : _codec = codec,
       _stagingDirectoryProvider = stagingDirectoryProvider ?? AppStorage.cache,
       _scratchCleaner = scratchCleaner ?? _deleteScratch;

  final WebDavSyncCodec _codec;
  final WebDavSyncStagingDirectoryProvider _stagingDirectoryProvider;
  final WebDavSyncScratchCleaner _scratchCleaner;

  /// Seals and commits one immutable section. Production transports stage it
  /// under the writable cache root and stream both directions, so the upload
  /// body and verification download never coexist as large memory buffers.
  Future<WebDavSyncSectionReference> sealWriteVerify({
    required WebDavSyncTransport transport,
    required WebDavSyncCircleKey key,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    required Object payload,
    WebDavSyncPayloadTransformer? payloadEncoder,
    required String semanticDigest,
    required int updatedAtMs,
    required int maxBytes,
  }) async {
    final WebDavSyncFileTransport? fileTransport =
        transport is WebDavSyncFileTransport &&
            (logicalName == 'bootstrap' ||
                logicalName == 'graph' ||
                logicalName == 'resources' ||
                _isLibrarySection(logicalName))
        ? transport as WebDavSyncFileTransport
        : null;
    if (fileTransport == null) {
      final encoded = await _codec.sealDocument(
        key: key,
        circleId: circleId,
        deviceId: deviceId,
        logicalName: logicalName,
        schemaVersion: schemaVersion,
        payload: payload,
        payloadEncoder: payloadEncoder,
        maxBytes: maxBytes,
        runInBackground:
            logicalName == 'bootstrap' ||
            logicalName == 'graph' ||
            logicalName == 'resources' ||
            _isLibrarySection(logicalName),
      );
      final reference = _reference(
        logicalName: logicalName,
        semanticDigest: semanticDigest,
        updatedAtMs: updatedAtMs,
        schemaVersion: schemaVersion,
        encoded: encoded,
      );
      final verified = await _writeBytes(
        transport: transport,
        deviceId: deviceId,
        reference: reference,
        encoded: encoded,
        maxBytes: maxBytes,
      );
      await _codec.openDocument(
        key: key,
        encoded: verified,
        circleId: circleId,
        deviceId: deviceId,
        logicalName: logicalName,
        schemaVersion: schemaVersion,
        maxBytes: maxBytes,
        runInBackground:
            logicalName == 'bootstrap' ||
            logicalName == 'graph' ||
            logicalName == 'resources' ||
            _isLibrarySection(logicalName),
      );
      return reference;
    }

    final scratch = await _createScratch();
    Object? operationFailure;
    try {
      final upload = File('${scratch.path}/upload.enc');
      final staged = await _sealToFile(
        file: upload,
        key: key,
        circleId: circleId,
        deviceId: deviceId,
        logicalName: logicalName,
        schemaVersion: schemaVersion,
        payload: payload,
        payloadEncoder: payloadEncoder,
        semanticDigest: semanticDigest,
        updatedAtMs: updatedAtMs,
        maxBytes: maxBytes,
      );
      WebDavException? writeFailure;
      StackTrace? writeFailureStackTrace;
      try {
        await fileTransport.writeSectionFile(
          deviceId,
          staged.contentHash,
          upload,
          maxBytes: maxBytes,
        );
      } on WebDavException catch (error, stackTrace) {
        writeFailure = error;
        writeFailureStackTrace = stackTrace;
      }
      try {
        final download = File('${scratch.path}/read-back.enc');
        final result = await fileTransport.readSectionToFile(
          deviceId,
          staged,
          download,
          maxBytes: maxBytes,
        );
        if (result.bytesWritten != staged.size ||
            await _sha256File(download) != staged.contentHash) {
          throw StateError('WebDAV sync section read-back verification failed');
        }
        final verified = await _readBounded(download, maxBytes);
        await _codec.openDocument(
          key: key,
          encoded: verified,
          circleId: circleId,
          deviceId: deviceId,
          logicalName: logicalName,
          schemaVersion: schemaVersion,
          maxBytes: maxBytes,
          runInBackground: true,
        );
      } on Object {
        if (writeFailure != null) {
          Error.throwWithStackTrace(writeFailure, writeFailureStackTrace!);
        }
        rethrow;
      }
      return staged;
    } catch (error) {
      operationFailure = error;
      rethrow;
    } finally {
      try {
        await _scratchCleaner(scratch);
      } catch (_) {
        // Never replace the integrity/network failure with a secondary cache
        // cleanup error. A successful operation still reports a cleanup
        // failure so storage problems are not silently ignored.
        if (operationFailure == null) rethrow;
      }
    }
  }

  /// Downloads a referenced graph section through disk when the transport
  /// supports it, then returns one bounded buffer for authenticated decoding.
  Future<Uint8List> readVerified({
    required WebDavSyncTransport transport,
    required String deviceId,
    required WebDavSyncSectionReference reference,
    required int maxBytes,
  }) async {
    if (reference.size > maxBytes) {
      throw const FormatException('WebDAV sync section exceeds its limit');
    }
    final WebDavSyncFileTransport? fileTransport =
        transport is WebDavSyncFileTransport
        ? transport as WebDavSyncFileTransport
        : null;
    if (fileTransport == null) {
      final read = await transport.readSection(
        deviceId,
        reference,
        maxBytes: maxBytes,
      );
      _requireReference(read.bytes, reference);
      return read.bytes;
    }

    final scratch = await _createScratch();
    Object? operationFailure;
    try {
      final download = File('${scratch.path}/download.enc');
      final result = await fileTransport.readSectionToFile(
        deviceId,
        reference,
        download,
        maxBytes: maxBytes,
      );
      if (result.bytesWritten != reference.size ||
          await _sha256File(download) != reference.contentHash) {
        throw const FormatException('WebDAV sync section content mismatch');
      }
      // Keep the read inside this try. Returning its Future directly lets the
      // finally block delete the scratch directory before readAsBytes opens
      // the file on slower filesystems (observed on Android).
      return await _readBounded(download, maxBytes);
    } catch (error) {
      operationFailure = error;
      rethrow;
    } finally {
      try {
        await _scratchCleaner(scratch);
      } catch (_) {
        if (operationFailure == null) rethrow;
      }
    }
  }

  Future<WebDavSyncSectionReference> _sealToFile({
    required File file,
    required WebDavSyncCircleKey key,
    required String circleId,
    required String deviceId,
    required String logicalName,
    required int schemaVersion,
    required Object payload,
    required WebDavSyncPayloadTransformer? payloadEncoder,
    required String semanticDigest,
    required int updatedAtMs,
    required int maxBytes,
  }) async {
    final encoded = await _codec.sealDocument(
      key: key,
      circleId: circleId,
      deviceId: deviceId,
      logicalName: logicalName,
      schemaVersion: schemaVersion,
      payload: payload,
      payloadEncoder: payloadEncoder,
      maxBytes: maxBytes,
      runInBackground: true,
    );
    final reference = _reference(
      logicalName: logicalName,
      semanticDigest: semanticDigest,
      updatedAtMs: updatedAtMs,
      schemaVersion: schemaVersion,
      encoded: encoded,
    );
    await file.writeAsBytes(encoded, flush: true);
    return reference;
  }

  static Future<Uint8List> _writeBytes({
    required WebDavSyncTransport transport,
    required String deviceId,
    required WebDavSyncSectionReference reference,
    required Uint8List encoded,
    required int maxBytes,
  }) async {
    WebDavResponseMetadata? metadata;
    WebDavException? writeFailure;
    StackTrace? writeFailureStackTrace;
    try {
      metadata = await transport.writeSection(
        deviceId,
        reference.contentHash,
        encoded,
        maxBytes: maxBytes,
      );
    } on WebDavException catch (error, stackTrace) {
      writeFailure = error;
      writeFailureStackTrace = stackTrace;
    }
    try {
      if (writeFailure != null || _requiresReadBack(reference.name)) {
        final readBack = await transport.readSection(
          deviceId,
          reference,
          maxBytes: maxBytes,
        );
        if (!_bytesEqual(encoded, readBack.bytes)) {
          throw StateError('WebDAV sync section read-back verification failed');
        }
        _requireReference(readBack.bytes, reference);
        return readBack.bytes;
      } else if (metadata != null) {
        validateWebDavSyncSectionWriteMetadata(
          metadata,
          expectedBytes: reference.size,
        );
      }
      return encoded;
    } on Object {
      if (writeFailure != null) {
        Error.throwWithStackTrace(writeFailure, writeFailureStackTrace!);
      }
      rethrow;
    }
  }

  Future<Directory> _createScratch() async {
    final base = await _stagingDirectoryProvider();
    await base.create(recursive: true);
    return base.createTemp('webdav-sync-section-');
  }

  static Future<void> _deleteScratch(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<Uint8List> _readBounded(File file, int maxBytes) async {
    final length = await file.length();
    if (length <= 0 || length > maxBytes) {
      throw const FormatException('WebDAV sync section exceeds its limit');
    }
    return file.readAsBytes();
  }

  static void _requireReference(
    Uint8List bytes,
    WebDavSyncSectionReference reference,
  ) {
    if (bytes.length != reference.size ||
        contentHashOf(bytes) != reference.contentHash) {
      throw const FormatException('WebDAV sync section content mismatch');
    }
  }

  static WebDavSyncSectionReference _reference({
    required String logicalName,
    required String semanticDigest,
    required int updatedAtMs,
    required int schemaVersion,
    required Uint8List encoded,
  }) => WebDavSyncSectionReference(
    name: logicalName,
    contentHash: contentHashOf(encoded),
    semanticDigest: semanticDigest,
    updatedAtMs: updatedAtMs,
    schemaVersion: schemaVersion,
    size: encoded.length,
  );

  static bool _requiresReadBack(String logicalName) =>
      logicalName == 'bootstrap' ||
      logicalName == 'graph' ||
      logicalName == 'profiles' ||
      logicalName == 'resources' ||
      _isLibrarySection(logicalName);

  static bool _isLibrarySection(String logicalName) =>
      logicalName.startsWith('library/') ||
      logicalName.startsWith('tv-library/');

  static bool _bytesEqual(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < left.length ? left[index] : 0) ^
          (index < right.length ? right[index] : 0);
    }
    return difference == 0;
  }
}
