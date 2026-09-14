// Run each case in a fresh release process to compare process high-water RSS:
// dart compile exe tool/benchmark_webdav_streaming.dart -o /tmp/webdav-bench
// /tmp/webdav-bench 64 compressible
// /tmp/webdav-bench 512 compressible
// /tmp/webdav-bench 64 random
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/transfer/streaming_encrypted_file.dart';
import 'package:debrify/services/transfer/transfer_io.dart';

Future<void> main(List<String> args) async {
  final mib = int.parse(args.first);
  if (mib < 1 || mib > 2048) throw ArgumentError('Use 1–2048 MiB');
  final legacy = args.length > 2 && args[2] == 'legacy';
  final random = args.length > 1 && args[1] == 'random';
  final directory = await Directory.systemTemp.createTemp('webdav-benchmark-');
  final source = File('${directory.path}/source');
  final sealed = File('${directory.path}/sealed');
  final restored = File('${directory.path}/restored');
  final key = SecretKey(List.generate(32, (i) => i));
  final initialRss = ProcessInfo.currentRss;
  var sampledPeakWorkingBytes = 0;
  Future<void>? sampling;
  Future<void> sampleStorage() async {
    var bytes = 0;
    try {
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File) continue;
        try {
          bytes += await entry.length();
        } on FileSystemException {
          /* Removed between samples. */
        }
      }
    } on FileSystemException {
      /* A codec scratch directory can disappear during traversal. */
    }
    if (bytes > sampledPeakWorkingBytes) sampledPeakWorkingBytes = bytes;
  }

  final sampler = Timer.periodic(const Duration(milliseconds: 100), (_) {
    sampling ??= sampleStorage().whenComplete(() => sampling = null);
  });
  try {
    final output = await source.open(mode: FileMode.writeOnly);
    var state = 0x35718642;
    try {
      final chunk = Uint8List(TransferIo.bufferBytes);
      for (var offset = 0; offset < mib * 1024 * 1024; offset += chunk.length) {
        for (var i = 0; i < chunk.length; i++) {
          state ^= (state << 13) & 0xffffffff;
          state ^= state >> 17;
          state ^= (state << 5) & 0xffffffff;
          chunk[i] = random ? state & 255 : (i % 1024 < 900 ? 0 : state & 255);
        }
        await output.writeFrom(chunk);
      }
    } finally {
      await output.close();
    }
    final hash = await TransferIo.hashFile(source);
    if (legacy) {
      // Prior bootstrap shape: database -> base64 -> JSON -> compressed AEAD
      // envelope. Excludes root KDF time and network, as does the binary case.
      final codec = WebDavSyncCodec();
      final marker = await codec.sealRoot(
        passphrase: 'benchmark-only',
        circleId: 'benchmark',
        createdAt: DateTime.utc(2026),
        memoryKiB: 8,
        iterations: 1,
      );
      final root = await codec.openRoot(marker, 'benchmark-only');
      final watch = Stopwatch()..start();
      final encoded = await codec.sealDocument(
        key: root.key,
        circleId: 'benchmark',
        deviceId: 'benchmark-device',
        logicalName: 'bootstrap',
        schemaVersion: 1,
        payload: {'database': base64Encode(await source.readAsBytes())},
        maxBytes: 128 * 1024 * 1024,
        runInBackground: true,
      );
      await sealed.writeAsBytes(encoded);
      final encryptMs = watch.elapsedMilliseconds;
      watch.reset();
      final opened = await codec.openDocument(
        key: root.key,
        circleId: 'benchmark',
        deviceId: 'benchmark-device',
        logicalName: 'bootstrap',
        schemaVersion: 1,
        encoded: await sealed.readAsBytes(),
        maxBytes: 128 * 1024 * 1024,
        runInBackground: true,
      );
      await restored.writeAsBytes(
        base64Decode((opened as Map)['database'] as String),
      );
      final decryptMs = watch.elapsedMilliseconds;
      if (await TransferIo.hashFile(restored) != hash) {
        throw StateError('Legacy mismatch');
      }
      stdout.writeln(
        jsonEncode({
          'pipeline': 'legacy',
          'mib': mib,
          'data': random ? 'random' : 'compressible',
          'sourceBytes': await source.length(),
          'transferredBytes': encoded.length,
          'encryptMs': encryptMs,
          'decryptMs': decryptMs,
          'initialRss': initialRss,
          'peakRss': ProcessInfo.maxRss,
          'sampledPeakWorkingBytes': sampledPeakWorkingBytes,
          'verified': true,
        }),
      );
      return;
    }
    final encrypted = await StreamingEncryptedFile.encrypt(
      source: source,
      destination: sealed,
      context: 'benchmark',
      key: key,
      compress: true,
    );
    final decrypted = await StreamingEncryptedFile.decrypt(
      source: sealed,
      destination: restored,
      context: 'benchmark',
      key: key,
    );
    if (decrypted.sha256Hex != hash) throw StateError('Round trip mismatch');
    stdout.writeln(
      jsonEncode({
        'mib': mib,
        'data': random ? 'random' : 'compressible',
        'sourceBytes': await source.length(),
        'transferredBytes': encrypted.bytes,
        'encryptMs': encrypted.elapsedMs,
        'decryptMs': decrypted.elapsedMs,
        'initialRss': initialRss,
        'peakRss': ProcessInfo.maxRss,
        'sampledPeakWorkingBytes': sampledPeakWorkingBytes,
        'verified': true,
      }),
    );
  } finally {
    sampler.cancel();
    await sampling;
    await directory.delete(recursive: true);
  }
}
