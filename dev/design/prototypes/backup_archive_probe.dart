// Standalone synthetic Mac feasibility probe, not an application backup reader.
// Uses the repository package config; run each phase in a fresh AOT process.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

Future<String> digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String> sql(String path, String statement) async {
  final result = await Process.run('/usr/bin/sqlite3', [path, statement]);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return '${result.stdout}'.trim();
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final timer = Stopwatch()..start();
  final mode = args[0];
  final root = Directory(args[1]);
  final variant = args.length > 2 ? args[2] : 'store';
  final archivePath = '${root.path}/$variant.zip';
  final manifestFile = File('${root.path}/expected.json');
  final baselineRss = ProcessInfo.currentRss;
  final details = <String, Object?>{};
  if (mode == 'fixture') {
    await root.create(recursive: true);
    final mib = int.parse(variant);
    final database = File('${root.path}/library.db');
    require(!database.existsSync(), 'Use a fresh fixture directory');
    await sql(database.path, '''
PRAGMA journal_mode=DELETE;
PRAGMA cache_size=-2048;
PRAGMA user_version=7;
CREATE TABLE saved_hashes(id INTEGER PRIMARY KEY, payload BLOB NOT NULL);
CREATE TABLE favorites(id INTEGER PRIMARY KEY, name TEXT, source TEXT);
INSERT INTO favorites VALUES(1,'Synthetic favorite','synthetic-provider');
BEGIN;
WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<${mib * 256})
INSERT INTO saved_hashes SELECT x,randomblob(4096) FROM n;
COMMIT;
''');
    final m3u = File('${root.path}/imported.m3u');
    final output = m3u.openSync(mode: FileMode.write);
    final chunk = utf8.encode(List.generate(512, (i) =>
        '#EXTINF:-1,Test channel $i\nhttps://example.invalid/live/$i\n').join());
    final target = (mib ~/ 10 + 1) * 1024 * 1024;
    while (output.positionSync() < target) {
      output.writeFromSync(chunk);
    }
    output.closeSync();
    final records = <String, Object?>{};
    for (final file in [database, m3u]) {
      records[file.uri.pathSegments.last] = {
        'size': await file.length(), 'sha256': await digest(file),
      };
    }
    await manifestFile.writeAsString(jsonEncode(records));
    details['files'] = records;
  } else if (mode == 'pack') {
    final output = OutputFileStream(archivePath);
    final encoder = ZipEncoder()..startEncode(output, level: 1);
    for (final name in ['library.db', 'imported.m3u', 'expected.json']) {
      final input = InputFileStream('${root.path}/$name');
      final entry = ArchiveFile.stream(name, input)
        ..compression = variant == 'store'
            ? CompressionType.none : CompressionType.deflate;
      encoder.add(entry, level: 1);
      await input.close();
    }
    encoder.endEncode();
    await output.close();
    details['archiveBytes'] = await File(archivePath).length();
  } else if (mode == 'copy') {
    final destination = File('${root.path}/saved-$variant.zip');
    final sink = destination.openWrite();
    await sink.addStream(File(archivePath).openRead());
    await sink.close();
    require(await digest(destination) == await digest(File(archivePath)),
        'Destination read-back mismatch');
    details['destinationVerified'] = true;
  } else if (mode == 'restore' || mode == 'corrupt' || mode == 'truncated') {
    final savedPath = '${root.path}/saved-$variant.zip';
    var source = mode == 'restore' && File(savedPath).existsSync()
        ? savedPath : archivePath;
    if (mode != 'restore') {
      require(variant == 'store', 'Fault probes use stored entries');
      source = '${root.path}/$mode.zip';
      await File(archivePath).copy(source);
      final reader = File(source).openSync();
      reader.setPositionSync(128 * 1024);
      final originalByte = reader.readByteSync();
      reader.closeSync();
      final file = File(source).openSync(mode: FileMode.append);
      if (mode == 'truncated') {
        file.truncateSync(file.lengthSync() ~/ 2);
      } else {
        file.setPositionSync(128 * 1024);
        file.writeByteSync(originalByte ^ 0xff);
      }
      file.closeSync();
    }
    var rejected = false;
    InputFileStream? input;
    try {
      final expected = jsonDecode(await manifestFile.readAsString()) as Map;
      final destination = Directory('${root.path}/restored-$variant-$mode');
      await destination.create();
      input = InputFileStream(source);
      final archive = ZipDecoder().decodeStream(input);
      require(archive.length == 3, 'Entry count mismatch');
      final seen = <String>{};
      for (final entry in archive) {
        require(seen.add(entry.name), 'Duplicate name');
        require(['library.db', 'imported.m3u', 'expected.json'].contains(entry.name)
            && entry.isFile && !entry.isSymbolicLink, 'Unexpected entry');
        final expectedSize = entry.name == 'expected.json'
            ? await manifestFile.length() : expected[entry.name]['size'] as int;
        require(entry.size == expectedSize, 'Declared size mismatch');
        final outputFile = File('${destination.path}/${entry.name}');
        final output = OutputFileStream(outputFile.path);
        try { entry.writeContent(output); } finally { await output.close(); }
        require(await outputFile.length() == expectedSize, 'Extracted size mismatch');
        final hash = entry.name == 'expected.json'
            ? await digest(manifestFile) : expected[entry.name]['sha256'];
        require(await digest(outputFile) == hash, 'SHA-256 mismatch');
      }
      final db = '${destination.path}/library.db';
      require(await sql(db, 'PRAGMA integrity_check;') == 'ok', 'SQLite integrity');
      require(await sql(db, 'PRAGMA user_version;') == '7', 'Schema version');
      require(await sql(db, 'SELECT name FROM favorites WHERE id=1;') ==
          'Synthetic favorite', 'Favorite missing');
      details['verified'] = true;
    } catch (error) {
      if (mode == 'restore') rethrow;
      rejected = true;
      details['rejectedWith'] = '$error';
    } finally {
      await input?.close();
    }
    if (mode != 'restore') require(rejected, 'Damaged archive was accepted');
  } else if (mode == 'json-baseline') {
    // Isolates the existing whole-file/base64/JSON allocation pattern.
    // Deliberately excludes encryption and does not represent full app timing.
    final files = <String, String>{};
    for (final name in ['library.db', 'imported.m3u']) {
      files[name] = base64Encode(await File('${root.path}/$name').readAsBytes());
    }
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode(files)));
    await File('${root.path}/baseline.json').writeAsBytes(encoded);
    details['outputBytes'] = encoded.length;
  } else {
    throw ArgumentError('Unknown mode $mode');
  }
  print(jsonEncode({
    'mode': mode, 'variant': variant, 'seconds': timer.elapsedMilliseconds / 1000,
    'baselineRssMiB': baselineRss / 1048576,
    'peakRssMiB': ProcessInfo.maxRss / 1048576, ...details,
  }));
}
