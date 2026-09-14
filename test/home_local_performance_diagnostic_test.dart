// Opt-in, read-only diagnostics. Never stores account credentials or preferences.
// HOME_DIAGNOSTIC_PLIST points at a local Mac app preference file.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debrify/models/home_collection_inventory.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/utils/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';

class _DiagnosticHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['HOME_DIAGNOSTIC_PLIST'];
  test(
    'local inventory and artwork constrained-cache diagnostic',
    () async {
      final process = await Process.run('plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        path!,
      ]);
      expect(process.exitCode, 0);
      final prefs =
          jsonDecode(process.stdout as String) as Map<String, dynamic>;
      final inventories = prefs.entries.where(
        (e) => e.key.endsWith('.remote_home_collections_v2'),
      );
      expect(
        inventories,
        hasLength(1),
        reason: 'Select a profile explicitly if multiple inventories exist.',
      );
      final encoded = inventories.single.value as String;
      final watch = Stopwatch()..start();
      final result = await HomeCollectionInventory.readAsync(encoded);
      final readMs = watch.elapsedMicroseconds / 1000;
      final collections = result.inventory.collections;
      final folders = collections.expand((c) => c.folders).toList();
      final rows = [
        for (final c in collections) HomeCollectionSection(collection: c),
      ];
      watch.reset();
      for (var repeat = 0; repeat < 10; repeat++) {
        for (final row in rows) {
          for (final item in row.items) {
            row.folderOf(item);
            row.focusArtOf(item);
            row.focusVideoOf(item);
            row.tileAspectOf(item);
            row.folderOf(item);
          }
        }
      }
      print(
        'HOME_DIAG ten collection row presentations: ms=${watch.elapsedMicroseconds / 1000}',
      );
      final sources = folders.expand((f) => f.sources).toList();
      print(
        'HOME_DIAG inventory: collections=${collections.length}, enabled=${collections.where((c) => c.enabled).length}, folders=${folders.length}, sources=${sources.length}, storedBytes=${encoded.length}, definitionBytes=${result.size}, asyncReadMs=$readMs',
      );
      final timings = <double>[];
      for (var i = 0; i < 12; i++) {
        watch.reset();
        HomeCollectionsStore.signatureOf(collections);
        timings.add(watch.elapsedMicroseconds / 1000);
      }
      timings.sort();
      watch.reset();
      var callerEventRan = false;
      Timer.run(() => callerEventRan = true);
      final workerSignature = await HomeCollectionsStore.signatureOfAsync(
        collections,
      );
      final workerMs = watch.elapsedMicroseconds / 1000;
      expect(workerSignature, HomeCollectionsStore.signatureOf(collections));
      expect(callerEventRan, isTrue);
      print(
        'HOME_DIAG worker signature: totalMs=$workerMs callerEventRan=$callerEventRan (includes worker startup/transfer, not UI-block time)',
      );
      print(
        'HOME_DIAG synchronous signature: medianMs=${timings[6]}, maxMs=${timings.last}',
      );
      for (final count in [0, 1, 4]) {
        final payload = [
          for (var i = 0; i < count; i++)
            for (final c in collections) c.toJson(),
        ];
        watch.reset();
        final measured = measureCanonicalJson(payload);
        print(
          'HOME_DIAG canonical hashing: inventoryCopies=$count bytes=${measured.bytes} mainIsolateMs=${watch.elapsedMicroseconds / 1000}',
        );
      }
      print(
        'HOME_DIAG animated folders: gif=${folders.where((f) => f.focusGifEnabled && f.focusGifUrl != null).length}, video=${folders.where((f) => f.focusVideoEnabled && f.focusVideoUrl != null).length}',
      );

      // Real collection artwork only; no tracker/API credentials or account calls.
      final urls = folders
          .expand((f) => [f.coverImageUrl, f.focusGifUrl])
          .whereType<String>()
          .toSet()
          .toList();
      print(
        'HOME_DIAG artwork hosts: ${urls.map((u) => Uri.tryParse(u)?.host).toSet()}',
      );
      final decodedBytes = <int>[];
      final samples = <Uint8List>[];
      final client = _DiagnosticHttpOverrides().createHttpClient(null)
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        var index = 0;
        var attempts = 0;
        for (final url in urls) {
          if (index >= 6) break;
          final uri = Uri.tryParse(url);
          if (uri == null ||
              uri.scheme != 'https' ||
              !{
                'raw.githubusercontent.com',
                'imkaptain.github.io',
              }.contains(uri.host)) {
            continue;
          }
          if (++attempts > 12) break;
          try {
            watch.reset();
            final request = await client
                .getUrl(uri)
                .timeout(const Duration(seconds: 15));
            final response = await request.close().timeout(
              const Duration(seconds: 15),
            );
            if (response.statusCode != 200) {
              await response.drain<void>();
              continue;
            }
            final bytes = await response
                .fold<List<int>>(<int>[], (out, chunk) {
                  if (out.length + chunk.length > 16 * 1024 * 1024) {
                    throw StateError('Artwork exceeds diagnostic download cap');
                  }
                  return out..addAll(chunk);
                })
                .timeout(const Duration(seconds: 20));
            final networkMs = watch.elapsedMicroseconds / 1000;
            samples.add(Uint8List.fromList(bytes));
            for (final width in [320, 640, 1280]) {
              watch.reset();
              final buffer = await ui.ImmutableBuffer.fromUint8List(
                Uint8List.fromList(bytes),
              );
              final codec = await ui.instantiateImageCodecFromBuffer(
                buffer,
                targetWidth: width,
                allowUpscaling: false,
              );
              final frame = await codec.getNextFrame();
              final size = frame.image.width * frame.image.height * 4;
              if (width == 640) decodedBytes.add(size);
              print(
                'HOME_DIAG art=$index downloadBytes=${bytes.length} networkMs=$networkMs width=$width decodedBytes=$size decodeMs=${watch.elapsedMicroseconds / 1000} frames=${codec.frameCount}',
              );
              frame.image.dispose();
              codec.dispose();
            }
            index++;
          } catch (e) {
            print('HOME_DIAG artwork sample unavailable (${e.runtimeType})');
          }
        }
      } finally {
        client.close(force: true);
      }
      if (decodedBytes.isNotEmpty) {
        final average =
            decodedBytes.reduce((a, b) => a + b) ~/ decodedBytes.length;
        for (final mb in [16, 32, 56]) {
          print(
            'HOME_DIAG cache arithmetic: budgetMiB=$mb average640pxBytes=$average capacity=${mb * 1024 * 1024 ~/ average} (excludes live images, heroes, GPU and animation frames)',
          );
        }
      }
      // Exercise Flutter's real decoded-image cache with the downloaded covers.
      // Smaller budgets model pressure from other artwork, not total TV RAM.
      final cache = PaintingBinding.instance.imageCache;
      final oldBytes = cache.maximumSizeBytes;
      final oldCount = cache.maximumSize;
      try {
        for (final mb in [1, 4, 16]) {
          cache.clear();
          cache.maximumSize = 140;
          cache.maximumSizeBytes = mb * 1024 * 1024;
          final providers = [
            for (final bytes in samples)
              ResizeImage(MemoryImage(bytes), width: 640),
          ];
          var secondPassHits = 0;
          for (var pass = 0; pass < 2; pass++) {
            for (final provider in providers) {
              final key = await provider.obtainKey(ImageConfiguration.empty);
              if (pass == 1 && cache.containsKey(key)) secondPassHits++;
              final complete = Completer<void>();
              final stream = provider.resolve(ImageConfiguration.empty);
              late ImageStreamListener listener;
              listener = ImageStreamListener(
                (info, _) {
                  info.dispose();
                  stream.removeListener(listener);
                  complete.complete();
                },
                onError: (Object error, StackTrace? stack) {
                  stream.removeListener(listener);
                  complete.completeError(error, stack);
                },
              );
              stream.addListener(listener);
              await complete.future.timeout(const Duration(seconds: 10));
            }
          }
          print(
            'HOME_DIAG real image-cache replay: budgetMiB=$mb cards=${providers.length} secondPassHits=$secondPassHits retainedBytes=${cache.currentSizeBytes}',
          );
          if (mb == 16 && providers.length == 6) expect(secondPassHits, 6);
        }
      } finally {
        cache.clear();
        cache.maximumSizeBytes = oldBytes;
        cache.maximumSize = oldCount;
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
