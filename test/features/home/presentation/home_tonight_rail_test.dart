import 'package:debrify/features/home/presentation/home_tonight_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Tonight rail keeps label clearance, trailing space and lazy construction',
    (tester) async {
      final built = <int>[];
      for (final height in [180.0, 220.0]) {
        built.clear();
        await tester.pumpWidget(_host(railHeight: height, built: built));
        expect(
          tester.getRect(find.byKey(const ValueKey('label'))),
          const Rect.fromLTWH(0, 0, 552, 27),
        );
        expect(
          tester.getRect(find.byType(ListView)),
          Rect.fromLTWH(0, 37, 600, height),
        );
        expect(tester.getSize(find.byType(Column)).height, height + 61);
        expect(built, contains(0));
        expect(built.length, lessThan(15));
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.scrollDirection, Axis.horizontal);
        expect(list.clipBehavior, Clip.hardEdge);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Tonight rail preserves scroll and borrowed focus during append and resize',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_host(node: node));
      node.requestFocus();
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(60);
      await tester.pump();
      await tester.pumpWidget(
        _host(
          node: node,
          count: 101,
          width: 700,
          railHeight: 200,
          labelHeight: 54,
        ),
      );
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        same(scroll),
      );
      expect(scroll.position.pixels, 60);
      expect(node.hasFocus, isTrue);
      expect(tester.getTopLeft(find.byType(ListView)).dy, 64);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: node, child: const SizedBox()),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing rail identity creates a fresh scroll position', (
    tester,
  ) async {
    await tester.pumpWidget(_host(rail: 'first'));
    final first = tester.state<ScrollableState>(find.byType(Scrollable));
    first.position.jumpTo(200);
    await tester.pump();
    await tester.pumpWidget(_host(rail: 'second'));
    final second = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(second, isNot(same(first)));
    expect(second.position.pixels, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  double width = 600,
  double railHeight = 180,
  double labelHeight = 27,
  int count = 100,
  String rail = 'stable',
  FocusNode? node,
  List<int>? built,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: buildHomeTonightRail(
        railHeight: railHeight,
        labelGap: 10,
        railKey: rail,
        itemCount: count,
        label: SizedBox(
          key: const ValueKey('label'),
          width: double.infinity,
          height: labelHeight,
        ),
        itemBuilder: (_, index) {
          built?.add(index);
          return SizedBox(
            width: 180,
            child: index == 0
                ? Focus(focusNode: node, child: const SizedBox.expand())
                : const SizedBox.expand(),
          );
        },
      ),
    ),
  ),
);
