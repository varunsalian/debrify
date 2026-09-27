import 'package:debrify/features/home/presentation/home_atrium_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final secondRow in [false, true]) {
    testWidgets(
      'Atrium keeps panel, surfaces and ${secondRow ? 'two rows' : 'one row'} in their rectangles',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_page(secondRow: secondRow));
        for (final name in ['art', 'trailer', 'live']) {
          expect(
            tester.getRect(find.byKey(ValueKey(name))),
            const Rect.fromLTWH(380, 0, 620, 600),
          );
        }
        final top = tester.getRect(find.byKey(const ValueKey('top')));
        expect(top, Rect.fromLTWH(420, secondRow ? 356 : 474, 540, 100));
        if (secondRow) {
          expect(
            tester.getRect(find.byKey(const ValueKey('bottom'))),
            const Rect.fromLTWH(420, 474, 540, 100),
          );
        } else {
          expect(find.byKey(const ValueKey('bottom')), findsNothing);
        }
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('label'))),
          const Offset(48, 249),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('identity'))),
          const Offset(48, 291),
        );
        final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
        final panel = boxes.singleWhere((w) => w.color == Colors.indigo);
        expect(
          tester.getRect(find.byWidget(panel)),
          const Rect.fromLTWH(0, 0, 380, 600),
        );
        final seam = boxes.singleWhere((w) => w.color == Colors.grey);
        expect(
          tester.getRect(find.byWidget(seam)),
          const Rect.fromLTWH(380, 0, 1, 600),
        );
        final artStack = tester
            .widgetList<Stack>(find.byType(Stack))
            .singleWhere((s) => s.children.first.key == const ValueKey('art'));
        expect(artStack.children.take(3).map((w) => w.key), [
          const ValueKey('art'),
          const ValueKey('trailer'),
          const ValueKey('live'),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Atrium retains top-row focus and surface state through resize and removes optional content',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final node = FocusNode();
      addTearDown(node.dispose);
      final initialized = <String>[];
      final disposed = <String>[];
      Widget page({bool compact = false, bool surfaces = true}) => _page(
        secondRow: !compact,
        split: compact ? 304 : 380,
        focus: node,
        trailer: surfaces
            ? _Surface(
                name: 'trailer',
                initialized: initialized,
                disposed: disposed,
              )
            : null,
        live: surfaces
            ? _Surface(
                name: 'live',
                initialized: initialized,
                disposed: disposed,
              )
            : null,
      );
      await tester.pumpWidget(page());
      node.requestFocus();
      await tester.pump();
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpWidget(page(compact: true));
      expect(node.hasFocus, isTrue);
      expect(initialized, ['trailer', 'live']);
      expect(disposed, isEmpty);
      expect(find.byKey(const ValueKey('bottom')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('top'))),
        const Rect.fromLTWH(344, 274, 416, 100),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('trailer'))),
        const Rect.fromLTWH(304, 0, 496, 400),
      );
      await tester.pumpWidget(page(compact: true, surfaces: false));
      expect(disposed, unorderedEquals(['trailer', 'live']));
      expect(node.hasFocus, isTrue);
      expect(find.byKey(const ValueKey('art')), findsOneWidget);
      expect(find.byKey(const ValueKey('trailer')), findsNothing);
      expect(find.byKey(const ValueKey('live')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _page({
  required bool secondRow,
  double split = 380,
  FocusNode? focus,
  Widget? trailer = const SizedBox.expand(key: ValueKey('trailer')),
  Widget? live = const SizedBox.expand(key: ValueKey('live')),
}) => MaterialApp(
  home: buildHomeAtriumLayout(
    splitX: split,
    wallH: secondRow ? 244 : 126,
    panelColor: Colors.indigo,
    seamColor: Colors.grey,
    artwork: const SizedBox.expand(key: ValueKey('art')),
    trailer: trailer,
    live: live,
    railLabel: const SizedBox(key: ValueKey('label'), width: 100, height: 20),
    identity: const SizedBox(key: ValueKey('identity'), width: 100, height: 60),
    topRow: SizedBox(
      key: const ValueKey('top'),
      width: double.infinity,
      height: 100,
      child: Focus(focusNode: focus, child: const SizedBox()),
    ),
    bottomRow: secondRow
        ? const SizedBox(
            key: ValueKey('bottom'),
            width: double.infinity,
            height: 100,
          )
        : null,
  ),
);

class _Surface extends StatefulWidget {
  _Surface({
    required this.name,
    required this.initialized,
    required this.disposed,
  }) : super(key: ValueKey(name));
  final String name;
  final List<String> initialized;
  final List<String> disposed;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  @override
  void initState() {
    super.initState();
    widget.initialized.add(widget.name);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  void dispose() {
    widget.disposed.add(widget.name);
    super.dispose();
  }
}
