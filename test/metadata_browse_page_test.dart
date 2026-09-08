import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrowseService extends MetadataExploreService {
  final pages = <int>[];
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MetadataBrowsePage(
          title: 'Person',
          kind: 'person',
          id: 3,
          preferences: MetadataPreferences(),
          onOpen: (_) {},
          service: service,
          isTelevision: tv,
        ),
      ),
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
