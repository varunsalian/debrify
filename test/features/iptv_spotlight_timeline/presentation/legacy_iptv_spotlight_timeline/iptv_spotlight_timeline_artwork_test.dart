import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

class HeldLogoCompleter extends ImageStreamCompleter {
  final listeners = <ImageStreamListener>[];
  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }

  void release() {
    for (final listener in listeners.toList()) {
      removeListener(listener);
    }
  }
}

class RecordingLogoCache extends ImageCache {
  final keys = <Object>[];
  final held = <Object, HeldLogoCompleter>{};
  @override
  ImageStreamCompleter? putIfAbsent(
    Object key,
    ImageStreamCompleter Function() loader, {
    ImageErrorListener? onError,
  }) {
    keys.add(key);
    // The loader is deliberately never called: no HTTP, filesystem or SQLite.
    return held.putIfAbsent(key, HeldLogoCompleter.new);
  }

  void release() {
    for (final completer in held.values) {
      completer.release();
    }
    held.clear();
    keys.clear();
    clear();
    clearLiveImages();
  }
}

final logos = RecordingLogoCache();

class TimelineArtworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => logos;
}

void main() {
  TimelineArtworkBinding();
  testWidgets(
    'channel logo retains dedicated cache, 96px decode and contain fit without storage access',
    (tester) async {
      final storage = <String>[];
      final bootstrap = <String>[];
      var initializing = true;
      const channels = [
        MethodChannel('plugins.flutter.io/path_provider'),
        MethodChannel('plugins.flutter.io/path_provider_macos'),
        MethodChannel('com.tekartik.sqflite'),
      ];
      for (final channel in channels) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (initializing && call.method != 'openDatabase') {
              bootstrap.add(call.method);
              return Completer<Object?>().future;
            }
            storage.add(call.method);
            throw StateError('Unexpected storage ${call.method}');
          },
        );
      }
      final cache = DebrifyImageCache.iptvLogos;
      await tester.pump();
      initializing = false;
      expect(
        bootstrap,
        contains('getTemporaryDirectory'),
        reason: 'ORIGINAL cache construction requests its directory eagerly',
      );
      try {
        await timelineCase(
          tester,
          (f) async {
            f.loader = (_) async => [];
            await f.mount(tester);
            await f.settle(tester);
            final image = tester.widget<CachedNetworkImage>(
              find.byType(CachedNetworkImage),
            );
            expect(image.cacheManager, same(cache));
            expect(image.memCacheHeight, 96);
            expect(image.memCacheWidth, isNull);
            expect(image.fit, BoxFit.contain);
            expect(image.imageUrl, 'https://artwork.test/logo.png');
            expect(
              logos.keys,
              isNotEmpty,
              reason: 'recording image cache intercepts resolution',
            );
            expect(
              storage,
              isEmpty,
              reason: 'recording cache never invokes an image loader',
            );
          },
          channels: [
            timelineChannel(0, logo: ' https://artwork.test/logo.png '),
          ],
        );
      } finally {
        logos.release();
        for (final channel in channels) {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
      }
    },
  );
}
