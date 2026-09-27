import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/presentation/home_hero_tint_surface.dart';
import 'package:debrify/features/home/presentation/home_hero_title_art.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';
import '../home_mdblist_continuation_screen_test.dart' show FixtureImages;
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

Widget host(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);

void main() {
  setUp(disableRuntimeFonts);
  late Directory images;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('hero_title_');
    final file = await File('${images.path}/image.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));

  testWidgets(
    'tint field eases to new color while art feathers use current tint',
    (tester) async {
      final tint = ObservedValue<Color?>(Colors.red);
      addTearDown(tint.dispose);
      const base = Color(0xFF0D0B1A);
      await tester.pumpWidget(
        host(
          Stack(
            fit: StackFit.expand,
            children: [
              buildHomeHeroMoodField(
                boxedTrailer: true,
                base: base,
                surface: Colors.black,
                tint: tint,
              ),
              buildHomeHeroArtFeathers(base: base, tint: tint),
            ],
          ),
        ),
      );
      LinearGradient gradient(Alignment begin) => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((box) => box.gradient)
          .whereType<LinearGradient>()
          .singleWhere((g) => g.begin == begin);
      final old = gradient(Alignment.topLeft).colors.first;
      tint.value = Colors.blue;
      await tester.pump();
      expect(
        gradient(Alignment.centerLeft).colors.first,
        Color.lerp(base, Colors.blue, 0.34),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final middle = gradient(Alignment.topLeft).colors.first;
      expect(middle, isNot(old));
      final target = Color.lerp(
        base,
        Colors.blue,
        0.55,
      )!.withValues(alpha: 0.55);
      expect(middle, isNot(target));
      await tester.pump(const Duration(milliseconds: 201));
      expect(gradient(Alignment.topLeft).colors.first, target);
      await tester.pumpWidget(const SizedBox());
      expect(tint.isObserved, isFalse);
    },
  );

  testWidgets(
    'title art preserves slot sizes, decode limit and session failure fallback',
    (tester) async {
      const url = 'https://fixture.invalid/hero-logo';
      for (final (tv, compact, height) in [
        (true, true, 46.0),
        (true, false, 76.0),
        (false, true, 38.0),
        (false, false, 58.0),
      ]) {
        await tester.pumpWidget(
          host(
            Center(
              child: HomeHeroTitleArt(
                title: 'Title',
                logoUrl: url,
                compact: compact,
                isTelevision: tv,
              ),
            ),
          ),
        );
        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.memCacheWidth, 480);
        expect(image.fit, BoxFit.contain);
        expect(tester.getSize(find.byType(HomeHeroTitleArt)).height, height);
        expect(find.text('Title'), findsNothing);
      }
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .errorListener!(StateError('missing logo'));
      await tester.pump();
      expect(find.text('Title'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(
          const HomeHeroTitleArt(
            title: 'Revisited',
            logoUrl: url,
            compact: true,
            isTelevision: true,
          ),
        ),
      );
      final title = tester.widget<Text>(find.text('Revisited'));
      expect(title.maxLines, 2);
      expect(title.style!.fontSize, 24);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
