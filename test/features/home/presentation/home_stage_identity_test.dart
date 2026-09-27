import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/presentation/home_stage_identity.dart';
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
    images = await io.Directory.systemTemp.createTemp('home_stage_identity_');
    final file = await io.File('${images.path}/image.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));

  for (final variant in HomeStageIdentityVariant.values) {
    testWidgets(
      '${variant.name} keeps its synopsis reservation during late enrichment',
      (tester) async {
        final h = _Identity();
        addTearDown(h.dispose);
        h.item.value = _item();
        await tester.pumpWidget(h.host(variant: variant));
        final titleBefore = tester.getTopLeft(find.text('Original'));
        final sizeBefore = tester.getSize(find.byType(HomeStageIdentity));
        h.enriched.value = _item(description: 'Late synopsis');
        await tester.pump();
        final hasSynopsis =
            variant == HomeStageIdentityVariant.stage ||
            variant == HomeStageIdentityVariant.narrow;
        expect(
          find.text('Late synopsis'),
          hasSynopsis ? findsOneWidget : findsNothing,
        );
        expect(tester.getTopLeft(find.text('Original')), titleBefore);
        expect(tester.getSize(find.byType(HomeStageIdentity)), sizeBefore);
        if (hasSynopsis) {
          expect(
            tester.widget<Text>(find.text('Late synopsis')).maxLines,
            variant == HomeStageIdentityVariant.narrow ? 4 : 3,
          );
        }
        final title = tester.widget<Text>(find.text('Original'));
        expect(
          title.maxLines,
          variant == HomeStageIdentityVariant.narrow ? 2 : 1,
        );
        expect(
          title.textAlign,
          variant == HomeStageIdentityVariant.centered
              ? TextAlign.center
              : TextAlign.start,
        );
        expect(find.textContaining('Third'), findsNothing);
        expect(
          find.text('Drama · Mystery'),
          (variant == HomeStageIdentityVariant.narrow ||
                  variant == HomeStageIdentityVariant.headline)
              ? findsOneWidget
              : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'metadata matching and provider selection preserve field precedence',
    (tester) async {
      final h = _Identity();
      addTearDown(h.dispose);
      h.item.value = _item();
      h.enriched.value = _item(
        id: 'wrong',
        name: 'Wrong',
        description: 'Wrong description',
        runtime: '200 min',
      );
      await tester.pumpWidget(h.host());
      expect(find.text('Original'), findsOneWidget);
      expect(find.textContaining('100 min'), findsOneWidget);
      expect(find.text('Wrong description'), findsNothing);
      h.enriched.value = _item(
        name: 'Sparse title',
        description: 'Matched',
        runtime: '80 min',
      );
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);
      expect(find.textContaining('80 min'), findsOneWidget);
      expect(find.text('Matched'), findsOneWidget);
      h.item.value = _item(id: 'tmdb:identity', imdb: 'ttidentity');
      h.enriched.value = HeroMetadataPresentation(
        const StremioMeta(id: 'ttidentity', type: 'movie', name: 'Approved'),
        MetadataPreferences(
          providers: {
            MetadataCategory.information: 'tmdb',
            MetadataCategory.backgrounds: 'tmdb',
          },
          fallback: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 221));
      expect(find.text('Approved'), findsOneWidget);
      expect(find.textContaining('100 min'), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('Matched'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logo loading stays blank and failure retains title fallback sizing',
    (tester) async {
      final h = _Identity();
      addTearDown(h.dispose);
      h.item.value = _item(logo: 'https://art.invalid/identity-logo');
      await tester.pumpWidget(
        h.host(variant: HomeStageIdentityVariant.headline),
      );
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      final context = tester.element(find.byType(HomeStageIdentity));
      expect(image.memCacheWidth, 480);
      expect(image.fit, BoxFit.contain);
      expect(image.fadeInDuration, Duration.zero);
      final placeholder =
          image.placeholder!(context, image.imageUrl) as SizedBox;
      expect(placeholder.height, homeStageHeadlineLogoHeight);
      final fallback =
          image.errorWidget!(context, image.imageUrl, StateError('404'))
              as ConstrainedBox;
      expect(fallback.constraints.maxWidth, 400);
      final text = fallback.child! as Text;
      expect(text.data, 'Original');
      expect(text.style!.fontSize, homeStageHeadlineTitleSize);
      expect(text.maxLines, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trailer fades facts for 480ms without fading title and releases subscriptions',
    (tester) async {
      final h = _Identity();
      addTearDown(h.dispose);
      await tester.pumpWidget(h.host());
      expect(h.item.isObserved, isTrue);
      expect(h.enriched.isObserved, isTrue);
      expect(h.showing.isObserved, isFalse);
      h.item.value = _item(description: 'Synopsis');
      await tester.pump();
      expect(h.showing.isObserved, isTrue);
      final facts = tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .child;
      expect(
        find.ancestor(
          of: find.text('Original'),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
      h.showing.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final fadeFinder = find.descendant(
        of: find.byType(AnimatedOpacity),
        matching: find.byType(FadeTransition),
      );
      expect(
        tester.widget<FadeTransition>(fadeFinder).opacity.value,
        closeTo(1 - Curves.easeOut.transform(.5), .00001),
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, 0);
      expect(
        identical(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).child,
          facts,
        ),
        isTrue,
      );
      h.item.value = null;
      await tester.pump();
      expect(h.showing.isObserved, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(h.item.isObserved, isFalse);
      expect(h.enriched.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow identity threshold follows text scaling', (tester) async {
    final heights = <double>[];
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              heights.add(homeStageNarrowIdentityHeight(context));
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(heights, [
      56 + 10 + 23 * 1.3 * 2 + 6 + 10 + 78,
      56 + 10 + 46 * 1.3 * 2 + 6 + 10 + 78,
    ]);
    await tester.pumpWidget(const SizedBox());
  });
}

StremioMeta _item({
  String id = 'a',
  String? imdb,
  String name = 'Original',
  String? description,
  String runtime = '100 min',
  String? logo,
}) => StremioMeta(
  id: id,
  imdbId: imdb,
  type: 'movie',
  name: name,
  description: description,
  runtime: runtime,
  logo: logo,
  year: '2020',
  genres: const ['Drama', 'Mystery', 'Third'],
);

class _Identity {
  final item = ObservedValue<StremioMeta?>(null);
  final enriched = ObservedValue<StremioMeta?>(null);
  final showing = ObservedValue(false);
  Widget host({
    HomeStageIdentityVariant variant = HomeStageIdentityVariant.stage,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          child: HomeStageIdentity(
            item: item,
            enriched: enriched,
            trailerShowing: showing,
            variant: variant,
            maxWidth: 400,
          ),
        ),
      ),
    ),
  );
  void dispose() {
    item.dispose();
    enriched.dispose();
    showing.dispose();
  }
}
