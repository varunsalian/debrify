import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/presentation/home_stage_art.dart';
import 'package:debrify/features/home/presentation/home_favorite_focus.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/hero_metadata_presentation.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';
import '../home_mdblist_continuation_screen_test.dart' show FixtureImages;

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('home_stage_art_');
    final file = await io.File('${images.path}/image.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() async {
    await images.delete(recursive: true);
  });

  testWidgets(
    'matching metadata enriches art; unrelated and disabled fallback cannot leak',
    (tester) async {
      final h = _Art();
      addTearDown(h.dispose);
      h.item.value = _item(
        'tmdb:stage',
        imdb: 'ttstage',
        background: 'catalog',
      );
      h.enriched.value = _item('other', background: 'wrong');
      await tester.pumpWidget(h.host());
      expect(h.current(tester).imageUrl, 'https://art.invalid/catalog');
      h.enriched.value = _item('ttstage', background: 'enriched');
      await tester.pump();
      expect(h.current(tester).imageUrl, 'https://art.invalid/enriched');
      h.enriched.value = _item('ttstage');
      await tester.pump();
      expect(h.current(tester).imageUrl, 'https://art.invalid/catalog');
      h.enriched.value = HeroMetadataPresentation(
        _item('ttstage'),
        MetadataPreferences(
          providers: {MetadataCategory.backgrounds: 'tmdb'},
          fallback: false,
        ),
      );
      await tester.pump();
      expect(h.switcher(tester).child, isA<SizedBox>());
      await tester.pumpWidget(const SizedBox());
      expect(h.item.isObserved, isFalse);
      expect(h.enriched.isObserved, isFalse);
      expect(h.fav.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favourite art overrides catalog with distinct contain and cover sizing',
    (tester) async {
      final h = _Art();
      addTearDown(h.dispose);
      h.item.value = _item('catalog', background: 'catalog');
      h.fav.value = const HomeFavoriteFocus(
        art: 'https://art.invalid/logo',
        title: 'Live',
        subtitle: '',
        fit: BoxFit.contain,
      );
      await tester.pumpWidget(h.host());
      final logo = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(logo.fit, BoxFit.contain);
      expect(logo.memCacheWidth, 480);
      final box = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.widthFactor, .38);
      expect(box.heightFactor, .38);
      h.fav.value = const HomeFavoriteFocus(
        art: 'https://art.invalid/channel',
        title: 'Live',
        subtitle: '',
      );
      await tester.pump();
      final cover = h.current(tester);
      expect(cover.imageUrl, 'https://art.invalid/channel');
      expect(cover.fit, BoxFit.cover);
      expect(cover.alignment, Alignment.topCenter);
      expect(cover.memCacheWidth, 640);
      h.fav.value = const HomeFavoriteFocus(
        art: null,
        title: 'Live',
        subtitle: '',
      );
      await tester.pump();
      expect(h.switcher(tester).child, isA<SizedBox>());
      // The original view retains all three borrowed subscriptions even while a
      // favourite supplies the image; disposal, not the override, releases them.
      expect(h.item.isObserved, isTrue);
      expect(h.enriched.isObserved, isTrue);
      h.fav.value = null;
      await tester.pump();
      expect(h.current(tester).imageUrl, 'https://art.invalid/catalog');
      await tester.pumpWidget(const SizedBox());
      expect(h.fav.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'derived failure falls back to poster and survives view recreation',
    (tester) async {
      final h = _Art();
      addTearDown(h.dispose);
      h.item.value = _item('ttstagefailure', poster: 'poster');
      await tester.pumpWidget(h.host());
      final derived = h.current(tester);
      expect(
        derived.imageUrl,
        'https://images.metahub.space/background/medium/ttstagefailure/img',
      );
      expect(derived.memCacheWidth, 640);
      expect(derived.memCacheHeight, isNull);
      final fallback =
          derived.errorWidget!(
                tester.element(find.byType(HomeStageArt)),
                derived.imageUrl,
                StateError('404'),
              )
              as CachedNetworkImage;
      expect(fallback.imageUrl, 'https://art.invalid/poster');
      expect(fallback.memCacheHeight, 360);
      expect(fallback.fadeInDuration, Duration.zero);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(h.host());
      expect(h.current(tester).imageUrl, 'https://art.invalid/poster');
      expect(h.current(tester).memCacheWidth, isNull);
      expect(h.current(tester).memCacheHeight, 360);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '240ms crossfade expands incoming and outgoing art in a square viewport',
    (tester) async {
      final h = _Art();
      addTearDown(h.dispose);
      h.item.value = _item('one', background: 'one');
      await tester.pumpWidget(h.host());
      h.item.value = _item('two', background: 'two');
      await tester.pump();
      final switcher = h.switcher(tester);
      expect(switcher.duration, const Duration(milliseconds: 240));
      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
      for (final element in find.byType(CachedNetworkImage).evaluate()) {
        expect((element.renderObject as RenderBox).size, const Size(400, 400));
      }
      expect(h.current(tester).fadeInDuration, Duration.zero);
      expect(h.current(tester).fadeOutDuration, Duration.zero);
      await tester.pump(const Duration(milliseconds: 241));
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      h.item.value = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 241));
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HomeStageArt),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

StremioMeta _item(
  String id, {
  String? imdb,
  String? background,
  String? poster,
}) => StremioMeta(
  id: id,
  imdbId: imdb,
  name: id,
  type: 'movie',
  background: background == null ? null : 'https://art.invalid/$background',
  poster: poster == null ? null : 'https://art.invalid/$poster',
);

class _Art {
  final item = ObservedValue<StremioMeta?>(null);
  final enriched = ObservedValue<StremioMeta?>(null);
  final fav = ObservedValue<HomeFavoriteFocus?>(null);
  Widget host() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: HomeStageArt(
            item: item,
            enriched: enriched,
            fav: fav,
            cacheWidth: 640,
            cacheHeight: 360,
          ),
        ),
      ),
    ),
  );
  AnimatedSwitcher switcher(WidgetTester tester) =>
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
  CachedNetworkImage current(WidgetTester tester) =>
      switcher(tester).child! as CachedNetworkImage;
  void dispose() {
    item.dispose();
    enriched.dispose();
    fav.dispose();
  }
}
