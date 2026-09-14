import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/see_all/discover_browsing_input.dart';

void main() {
  testWidgets('browsing keys reveal controls and still reach focused cards', (
    tester,
  ) async {
    var activity = 0;
    var moves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverBrowsingInput(
          onActivity: () => activity++,
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.arrowRight) {
                moves++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(activity, 1);
    expect(moves, 1);
    await tester.tapAt(const Offset(20, 20));
    expect(activity, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(activity, 2);
  });
}
