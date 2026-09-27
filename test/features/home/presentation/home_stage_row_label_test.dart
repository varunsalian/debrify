import 'package:debrify/features/home/presentation/home_stage_row_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('shared row label fits narrow scaled headers in $direction', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          _host(
            'A long title provided by a catalog',
            scale: scale,
            direction: direction,
          ),
        );
        final text = tester.widget<Text>(
          find.text('A LONG TITLE PROVIDED BY A CATALOG'),
        );
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.style!.fontSize, 12);
        expect(text.style!.letterSpacing, 1.8);
        expect(
          tester.widget<Row>(find.byType(Row)).mainAxisAlignment,
          MainAxisAlignment.start,
        );
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        final title = tester.getRect(find.byType(Text));
        final chevron = tester.getRect(
          find.byIcon(Icons.keyboard_arrow_up_rounded),
        );
        if (direction == TextDirection.ltr) {
          expect(title.left, greaterThan(chevron.right));
        } else {
          expect(title.right, lessThan(chevron.left));
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('title updates keep directional handling with the caller', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var downs = 0;
    Widget page(String title) => _host(
      title,
      owner: (label) => Focus(
        focusNode: node,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            downs++;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: label,
      ),
    );
    await tester.pumpWidget(page('First'));
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpWidget(page('Second'));
    expect(find.text('FIRST'), findsNothing);
    expect(find.text('SECOND'), findsOneWidget);
    expect(node.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(downs, 2);
    await tester.pumpWidget(page(''));
    expect(node.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _host(
  String title, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  Widget Function(Widget)? owner,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 160,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Builder(
            builder: (context) {
              final label = buildHomeStageRowLabel(
                context: context,
                title: title,
              );
              return owner == null ? label : owner(label);
            },
          ),
        ),
      ),
    ),
  ),
);
