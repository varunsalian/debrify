import 'package:debrify/features/home/presentation/home_tonight_card_caption.dart';
import 'package:debrify/features/home/presentation/home_favorite_focus.dart';
import 'package:debrify/features/home/models/home_tonight_card_info.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/hero_metadata_presentation.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  testWidgets(
    'favourite focus takes precedence and releases catalog subscriptions',
    (tester) async {
      final h = _Caption();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Catalog');
      h.info.value = const HomeTonightCardInfo(
        action: 'Open',
        holdAction: 'Options',
        progress: .5,
      );
      await tester.pumpWidget(h.host());
      expect(h.item.isObserved, isTrue);
      expect(find.text('HOLD  Options'), findsOneWidget);
      h.fav.value = const HomeFavoriteFocus(
        art: null,
        title: 'Channel',
        subtitle: 'Live now',
      );
      await tester.pump();
      expect(find.text('Channel'), findsOneWidget);
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('OK  Watch'), findsOneWidget);
      expect(find.text('Catalog'), findsNothing);
      expect(find.text('HOLD  Options'), findsNothing);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(h.item.isObserved, isFalse);
      expect(h.enriched.isObserved, isFalse);
      expect(h.info.isObserved, isFalse);
      h.fav.value = null;
      await tester.pump();
      expect(find.text('Catalog'), findsOneWidget);
      expect(h.item.isObserved, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(h.fav.isObserved, isFalse);
      expect(h.item.isObserved, isFalse);
      expect(h.enriched.isObserved, isFalse);
      expect(h.info.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale enrichment cannot change episode or remaining-time display',
    (tester) async {
      final h = _Caption();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(
        id: 'a',
        type: 'series',
        name: 'Catalog',
        runtime: '100 min',
      );
      h.enriched.value = const StremioMeta(
        id: 'b',
        type: 'series',
        name: 'Wrong',
        runtime: '200 min',
      );
      h.info.value = const HomeTonightCardInfo(
        action: 'Open',
        holdAction: 'Options',
        episode: 'S2 · E5',
        progress: .5,
      );
      await tester.pumpWidget(h.host());
      expect(find.text('S2 · E5  ·  50 min left'), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        .5,
      );
      h.enriched.value = const StremioMeta(
        id: 'a',
        type: 'series',
        name: 'Details',
        runtime: '80 min',
      );
      await tester.pump();
      expect(find.text('S2 · E5  ·  40 min left'), findsOneWidget);
      expect(find.text('Catalog'), findsOneWidget);
      h.info.value = null;
      await tester.pump();
      expect(find.text('80 min  ·  SERIES'), findsOneWidget);
      expect(find.text('OK  Open'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canonical provider policy suppresses unapproved logo fallback and honors title',
    (tester) async {
      final h = _Caption();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(
        id: 'tmdb:1',
        imdbId: 'tt1',
        type: 'movie',
        name: 'Original',
        runtime: '90 min',
        logo: 'catalog-logo',
      );
      h.enriched.value = HeroMetadataPresentation(
        const StremioMeta(id: 'tt1', type: 'movie', name: 'Approved'),
        MetadataPreferences(
          providers: {
            MetadataCategory.backgrounds: 'tmdb',
            MetadataCategory.information: 'tmdb',
          },
          fallback: false,
        ),
      );
      await tester.pumpWidget(h.host());
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('MOVIE'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.textContaining('90 min'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty item hides the caption and progress is clamped when it returns',
    (tester) async {
      final h = _Caption();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.host());
      expect(find.text('OK  Open'), findsNothing);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Movie');
      h.info.value = const HomeTonightCardInfo(action: 'Open', progress: 1.5);
      await tester.pump();
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor,
        1,
      );
      h.info.value = const HomeTonightCardInfo(action: 'Open', progress: -.5);
      await tester.pump();
      expect(find.byType(FractionallySizedBox), findsNothing);
      h.item.value = null;
      await tester.pump();
      expect(find.text('Movie'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Caption {
  final item = ObservedValue<StremioMeta?>(null);
  final enriched = ObservedValue<StremioMeta?>(null);
  final fav = ObservedValue<HomeFavoriteFocus?>(null);
  final info = ObservedValue<HomeTonightCardInfo?>(null);
  Widget host() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 560,
          child: HomeTonightCardCaption(
            item: item,
            enriched: enriched,
            fav: fav,
            info: info,
          ),
        ),
      ),
    ),
  );
  void dispose() {
    item.dispose();
    enriched.dispose();
    fav.dispose();
    info.dispose();
  }
}
