import 'dart:io';

import 'package:debrify/services/transfer/transfer_io.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_snapshot_io.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_snapshot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late _Objects transport;
  late WebDavSyncCircleKey key;
  const io = WebDavSyncSnapshotIo();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('snapshot-retry-test-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    transport = _Objects(directory);
    final codec = WebDavSyncCodec();
    final marker = await codec.sealRoot(
      passphrase: 'test-only-secret',
      circleId: 'test-circle',
      createdAt: DateTime.utc(2026),
      memoryKiB: 8,
      iterations: 1,
    );
    key = (await codec.openRoot(marker, 'test-only-secret')).key;
  });
  tearDown(() async {
    AppStorage.debugReset();
    await directory.delete(recursive: true);
  });

  Future<WebDavSyncPreparedSnapshot> prepare() async {
    final staging = await directory.createTemp('staging-');
    final archive = File('${staging.path}/archive');
    await archive.writeAsString('snapshot payload' * 1000);
    return WebDavSyncPreparedSnapshot(
      archive: archive,
      staging: staging,
      semanticDigest: 'a' * 64,
      databaseDigest: 'b' * 64,
      profileMap: const {'backup-profile': 'circle-profile'},
      resourceMap: const {},
    );
  }

  Future<WebDavSyncSnapshotDescriptor> publish() async {
    final snapshot = await prepare();
    try {
      return await io.publish(
        transport: transport,
        key: key,
        circleId: 'test-circle',
        snapshot: snapshot,
      );
    } finally {
      await snapshot.dispose();
    }
  }

  test('lost PUT response is recovered by authenticated read-back', () async {
    transport.failWriteAfterStore = true;
    final result = await publish();
    expect(result.contentHash, transport.hash);
    expect(transport.writes, 1);
    expect(transport.reads, 1);
  });

  test(
    'failed verification reuses ciphertext and completed upload on retry',
    () async {
      transport.failRead = true;
      await expectLater(publish(), throwsA(isA<WebDavException>()));
      final firstHash = transport.hash;
      transport.failRead = false;
      final retry = await publish();
      expect(retry.contentHash, firstHash);
      expect(transport.writes, 1);
      expect(transport.reads, 2);

      // A verified immutable object with the same strong ETag needs no third GET.
      await publish();
      expect(transport.writes, 1);
      expect(transport.reads, 2);
    },
  );

  test(
    'corrupt remote bytes cannot produce a publishable descriptor',
    () async {
      transport.corruptRead = true;
      await expectLater(publish(), throwsFormatException);
      transport.corruptRead = false;
      await publish();
      expect(transport.writes, 1);
      expect(transport.reads, 2);
    },
  );

  test(
    'next transfer prunes abandoned codec scratch in another circle',
    () async {
      final abandoned = Directory(
        '${directory.path}/webdav-sync/object-cache/old-circle/.stream-codec-abandoned',
      );
      await abandoned.create(recursive: true);
      await File(
        '${abandoned.path}/payload.gz',
      ).writeAsString('private scratch');
      await publish();
      expect(await abandoned.exists(), isFalse);
    },
  );
}

final class _Objects
    implements WebDavSyncTransport, WebDavSyncSharedObjectTransport {
  _Objects(this.directory);
  final Directory directory;
  String? hash;
  File? remote;
  int writes = 0;
  int reads = 0;
  bool failWriteAfterStore = false;
  bool failRead = false;
  bool corruptRead = false;
  WebDavResponseMetadata get metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/object'),
    headers: const {},
    etag: '"immutable-object"',
  );
  static const failure = WebDavException(
    kind: WebDavErrorKind.network,
    message: 'simulated interrupted connection',
  );

  @override
  Future<WebDavExistenceResult> probeSharedObject(String contentHash) async =>
      WebDavExistenceResult(exists: hash == contentHash, metadata: metadata);

  @override
  Future<WebDavResponseMetadata> writeSharedObject(
    String contentHash,
    File file, {
    required int maxBytes,
  }) async {
    writes++;
    hash = contentHash;
    remote = await file.copy('${directory.path}/remote');
    if (failWriteAfterStore) throw failure;
    return metadata;
  }

  @override
  Future<WebDavFileResult> readSharedObject(
    String contentHash,
    File destination, {
    required int maxBytes,
    void Function()? checkCancelled,
  }) async {
    reads++;
    checkCancelled?.call();
    if (failRead) throw failure;
    await remote!.copy(destination.path);
    if (corruptRead) await destination.writeAsString('corrupt');
    return WebDavFileResult(
      file: destination,
      bytesWritten: await destination.length(),
      metadata: metadata,
      sha256Hex: await TransferIo.hashFile(destination),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
