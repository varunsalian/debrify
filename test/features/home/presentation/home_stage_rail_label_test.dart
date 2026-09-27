import 'package:debrify/features/home/presentation/home_stage_rail_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final align in [MainAxisAlignment.center, MainAxisAlignment.end]) {
    testWidgets('rail title and counter remain flexible for $align', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          _host(
            title: 'A very long catalog title from an addon',
            index: 9,
            count: 12,
            width: 160,
            scale: scale,
            align: align,
          ),
        );
        expect(
          find.text('A VERY LONG CATALOG TITLE FROM AN ADDON'),
          findsOneWidget,
        );
        expect(find.text('10/12'), findsOneWidget);
        expect(tester.widget<Row>(find.byType(Row)).mainAxisAlignment, align);
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
        }
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'one rail hides the counter; new selection updates its position',
    (tester) async {
      await tester.pumpWidget(_host(title: 'Movies', index: 0, count: 1));
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.text('1/1'), findsNothing);
      expect(find.byType(Flexible), findsOneWidget);
      await tester.pumpWidget(_host(title: 'Shows', index: 2, count: 3));
      expect(find.text('MOVIES'), findsNothing);
      expect(find.text('SHOWS'), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget);
      expect(find.byType(Flexible), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'label height keeps its shared chevron floor under text scaling',
    (tester) async {
      final heights = <double>[];
      for (final scale in [.5, 1.0, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) {
                heights.add(homeStageRailLabelHeight(context));
                return const SizedBox();
              },
            ),
          ),
        );
      }
      expect(heights[0], 27);
      expect(heights[1], 27);
      expect(heights[2], closeTo(32.4, .00001));
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _host({
  required String title,
  required int index,
  required int count,
  double width = 400,
  double scale = 1,
  MainAxisAlignment align = MainAxisAlignment.center,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SizedBox(
        width: width,
        child: Builder(
          builder: (context) => buildHomeStageRailLabel(
            context: context,
            title: title,
            railIndex: index,
            railCount: count,
            align: align,
          ),
        ),
      ),
    ),
  ),
);
