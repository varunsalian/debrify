import 'package:debrify/features/home/presentation/home_catalog_continuation_footer.dart';
import 'package:debrify/widgets/home/catalog_continuation_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final paused in [false, true]) {
    testWidgets(
      'empty board gives autofocus to first available action: $paused',
      (tester) async {
        final resume = FocusNode();
        final more = FocusNode();
        addTearDown(resume.dispose);
        addTearDown(more.dispose);
        var resumed = 0;
        var expanded = 0;
        Widget frame(bool busy) => MaterialApp(
          home: Scaffold(
            body: buildHomeCatalogContinuationFooter(
              hasPausedRows: paused,
              hasMoreCatalogs: true,
              catalogsEmpty: true,
              busy: busy,
              continueNode: resume,
              moreNode: more,
              onRestoreFocus: () {},
              onContinueRows: () => resumed++,
              onMoreCatalogs: () => expanded++,
            ),
          ),
        );
        await tester.pumpWidget(frame(false));
        await tester.pump();
        final first = paused ? resume : more;
        expect(first.hasFocus, isTrue);
        expect(
          find.byType(CatalogContinuationButton),
          findsNWidgets(paused ? 2 : 1),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect((resumed, expanded), paused ? (1, 0) : (0, 1));
        await tester.pumpWidget(frame(true));
        await tester.pump();
        expect(first.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect((resumed, expanded), paused ? (1, 0) : (0, 1));
        expect(find.textContaining('Loading…'), findsNWidgets(paused ? 2 : 1));
        await tester.pumpWidget(frame(false));
        more.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(expanded, paused ? 1 : 2);
        await tester.pumpWidget(const SizedBox());
        // The footer borrows both nodes; they remain usable after it disappears.
        await tester.pumpWidget(
          MaterialApp(
            home: Focus(focusNode: first, child: const SizedBox()),
          ),
        );
        first.requestFocus();
        await tester.pump();
        expect(first.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Up dispatches once on key down and other events bubble', (
    tester,
  ) async {
    final resume = FocusNode();
    final more = FocusNode();
    addTearDown(resume.dispose);
    addTearDown(more.dispose);
    var restored = 0;
    final bubbled = <KeyEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              bubbled.add(event);
              return KeyEventResult.ignored;
            },
            child: buildHomeCatalogContinuationFooter(
              hasPausedRows: true,
              hasMoreCatalogs: false,
              catalogsEmpty: false,
              busy: false,
              continueNode: resume,
              moreNode: more,
              onRestoreFocus: () => restored++,
              onContinueRows: () {},
              onMoreCatalogs: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(resume.hasFocus, isFalse);
    expect(find.text('Load more catalogs'), findsNothing);
    resume.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    expect(restored, 1);
    expect(bubbled, isEmpty);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    expect(restored, 1);
    expect(bubbled.whereType<KeyRepeatEvent>(), hasLength(1));
    expect(bubbled.whereType<KeyUpEvent>(), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(
      bubbled.where((event) => event.logicalKey == LogicalKeyboardKey.keyA),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
