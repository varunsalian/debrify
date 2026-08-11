import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/home_sections_filter_page.dart';
import 'package:debrify/services/storage_service.dart';

Future<void> _pumpPage(
  WidgetTester tester, {
  List<HomeExtraRow> extraRows = const [],
  Set<String> disabled = const {},
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
}
