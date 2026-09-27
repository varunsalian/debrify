import 'package:debrify/features/home/presentation/home_row_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'delayed entrance rises and fades once, then stays settled on rebuild',
    (tester) async {
      await tester.pumpWidget(_host(play: true, delay: 120));
      expect(_opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 119));
      expect(_opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_opacity(tester), greaterThan(0));
      expect(_opacity(tester), lessThan(1));
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(HomeRowEntrance),
          matching: find.byType(Transform),
        ),
      );
      expect(transform.transform.storage[13], inExclusiveRange(0, 12));
      await tester.pump(const Duration(milliseconds: 151));
      expect(_opacity(tester), 1);
      await tester.pumpWidget(_host(play: true, delay: 120));
      expect(_opacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion settles immediately and cancels the delayed start',
    (tester) async {
      await tester.pumpWidget(_host(play: true, delay: 300, reduced: true));
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_opacity(tester), 1);
      await tester.pumpWidget(_host(play: true, delay: 300));
      expect(_opacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposal cancels delayed work and an initially settled row never starts later',
    (tester) async {
      await tester.pumpWidget(_host(play: true, delay: 300));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_host(play: false));
      await tester.pumpWidget(_host(play: true));
      expect(
        find.descendant(
          of: find.byType(HomeRowEntrance),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(find.text('Row'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(HomeRowEntrance),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;
Widget _host({required bool play, int delay = 0, bool reduced = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: HomeRowEntrance(
          play: play,
          delayMs: delay,
          child: const Text('Row'),
        ),
      ),
    );
