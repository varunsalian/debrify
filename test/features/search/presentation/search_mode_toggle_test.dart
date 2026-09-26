import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/features/search/presentation/search_mode_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('one permitted workflow hides the selector', (tester) async {
    await tester.pumpWidget(
      host(
        SearchModeToggle(
          mode: SearchMode.catalog,
          isTelevision: false,
          listsAvailable: false,
          keywordAvailable: false,
          onChanged: (_) => fail('Rendering must not dispatch an action'),
        ),
      ),
    );
    expect(find.text('Catalog'), findsNothing);
    expect(find.text('Keyword'), findsNothing);
    expect(find.text('Lists'), findsNothing);
  });

  testWidgets('pointer dispatch uses only caller-permitted modes', (
    tester,
  ) async {
    final selected = <SearchMode>[];
    await tester.pumpWidget(
      host(
        SearchModeToggle(
          mode: SearchMode.catalog,
          isTelevision: false,
          listsAvailable: true,
          keywordAvailable: false,
          onChanged: selected.add,
        ),
      ),
    );
    expect(find.text('Keyword'), findsNothing);
    await tester.tap(find.text('Lists'));
    await tester.pump();
    expect(selected, [SearchMode.lists]);
    expect(tester.takeException(), isNull);
  });

  for (final keywordAvailable in [false, true]) {
    testWidgets(
      'D-pad visits permitted modes and dispatches once, keyword=$keywordAvailable',
      (tester) async {
        final catalog = FocusNode();
        final keyword = FocusNode();
        final lists = FocusNode();
        final selected = <SearchMode>[];
        var fieldLeaves = 0;
        var contentLeaves = 0;
        final view = SearchModeToggle(
          mode: SearchMode.catalog,
          isTelevision: true,
          listsAvailable: true,
          keywordAvailable: keywordAvailable,
          catalogNode: catalog,
          keywordNode: keyword,
          listsNode: lists,
          onChanged: selected.add,
          onLeaveToField: () => fieldLeaves++,
          onLeaveToContent: () => contentLeaves++,
        );
        await tester.pumpWidget(host(view));
        catalog.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        expect(fieldLeaves, 2);
        expect(contentLeaves, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(keywordAvailable ? keyword.hasFocus : lists.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(selected, [
          keywordAvailable ? SearchMode.keyword : SearchMode.lists,
        ]);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(catalog.hasFocus, isTrue);

        // The parent retains node ownership; unmount/remount must not dispose them.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(host(view));
        catalog.requestFocus();
        await tester.pump();
        expect(catalog.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        catalog.dispose();
        keyword.dispose();
        lists.dispose();
      },
    );
  }

  testWidgets(
    'compact selector falls back from a unavailable mode and opens choices',
    (tester) async {
      final selected = <SearchMode>[];
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 180,
            child: SearchModeToggle(
              mode: SearchMode.keyword,
              isTelevision: false,
              compact: true,
              fullWidth: true,
              listsAvailable: true,
              keywordAvailable: false,
              onChanged: selected.add,
            ),
          ),
        ),
      );
      expect(find.text('Catalog'), findsOneWidget);
      expect(find.text('Keyword'), findsNothing);
      expect(selected, isEmpty);
      await tester.tap(find.text('Catalog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lists'));
      await tester.pumpAndSettle();
      expect(selected, [SearchMode.lists]);
      expect(tester.takeException(), isNull);
    },
  );
}
