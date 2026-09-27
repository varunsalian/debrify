import 'package:debrify/features/home/presentation/home_atrium_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Atrium label scales with platform typography and lazy strip', (
    tester,
  ) async {
    for (final androidTv in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final built = <int>[];
        await tester.pumpWidget(
          _host(androidTv: androidTv, scale: scale, built: built),
        );
        final label = find.text('A LONG CATALOG TITLE');
        final text = tester.widget<Text>(label);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.style!.height, androidTv ? 1.35 : null);
        expect(text.style!.fontSize, 12);
        expect(text.style!.letterSpacing, 1.6);
        expect(
          tester.getTopLeft(find.byType(ListView)).dy,
          tester.getBottomLeft(label).dy + 10,
        );
        expect(tester.getSize(find.byType(ListView)).height, 180);
        expect(built, contains(0));
        expect(built.length, lessThan(15));
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.scrollDirection, Axis.horizontal);
        expect(list.clipBehavior, Clip.hardEdge);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('append and resize preserve scroll and borrowed focus', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(node: node));
    node.requestFocus();
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(60);
    await tester.pump();
    await tester.pumpWidget(
      _host(node: node, count: 101, width: 700, height: 200),
    );
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)),
      same(scroll),
    );
    expect(scroll.position.pixels, 60);
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: node, child: const SizedBox()),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new rail identity resets scroll and updates its label', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final first = tester.state<ScrollableState>(find.byType(Scrollable));
    first.position.jumpTo(200);
    await tester.pump();
    await tester.pumpWidget(_host(rail: 'second', title: 'Second'));
    final second = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(second, isNot(same(first)));
    expect(second.position.pixels, 0);
    expect(find.text('SECOND'), findsOneWidget);
    expect(find.text('A LONG CATALOG TITLE'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _host({
  bool androidTv = true,
  double scale = 1,
  double width = 600,
  double height = 180,
  int count = 100,
  String rail = 'first',
  String title = 'A long catalog title',
  FocusNode? node,
  List<int>? built,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Builder(
          builder: (context) => buildHomeAtriumRow(
            context: context,
            title: title,
            androidTv: androidTv,
            labelGap: 10,
            rowHeight: height,
            railKey: rail,
            itemCount: count,
            itemBuilder: (_, index) {
              built?.add(index);
              return SizedBox(
                width: 120,
                child: index == 0 && node != null
                    ? Focus(focusNode: node, child: const Text('Cell'))
                    : Text('Cell $index'),
              );
            },
          ),
        ),
      ),
    ),
  ),
);
