import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/home_sections_filter_page.dart';
import 'package:debrify/services/storage_service.dart';

Future<void> _pumpPage(
  WidgetTester tester, {
  List<HomeExtraRow> extraRows = const [],
  Set<String> disabled = const {},
  List<String> rowOrder = const [],
}) async {
  // The wide (two-pane) header needs more than the 800x600 test default —
  // match a TV/desktop canvas.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeSectionsFilterPage(
        catalogTree: const [],
        disabled: Set.of(disabled),
        extraRows: extraRows,
        rowOrder: rowOrder,
        isTelevision: false,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _saveAndClose(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_rounded));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opt-in leaf toggles persist to the extras store, not the '
      'disabled set', (tester) async {
    await _pumpPage(tester);

    // Trakt group → its Watchlist list leaf (opt-in, default OFF).
    await tester.tap(find.text('Trakt'));
    await tester.pump();
    await tester.tap(find.text('Watchlist'));
    await tester.pump();
    await _saveAndClose(tester);

    final extras = await StorageService.getHomeExtraRows();
    expect(extras.map((r) => r.id), ['traktlist:watchlist']);
    expect(extras.single.title, 'Watchlist');
    // The opt-in toggle must not leak into the disabled-id store.
    expect(await StorageService.getHomeDisabledSections(), isEmpty);
  });

  testWidgets('default-on leaf toggles persist to the disabled set, not the '
      'extras store', (tester) async {
    await _pumpPage(tester);

    // Continue Watching group is selected by default; turn Movies OFF.
    await tester.tap(find.text('Movies').first);
    await tester.pump();
    await _saveAndClose(tester);

    expect(await StorageService.getHomeDisabledSections(), {'cw:movies'});
    expect(await StorageService.getHomeExtraRows(), isEmpty);
  });

  testWidgets('My Watchlist has independent default-on movie and series rows', (
    tester,
  ) async {
    await _pumpPage(tester);

    await tester.tap(find.text('My Watchlist'));
    await tester.pump();
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    await tester.tap(find.text('Movies'));
    await tester.pump();
    await _saveAndClose(tester);

    expect(await StorageService.getHomeDisabledSections(), {
      'watchlist:movies',
    });
  });

  testWidgets('an enabled extra with no loaded backing data survives an '
      'unrelated save as an unavailable leaf', (tester) async {
    const stray = (id: 'traktlist:custom:404', title: 'Vanished List');
    await StorageService.setHomeExtraRows(const [stray]);
    await _pumpPage(tester, extraRows: const [stray]);

    // It must be visible (dimmed leaf under Trakt) so it stays deliberate.
    await tester.tap(find.text('Trakt'));
    await tester.pump();
    expect(find.text('Vanished List'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);

    // Toggle something unrelated and save — the stray must survive verbatim.
    await tester.tap(find.text('Watchlist'));
    await tester.pump();
    await _saveAndClose(tester);

    final extras = await StorageService.getHomeExtraRows();
    expect(extras.map((r) => r.id).toSet(), {
      'traktlist:watchlist',
      'traktlist:custom:404',
    });
    expect(extras.firstWhere((r) => r.id == stray.id).title, 'Vanished List');
  });

  testWidgets('deliberately turning an unavailable leaf off removes it', (
    tester,
  ) async {
    const stray = (id: 'iptvlist:list_9', title: 'Old Sports');
    await StorageService.setHomeExtraRows(const [stray]);
    await _pumpPage(tester, extraRows: const [stray]);

    // Strays with no loaded IPTV lists still get an IPTV Lists group.
    await tester.tap(find.text('IPTV Lists'));
    await tester.pump();
    await tester.tap(find.text('Old Sports'));
    await tester.pump();
    await _saveAndClose(tester);

    expect(await StorageService.getHomeExtraRows(), isEmpty);
  });

  testWidgets('Arrange moves enabled rows globally and persists stable ids', (
    tester,
  ) async {
    await _pumpPage(tester);

    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();
    expect(find.text('Arrange Home Rows'), findsOneWidget);

    // Canonical order starts Movies then Series in local Continue Watching.
    // Move Movies down one global slot using the touch/mouse affordance.
    await tester.tap(find.byIcon(Icons.arrow_downward_rounded).first);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await _saveAndClose(tester);

    final order = await StorageService.getHomeRowOrder();
    expect(order.take(2), ['cw:series', 'cw:movies']);
  });

  testWidgets('Arrange supports dragging a row to a new position', (
    tester,
  ) async {
    await _pumpPage(tester);

    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();
    final handle = find.byIcon(Icons.drag_indicator_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await _saveAndClose(tester);

    expect((await StorageService.getHomeRowOrder()).take(2), [
      'cw:series',
      'cw:movies',
    ]);
  });

  testWidgets('Arrange supports pick-up, DPAD move, and drop', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('Arrange'));
    await tester.pumpAndSettle();
    // Entry focus lands on the first row. OK picks it up; Down changes its
    // order instead of merely changing focus; OK drops it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await _saveAndClose(tester);

    expect((await StorageService.getHomeRowOrder()).take(2), [
      'cw:series',
      'cw:movies',
    ]);
  });
}
