import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

void main() {
  setUp(disableRuntimeFonts);
  testWidgets(
    'Mosaic hold jumps once until release, then a fresh press can change rails',
    (tester) async {
      final home = HomeFixture(tester, style: 'mosaic', fastCount: 20);
      await home.mount();
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      await home.focusFast();
      Key railKey() => tester
          .widgetList<GridView>(find.byType(GridView))
          .singleWhere((grid) => grid.key.toString().contains('mosaic-rail-'))
          .key!;
      final first = railKey();
      await home.drive(
        () => tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown),
      );
      await home.pump(const Duration(milliseconds: 300));
      expect(railKey(), first);
      await home.drive(
        () => tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown),
      );
      await home.pump(const Duration(milliseconds: 500));
      final held = railKey();
      expect(held, isNot(first));
      for (var i = 0; i < 3; i++) {
        await home.drive(
          () => tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown),
        );
        await home.pump(const Duration(milliseconds: 300));
        expect(railKey(), held);
      }
      await home.drive(
        () => tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown),
      );
      await home.key(LogicalKeyboardKey.arrowDown);
      await home.pump(const Duration(milliseconds: 500));
      expect(railKey(), isNot(held));
      await home.dispose();
    },
  );
}
