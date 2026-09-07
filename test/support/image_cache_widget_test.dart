import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Exercises real image loading and cache maintenance without native storage,
/// network access, or a shared cache surviving into the next widget test.
void testWidgetsWithImageCache(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    final previous = CachedNetworkImageProvider.defaultCacheManager;
    // A valid one-pixel PNG; these tests inspect visibility/layout, not GIF frames.
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    final client = MockClient(
      (_) async => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/png', 'cache-control': 'max-age=3600'},
      ),
    );
    final cache = CacheManager(
      Config(
        'widget-test-images',
        repo: NonStoringObjectProvider(),
        fileSystem: MemoryCacheSystem(),
        fileService: HttpFileService(httpClient: client),
        maxCacheBytes: 30 * 1024 * 1024,
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = cache;
    try {
      await body(tester);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        // Dispose inside the test body: ordinary addTearDown runs after the
        // binding's pending-timer invariant has already been checked.
        try {
          await cache.dispose();
        } finally {
          CachedNetworkImageProvider.defaultCacheManager = previous;
          client.close();
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      }
    }
  });
}
