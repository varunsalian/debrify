import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_zip.dart';
import 'package:debrify/services/transfer/streaming_encrypted_file.dart';
import 'package:debrify/services/transfer/transfer_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late File source;
  late File encrypted;
  late File restored;
  final key = SecretKey(List<int>.generate(32, (i) => i));
  const context = 'test/circle/bootstrap';

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('streaming-file-test-');
    source = File('${scratch.path}/source');
    encrypted = File('${scratch.path}/encrypted');
    restored = File('${scratch.path}/restored');
  });

  tearDown(() => scratch.delete(recursive: true));

  Future<void> seed(int length) async {
    final sink = await source.open(mode: FileMode.writeOnly);
    try {
      var offset = 0;
      while (offset < length) {
        final count = (length - offset).clamp(0, 65536);
        await sink.writeFrom(
          Uint8List.fromList(
            List.generate(count, (i) => ((offset + i) * 97) % 251),
          ),
        );
        offset += count;
      }
    } finally {
      await sink.close();
    }
  }

  Future<StreamingFileResult> seal({
    LocalBackupCancellation? cancellation,
    void Function(int, int)? onProgress,
  }) => StreamingEncryptedFile.encrypt(
    source: source,
    destination: encrypted,
    context: context,
    key: key,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<StreamingFileResult> open({
    String expectedContext = context,
    SecretKey? expectedKey,
  }) => StreamingEncryptedFile.decrypt(
    source: encrypted,
    destination: restored,
    context: expectedContext,
    key: expectedKey ?? key,
  );

  test(
    'compression round trip stays bounded and rejects excess expansion',
    () async {
      await seed(12 * 1024 * 1024);
      final sealed = await StreamingEncryptedFile.encrypt(
        source: source,
        destination: encrypted,
        context: context,
        key: key,
        compress: true,
      );
      expect(sealed.bytes, lessThan(256 * 1024));
      await expectLater(
        StreamingEncryptedFile.decrypt(
          source: encrypted,
          destination: restored,
          context: context,
          key: key,
          maxPlainBytes: 1024 * 1024,
        ),
        throwsFormatException,
      );
      expect(await restored.exists(), isFalse);
      final opened = await open();
      expect(opened.bytes, await source.length());
      expect(opened.sha256Hex, await TransferIo.hashFile(source));
      expect(await scratch.list().where((e) => e is Directory).isEmpty, isTrue);
    },
  );

  for (final length in [0, 1, 262088, 262089, 524216, 800003]) {
    test(
      'round trip authenticates every byte across segment boundary $length',
      () async {
        await seed(length);
        final sealed = await seal();
        expect(await StreamingEncryptedFile.looksLike(encrypted), isTrue);
        expect(sealed.bytes, await encrypted.length());
        expect(sealed.sha256Hex, await TransferIo.hashFile(encrypted));
        final result = await open();
        expect(result.bytes, length);
        expect(result.sha256Hex, await TransferIo.hashFile(source));
        expect(await TransferIo.hashFile(restored), result.sha256Hex);
        expect(result.peakResidentBytes, greaterThan(0));
      },
    );
  }

  test('decrypts an independent Python AESGCM/HKDF test vector', () async {
    final fixture =
        jsonDecode(
              await File('test/fixtures/streaming_file_v2.json').readAsString(),
            )
            as Map;
    await encrypted.writeAsBytes(
      base64Decode(fixture['encodedBase64'] as String),
    );
    await open(expectedContext: fixture['context'] as String);
    expect(
      await restored.readAsBytes(),
      base64Decode(fixture['plainBase64'] as String),
    );
    expect(await TransferIo.hashFile(encrypted), fixture['encodedSha256']);
  });

  test('password backup derives once and authenticates on restore', () async {
    await seed(800003);
    await StreamingEncryptedFile.encrypt(
      source: source,
      destination: encrypted,
      context: context,
      passphrase: 'manual-backup-passphrase',
    );
    await expectLater(
      StreamingEncryptedFile.decrypt(
        source: encrypted,
        destination: restored,
        context: context,
        passphrase: 'incorrect-password',
      ),
      throwsFormatException,
    );
    expect(await restored.exists(), isFalse);
    await StreamingEncryptedFile.decrypt(
      source: encrypted,
      destination: restored,
      context: context,
      passphrase: 'manual-backup-passphrase',
    );
    expect(
      await TransferIo.hashFile(source),
      await TransferIo.hashFile(restored),
    );
  });

  test('password worker keeps standard Argon2id key derivation', () async {
    await seed(127);
    const passphrase = 'standard-argon2id-interoperability';
    await StreamingEncryptedFile.encrypt(
      source: source,
      destination: encrypted,
      context: context,
      passphrase: passphrase,
    );
    final bytes = await encrypted.readAsBytes();
    final header = Uint8List.sublistView(
      bytes,
      0,
      StreamingEncryptedFile.headerBytes,
    );
    final stream = Uint8List.sublistView(
      bytes,
      StreamingEncryptedFile.headerBytes,
      StreamingEncryptedFile.headerBytes +
          StreamingEncryptedFile.streamHeaderBytes,
    );
    // Use the library's default implementation independently of the production
    // worker configuration. Scheduling/memory changes must preserve the key.
    final master =
        await Argon2id(
          memory: 19456,
          iterations: 2,
          parallelism: 1,
          hashLength: 32,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(passphrase)),
          nonce: Uint8List.sublistView(header, 21, 37),
        );
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: master,
      nonce: Uint8List.sublistView(stream, 1, 33),
      info: header,
    );
    try {
      final nonce = Uint8List(12)
        ..setRange(0, 7, stream, 33)
        ..[11] = 1; // One final segment, index zero.
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(
          Uint8List.sublistView(
            bytes,
            header.length + stream.length,
            bytes.length - 16,
          ),
          nonce: nonce,
          mac: Mac(Uint8List.sublistView(bytes, bytes.length - 16)),
        ),
        secretKey: derived,
      );
      expect(plaintext, await source.readAsBytes());
    } finally {
      derived.destroy();
      master.destroy();
    }
  });

  for (final damage in [
    'header',
    'ciphertext',
    'truncated',
    'appended',
    'reordered',
  ]) {
    test('$damage data is rejected and staged plaintext is removed', () async {
      await seed(800003);
      await seal();
      var bytes = await encrypted.readAsBytes();
      switch (damage) {
        case 'header':
          bytes[21] ^= 1;
        case 'ciphertext':
          bytes[bytes.length - 1] ^= 1;
        case 'truncated':
          bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
        case 'appended':
          bytes = Uint8List.fromList([...bytes, 1]);
        case 'reordered':
          const offset =
              StreamingEncryptedFile.headerBytes +
              StreamingEncryptedFile.segmentBytes;
          const size = StreamingEncryptedFile.segmentBytes;
          final second = bytes.sublist(offset, offset + size);
          bytes.setRange(offset, offset + size, bytes, offset + size);
          bytes.setRange(offset + size, offset + 2 * size, second);
      }
      await encrypted.writeAsBytes(bytes);
      await expectLater(open(), throwsFormatException);
      expect(await restored.exists(), isFalse);
    });
  }

  test(
    'ciphertext from another file cannot replace a same-length segment',
    () async {
      await seed(800003);
      await seal();
      final other = File('${scratch.path}/other');
      await StreamingEncryptedFile.encrypt(
        source: source,
        destination: other,
        context: context,
        key: key,
      );
      final original = await encrypted.readAsBytes();
      final foreign = await other.readAsBytes();
      const offset =
          StreamingEncryptedFile.headerBytes +
          StreamingEncryptedFile.segmentBytes;
      original.setRange(
        offset,
        offset + StreamingEncryptedFile.segmentBytes,
        foreign,
        offset,
      );
      await encrypted.writeAsBytes(original);
      await expectLater(open(), throwsFormatException);
      expect(await restored.exists(), isFalse);
    },
  );

  test(
    'wrong context, key and size limit never produce usable output',
    () async {
      await seed(500);
      await seal();
      await expectLater(
        open(expectedContext: 'other/circle/bootstrap'),
        throwsFormatException,
      );
      await expectLater(
        open(expectedKey: SecretKey(List.filled(32, 99))),
        throwsFormatException,
      );
      await expectLater(
        StreamingEncryptedFile.decrypt(
          source: encrypted,
          destination: restored,
          context: context,
          key: key,
          maxPlainBytes: 499,
        ),
        throwsFormatException,
      );
      expect(await restored.exists(), isFalse);
    },
  );

  test(
    'cancel during a transfer stops the worker and removes its partial file',
    () async {
      await seed(4 * 1024 * 1024);
      final cancellation = LocalBackupCancellation();
      var progress = 0;
      await expectLater(
        seal(
          cancellation: cancellation,
          onProgress: (done, total) {
            progress = done;
            cancellation.cancel();
          },
        ),
        throwsA(isA<LocalBackupCancelledException>()),
      );
      expect(progress, greaterThan(0));
      expect(progress, lessThan(await source.length()));
      expect(await encrypted.exists(), isFalse);
      // A cancellation must also release the global worker permit.
      await seal();
      await open();
    },
  );

  test('never overwrites an existing destination', () async {
    await seed(123);
    await encrypted.writeAsString('existing');
    await expectLater(seal(), throwsStateError);
    expect(await encrypted.readAsString(), 'existing');
  });

  test(
    'a failing progress observer cancels cleanly without leaking the output',
    () async {
      await seed(2 * 1024 * 1024);
      final failure = StateError('observer failed');
      await expectLater(
        seal(onProgress: (_, _) => throw failure),
        throwsA(same(failure)),
      );
      expect(await encrypted.exists(), isFalse);
      await seal();
    },
  );
}
