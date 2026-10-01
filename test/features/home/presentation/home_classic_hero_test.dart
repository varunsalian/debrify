import 'dart:convert';
import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/presentation/home_classic_hero.dart';
import 'package:debrify/features/home/presentation/home_hero_spotlight.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../discover/presentation/observed_value.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../fixtures/card_metadata_fixture.dart';
import '../home_mdblist_continuation_screen_test.dart' show FixtureImages;

class HeroHarness {
  final focused = ObservedValue<StremioMeta?>(null);
  final enriched = ObservedValue<StremioMeta?>(null);
  final tint = ObservedValue<Color?>(null);
  final showing = ObservedValue(false);
  final live = ObservedValue(false);
  var configuration = (
    compact: false,
    isTelevision: true,
    artworkCacheWidth: 1000,
    artworkCacheHeight: 600 as int?,
    trailerActive: true,
  );
  var reads = 0;
  final data = CardMetadataFake();

  HeroHarness() {
    data.respond = (item) async => MetadataPresentation(item);
    addTearDown(() {
      focused.dispose();
      enriched.dispose();
      tint.dispose();
      showing.dispose();
      live.dispose();
    });
  }

  Widget host() => ProviderScope(
    overrides: [
      homeCardMetadataRepositoryProvider.overrideWith(
        (ref, epoch) => data.repository(epoch),
      ),
    ],
    child: MaterialApp(
      home: AppThemeScope(
        theme: AppThemes.legacy,
        child: buildHomeClassicHero(
          focused: focused,
          enriched: enriched,
          height: 350,
          readConfiguration: () {
            reads++;
            return configuration;
          },
          tint: tint,
          trailerShowing: showing,
          liveTakeover: live,
        ),
      ),
    ),
  );
}

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('classic_hero_');
    final file = await io.File('${images.path}/poster.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));
  setUp(disableRuntimeFonts);

  testWidgets(
    'empty focus is lazy and subscriptions detach without disposing borrowed signals',
    (tester) async {
      final hero = HeroHarness();
      await tester.pumpWidget(hero.host());
      expect(hero.focused.isObserved, isTrue);
      expect(hero.enriched.isObserved, isFalse);
      expect(hero.reads, 0);
      expect(find.byType(HomeHeroSpotlight), findsNothing);
      hero.enriched.value = const StremioMeta(
        id: 'fixture',
        type: 'movie',
        name: 'Details',
      );
      await tester.pump();
      expect(hero.reads, 0);
      hero.focused.value = const StremioMeta(
        id: 'fixture',
        type: 'movie',
        name: 'Catalog',
      );
      await tester.pump();
      expect(hero.enriched.isObserved, isTrue);
      expect(find.byType(HomeHeroSpotlight), findsOneWidget);
      hero.focused.value = null;
      await tester.pump();
      expect(hero.enriched.isObserved, isFalse);
      expect(find.byType(HomeHeroSpotlight), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(hero.focused.isObserved, isFalse);
      expect(hero.showing.isObserved, isFalse);
      expect(hero.live.isObserved, isFalse);
      hero.focused.value = const StremioMeta(
        id: 'reuse',
        type: 'movie',
        name: 'Reuse',
      );
      await tester.pumpWidget(hero.host());
      expect(find.byType(HomeHeroSpotlight), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late enrichment fills missing metadata and preserves the mounted hero',
    (tester) async {
      final hero = HeroHarness();
      hero.focused.value = const StremioMeta(
        id: 'tt1234567',
        type: 'movie',
        name: 'Catalog',
        background: '',
        description: '',
        logo: '',
      );
      await tester.pumpWidget(hero.host());
      final finder = find.byType(HomeHeroSpotlight);
      final state = tester.state(finder);
      var view = tester.widget<HomeHeroSpotlight>(finder);
      expect(
        view.logo,
        'https://images.metahub.space/logo/medium/tt1234567/img',
      );
      hero.enriched.value = const StremioMeta(
        id: 'tt1234567',
        type: 'movie',
        name: 'Details',
        background: 'https://fixture.invalid/details.jpg',
        description: 'Resolved plot',
        logo: 'https://fixture.invalid/details.png',
        imdbRating: 8.1,
        runtime: '120',
      );
      await tester.pump();
      view = tester.widget<HomeHeroSpotlight>(finder);
      expect(tester.state(finder), same(state));
      expect(view.item, same(hero.focused.value));
      expect(view.background, hero.enriched.value!.background);
      expect(view.description, 'Resolved plot');
      expect(view.rating, 8.1);
      expect(view.runtime, hero.enriched.value!.runtimeDisplay);
      expect(view.logo, hero.enriched.value!.logo);
      hero.focused.value = const StremioMeta(
        id: 'tt1234567',
        type: 'movie',
        name: 'Catalog',
        background: 'https://fixture.invalid/catalog.jpg',
        description: 'Catalog plot',
        logo: 'https://fixture.invalid/catalog.png',
        imdbRating: 0,
        runtime: '90',
      );
      await tester.pump();
      view = tester.widget<HomeHeroSpotlight>(finder);
      expect(view.background, hero.focused.value!.background);
      expect(view.description, 'Catalog plot');
      expect(view.logo, hero.focused.value!.logo);
      expect(view.rating, 0);
      expect(view.runtime, hero.focused.value!.runtimeDisplay);
      expect(tester.state(finder), same(state));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'metadata-only rebuild reads live sizing and trailer configuration',
    (tester) async {
      final hero = HeroHarness();
      hero.focused.value = const StremioMeta(
        id: 'fixture',
        type: 'movie',
        name: 'Catalog',
      );
      await tester.pumpWidget(hero.host());
      final finder = find.byType(HomeHeroSpotlight);
      final state = tester.state(finder);
      var view = tester.widget<HomeHeroSpotlight>(finder);
      expect(view.boxedTrailer, isTrue);
      expect(view.trailerShowing, same(hero.showing));
      expect(view.liveTakeover, same(hero.live));
      expect(view.trailerLoading, isNull);
      hero.configuration = (
        compact: true,
        isTelevision: false,
        artworkCacheWidth: 640,
        artworkCacheHeight: null,
        trailerActive: false,
      );
      hero.enriched.value = const StremioMeta(
        id: 'fixture',
        type: 'movie',
        name: 'Details',
      );
      await tester.pump();
      view = tester.widget<HomeHeroSpotlight>(finder);
      expect(view.compact, isTrue);
      expect(view.isTelevision, isFalse);
      expect(view.artworkCacheWidth, 640);
      expect(view.artworkCacheHeight, isNull);
      expect(view.height, 350);
      expect(view.boxedTrailer, isFalse);
      expect(view.trailerShowing, isNull);
      expect(view.liveTakeover, isNull);
      expect(view.tint, same(hero.tint));
      expect(tester.state(finder), same(state));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
