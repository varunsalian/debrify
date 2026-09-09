import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file/local.dart';
import 'package:debrify/widgets/recoverable_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class Images extends Fake implements BaseCacheManager {
  final File file;
  final bool alwaysFail;
  int reads = 0;
  int removals = 0;
  Images(this.file, {this.alwaysFail = false});
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    reads++;
    if (reads == 1 || alwaysFail) {
      throw const HttpException('temporary failure');
    }
    yield FileInfo(
      const LocalFileSystem().file(file.path),
      FileSource.Cache,
      DateTime.now().add(const Duration(hours: 1)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {
    removals++;
  }
}

void main() {
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
  late Directory temp;
  late File png;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('debrify-image-test');
    png = File('${temp.path}/image.png');
    await png.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
  });
  tearDownAll(() => temp.delete(recursive: true));
  Widget app(Images images, String url) => MaterialApp(
    home: RecoverableNetworkImage(
      imageUrl: url,
      cacheManager: images,
      placeholder: (_, __) => const Text('loading'),
      errorWidget: (_, __, ___) => const Text('failed'),
    ),
  );
  testWidgets('TV image reveal uses one short fade and honors reduced motion', (
    tester,
  ) async {
    for (final tv in [false, true]) {
      PlatformUtil.debugSetAndroidTvCached(tv);
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: RecoverableNetworkImage(
                imageUrl: 'https://image.test/policy.png',
                cacheManager: Images(png, alwaysFail: true),
                fadeInDuration: const Duration(milliseconds: 420),
                fadeOutDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => const SizedBox(),
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
          ),
        );
        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(
          image.fadeInDuration,
          reduced ? Duration.zero : Duration(milliseconds: tv ? 180 : 420),
        );
        expect(
          image.fadeOutDuration,
          reduced || tv ? Duration.zero : const Duration(milliseconds: 180),
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
  testWidgets('failed image retries in the same mounted card', (tester) async {
    final images = Images(png);
    await tester.pumpWidget(app(images, 'https://image.test/recover.png'));
    await tester.pump();
    expect(find.text('failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(images.reads, 2);
    expect(find.text('failed'), findsNothing);
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((i) => i.image != null),
      true,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('permanent failures are bounded and disposal cancels retry', (
    tester,
  ) async {
    final images = Images(png, alwaysFail: true);
    await tester.pumpWidget(app(images, 'https://image.test/permanent.png'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    }
    expect(images.reads, 3);
    await tester.pumpWidget(app(images, 'https://image.test/dispose.png'));
    await tester.pump();
    final reads = images.reads;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(images.reads, reads);
  });
}
