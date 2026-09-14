import 'package:debrify/widgets/home/home_continuation_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'continuation skips an unmounted first rail and restores the active rail',
    (tester) async {
      final firstRail = FocusNode(debugLabel: 'first');
      final activeRail = FocusNode(debugLabel: 'active');
      final continuation = FocusNode(debugLabel: 'continue');
      addTearDown(() {
        firstRail.dispose();
        activeRail.dispose();
        continuation.dispose();
      });
      Widget board(bool showFirst) => MaterialApp(
        home: Column(
          children: [
            if (showFirst)
              Focus(focusNode: firstRail, child: const Text('First rail')),
            Focus(focusNode: activeRail, child: const Text('Active rail')),
            TextButton(
              focusNode: continuation,
              onPressed: () {},
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      await tester.pumpWidget(board(true));
      firstRail.requestFocus();
      await tester.pump();
      // Canvas replaces the previously displayed rail while keeping its nodes.
      await tester.pumpWidget(board(false));
      continuation.requestFocus();
      await tester.pump();
      expect(focusMountedHomeNode([firstRail, activeRail]), isTrue);
      await tester.pump();
      expect(activeRail.hasFocus, isTrue);
      expect(continuation.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(focusMountedHomeNode([firstRail, activeRail]), isFalse);
    },
  );

  testWidgets('a mounted origin takes precedence over other visible cards', (
    tester,
  ) async {
    final origin = FocusNode();
    final other = FocusNode();
    addTearDown(() {
      origin.dispose();
      other.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Focus(focusNode: origin, child: const Text('Origin')),
            Focus(focusNode: other, child: const Text('Other')),
          ],
        ),
      ),
    );
    other.requestFocus();
    await tester.pump();
    expect(focusMountedHomeNode([origin, other]), isTrue);
    await tester.pump();
    expect(origin.hasFocus, isTrue);
  });
}
