import 'package:debrify/features/home/presentation/home_tonight_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Tonight renders the supplied local weekday without a ticking clock',
    (tester) async {
      const days = [
        'MONDAY',
        'TUESDAY',
        'WEDNESDAY',
        'THURSDAY',
        'FRIDAY',
        'SATURDAY',
        'SUNDAY',
      ];
      for (var i = 0; i < days.length; i++) {
        await tester.pumpWidget(_host(now: DateTime(2026, 9, 21 + i)));
        expect(find.text(days[i]), findsOneWidget);
        expect(find.text('Tonight'), findsOneWidget);
        await tester.pump(const Duration(days: 1));
        expect(find.text(days[i]), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'zero progress hides the badge and updates preserve the header extent',
    (tester) async {
      for (final count in [0, 1, 25, 0]) {
        await tester.pumpWidget(_host(count: count));
        if (count == 0) {
          expect(find.textContaining('IN PROGRESS'), findsNothing);
        } else {
          expect(find.text('$count IN PROGRESS'), findsOneWidget);
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('header'))).height,
          closeTo(69.1, .001),
        );
        expect(
          tester.widget<Row>(find.byType(Row)).crossAxisAlignment,
          CrossAxisAlignment.baseline,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'header clearance follows text scale while retaining bottom spacing',
    (tester) async {
      for (final (scale, height) in [(1.0, 69.1), (1.5, 86.65), (2.0, 104.2)]) {
        await tester.pumpWidget(_host(scale: scale));
        final rect = tester.getRect(find.byKey(const ValueKey('header')));
        expect(rect.height, closeTo(height, .001));
        expect(
          tester.getBottomLeft(find.byType(Row)).dy,
          closeTo(rect.bottom - 10, .001),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _host({DateTime? now, int count = 0, double scale = 1}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Builder(
        builder: (context) => SizedBox(
          key: const ValueKey('header'),
          height: homeTonightHeaderHeight(context),
          child: buildHomeTonightHeader(
            context: context,
            inProgress: count,
            now: now ?? DateTime(2026, 9, 21),
          ),
        ),
      ),
    ),
  ),
);
