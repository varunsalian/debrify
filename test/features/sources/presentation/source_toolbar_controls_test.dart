import 'package:debrify/features/sources/presentation/source_toolbar_controls.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FocusNode filter;
  late List<Object?> events;
  late List<int> seasons;
  late int menuReads;
  setUp(() {
    filter = FocusNode();
    events = [];
    seasons = [1, 2];
    menuReads = 0;
  });
  tearDown(() => filter.dispose());

  Future<void> mount(
    WidgetTester tester, {
    String sort = 'source',
    bool showSeason = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: filter,
              builder: (_, _) => SourceToolbarControls(
                showSeason: showSeason,
                selectedSeason: null,
                seasonMenuNumbers: () {
                  menuReads++;
                  return seasons;
                },
                sortBy: sort,
                sortAsc: false,
                filtersActive: false,
                filterFocus: filter,
                onSelectSeason: events.add,
                onSelectSort: events.add,
                onToggleDirection: () => events.add('direction'),
                onOpenFilters: () => events.add('filter'),
                onFilterDown: () => events.add('down'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('season options are read on opening; all maps to null', (
    tester,
  ) async {
    await mount(tester);
    expect(menuReads, 0);
    seasons = [7];
    await tester.tap(find.byTooltip('Season'));
    await tester.pumpAndSettle();
    expect(menuReads, 1);
    expect(find.text('Season 7'), findsOneWidget);
    expect(find.text('Season 1'), findsNothing);
    await tester.tap(find.text('Season 7'));
    await tester.pumpAndSettle();
    expect(events, [7]);
    await tester.tap(find.byTooltip('Season'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Seasons'));
    await tester.pumpAndSettle();
    expect(events, [7, null]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'sort menu dispatches selection and explicit sort exposes direction',
    (tester) async {
      await mount(tester, showSeason: false);
      expect(find.byTooltip('Season'), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();
      expect(events, ['size']);
      await mount(tester, sort: 'size', showSeason: false);
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pump();
      expect(events, ['size', 'direction']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.arrowDown,
  ]) {
    testWidgets('filter ${key.keyLabel} dispatches once and ignores repeats', (
      tester,
    ) async {
      await mount(tester);
      filter.requestFocus();
      await tester.pump();
      final ink = tester.widget<InkWell>(
        find.ancestor(of: find.text('Filter'), matching: find.byType(InkWell)),
      );
      expect(ink.canRequestFocus, isFalse);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      expect(events, [key == LogicalKeyboardKey.arrowDown ? 'down' : 'filter']);
      expect(filter.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      filter.requestFocus();
      await tester.pump();
      expect(filter.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
