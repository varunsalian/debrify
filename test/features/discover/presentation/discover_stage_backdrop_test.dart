import 'observed_value.dart';
import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/discover/presentation/discover_stage_backdrop.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home/home_mdblist_continuation_screen_test.dart'
    show FixtureImages;

StremioMeta art(String id, {bool background = true}) => StremioMeta(
  id: id,
  name: id,
  type: 'movie',
  background: background ? 'https://art.invalid/$id.png' : null,
  poster: 'https://art.invalid/poster.png',
);

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('discover_backdrop_');
    final file = await io.File('${images.path}/image.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
  testWidgets(
    'first backdrop is immediate; later focus debounces and missing backgrounds clear',
    (tester) async {
      final shown = ObservedValue<StremioMeta?>(null);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DiscoverStageBackdrop(shown: shown)),
      );
      String? image() => find.byType(CachedNetworkImage).evaluate().isEmpty
          ? null
          : tester
                .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
                .imageUrl;
      shown.value = art('first');
      await tester.pump();
      expect(image(), 'https://art.invalid/first.png');
      shown.value = art('second');
      await tester.pump(const Duration(milliseconds: 379));
      expect(image(), 'https://art.invalid/first.png');
      shown.value = art('third');
      await tester.pump(const Duration(milliseconds: 379));
      expect(image(), 'https://art.invalid/first.png');
      await tester.pump(const Duration(milliseconds: 1));
      expect(image(), 'https://art.invalid/third.png');
      shown.value = art('poster-only', background: false);
      await tester.pump();
      expect(image(), isNull);
      shown.value = art('fourth');
      await tester.pump();
      expect(image(), 'https://art.invalid/fourth.png');
      shown.value = art('pending');
      await tester.pumpWidget(const SizedBox());
      expect(shown.isObserved, isFalse);
      shown.value = art('after-disposal');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
  for (final androidTv in [false, true]) {
    testWidgets(
      'settled stage art preserves crossfade policy: Android TV=$androidTv',
      (tester) async {
        PlatformUtil.debugSetAndroidTvCached(androidTv);
        final shown = ObservedValue<StremioMeta?>(art('first'));
        addTearDown(shown.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: DiscoverStageBackdrop(
              shown: shown,
              dwell: Duration.zero,
              crossfade: true,
            ),
          ),
        );
        expect(
          find.byType(AnimatedSwitcher),
          androidTv ? findsNothing : findsOneWidget,
        );
        shown.value = art('next');
        await tester.pump();
        expect(
          tester
              .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .last
              .imageUrl,
          'https://art.invalid/next.png',
        );
        if (!androidTv) {
          final switcher = tester.widget<AnimatedSwitcher>(
            find.byType(AnimatedSwitcher),
          );
          expect(switcher.duration, const Duration(milliseconds: 240));
          expect(switcher.reverseDuration, const Duration(milliseconds: 240));
        }
        await tester.pump(const Duration(milliseconds: 250));
        shown.value = null;
        await tester.pump();
        await tester.pump();
        if (!androidTv) {
          final switcher = tester.widget<AnimatedSwitcher>(
            find.byType(AnimatedSwitcher),
          );
          expect(switcher.child, isA<SizedBox>());
          expect(switcher.reverseDuration, Duration.zero);
          // The outgoing entry retains the controller created for its prior
          // image. Preserve its existing 240ms removal behavior.
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.byType(CachedNetworkImage), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expect(shown.isObserved, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
