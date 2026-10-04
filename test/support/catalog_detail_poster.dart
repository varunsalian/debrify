import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Serve and decode the fixture poster, then prime only Flutter's 32px image
/// cache key. The production cache/extractor still computes the real colour;
/// native disk caching is outside this view-publication characterization.
Future<void> catalogFixturePoster(WidgetTester t, String url) async {
  await t.runAsync(() async {
    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, 200);
    final codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: 32,
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final provider = ResizeImage(
      CachedNetworkImageProvider(url),
      width: 32,
      policy: ResizeImagePolicy.fit,
    );
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final ready = Completer<void>();
    final stream = OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image)),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      ready.complete();
      stream.removeListener(listener);
    });
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => stream);
    stream.addListener(listener);
    await ready.future;
    addTearDown(() {
      PaintingBinding.instance.imageCache.evict(key);
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  });
}
