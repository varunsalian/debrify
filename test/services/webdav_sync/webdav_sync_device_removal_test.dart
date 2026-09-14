import 'dart:typed_data';

import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_device_removal.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends Fake
    implements WebDavSyncTransport, WebDavSyncDeviceRemovalTransport {
  final records = <String, Uint8List>{};
  final guards = <String, Future<void> Function()>{};
  bool failRead = false;
  bool dropWrite = false;
  int writes = 0;
  @override
  Future<WebDavBytesResult?> readDeviceRemoval(String deviceId) async {
    if (failRead) throw StateError('offline');
    final bytes = records[deviceId];
    return bytes == null
        ? null
        : WebDavBytesResult(
            bytes: bytes,
            metadata: WebDavResponseMetadata(
              statusCode: 200,
              uri: Uri.parse('https://example.test'),
              headers: const {},
            ),
          );
  }

  @override
  Future<void> writeDeviceRemoval(String deviceId, Uint8List bytes) async {
    writes++;
    if (!dropWrite) records[deviceId] = bytes;
  }

  @override
  void setDeviceWriteGuard(String deviceId, Future<void> Function() guard) {
    guards[deviceId] = guard;
  }
}

void main() {
  late WebDavSyncCodec codec;
  late OpenedWebDavSyncRoot root;
  late _Transport transport;
  setUp(() async {
    codec = WebDavSyncCodec();
    root = await codec.openRoot(
      await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'test-circle',
        createdAt: DateTime.utc(2026),
        memoryKiB: 8,
        iterations: 1,
      ),
      'circle-secret',
    );
    transport = _Transport();
  });
  Future<void> publish(String id) => WebDavSyncDeviceRemoval.publish(
    transport: transport,
    codec: codec,
    root: root,
    deviceId: id,
  );
  Future<void> guard(String id, Future<void> Function() onRemoved) =>
      WebDavSyncDeviceRemoval.guard(
        transport: transport,
        codec: codec,
        root: root,
        deviceId: id,
        onRemoved: onRemoved,
      );

  test('authenticated removal blocks initial use and is idempotent', () async {
    await publish('one');
    await publish('one');
    expect(transport.writes, 1);
    var retired = false;
    await expectLater(
      guard('one', () async {
        retired = true;
      }),
      throwsA(isA<WebDavSyncDeviceRemovedException>()),
    );
    expect(retired, isTrue);
    await guard('two', () async {
      fail('Unrelated device retired');
    });
  });
  test('removal after initial check blocks the next write', () async {
    var retired = false;
    await guard('one', () async {
      retired = true;
    });
    await publish('one');
    await expectLater(
      transport.guards['one']!(),
      throwsA(isA<WebDavSyncDeviceRemovedException>()),
    );
    expect(retired, isTrue);
  });
  test('read failures block writes without signing out the user', () async {
    await guard('one', () async {
      fail('Network failure must not sign out');
    });
    transport.failRead = true;
    await expectLater(transport.guards['one']!(), throwsStateError);
  });
  test('a copied record cannot remove a different device', () async {
    await publish('one');
    transport.records['two'] = transport.records['one']!;
    await expectLater(
      guard('two', () async {
        fail('Unauthenticated removal');
      }),
      throwsA(isNot(isA<WebDavSyncDeviceRemovedException>())),
    );
  });
  test('publication requires read-back before deletion can proceed', () async {
    transport.dropWrite = true;
    await expectLater(publish('one'), throwsStateError);
  });
}
