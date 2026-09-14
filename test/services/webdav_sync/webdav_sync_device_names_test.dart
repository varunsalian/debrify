import 'dart:typed_data';
import 'dart:async';

import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_device_names.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NamesTransport extends Fake
    implements WebDavSyncTransport, WebDavSyncDeviceNameTransport {
  final names = <String, Uint8List>{};
  int writes = 0;
  bool fail = false;
  Completer<void>? firstWriteGate;
  final firstWriteStarted = Completer<void>();
  @override
  Future<WebDavBytesResult?> readDeviceName(String deviceId) async {
    if (fail) throw StateError('offline');
    final bytes = names[deviceId];
    return bytes == null
        ? null
        : WebDavBytesResult(
            bytes: bytes,
            metadata: WebDavResponseMetadata(
              statusCode: 200,
              uri: Uri.parse('https://test.invalid'),
              headers: const {},
            ),
          );
  }

  @override
  Future<void> writeDeviceName(String deviceId, Uint8List bytes) async {
    if (fail) throw StateError('offline');
    writes++;
    if (writes == 1 && firstWriteGate != null) {
      firstWriteStarted.complete();
      await firstWriteGate!.future;
    }
    names[deviceId] = bytes;
  }
}

class OldTransport extends Fake implements WebDavSyncTransport {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebDavSyncCodec codec;
  late OpenedWebDavSyncRoot root;
  late NamesTransport transport;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    codec = WebDavSyncCodec();
    final bytes = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'test-circle',
      createdAt: DateTime.utc(2026),
      memoryKiB: 8,
      iterations: 1,
    );
    root = await codec.openRoot(bytes, 'circle-secret');
    transport = NamesTransport();
  });
  Future<String?> read(String id) => WebDavSyncDeviceNames.read(
    transport: transport,
    codec: codec,
    root: root,
    deviceId: id,
  );
  Future<void> publish(String name) => WebDavSyncDeviceNames.publish(
    transport: transport,
    codec: codec,
    root: root,
    deviceId: 'device-one',
    name: name,
  );

  test(
    'a timed-out automatic PUT cannot overwrite a later manual rename',
    () async {
      transport.firstWriteGate = Completer<void>();
      final old = publish('Old automatic name');
      await transport.firstWriteStarted.future;
      await expectLater(
        old.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      final rename = publish('Living room TV');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.writes, 1);
      transport.firstWriteGate!.complete();
      await rename;
      expect(await read('device-one'), 'Living room TV');
    },
  );
  test(
    'encrypted names round trip, rename and avoid unchanged writes',
    () async {
      await publish(' Living room TV ');
      expect(await read('device-one'), 'Living room TV');
      expect(
        String.fromCharCodes(transport.names['device-one']!),
        isNot(contains('Living room')),
      );
      await publish('Living room TV');
      expect(transport.writes, 1);
      await publish('Bedroom TV');
      expect(await read('device-one'), 'Bedroom TV');
      expect(transport.names.keys, ['device-one']);
    },
  );
  test(
    'device identity is authenticated; malformed or absent metadata falls back',
    () async {
      expect(await read('missing'), isNull);
      await publish('TV');
      transport.names['device-two'] = transport.names['device-one']!;
      expect(await read('device-two'), isNull);
      transport.names['device-one'] = Uint8List.fromList([1, 2, 3]);
      expect(await read('device-one'), isNull);
      transport.fail = true;
      expect(await read('device-one'), isNull);
      await expectLater(publish('New name'), throwsStateError);
    },
  );
  test('old transport remains compatible', () async {
    expect(
      await WebDavSyncDeviceNames.read(
        transport: OldTransport(),
        codec: codec,
        root: root,
        deviceId: 'old-device',
      ),
      isNull,
    );
    await WebDavSyncDeviceNames.publish(
      transport: OldTransport(),
      codec: codec,
      root: root,
      deviceId: 'old-device',
      name: 'Old TV',
    );
  });
  test('name is local, trimmed, bounded and accepts Unicode', () async {
    await WebDavSyncDeviceNames.saveLocal('  Salon 📺  ');
    expect(await WebDavSyncDeviceNames.localName(), 'Salon 📺');
    expect(
      ProfilePreferencePortability.allowsKey(
        WebDavSyncDeviceNames.preferenceKey,
      ),
      isFalse,
    );
    for (final name in ['', '  ', 'TV\nRoom', 'a' * 61]) {
      expect(() => WebDavSyncDeviceNames.validate(name), throwsFormatException);
    }
    expect(WebDavSyncDeviceNames.validate('a' * 60), hasLength(60));
  });
}
