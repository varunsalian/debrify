import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/see_all/discover_shelf_scope.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrowseService extends MetadataExploreService {
  final pages = <int>[];
  final requests = <({String type, Map<String, String> filters})>[];
  int failures = 0;
  @override
  Future<MetadataBrowseResult> browse({
    required String kind,
    int? id,
    required MetadataPreferences preferences,
    int page = 1,
    String type = 'movie',
    Map<String, String> filters = const {},
  }) async {
    pages.add(page);
    requests.add((type: type, filters: filters));
    if (failures-- > 0) throw Exception('Temporary failure');
    return MetadataBrowseResult(
      List.generate(
        40,
        (i) => StremioMeta(
          id: 'tmdb:${page * 40 + i}',
          type: 'movie',
          name: 'Title $page $i',
        ),
      ),
      hasMore: page < 2,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(
    WidgetTester tester,
    BrowseService service, {
    bool tv = false,
    bool embedded = false,
    bool shelf = false,
    FocusNode? sourceNode,
    ValueChanged<StremioMeta>? onItemFocused,
  }) async {
    Widget page = MetadataBrowsePage(
      title: embedded ? 'TMDB' : 'Person',
      kind: embedded ? 'discover' : 'person',
      id: embedded ? null : 3,
      preferences: MetadataPreferences(),
      onOpen: (_) {},
      service: service,
      isTelevision: tv,
      embedded: embedded,
      leading: embedded
          ? StremioDropdown<String>(
              label: 'Source',
              value: 'tmdb',
              isTelevision: tv,
              quiet: tv,
              focusNode: sourceNode,
              options: const [StremioDropdownOption('tmdb', 'TMDB')],
              onSelected: (_) {},
            )
          : null,
      leadingNode: sourceNode,
      onItemFocused: onItemFocused,
    );
    if (shelf) {
      page = DiscoverShelfScope(
        metrics: const DiscoverShelfMetrics(cardHeight: 200, hPad: 24),
        child: page,
      );
    }
    await tester.pumpWidget(
      MaterialApp(home: embedded ? Scaffold(body: page) : page),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('touch scrolling appends the next page once', (tester) async {
    final service = BrowseService();
    await open(tester, service);
    expect(service.pages, [1]);
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(service.pages, [1, 2]);
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(service.pages, [1, 2]);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('embedded discovery filters reload in place and paginate', (
    tester,
  ) async {
    final service = BrowseService();
    await open(tester, service, embedded: true);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(SeeAllPosterGrid), findsOneWidget);
    expect(service.requests.last.type, 'movie');

    Future<void> select(String label, String option) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              (w is StremioDropdown<String> && w.label == label) ||
              (w is StremioDropdown<bool> && w.label == label),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await select('Type', 'TV shows');
    await select('Runtime', 'Under two hours');
    await select('Language', 'Hindi');
    expect(service.requests.last.type, 'tv');
    expect(service.requests.last.filters, {
      'with_runtime.lte': '120',
      'with_original_language': 'hi',
    });
    expect(service.pages, [1, 1, 1, 1]);
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SeeAllPosterGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(service.pages, [1, 1, 1, 1, 2]);
    expect(service.requests.last.filters['with_original_language'], 'hi');
    expect(tester.takeException(), isNull);
  });

  for (final shelf in [false, true]) {
    testWidgets(
      'embedded TV focus connects source, filters, posters and sidebar (shelf=$shelf)',
      (tester) async {
        final source = FocusNode();
        addTearDown(source.dispose);
        var sidebar = 0;
        MainPageBridge.focusTvSidebar = () => sidebar++;
        addTearDown(() => MainPageBridge.focusTvSidebar = null);
        StremioMeta? focused;
        await open(
          tester,
          BrowseService(),
          tv: true,
          embedded: true,
          shelf: shelf,
          sourceNode: source,
          onItemFocused: (item) => focused = item,
        );
        source.requestFocus();
        await tester.pumpAndSettle();
        for (final label in ['Type', 'Runtime', 'Language']) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'tmdb_${label.toLowerCase()}',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'seeall_grid_0');
        expect(focused?.id, 'tmdb:40');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(source.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        expect(sidebar, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('embedded TV can reach retry after an initial failure', (
    tester,
  ) async {
    final source = FocusNode();
    addTearDown(source.dispose);
    final service = BrowseService()..failures = 3;
    await open(tester, service, tv: true, embedded: true, sourceNode: source);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    source.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tmdb_retry');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(source.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SeeAllPosterGrid), findsOneWidget);
    expect(source.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV Retry returns to posters when the first grid row is unmounted',
    (tester) async {
      final service = BrowseService();
      await open(tester, service, tv: true, embedded: true);
      final firstNode = tester
          .widget<CatalogItemTile>(find.byType(CatalogItemTile).first)
          .focusNode!;
      final grid = find.byType(SeeAllPosterGrid);
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: grid, matching: find.byType(Scrollable)).first,
          )
          .position;
      service.failures = 3;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(service.pages, [1, 2, 2, 2]);
      expect(firstNode.context?.mounted ?? false, isFalse);
      expect(find.text('Could not load titles. Retry'), findsOneWidget);

      final lastNode = tester
          .widget<CatalogItemTile>(find.byType(CatalogItemTile).last)
          .focusNode!;
      lastNode.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tmdb_retry');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(firstNode.hasFocus, isTrue);
      expect(firstNode.context?.mounted, isTrue);
      expect(scroll.pixels, 0);
      expect(
        tester
            .getRect(find.byType(CatalogItemTile).first)
            .overlaps(tester.getRect(grid)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small phones keep Source visible and put TMDB filters in a sheet',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = BrowseService();
      await open(tester, service, embedded: true);
      expect(find.text('TMDB'), findsOneWidget);
      expect(find.text('Movies'), findsNothing);
      final grid = find.byType(SeeAllPosterGrid);
      expect(tester.getSize(grid).height, greaterThan(300));
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TV shows').last);
      await tester.pumpAndSettle();
      expect(service.requests.last.type, 'tv');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('DPAD tile focus near the end appends without dropping focus', (
    tester,
  ) async {
    final service = BrowseService();
    await open(tester, service, tv: true);
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    // Build the final rows without dispatching a scroll update to the pager.
    scroll.jumpTo(scroll.maxScrollExtent - scroll.viewportDimension - 100);
    await tester.pumpAndSettle();
    final tiles = tester
        .widgetList<CatalogItemTile>(find.byType(CatalogItemTile))
        .toList();
    final tile = tiles.last;
    tile.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(service.pages, [1, 2]);
    expect(tile.focusNode!.hasFocus, isTrue);
  });

  testWidgets('temporary failure retries the same page automatically', (
    tester,
  ) async {
    final service = BrowseService()..failures = 1;
    await open(tester, service);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.pages, [1, 1]);
    expect(find.text('Could not load titles. Retry'), findsNothing);
    expect(find.byType(CatalogItemTile), findsWidgets);
  });

  testWidgets('retries stop after two and are cancelled on disposal', (
    tester,
  ) async {
    final service = BrowseService()..failures = 10;
    await open(tester, service);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(service.pages, [1, 1, 1]);
    expect(find.text('Could not load titles. Retry'), findsOneWidget);
    await tester.tap(find.text('Could not load titles. Retry'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(service.pages, [1, 1, 1, 1]);
    expect(tester.takeException(), isNull);
  });
}
