import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/season_action_region.dart';

void main() {
  for (final ink in [false, true]) {
    testWidgets('season long press and held OK, ink=$ink', (tester) async {
      var taps = 0;
      var holds = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeasonActionRegion(
              onTap: () => taps++,
              onOptions: () => holds++,
              child: ink
                  ? InkWell(
                      focusNode: node,
                      onTap: () => taps++,
                      child: const SizedBox(
                        width: 160,
                        height: 60,
                        child: Text('Season 1'),
                      ),
                    )
                  : Focus(
                      focusNode: node,
                      child: GestureDetector(
                        onTap: () => taps++,
                        child: const SizedBox(
                          width: 160,
                          height: 60,
                          child: Text('Season 1'),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Season 1'));
      expect(taps, 1);
      await tester.longPress(find.text('Season 1'));
      expect(holds, 1);
      expect(taps, 1);
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 650));
      expect(holds, 2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(taps, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
