import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const String _legacyDocumentFixture =
    'eyJjaXBoZXJ0ZXh0IjoiT0NNeXA3bnV2S3JSblZhaDNQWElCdVpwSUY5YytkVm9jKzl5VkVhaG5Qc2pzWUN0dlNUUVlJc2lZc3V4N2x2SjdsYTM3VlRBMkZ2ZElWdEc3eXNJNHMzMmlsczZtUENQeHFNV1RVTlUiLCJoZWFkZXIiOnsiYWVhZCI6ImFlcy0yNTYtZ2NtIiwiY2lyY2xlSWQiOiJjaXJjbGUtdGVzdC0xIiwiZGV2aWNlSWQiOiJkZXZpY2UtdGVzdC0xIiwiZm9ybWF0IjoiZGVicmlmeS13ZWJkYXYtc3luYy1kb2N1bWVudCIsImxvZ2ljYWxOYW1lIjoibGVnYWN5LWZpeHR1cmUiLCJzY2hlbWFWZXJzaW9uIjoxLCJ2ZXJzaW9uIjoxfSwibm9uY2UiOiJIQjBlSHlBaElpTWtKU1luIn0=';
const List<int> _compressedMarker = <int>[
  0x00,
  0x44,
  0x42,
  0x52,
  0x46,
  0x59,
  0x2d,
  0x5a,
  0x4c,
  0x49,
  0x42,
  0x01,
];

Object? _decodeWithIsolateProbe(Object? payload) => <String, Object?>{
  'decoderIsolate': Isolate.current.hashCode,
  'payload': payload,
};

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
      '214ae014045d558f3411adaa58e1ab70f0f55b321f45d66a10c9680c62d384df',
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

  test(
    'documents are zlib-compressed behind a collision-proof marker',
    () async {
      final root = await codec.openRoot(await createRoot(), 'correct horse');
      final payload = <String, Object?>{
        'records': List<Object?>.generate(
          100,
          (index) => <String, Object?>{
            'hash': '0123456789abcdef0123456789abcdef01234567',
            'rank': index,
          },
        ),
      };
      final encoded = await codec.sealDocument(
        key: root.key,
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'library/profile-1',
        schemaVersion: 1,
        payload: payload,
      );

      final clear = await _decryptDocument(encoded, root.key);
      expect(
        clear.take(_compressedMarker.length),
        orderedEquals(_compressedMarker),
      );
      // Every canonical JSON value emitted by the legacy codec starts with one
      // of these token bytes. NUL cannot be a legacy payload prefix.
      expect(
        'ntf"-0123456789[{'.codeUnits,
        isNot(contains(_compressedMarker.first)),
      );
      final inflated = zlib.decode(clear.sublist(_compressedMarker.length));
      expect(jsonDecode(utf8.decode(inflated)), payload);
      expect(
        await codec.openDocument(
          key: root.key,
          encoded: encoded,
          circleId: 'circle-test-1',
          deviceId: 'device-test-1',
          logicalName: 'library/profile-1',
          schemaVersion: 1,
        ),
        payload,
      );
    },
  );

  test('legacy uncompressed document fixture still decodes', () async {
    final root = await codec.openRoot(await createRoot(), 'correct horse');

    expect(
      await codec.openDocument(
        key: root.key,
        encoded: base64Decode(_legacyDocumentFixture),
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'legacy-fixture',
        schemaVersion: 1,
      ),
      const <String, Object?>{
        'records': <Object?>[
          <String, Object?>{'hash': '0123456789abcdef', 'rank': 1},
        ],
        'version': 1,
      },
    );
  });

  test('compressed documents retain the uncompressed size bound', () async {
    final root = await codec.openRoot(await createRoot(), 'correct horse');
    final oversizedJson = utf8.encode(
      jsonEncode(<String, Object?>{'value': 'x' * 4096}),
    );
    final encoded = await _encryptDocumentPlaintext(
      key: root.key,
      logicalName: 'hot/profile-1',
      clear: <int>[..._compressedMarker, ...zlib.encode(oversizedJson)],
    );
    expect(encoded.length, lessThan(512));

    await expectLater(
      codec.openDocument(
        key: root.key,
        encoded: encoded,
        circleId: 'circle-test-1',
        deviceId: 'device-test-1',
        logicalName: 'hot/profile-1',
        schemaVersion: 1,
        maxBytes: 512,
      ),
      throwsFormatException,
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
    final mainIsolate = Isolate.current.hashCode;

    final opened = await codec.openDocument(
      key: root.key,
      encoded: encoded,
      circleId: root.document.circleId,
      deviceId: 'device-worker-1',
      logicalName: 'graph',
      schemaVersion: 1,
      payloadDecoder: _decodeWithIsolateProbe,
      runInBackground: true,
    );
    final result = opened! as Map<String, Object?>;
    expect(result['decoderIsolate'], isNot(mainIsolate));
    expect(result['payload'], const <String, Object?>{'worker': true});
  });
}

Future<Uint8List> _decryptDocument(
  Uint8List encoded,
  WebDavSyncCircleKey key,
) async {
  final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
  final header = envelope['header'] as Map<String, dynamic>;
  final ciphertext = base64Decode(envelope['ciphertext'] as String);
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(
      ciphertext.sublist(0, ciphertext.length - 16),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
    ),
    secretKey: key.secretKey,
    aad: WebDavSyncCodec.canonicalJsonBytes(header),
  );
  return Uint8List.fromList(clear);
}

Future<Uint8List> _encryptDocumentPlaintext({
  required WebDavSyncCircleKey key,
  required String logicalName,
  required List<int> clear,
}) async {
  final header = <String, Object?>{
    'format': 'debrify-webdav-sync-document',
    'version': 1,
    'circleId': 'circle-test-1',
    'deviceId': 'device-test-1',
    'logicalName': logicalName,
    'schemaVersion': 1,
    'aead': 'aes-256-gcm',
  };
  final box = await AesGcm.with256bits().encrypt(
    clear,
    secretKey: key.secretKey,
    nonce: Uint8List(12),
    aad: WebDavSyncCodec.canonicalJsonBytes(header),
  );
  return Uint8List.fromList(
    utf8.encode(
      WebDavSyncCodec.canonicalJson(<String, Object?>{
        'header': header,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(<int>[...box.cipherText, ...box.mac.bytes]),
      }),
    ),
  );
}
