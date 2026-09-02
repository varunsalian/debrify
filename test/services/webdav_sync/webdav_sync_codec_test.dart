import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int randomCursor;
  late WebDavSyncCodec codec;

  setUp(() {
    randomCursor = 0;
    codec = WebDavSyncCodec(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => randomCursor++ & 0xff),
      ),
    );
  });

  Future<Uint8List> createRoot() => codec.sealRoot(
    passphrase: 'correct horse',
    circleId: 'circle-test-1',
    createdAt: DateTime.utc(2026, 9, 1, 12, 34, 56),
    memoryKiB: 8,
    iterations: 1,
  );

  test('root envelope has a stable golden vector and authenticates', () async {
    final encoded = await createRoot();

    expect(
      sha256.convert(encoded).toString(),
      'ca83d3d56d82cac1cc5e030c63fa8ae63d31745204273aa56ec152749d87ce53',
    );
    final opened = await codec.openRoot(encoded, 'correct horse');
    expect(opened.document.circleId, 'circle-test-1');
    expect(opened.document.createdAt, DateTime.utc(2026, 9, 1, 12, 34, 56));
    expect(opened.document.schemaFloor, 1);
    expect(
      opened.document.kdfSalt,
      orderedEquals(List<int>.generate(16, (i) => i)),
    );
  });

  test('wrong root passphrase is typed', () async {
    final encoded = await createRoot();

    await expectLater(
      codec.openRoot(encoded, 'wrong password'),
      throwsA(isA<WebDavSyncWrongPassphraseException>()),
    );
  });

  test('passphrase validation never echoes the secret', () {
    final secret = List<String>.filled(1025, 's').join();

    expect(
      () => WebDavSyncCodec.validatePassphrase(secret),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test('root header tampering is authenticated', () async {
    final encoded = await createRoot();
    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final header = envelope['header'] as Map<String, dynamic>;
    final kdf = header['kdf'] as Map<String, dynamic>;
    kdf['memoryKiB'] = 9;

    await expectLater(
      codec.openRoot(utf8.encode(jsonEncode(envelope)), 'correct horse'),
      throwsA(isA<WebDavSyncWrongPassphraseException>()),
    );
  });

  test('unsafe KDF bounds fail before derivation', () async {
    final encoded = await createRoot();
    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final header = envelope['header'] as Map<String, dynamic>;
    final kdf = header['kdf'] as Map<String, dynamic>;
    kdf['memoryKiB'] = 131073;

    await expectLater(
      codec.openRoot(utf8.encode(jsonEncode(envelope)), 'correct horse'),
      throwsA(isA<FormatException>()),
    );
  });

  test('newer root format is rejected without reinterpretation', () async {
    final encoded = await createRoot();
    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final header = envelope['header'] as Map<String, dynamic>;
    header['version'] = 2;

    await expectLater(
      codec.openRoot(utf8.encode(jsonEncode(envelope)), 'correct horse'),
      throwsA(isA<FormatException>()),
    );
  });

  test('manifest envelope has a stable golden vector', () async {
    final root = await codec.openRoot(await createRoot(), 'correct horse');
    final encoded = await codec.sealDocument(
      key: root.key,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'manifest',
      schemaVersion: 1,
      payload: const <String, Object?>{
        'updatedAt': '2026-09-01T12:34:56.000Z',
        'sections': <Object?>[],
      },
    );

    expect(
      sha256.convert(encoded).toString(),
      '153977c4aeb77cda6f9233bc84475ea225151dff536893e0e36529d8cf2b9f7b',
    );
  });

  test('document AAD binds root, device, name, and schema', () async {
    final root = await codec.openRoot(await createRoot(), 'correct horse');
    final encoded = await codec.sealDocument(
      key: root.key,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'hot/profile-1',
      schemaVersion: 1,
      payload: <String, Object?>{
        'z': 2,
        'a': <String, Object?>{'b': true, 'a': 1},
      },
    );

    final opened = await codec.openDocument(
      key: root.key,
      encoded: encoded,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'hot/profile-1',
      schemaVersion: 1,
    );
    expect(opened, <String, Object?>{
      'a': <String, Object?>{'a': 1, 'b': true},
      'z': 2,
    });
    await expectLater(
      codec.openDocument(
        key: root.key,
        encoded: encoded,
        circleId: 'circle-test-1',
        deviceId: 'device-test-2',
        logicalName: 'hot/profile-1',
        schemaVersion: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('each seal uses a fresh nonce', () async {
    final root = await codec.openRoot(await createRoot(), 'correct horse');
    Future<Uint8List> seal() => codec.sealDocument(
      key: root.key,
      circleId: 'circle-test-1',
      deviceId: 'device-test-1',
      logicalName: 'manifest',
      schemaVersion: 1,
      payload: const <String, Object?>{'same': true},
    );

    expect(await seal(), isNot(orderedEquals(await seal())));
  });

  test('background root and document crypto round-trip', () async {
    final rootBytes = await codec.sealRoot(
      passphrase: 'correct horse',
      circleId: 'circle-worker-1',
      createdAt: DateTime.utc(2026, 9, 2),
      memoryKiB: 8,
      iterations: 1,
      runInBackground: true,
    );
    final root = await codec.openRoot(
      rootBytes,
      'correct horse',
      runInBackground: true,
    );
    final encoded = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: 'device-worker-1',
      logicalName: 'graph',
      schemaVersion: 1,
      payload: const <String, Object?>{'worker': true},
      runInBackground: true,
    );

    expect(
      await codec.openDocument(
        key: root.key,
        encoded: encoded,
        circleId: root.document.circleId,
        deviceId: 'device-worker-1',
        logicalName: 'graph',
        schemaVersion: 1,
        runInBackground: true,
      ),
      const <String, Object?>{'worker': true},
    );
  });
}
