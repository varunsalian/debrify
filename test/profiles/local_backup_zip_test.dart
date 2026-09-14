import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-backup-zip-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> fixture(String name, int bytes, {int seed = 7}) async {
    final file = File('${root.path}/$name');
    final random = Random(seed);
    final sink = file.openWrite();
    var remaining = bytes;
    while (remaining > 0) {
      final size = min(remaining, 64 * 1024);
      sink.add(
        Uint8List.fromList(
          List<int>.generate(size, (_) => random.nextInt(256)),
        ),
      );
      remaining -= size;
    }
    await sink.close();
    return file;
  }

  Future<File> writeArchive(List<LocalBackupZipSource> sources) async {
    final output = File('${root.path}/out.zip');
    await LocalBackupZip.write(
      output: output,
      sources: sources,
      modified: DateTime.utc(2026, 9, 5, 12, 30, 10),
    );
    return output;
  }

  test('round-trips stored entries with verified CRC and SHA-256', () async {
    final big = await fixture('big.bin', 3 * 1024 * 1024 + 123);
    final small = await fixture('small.txt', 17, seed: 2);
    final empty = await fixture('empty.bin', 0);
    final expectedBig = await StreamedSha256.ofFile(big);
    final expectedSmall = await StreamedSha256.ofFile(small);
    final archive = await writeArchive(<LocalBackupZipSource>[
      LocalBackupZipSource(
        name: 'databases/p0/big.db',
        file: big,
        bytes: big.lengthSync(),
      ),
      LocalBackupZipSource(
        name: 'attachments/small.m3u',
        file: small,
        bytes: 17,
      ),
      LocalBackupZipSource(name: 'empty.bin', file: empty, bytes: 0),
    ]);

    final reader = await LocalBackupZipReader.open(archive);
    try {
      expect(reader.entries.map((entry) => entry.name), <String>[
        'databases/p0/big.db',
        'attachments/small.m3u',
        'empty.bin',
      ]);
      final extracted = File('${root.path}/restored.db');
      final progress = <int>[];
      final digest = await reader.extract(
        reader.find('databases/p0/big.db')!,
        extracted,
        onProgress: (_, done, total) => progress.add(done),
      );
      expect(digest, expectedBig);
      expect(await extracted.length(), await big.length());
      expect(progress.last, await big.length());
      expect(
        await reader.digest(reader.find('attachments/small.m3u')!),
        expectedSmall,
      );
      expect(
        await reader.readSmall(
          reader.find('attachments/small.m3u')!,
          maxBytes: 64,
        ),
        await small.readAsBytes(),
      );
      expect(
        await reader.digest(reader.find('empty.bin')!),
        await StreamedSha256.ofFile(empty),
      );
    } finally {
      await reader.close();
    }
  });

  test('archives are readable by the archive package decoder', () async {
    final data = await fixture('data.bin', 200 * 1024);
    final archive = await writeArchive(<LocalBackupZipSource>[
      LocalBackupZipSource(
        name: 'databases/p0/data.db',
        file: data,
        bytes: 200 * 1024,
      ),
    ]);
    final input = InputFileStream(archive.path);
    try {
      final decoded = ZipDecoder().decodeStream(input);
      expect(decoded.length, 1);
      final entry = decoded.first;
      expect(entry.name, 'databases/p0/data.db');
      expect(entry.size, 200 * 1024);
      expect(entry.readBytes(), await data.readAsBytes());
    } finally {
      await input.close();
    }
  });

  test('rejects a flipped byte through the CRC check', () async {
    final data = await fixture('data.bin', 300 * 1024);
    final archive = await writeArchive(<LocalBackupZipSource>[
      LocalBackupZipSource(name: 'data.bin', file: data, bytes: 300 * 1024),
    ]);
    final raf = await archive.open(mode: FileMode.append);
    await raf.setPosition(100 * 1024);
    final original = (await raf.read(1)).single;
    await raf.setPosition(100 * 1024);
    await raf.writeByte(original ^ 0xff);
    await raf.close();

    final reader = await LocalBackupZipReader.open(archive);
    try {
      await expectLater(
        reader.digest(reader.entries.single),
        throwsA(isA<LocalBackupFormatException>()),
      );
      expect(File('${root.path}/never.bin').existsSync(), isFalse);
    } finally {
      await reader.close();
    }
  });

  test('rejects a truncated archive before extraction', () async {
    final data = await fixture('data.bin', 300 * 1024);
    final archive = await writeArchive(<LocalBackupZipSource>[
      LocalBackupZipSource(name: 'data.bin', file: data, bytes: 300 * 1024),
    ]);
    final raf = await archive.open(mode: FileMode.append);
    await raf.truncate(150 * 1024);
    await raf.close();
    await expectLater(
      LocalBackupZipReader.open(archive),
      throwsA(isA<LocalBackupFormatException>()),
    );
  });

  test('refuses unsafe, duplicate, and compressed entries', () async {
    final data = await fixture('data.bin', 10);
    expect(
      () => writeArchive(<LocalBackupZipSource>[
        LocalBackupZipSource(name: '../escape', file: data, bytes: 10),
      ]),
      throwsA(isA<LocalBackupFormatException>()),
    );
    expect(
      () => writeArchive(<LocalBackupZipSource>[
        LocalBackupZipSource(name: 'a.bin', file: data, bytes: 10),
        LocalBackupZipSource(name: 'a.bin', file: data, bytes: 10),
      ]),
      throwsA(isA<LocalBackupFormatException>()),
    );
    expect(
      () => writeArchive(<LocalBackupZipSource>[
        LocalBackupZipSource(name: 'a.bin', file: data, bytes: 11),
      ]),
      throwsA(isA<LocalBackupFormatException>()),
    );

    // A deflated archive from the library must be turned away by the reader.
    final deflated = File('${root.path}/deflated.zip');
    final output = OutputFileStream(deflated.path);
    final encoder = ZipEncoder()..startEncode(output);
    final stream = InputFileStream(data.path);
    encoder.add(ArchiveFile.stream('a.bin', stream));
    encoder.endEncode();
    await output.close();
    await expectLater(
      LocalBackupZipReader.open(deflated),
      throwsA(isA<LocalBackupFormatException>()),
    );
  });

  test('cancellation aborts the write and leaves no partial output', () async {
    final data = await fixture('data.bin', 2 * 1024 * 1024);
    final output = File('${root.path}/cancelled.zip');
    final cancellation = LocalBackupCancellation();
    await expectLater(
      LocalBackupZip.write(
        output: output,
        sources: <LocalBackupZipSource>[
          LocalBackupZipSource(
            name: 'data.bin',
            file: data,
            bytes: 2 * 1024 * 1024,
          ),
        ],
        modified: DateTime.utc(2026),
        cancellation: cancellation,
        onProgress: (_, done, _) {
          if (done > 512 * 1024) cancellation.cancel();
        },
      ),
      throwsA(isA<LocalBackupCancelledException>()),
    );
    expect(output.existsSync(), isFalse);
  });

  test('header probe distinguishes archives from JSON', () async {
    final data = await fixture('data.bin', 10);
    final archive = await writeArchive(<LocalBackupZipSource>[
      LocalBackupZipSource(name: 'data.bin', file: data, bytes: 10),
    ]);
    final json = File('${root.path}/backup.json')..writeAsStringSync('{"a":1}');
    expect(await LocalBackupZip.looksLikeArchive(archive), isTrue);
    expect(await LocalBackupZip.looksLikeArchive(json), isFalse);
  });
}
