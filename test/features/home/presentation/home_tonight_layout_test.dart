import 'package:debrify/features/home/presentation/home_tonight_layout.dart';
import 'package:debrify/features/home/presentation/home_stage_corner_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final c in [
    (1000.0, 600.0, 120.0, true, true, 580.0, 302.0, 103 + 1 / 3, 334.0),
    (600.0, 600.0, 120.0, true, true, 222.0, 260.0, 103 + 1 / 3, 334.0),
    (500.0, 600.0, 120.0, true, false, 170.0, 212.0, 103 + 1 / 3, 334.0),
    (1000.0, 200.0, 80.0, true, false, 0.0, 882.0, 0.0, 0.0),
    (300.0, 200.0, 0.0, false, true, 102.0, 204.0, 108.0, 108.0),
    (300.0, 50.0, 0.0, false, true, 0.0, 204.0, 80.0, 0.0),
  ]) {
    test('Tonight queue fit at ${c.$1}x${c.$2}, rail=${c.$4}', () {
      final g = _geometry(c.$1, c.$2, hasRail: c.$4, railH: c.$3);
      expect(g.showQueue, c.$5);
      expect(g.queueOnly, !c.$4);
      expect(g.cardW, closeTo(c.$6, .0001));
      expect(g.cardH, closeTo(c.$6 * 9 / 16, .0001));
      expect(g.effQueueW, closeTo(c.$7, .0001));
      expect(g.rowH, closeTo(c.$8, .0001));
      expect(g.queueBoxH, closeTo(c.$9, .0001));
    });
  }

  testWidgets(
    'Tonight places native slots, caption and painted corners above the reserved rail',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = <String>[];
      final g = _geometry(1000, 600);
      await tester.pumpWidget(
        _host(
          1000,
          600,
          buildHomeTonightLayout(
            geometry: g,
            header: const SizedBox(key: ValueKey('header')),
            cardBuilder: () {
              order.add('card');
              return _frame();
            },
            queueBuilder: () {
              order.add('queue');
              return const SizedBox.expand(key: ValueKey('queue'));
            },
            railBuilder: () {
              order.add('rail');
              return const SizedBox(key: ValueKey('rail'), height: 174);
            },
          ),
        ),
      );
      expect(order, ['card', 'queue', 'rail']);
      for (final name in ['art', 'trailer', 'live']) {
        final f = find.byKey(ValueKey(name));
        expect(tester.getRect(f), const Rect.fromLTWH(48, 70, 580, 326.25));
        expect(
          find.ancestor(of: f, matching: find.byType(ClipRRect)),
          findsNothing,
        );
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('queue'))),
        const Rect.fromLTWH(650, 70, 302, 334),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('rail'))),
        const Offset(48, 426),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('caption'))),
        const Offset(72, 356.25),
      );
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .singleWhere((w) => w.painter is HomeStageCornerPainter);
      expect(
        tester.getRect(find.byWidget(paint)),
        const Rect.fromLTWH(48, 70, 580, 326.25),
      );
      final stack = tester
          .widgetList<Stack>(find.byType(Stack))
          .singleWhere((w) => w.children.first.key == const ValueKey('art'));
      expect(stack.children.take(3).map((w) => w.key), [
        const ValueKey('art'),
        const ValueKey('trailer'),
        const ValueKey('live'),
      ]);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'queue-only mode never constructs hidden card content and retains queue focus on resize',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget page(double width) => _host(
        width,
        200,
        buildHomeTonightLayout(
          geometry: _geometry(width, 200, hasRail: false, railH: 0),
          header: const SizedBox(),
          cardBuilder: () =>
              throw StateError('Hidden native/card content constructed'),
          queueBuilder: () => Focus(
            focusNode: node,
            child: const SizedBox.expand(key: ValueKey('queue')),
          ),
          railBuilder: null,
        ),
      );
      await tester.pumpWidget(page(300));
      expect(
        tester.getRect(find.byKey(const ValueKey('queue'))),
        const Rect.fromLTWH(48, 70, 204, 108),
      );
      node.requestFocus();
      await tester.pump();
      await tester.pumpWidget(page(500));
      expect(node.hasFocus, isTrue);
      expect(tester.getSize(find.byKey(const ValueKey('queue'))).width, 404);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden queue is lazy while card State and rail focus survive narrow resize',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final node = FocusNode();
      addTearDown(node.dispose);
      final initialized = <String>[];
      var queueBuilds = 0;
      Widget page(double width, {bool hasQueue = true}) => _host(
        width,
        600,
        buildHomeTonightLayout(
          geometry: _geometry(width, 600, hasQueue: hasQueue),
          header: const SizedBox(),
          cardBuilder: () => _frame(live: _Live(initialized)),
          queueBuilder: () {
            queueBuilds++;
            return const SizedBox.expand(key: ValueKey('queue'));
          },
          railBuilder: () => SizedBox(
            height: 174,
            child: Focus(focusNode: node, child: const SizedBox()),
          ),
        ),
      );
      await tester.pumpWidget(page(1000));
      node.requestFocus();
      await tester.pump();
      expect(queueBuilds, 1);
      await tester.pumpWidget(page(500));
      expect(queueBuilds, 1);
      expect(find.byKey(const ValueKey('queue')), findsNothing);
      expect(node.hasFocus, isTrue);
      expect(initialized, ['live']);
      await tester.pumpWidget(page(1000, hasQueue: false));
      expect(queueBuilds, 1);
      expect(initialized, ['live']);
      await tester.pumpWidget(page(1000));
      expect(queueBuilds, 2);
      expect(node.hasFocus, isTrue);
      expect(initialized, ['live']);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

HomeTonightGeometry _geometry(
  double width,
  double height, {
  bool hasRail = true,
  bool hasQueue = true,
  double railH = 120,
}) => HomeTonightGeometry(
  boardW: width,
  boardH: height,
  hasRail: hasRail,
  hasQueue: hasQueue,
  railBoxH: railH,
  labelHeight: 20,
  labelGap: 10,
  headerH: 70,
  rowMinH: 80,
);
Widget _host(double width, double height, Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, height: height, child: child),
  ),
);
Widget _frame({Widget? live}) => buildHomeTonightCardFrame(
  artwork: const SizedBox.expand(key: ValueKey('art')),
  trailer: const SizedBox.expand(key: ValueKey('trailer')),
  live: live ?? const SizedBox.expand(key: ValueKey('live')),
  caption: const SizedBox(key: ValueKey('caption'), height: 20),
);

class _Live extends StatefulWidget {
  const _Live(this.initialized);
  final List<String> initialized;
  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> {
  @override
  void initState() {
    super.initState();
    widget.initialized.add('live');
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
