import 'package:debrify/features/sources/presentation/source_pending_results_pill.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FocusNode pill;
  late FocusNode row;
  late FocusNode filter;
  late List<String> events;

  setUp(() {
    pill = FocusNode();
    row = FocusNode();
    filter = FocusNode();
    events = [];
  });
  tearDown(() {
    pill.dispose();
    row.dispose();
    filter.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool toolbar = true,
    bool moveToRow = true,
    int count = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) events.add('bubble');
                return KeyEventResult.handled;
              },
              child: Column(
                children: [
                  if (toolbar)
                    Focus(focusNode: filter, child: const Text('Filter')),
                  SourcePendingResultsPill(
                    count: count,
                    focusNode: pill,
                    onAdopt: () => events.add('adopt'),
                    onNavigateDown: () {
                      events.add('row');
                      if (moveToRow) row.requestFocus();
                    },
                    onNavigateUp: () {
                      if (filter.context == null) return false;
                      events.add('filter');
                      filter.requestFocus();
                      return true;
                    },
                  ),
                  Focus(focusNode: row, child: const Text('Row')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    pill.requestFocus();
    await tester.pump();
  }

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  ]) {
    testWidgets('${key.keyLabel} adopts before returning focus to rows', (
      tester,
    ) async {
      await mount(tester);
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(events, ['adopt', 'row']);
      expect(row.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('touch adopts without forcing row focus', (tester) async {
    await mount(tester, count: 3);
    expect(find.text('3 new sources'), findsOneWidget);
    await tester.tap(find.text('3 new sources'));
    await tester.pump();
    expect(events, ['adopt']);
    expect(pill.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Down returns to rows without adopting pending results', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(events, ['row']);
    expect(row.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final toolbar in [true, false]) {
    testWidgets('Up handles only an attached toolbar: $toolbar', (
      tester,
    ) async {
      await mount(tester, toolbar: toolbar);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(events, [toolbar ? 'filter' : 'bubble']);
      expect(filter.hasFocus, toolbar);
      expect(pill.hasFocus, !toolbar);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('held activation and key release do not adopt again', (
    tester,
  ) async {
    await mount(tester, moveToRow: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(events, ['adopt', 'row']);
    expect(find.text('1 new source'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // Unmount must not dispose the focus node borrowed from the view.
    await mount(tester, count: 2);
    expect(pill.hasFocus, isTrue);
    expect(find.text('2 new sources'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
