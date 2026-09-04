import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_large_section_io.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _encodeWithIsolateProbe(Object? payload) {
  final source = payload! as Map<String, Object?>;
  return <String, Object?>{
    'encoderIsolate': Isolate.current.hashCode,
    'mainIsolate': source['mainIsolate'],
  };
}

void main() {
  late Directory stagingBase;
  late WebDavSyncCodec codec;
  late WebDavSyncCircleKey key;
  late _FileTransport transport;
  late WebDavSyncLargeSectionIo io;

  setUp(() async {
    stagingBase = await Directory.systemTemp.createTemp(
      'webdav-sync-large-section-test-',
    );
    var randomCursor = 0;
    codec = WebDavSyncCodec(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => randomCursor++ & 0xff),
      ),
    );
    final rootBytes = await codec.sealRoot(
      passphrase: 'correct horse',
      circleId: 'circle-test-1',
      createdAt: DateTime.utc(2026, 9, 2),
      memoryKiB: 8,
      iterations: 1,
    );
    key = (await codec.openRoot(rootBytes, 'correct horse')).key;
    transport = _FileTransport();
    io = WebDavSyncLargeSectionIo(
      codec: codec,
      stagingDirectoryProvider: () async => stagingBase,
    );
  });

  tearDown(() async {
    if (await stagingBase.exists()) {
      await stagingBase.delete(recursive: true);
    }
  });

  test('large sections stream through scratch files and clean them', () async {
    final reference = await io.sealWriteVerify(
      transport: transport,
      key: key,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'bootstrap',
      schemaVersion: 1,
      payload: const <String, Object?>{
        'kind': 'bootstrap',
        'records': <Object?>[
          <String, Object?>{'id': 'one', 'value': 'payload'},
        ],
      },
      semanticDigest: List<String>.filled(64, 'a').join(),
      updatedAtMs: 1234,
      maxBytes: 1024 * 1024,
    );

    expect(transport.fileWrites, 1);
    expect(transport.fileReads, 1);
    expect(transport.byteWrites, 0);
    expect(transport.byteReads, 0);
    expect(reference.size, transport.sections[reference.contentHash]!.length);
    expect(await stagingBase.list().toList(), isEmpty);

    final encoded = await io.readVerified(
      transport: transport,
      deviceId: 'device-test-1',
      reference: reference,
      maxBytes: 1024 * 1024,
    );
    final opened = await codec.openDocument(
      key: key,
      encoded: encoded,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'bootstrap',
      schemaVersion: 1,
      maxBytes: 1024 * 1024,
    );

    expect(opened, isA<Map<String, Object?>>());
    expect(transport.fileReads, 2);
    expect(transport.byteReads, 0);
    expect(await stagingBase.list().toList(), isEmpty);
  });

  test('download bytes are fully read before scratch cleanup starts', () async {
    final reference = await io.sealWriteVerify(
      transport: transport,
      key: key,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'bootstrap',
      schemaVersion: 1,
      payload: const <String, Object?>{
        'kind': 'bootstrap',
        'records': <Object?>[
          <String, Object?>{'id': 'one', 'value': 'payload'},
        ],
      },
      semanticDigest: List<String>.filled(64, 'd').join(),
      updatedAtMs: 4321,
      maxBytes: 1024 * 1024,
    );
    var cleanupRan = false;
    final readIo = WebDavSyncLargeSectionIo(
      codec: codec,
      stagingDirectoryProvider: () async => stagingBase,
      scratchCleaner: (directory) async {
        cleanupRan = true;
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      },
    );

    final encoded = await readIo.readVerified(
      transport: transport,
      deviceId: 'device-test-1',
      reference: reference,
      maxBytes: 1024 * 1024,
    );
    final opened = await codec.openDocument(
      key: key,
      encoded: encoded,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'bootstrap',
      schemaVersion: 1,
      maxBytes: 1024 * 1024,
    );

    expect(opened, isA<Map<String, Object?>>());
    expect(cleanupRan, isTrue);
    expect(await stagingBase.list().toList(), isEmpty);
  });

  test(
    'corrupt stored resources section fails push-time verification',
    () async {
      transport.corruptReadBack = true;

      await expectLater(
        io.sealWriteVerify(
          transport: transport,
          key: key,
          circleId: 'circle-test-1',
          deviceId: 'device-test-1',
          logicalName: 'resources',
          schemaVersion: 1,
          payload: const <String, Object?>{'kind': 'resources'},
          semanticDigest: List<String>.filled(64, 'b').join(),
          updatedAtMs: 5678,
          maxBytes: 1024 * 1024,
        ),
        throwsA(isA<StateError>()),
      );

      expect(transport.fileWrites, 1);
      expect(transport.fileReads, 1);
      expect(transport.byteWrites, 0);
      expect(transport.byteReads, 0);
      expect(await stagingBase.list().toList(), isEmpty);
    },
  );

  test('scratch cleanup failure never masks an integrity failure', () async {
    transport.corruptReadBack = true;
    io = WebDavSyncLargeSectionIo(
      codec: codec,
      stagingDirectoryProvider: () async => stagingBase,
      scratchCleaner: (_) async => throw StateError('cleanup failed'),
    );

    await expectLater(
      io.sealWriteVerify(
        transport: transport,
        key: key,
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'bootstrap',
        schemaVersion: 1,
        payload: const <String, Object?>{'kind': 'bootstrap'},
        semanticDigest: List<String>.filled(64, 'c').join(),
        updatedAtMs: 9012,
        maxBytes: 1024 * 1024,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('read-back verification'),
        ),
      ),
    );
  });

  for (final status in <int>[403, 405, 409, 412]) {
    test(
      'pre-existing immutable section accepts HTTP $status by read-back',
      () async {
        transport.writeFailure = WebDavException(
          kind: switch (status) {
            403 => WebDavErrorKind.authentication,
            409 => WebDavErrorKind.conflict,
            412 => WebDavErrorKind.preconditionFailed,
            _ => WebDavErrorKind.unexpectedStatus,
          },
          message: 'already exists',
          statusCode: status,
        );

        final reference = await io.sealWriteVerify(
          transport: transport,
          key: key,
          circleId: 'circle-test-1',
          deviceId: 'device-test-1',
          logicalName: 'resources',
          schemaVersion: 1,
          payload: const <String, Object?>{'kind': 'resources'},
          semanticDigest: List<String>.filled(64, 'e').join(),
          updatedAtMs: 9013,
          maxBytes: 1024 * 1024,
        );

        expect(reference.size, greaterThan(0));
        expect(transport.fileWrites, 1);
        expect(transport.fileReads, 1);
        expect(await stagingBase.list().toList(), isEmpty);
      },
    );
  }

  test(
    'immutable section replay rethrows when the existing hash differs',
    () async {
      transport
        ..writeFailure = const WebDavException(
          kind: WebDavErrorKind.conflict,
          message: 'already exists',
          statusCode: 409,
        )
        ..corruptOnWriteFailure = true;

      await expectLater(
        io.sealWriteVerify(
          transport: transport,
          key: key,
          circleId: 'circle-test-1',
          deviceId: 'device-test-1',
          logicalName: 'resources',
          schemaVersion: 1,
          payload: const <String, Object?>{'kind': 'resources'},
          semanticDigest: List<String>.filled(64, 'e').join(),
          updatedAtMs: 9013,
          maxBytes: 1024 * 1024,
        ),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.statusCode,
            'status',
            409,
          ),
        ),
      );

      expect(transport.fileReads, 1);
      expect(await stagingBase.list().toList(), isEmpty);
    },
  );

  test(
    'per-profile library uses the verified file path and fails closed',
    () async {
      final mainIsolate = Isolate.current.hashCode;
      final reference = await io.sealWriteVerify(
        transport: transport,
        key: key,
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'library/profile-circle',
        schemaVersion: 1,
        payload: <String, Object?>{'mainIsolate': mainIsolate},
        payloadEncoder: _encodeWithIsolateProbe,
        semanticDigest: List<String>.filled(64, 'f').join(),
        updatedAtMs: 9014,
        maxBytes: 1024 * 1024,
      );

      expect(reference.name, 'library/profile-circle');
      expect(transport.fileWrites, 1);
      expect(transport.fileReads, 1);
      expect(transport.byteWrites, 0);
      final opened = await codec.openDocument(
        key: key,
        encoded: transport.sections[reference.contentHash]!,
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'library/profile-circle',
        schemaVersion: 1,
        maxBytes: 1024 * 1024,
      );
      final openedMap = opened! as Map<String, Object?>;
      expect(openedMap['mainIsolate'], mainIsolate);
      expect(openedMap['encoderIsolate'], isNot(mainIsolate));

      await expectLater(
        io.sealWriteVerify(
          transport: transport,
          key: key,
          circleId: 'circle-test-1',
          deviceId: 'device-test-1',
          logicalName: 'library/profile-circle',
          schemaVersion: 1,
          payload: <String, Object?>{'payload': 'x' * 4096},
          semanticDigest: List<String>.filled(64, 'f').join(),
          updatedAtMs: 9015,
          maxBytes: 256,
        ),
        throwsFormatException,
      );
      expect(
        transport.fileWrites,
        1,
        reason: 'overflow must fail before upload',
      );
    },
  );
}

final class _FileTransport
    implements WebDavSyncTransport, WebDavSyncFileTransport {
  final Map<String, Uint8List> sections = <String, Uint8List>{};

  int fileWrites = 0;
  int fileReads = 0;
  int byteWrites = 0;
  int byteReads = 0;
  bool corruptReadBack = false;
  bool corruptOnWriteFailure = false;
  WebDavException? writeFailure;

  static final WebDavResponseMetadata _metadata = WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://dav.example.test/sync'),
    headers: const <String, String>{},
    serverDate: DateTime.utc(2026, 9, 2),
  );

  @override
  Future<WebDavResponseMetadata> writeSectionFile(
    String deviceId,
    String contentHash,
    File file, {
    required int maxBytes,
  }) async {
    fileWrites += 1;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw StateError('test section too large');
    sections[contentHash] = Uint8List.fromList(bytes);
    if (writeFailure case final error?) {
      if (corruptOnWriteFailure) sections[contentHash]![0] ^= 0xff;
      throw error;
    }
    return _metadata;
  }

  @override
  Future<WebDavFileResult> readSectionToFile(
    String deviceId,
    WebDavSyncSectionReference reference,
    File destination, {
    required int maxBytes,
  }) async {
    fileReads += 1;
    final stored = sections[reference.contentHash];
    if (stored == null) throw StateError('missing test section');
    final bytes = Uint8List.fromList(stored);
    if (corruptReadBack) bytes[0] ^= 0xff;
    await destination.writeAsBytes(bytes, flush: true);
    return WebDavFileResult(
      file: destination,
      bytesWritten: bytes.length,
      metadata: _metadata,
    );
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) {
    byteReads += 1;
    throw StateError('byte reads must not be used for large sections');
  }

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) {
    byteWrites += 1;
    throw StateError('byte writes must not be used for large sections');
  }

  @override
  Future<void> ensureOwnLayout(String deviceId) async {}

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() => throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readRootMarker() => throw UnimplementedError();

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) => throw UnimplementedError();

  @override
  void close() {}
}
