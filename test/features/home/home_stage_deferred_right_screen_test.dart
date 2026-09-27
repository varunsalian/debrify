import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

void main() {
  setUp(disableRuntimeFonts);
  for (final moveAway in [false, true]) {
    testWidgets(
      'Mosaic paginated Right preserves focus intent (away=$moveAway)',
      (tester) async {
        final home = HomeFixture(tester, style: 'mosaic', horizontal: true);
        await home.mount();
        await home.drive(() => home.slow.complete(page('Slow')));
        await home.settle();
        final grid = find.byType(GridView);
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: grid, matching: find.byType(Scrollable)),
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await home.pump(const Duration(milliseconds: 500));
        final last = Focus.of(tester.element(find.text('Fast 99').last));
        last.requestFocus();
        await home.pump(const Duration(milliseconds: 500));
        expect(last.hasFocus, isTrue);
        await home.key(LogicalKeyboardKey.arrowRight);
        await home.pump(Duration.zero);
        expect(home.requests.any((path) => path.contains('skip=100')), isTrue);
        FocusNode? previous;
        if (moveAway) {
          await home.key(LogicalKeyboardKey.arrowUp);
          await home.pump(Duration.zero);
          previous = FocusManager.instance.primaryFocus;
          expect(previous, isNotNull);
          expect(previous, isNot(same(last)));
          expect(previous!.hasFocus, isTrue);
        }
        await home.drive(
          () => home.secondPage.complete(page('Fast', start: 100, count: 100)),
        );
        await home.settle();
        if (moveAway) {
          expect(previous!.hasFocus, isTrue);
        } else {
          expect(
            Focus.of(tester.element(find.text('Fast 100').last)).hasFocus,
            isTrue,
          );
        }
        await home.dispose();
      },
    );
  }
}
