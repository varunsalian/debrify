import 'package:debrify/widgets/collections/collection_category_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 900.0]) {
    testWidgets(
      'categories scroll and select with large text at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) => Column(
                    children: [
                      CollectionCategoryTabs(
                        labels: List.generate(12, (i) => 'Category $i'),
                        selectedIndex: selected,
                        onSelected: (i) => update(() => selected = i),
                      ),
                      Text('Selected $selected'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Category 11'),
          300,
          scrollable: find.byType(Scrollable),
        );
        await tester.tap(find.text('Category 11'));
        await tester.pumpAndSettle();
        expect(find.text('Selected 11'), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Category 11'),
              )
              .selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
