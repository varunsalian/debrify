import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/see_all/discover_detail_rail.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';
import 'package:debrify/widgets/movie_watched_badge.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:debrify/widgets/see_all/discover_shelf_scope.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';

/// The Discover STAGE shelf: [SeeAllPosterGrid] laying its items out as one
/// bottom row instead of a wall, and the DPAD contract that goes with it.
///
/// The TV canvas these run at (960×540 logical) is the real one — the layout
/// maths here have to survive it, since that is where the identity block's
/// clearance is derived from the shelf's own height.
void main() {
  const tvSize = Size(960, 540);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<StremioMeta> items(int n) => [
    for (var i = 0; i < n; i++)
      StremioMeta(id: 'tt$i', imdbId: 'tt$i', type: 'movie', name: 'Title $i'),
  ];

  Widget harness(
    Widget child, {
    DiscoverShelfMetrics? shelf,
    Size size = tvSize,
  }) {
    final body = shelf == null
        ? child
        : DiscoverShelfScope(metrics: shelf, child: child);
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Material(
                color: const Color(0xFF000000),
                child: SizedBox.fromSize(size: size, child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SeeAllPosterGrid grid(
    List<StremioMeta> data, {
    VoidCallback? onExitTop,
    VoidCallback? onExitLeft,
    VoidCallback? onLoadMore,
    bool exhausted = true,
  }) => SeeAllPosterGrid(
    items: data,
    isTelevision: true,
    loadingMore: false,
    exhausted: exhausted,
    onOpen: (_) {},
    onLoadMore: onLoadMore ?? () {},
    onExitTop: onExitTop,
    onExitLeft: onExitLeft,
    showTypeBadge: false,
    showRatingBadge: false,
  );

  /// The metrics the Discover host publishes on a 540-high canvas.
  const shelf = DiscoverShelfMetrics(cardHeight: 162, hPad: 24);

  /// A DPAD press, then enough frames for the shelf's scroll GLIDE (140ms on
  /// TV) and the card's focus rise to finish. Pumping a single frame would
  /// leave the animated scroll parked where it started — the shelf would look
  /// like it never moved.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pump(); // deliver the key + queue the post-frame reveal
    await tester.pump(const Duration(milliseconds: 200)); // let it glide
  }

  testWidgets('lays out ONE row on the TV canvas, inside its bounds', (
    tester,
  ) async {
    // The real Android TV surface — the default 800×600 test view would
    // measure a canvas this layout never runs on.
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(grid(items(30)), shelf: shelf));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final tiles = find.byType(CatalogItemTile);
    expect(tiles, findsWidgets);
    final boxes = [
      for (final e in tiles.evaluate()) tester.getRect(find.byWidget(e.widget)),
    ];
    // One row: every mounted poster shares a top edge...
    final top = boxes.first.top;
    for (final b in boxes) {
      expect(b.top, closeTo(top, 0.5));
    }
    // ...and the row sits inside the canvas, clearing the tail.
    expect(
      boxes.first.bottom,
      closeTo(tvSize.height - DiscoverShelfMetrics.tail - 10, 0.5),
      reason: 'card centred in the slack, above the tail',
    );
    expect(
      boxes.first.height,
      closeTo(shelf.cardHeight, 0.5),
      reason: 'the host reserves clearance from exactly this height',
    );
  });

  testWidgets('shelf: RIGHT and LEFT walk the row, LEFT at the head exits', (
    tester,
  ) async {
    var exitedLeft = 0;
    await tester.pumpWidget(
      harness(grid(items(8), onExitLeft: () => exitedLeft++), shelf: shelf),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final state = tester.state<SeeAllPosterGridState>(
      find.byType(SeeAllPosterGrid),
    );
    state.focusFirst();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    // Two right, one left → sitting on item 1; LEFT again → item 0; once more
    // → the sidebar, not a wrap-around.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(exitedLeft, 0, reason: 'still inside the row');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(exitedLeft, 1);
  });

  testWidgets('shelf: UP leaves for the filter line, DOWN is swallowed', (
    tester,
  ) async {
    var exitedTop = 0;
    await tester.pumpWidget(
      harness(grid(items(6), onExitTop: () => exitedTop++), shelf: shelf),
    );
    await tester.pump();

    tester
        .state<SeeAllPosterGridState>(find.byType(SeeAllPosterGrid))
        .focusFirst();
    await tester.pump();

    final onFirst = FocusManager.instance.primaryFocus;
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(exitedTop, 0);
    // Swallowed, not ignored: DOWN must not bubble out to whatever the app
    // shell has below the shelf, so the ring stays exactly where it was.
    expect(FocusManager.instance.primaryFocus, same(onFirst));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(exitedTop, 1);
  });

  testWidgets('shelf: stepping toward the tail asks for the next page', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      harness(
        grid(items(6), onLoadMore: () => loads++, exhausted: false),
        shelf: shelf,
      ),
    );
    await tester.pump();
    loads = 0; // the auto-fill probe may have fired one already

    tester
        .state<SeeAllPosterGridState>(find.byType(SeeAllPosterGrid))
        .focusFirst();
    await tester.pump();

    // 0 → 1 → 2: still runway ahead of a 6-item row (prefetch starts at 3).
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(loads, 0);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(loads, greaterThan(0));
  });

  testWidgets('shelf cards wear the board\'s focus grammar', (tester) async {
    // The stage sits beside the Home board, so its posters must rise, fade
    // and glide like the board's — not like the grid's gold-rim tiles.
    await tester.pumpWidget(harness(grid(items(6)), shelf: shelf));
    await tester.pump();
    final shelfTiles = tester.widgetList<CatalogItemTile>(
      find.byType(CatalogItemTile),
    );
    expect(shelfTiles, isNotEmpty);
    expect(shelfTiles.every((t) => t.boardChrome), isTrue);
    expect(find.byType(CardFocusRise), findsWidgets);
  });

  testWidgets('narrow shelf posters stack enabled badges without overlap', (
    tester,
  ) async {
    const rated = StremioMeta(
      id: 'rated-stage-card',
      imdbId: 'rated-stage-card',
      type: 'movie',
      name: 'Rated stage card',
      imdbRating: 8.2,
    );
    Future<void> verify(DiscoverShelfMetrics metrics, Size size) async {
      await tester.pumpWidget(
        harness(
          SeeAllPosterGrid(
            items: const [rated],
            isTelevision: true,
            loadingMore: false,
            exhausted: true,
            onOpen: (_) {},
            onLoadMore: () {},
          ),
          shelf: metrics,
          size: size,
        ),
      );
      await tester.pump();

      final tile = tester.widget<CatalogItemTile>(find.byType(CatalogItemTile));
      expect(tile.compactBadgeLayout, isTrue);
      expect(
        tester.getSize(find.byType(CatalogItemTile)).width,
        closeTo(metrics.cardWidth, 0.01),
      );

      final typeRect = tester.getRect(find.text('MOVIE'));
      final ratingRect = tester.getRect(find.text('8.2'));
      expect(typeRect.overlaps(ratingRect), isFalse);
      expect(ratingRect.top, greaterThanOrEqualTo(typeRect.bottom));

      final watched = tester.widget<MovieWatchedBadge>(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-compact-badges')),
          matching: find.byType(MovieWatchedBadge),
        ),
      );
      expect(watched.compact, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await verify(shelf, tvSize);
    await verify(
      const DiscoverShelfMetrics(cardHeight: 140, hPad: 24),
      const Size(960, 420),
    );
  });

  testWidgets('the wall keeps its own chrome', (tester) async {
    await tester.pumpWidget(harness(grid(items(6))));
    await tester.pump();
    final wallTiles = tester.widgetList<CatalogItemTile>(
      find.byType(CatalogItemTile),
    );
    expect(wallTiles, isNotEmpty);
    expect(wallTiles.any((t) => t.boardChrome), isFalse);
    expect(find.byType(CardFocusRise), findsNothing);
  });

  testWidgets('narrow two-pane wall cards use the same safe badge stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SeeAllPosterGrid(
          items: const [
            StremioMeta(
              id: 'rated-wall-card',
              type: 'series',
              name: 'Rated wall card',
              imdbRating: 7.9,
            ),
          ],
          isTelevision: true,
          loadingMore: false,
          exhausted: true,
          onOpen: (_) {},
          onLoadMore: () {},
        ),
        size: const Size(565, 540),
      ),
    );
    await tester.pump();

    final tile = tester.widget<CatalogItemTile>(find.byType(CatalogItemTile));
    expect(tile.compactBadgeLayout, isTrue);
    expect(
      tester.getRect(find.text('SERIES')).overlaps(
        tester.getRect(find.text('7.9')),
      ),
      isFalse,
    );
  });

  testWidgets('Discover card settings govern both poster badges', (
    tester,
  ) async {
    Widget scopedGrid({required bool tags, required bool ratings}) =>
        DiscoverCardSettingsScope(
          showTypeTags: tags,
          showRatings: ratings,
          child: SeeAllPosterGrid(
            items: [
              const StremioMeta(
                id: 'rated',
                type: 'movie',
                name: 'Rated movie',
                imdbRating: 8.2,
              ),
            ],
            isTelevision: true,
            loadingMore: false,
            exhausted: true,
            onOpen: (_) {},
            onLoadMore: () {},
          ),
        );

    await tester.pumpWidget(
      harness(scopedGrid(tags: false, ratings: false), shelf: shelf),
    );
    await tester.pump();
    var tile = tester.widget<CatalogItemTile>(find.byType(CatalogItemTile));
    expect(tile.showTypeBadge, isFalse);
    expect(tile.showRatingBadge, isFalse);

    // The harness uses Overlay.initialEntries, which are only consumed on the
    // Overlay's first mount. Remount it before changing the inherited values.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(harness(scopedGrid(tags: true, ratings: true)));
    await tester.pump();
    tile = tester.widget<CatalogItemTile>(find.byType(CatalogItemTile));
    expect(tile.showTypeBadge, isTrue);
    expect(tile.showRatingBadge, isTrue);
  });

  testWidgets('no scope → the poster wall, unchanged', (tester) async {
    await tester.pumpWidget(harness(grid(items(12))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('re-entry from the filter line lands on the card you left', (
    tester,
  ) async {
    // The defect this pins: UP exits the shelf from ANY index without
    // rewinding the row, so item 0 is long unbuilt by then — focusing it is a
    // silent no-op and DOWN from the filter bar does nothing at all.
    tester.view.physicalSize = tvSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A stand-in for the filter line, so UP actually hands focus away the way
    // the real See-All screens do (they answer onExitTop by focusing a filter
    // dropdown, and answer DOWN with focusFirst()).
    final filter = FocusNode(debugLabel: 'filter');
    addTearDown(filter.dispose);
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            Focus(focusNode: filter, child: const SizedBox(height: 40)),
            Expanded(child: grid(items(60), onExitTop: filter.requestFocus)),
          ],
        ),
        shelf: shelf,
      ),
    );
    await tester.pump();

    final state = tester.state<SeeAllPosterGridState>(
      find.byType(SeeAllPosterGrid),
    );
    state.focusFirst();
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    // Item 0 really is gone from the tree by now — otherwise this test proves
    // nothing.
    expect(
      find.text('Title 0'),
      findsNothing,
      reason: 'the head must have scrolled out for this to be the real case',
    );
    final onCard = FocusManager.instance.primaryFocus;

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(filter.hasPrimaryFocus, isTrue);

    // ...and DOWN comes back to a real, mounted card.
    state.focusFirst();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(onCard));
  });

  test('the identity block clears exactly what the shelf occupies', () {
    const m = DiscoverShelfMetrics(cardHeight: 162, hPad: 24);
    expect(m.cardWidth, closeTo(108, 0.01));
    // Literals, not the getters' own formulae: the host reserves the identity
    // block's clearance from these numbers, so a change to them has to break
    // something rather than move both sides of an equation at once.
    expect(m.boxHeight, 182);
    expect(m.columnHeight, 226);
  });

  test('the shortest canvas the stage runs at still fits the identity', () {
    // The host's own maths at the 420-high guard floor: card = (H * 0.30)
    // clamped to 140..200, identity gets what's left between the filter band
    // and the shelf column.
    const filterBand = 62.0; // _kDiscStageFilterBand
    const identityGap = 22.0; // _kDiscStageIdentityGap
    const metaOnly = 116.0; // _StageContent._metaHeight — the last rung
    final cardHeight = (420 * 0.30).clamp(140.0, 200.0);
    final m = DiscoverShelfMetrics(cardHeight: cardHeight, hPad: 24);
    final free = 420 - filterBand - (m.columnHeight + identityGap);
    expect(
      free,
      greaterThanOrEqualTo(metaOnly),
      reason: 'title art + meta line must survive the shortest stage canvas',
    );
  });

  group('stage identity settle', () {
    /// A title complete enough that the rail never fetches: no imdbId (so no
    /// enrichment and no metahub logo either, which makes the name render as
    /// TEXT and therefore findable).
    StremioMeta full(String name) => StremioMeta(
      id: name.toLowerCase(),
      type: 'movie',
      name: name,
      description: '$name synopsis.',
      background: 'https://example.invalid/$name.jpg',
      year: '2024',
      runtime: '120 min',
      imdbRating: 8.0,
      genres: const ['Drama'],
    );

    Widget rail(
      StremioMeta? item,
      Duration settle,
      ValueNotifier<StremioMeta?> shown,
    ) => MediaQuery(
      data: const MediaQueryData(size: tvSize),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: DiscoverDetailRail(
            item: item,
            layout: DiscoverDetailLayout.stage,
            settleDelay: settle,
            stageBudget: 240,
            trailerStreams: ValueNotifier(null),
            trailerLoading: ValueNotifier(false),
            trailerVolume: ValueNotifier(0),
            trailerMeta: ValueNotifier(null),
            shownItem: shown,
          ),
        ),
      ),
    );

    testWidgets('the settled swap actually repaints', (tester) async {
      // The defect this pins: the settle runs from a Timer, outside any build.
      // _applyAdopt assigns its shown item directly — on the assumption that a
      // build always follows — so without an explicit setState the identity
      // block kept painting the PREVIOUS title indefinitely, one step behind
      // the focus ring, and never published the new one to the backdrop.
      final shown = ValueNotifier<StremioMeta?>(null);
      addTearDown(shown.dispose);
      const settle = Duration(milliseconds: 260);

      await tester.pumpWidget(rail(full('Alpha'), settle, shown));
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);

      await tester.pumpWidget(rail(full('Bravo'), settle, shown));
      await tester.pump();
      // Still the old title — that part is the point of a settle.
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Bravo'), findsOneWidget);
      expect(shown.value?.name, 'Bravo');
      // Alpha is still on screen for a moment — the identity block crossfades
      // titles, like the board's. Once that lands it is gone.
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('no settle (the two-pane rail) swaps on the focus change', (
      tester,
    ) async {
      final shown = ValueNotifier<StremioMeta?>(null);
      addTearDown(shown.dispose);

      await tester.pumpWidget(rail(full('Alpha'), Duration.zero, shown));
      await tester.pump();
      await tester.pumpWidget(rail(full('Bravo'), Duration.zero, shown));
      await tester.pump();
      expect(find.text('Bravo'), findsOneWidget);
      expect(shown.value?.name, 'Bravo');
    });
  });
}
