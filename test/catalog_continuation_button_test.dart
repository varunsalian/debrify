import 'package:debrify/widgets/home/catalog_continuation_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DPAD focus survives busy and repeated Enter cannot queue work', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var calls = 0;
    Widget board(bool busy) => MaterialApp(
      home: Scaffold(
        body: CatalogContinuationButton(
          focusNode: node,
          busy: busy,
          label: 'Continue paused rows',
          onPressed: () => calls++,
        ),
      ),
    );
    await tester.pumpWidget(board(false));
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await tester.pumpWidget(board(true));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    // A watched-only batch leaves the action present and ready for another try.
    await tester.pumpWidget(board(false));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
