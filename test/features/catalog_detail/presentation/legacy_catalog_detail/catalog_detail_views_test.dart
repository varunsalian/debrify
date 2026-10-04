import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../../support/catalog_detail_metadata_responses.dart';
import 'package:debrify/widgets/shimmer.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/catalog_detail_fixture.dart';
import '../../../../support/catalog_detail_goldens.dart';
import 'package:debrify/theme/artwork_accent.dart';

void main() {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = CatalogDetailGoldenComparator(
      comparator.basedir.resolve('catalog_detail_views_test.dart'),
    );
  }
  for (final c in [
    (
      name: 'tv_movie_wide',
      size: const Size(1200, 900),
      type: 'movie',
      tv: true,
      resume: false,
    ),
    (
      name: 'phone_movie_narrow',
      size: const Size(430, 900),
      type: 'movie',
      tv: false,
      resume: false,
    ),
    (
      name: 'desktop_series_wide',
      size: const Size(1200, 900),
      type: 'series',
      tv: false,
      resume: false,
    ),
    (
      name: 'tv_series_resume',
      size: const Size(1200, 900),
      type: 'series',
      tv: true,
      resume: true,
    ),
  ]) {
    testWidgets('R reachable pixel golden ${c.name}', (t) async {
      await catalogDetailCase(t, (f) async {
        f.television = c.tv;
        f.item = f.meta(
          id: 'golden-${c.name}',
          type: c.type,
          background: 'https://catalog-fixture.invalid/${c.name}.png',
          poster: '',
        );
        f.resume = (
          started: c.resume,
          season: c.resume ? 3 : null,
          episode: c.resume ? 4 : null,
        );
        await f.mount(t, size: c.size, wait: false);
        // Decode waiting advances no fake-clock time. The next zero-duration
        // frame starts the asynchronous Image.network opacity fade.
        await f.until(
          t,
          () =>
              t
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((w) => w.image != null) &&
              find.byType(Shimmer).evaluate().isEmpty,
        );
        await t.pump();
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        for (final w in t.widgetList<AnimatedBuilder>(
          find.byType(AnimatedBuilder),
        )) {
          if (w.animation is AnimationController &&
              (w.animation as AnimationController).duration ==
                  const Duration(milliseconds: 1100)) {
            expect((w.animation as AnimationController).value, 1);
          }
        }
        expect(find.byType(Shimmer), findsNothing);
        expect(
          t.widget<ArtworkAccentScope>(find.byType(ArtworkAccentScope)).accent,
          isNull,
        );
        if (!c.tv) {
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump();
        } else {
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail-play');
        }
        expect(
          find.text(
            c.resume
                ? 'Resume · S3E4'
                : c.type == 'series'
                ? 'Start Watching'
                : 'Play',
          ),
          findsOneWidget,
        );
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path = 'test/goldens/catalog_detail/$platform/${c.name}.png';
        expect(
          File(path).existsSync() || autoUpdateGoldenFiles,
          true,
          reason: 'Missing original golden $path',
        );
        await expectLater(
          find.byKey(const ValueKey('catalog-canvas')),
          matchesGoldenFile(
            '../../../../goldens/catalog_detail/$platform/${c.name}.png',
          ),
        );
      });
    });
  }
  testWidgets('R reachable pixel golden tv_movie_rich', (t) async {
    await catalogDetailCase(t, (f) async {
      f.item = f.meta(
        name: 'Rich Original Catalog',
        background: 'https://catalog-fixture.invalid/rich-backdrop.png',
        poster: '',
      );
      f.recommendations = [
        f.meta(id: 'rich-rec-one', name: 'Rich Recommendation One', poster: ''),
        f.meta(id: 'rich-rec-two', name: 'Rich Recommendation Two', poster: ''),
      ];
      f.traktOptions = buildTraktAddOnlyMenuOptions(
        isMovie: true,
        isSeries: false,
      ).take(2).toList();
      f.onRequest = (r) async => catalogParentsRequest(r)
          ? catalogParentsResponse()
          : catalogImdbRequest(r)
          ? catalogRichImdbResponse()
          : http.Response('{}', 404);
      await f.mount(t, size: const Size(1600, 1500), wait: false);
      await f.until(
        t,
        () =>
            t
                .widgetList<RawImage>(find.byType(RawImage))
                .any((w) => w.image != null) &&
            find.byType(Shimmer).evaluate().isEmpty &&
            find.text('Rich Actor').evaluate().isNotEmpty &&
            find.text('Sex & Nudity').evaluate().isNotEmpty &&
            find.text('Rich Recommendation One').evaluate().isNotEmpty,
      );
      await t.pump();
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Shimmer), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail-play');
      expect(find.text('PG-13'), findsOneWidget);
      expect(find.text('87'), findsOneWidget);
      for (final marker in [
        'Rich Actor',
        'Sex & Nudity',
        'Rich Recommendation One',
        f.traktOptions.first.caption,
      ]) {
        expect(find.text(marker), findsWidgets);
        expect(
          t
              .getRect(find.text(marker).first)
              .overlaps(const Rect.fromLTWH(0, 0, 1600, 1500)),
          true,
          reason:
              'Rich fixture section must be in the captured viewport: $marker',
        );
      }
      expect(f.requests.where(catalogImdbRequest), hasLength(1));
      expect(f.requests.where(catalogParentsRequest), hasLength(1));
      final platform = Platform.isLinux ? 'linux' : 'macos';
      final path = 'test/goldens/catalog_detail/$platform/tv_movie_rich.png';
      expect(
        File(path).existsSync() || autoUpdateGoldenFiles,
        true,
        reason: 'Missing original golden $path',
      );
      await expectLater(
        find.byKey(const ValueKey('catalog-canvas')),
        matchesGoldenFile(
          '../../../../goldens/catalog_detail/$platform/tv_movie_rich.png',
        ),
      );
    });
  });
  testWidgets(
    'R tight desktop layout keeps title actions and completed reveal',
    (t) async {
      await catalogDetailCase(t, (f) async {
        f.television = false;
        await f.mount(t, size: const Size(1200, 580));
        expect(find.text('Original Catalog'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Sources'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    },
  );
  for (final quick in [false, true]) {
    testWidgets(
      'R TV autofocus ${quick ? 'Play' : 'Sources'} and directional traversal',
      (t) async {
        await catalogDetailCase(t, (f) async {
          f.quick = quick;
          await f.mount(t);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            quick ? 'detail-play' : 'detail-browse',
          );
          if (quick) {
            await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await t.pump();
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'detail-browse',
            );
          }
          f.calls.clear();
          await t.sendKeyEvent(LogicalKeyboardKey.select);
          await t.pump();
          expect(f.calls, ['browse']);
        });
      },
    );
  }
  testWidgets('R O TV quick action traversal Select keeps exact host action', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.traktOptions = buildTraktAddOnlyMenuOptions(
        isMovie: true,
        isSeries: false,
      ).take(2).toList();
      await f.mount(t);
      final first = find.text(f.traktOptions.first.caption);
      await t.ensureVisible(first);
      await t.pump();
      Focus.of(t.element(first)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(f.traktActions, [f.traktOptions[1].action]);
    });
  });
  testWidgets('R TV held Select opens sources without Play', (t) async {
    await catalogDetailCase(t, (f) async {
      await f.mount(t);
      f.calls.clear();
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 900));
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(f.calls, ['browse']);
    });
  });
  testWidgets('R TV Read more Select and UP returns wide scroll to top', (
    t,
  ) async {
    await catalogDetailCase(t, (f) async {
      f.item = f.meta(
        description: List.filled(50, 'Long original synopsis.').join(' '),
      );
      await f.mount(t);
      final more = find.text('Read more');
      expect(more, findsOneWidget);
      await t.ensureVisible(more);
      await t.pump();
      Focus.of(t.element(more)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(find.text('Show less'), findsOneWidget);
      final scroll = t
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere((w) => w.controller != null)
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await t.pump();
      expect(scroll.offset, greaterThan(0));
      final play = t.widget<Focus>(
        find
            .ancestor(of: find.text('Play'), matching: find.byType(Focus))
            .first,
      );
      play.focusNode!.requestFocus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail-play');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      await t.pump(const Duration(milliseconds: 280));
      await t.pump();
      expect(scroll.offset, 0);
    });
  });
}
