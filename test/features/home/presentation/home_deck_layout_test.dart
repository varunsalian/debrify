import 'package:debrify/features/home/presentation/home_deck_layout.dart';
import 'package:debrify/features/home/presentation/home_stage_corner_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final c in [
    (1000.0, 600.0, 144.0, Rect.fromLTWH(414 + 2 / 3, 66, 549 + 1 / 3, 309)),
    (600.0, 600.0, 144.0, const Rect.fromLTWH(228, 66, 336, 189)),
    (1000.0, 200.0, 150.0, const Rect.fromLTWH(964, 22, 0, 0)),
  ]) {
    test('Deck reserves rail before fitting card at ${c.$1}x${c.$2}', () {
      final g = HomeDeckGeometry(
        boardW: c.$1,
        boardH: c.$2,
        railBoxH: c.$3,
        labelHeight: 27,
        labelGap: 10,
      );
      expect(g.cardLeft, closeTo(c.$4.left, .0001));
      expect(g.cardTop, closeTo(c.$4.top, .0001));
      expect(g.cardW, closeTo(c.$4.width, .0001));
      expect(g.cardH, closeTo(c.$4.height, .0001));
      expect(g.railZoneH, c.$3 + 63);
      expect(g.identityWidth, inInclusiveRange(140, 560));
    });
  }

  for (final (height, labelHeight) in [(400.0, 54.0), (720.0, 27.0)]) {
    testWidgets(
      'Deck preserves surface rectangle and focus through theater and resize at height $height',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final node = FocusNode();
        addTearDown(node.dispose);
        final initialized = <String>[];
        final built = <int>[];
        Widget page(bool theater, {double width = 1000}) => _page(
          height: height,
          width: width,
          labelHeight: labelHeight,
          theater: theater,
          node: node,
          initialized: initialized,
          built: built,
        );
        await tester.pumpWidget(page(false));
        final g = _geometry(1000, height, labelHeight);
        final cardRect = Rect.fromLTWH(g.cardLeft, g.cardTop, g.cardW, g.cardH);
        for (final name in ['art', 'trailer', 'live']) {
          final finder = find.byKey(ValueKey(name));
          expect(tester.getRect(finder), cardRect);
          expect(
            find.ancestor(of: finder, matching: find.byType(ClipRRect)),
            findsNothing,
          );
        }
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .singleWhere((w) => w.painter is HomeStageCornerPainter);
        expect(tester.getRect(find.byWidget(painter)), cardRect);
        final cardStack = tester
            .widgetList<Stack>(find.byType(Stack))
            .singleWhere((w) => w.children.first.key == const ValueKey('art'));
        expect(cardStack.children.take(3).map((w) => w.key), [
          const ValueKey('art'),
          const ValueKey('trailer'),
          const ValueKey('live'),
        ]);
        expect(cardStack.children[3], isA<IgnorePointer>());
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('label'))),
          Offset(48, height - g.railZoneH),
        );
        expect(cardRect.bottom, lessThanOrEqualTo(height - g.railZoneH - 18));
        expect(built.length, lessThan(30));
        node.requestFocus();
        await tester.pump();
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        scroll.position.jumpTo(80);
        await tester.pump();
        await tester.pumpWidget(page(true));
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
          const Duration(milliseconds: 900),
        );
        expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          0,
        );
        await tester.pump(const Duration(milliseconds: 900));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('label'))).dy,
          closeTo(height - g.railZoneH + g.railZoneH * .12, .001),
        );
        expect(node.hasFocus, isTrue);
        expect(scroll.position.pixels, 80);
        await tester.pumpWidget(page(false, width: 900));
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
          const Duration(milliseconds: 250),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.state<ScrollableState>(find.byType(Scrollable)),
          same(scroll),
        );
        expect(scroll.position.pixels, 80);
        expect(node.hasFocus, isTrue);
        expect(initialized, ['trailer', 'live']);
        final resized = _geometry(900, height, labelHeight);
        expect(
          tester.getRect(find.byKey(const ValueKey('live'))),
          Rect.fromLTWH(
            resized.cardLeft,
            resized.cardTop,
            resized.cardW,
            resized.cardH,
          ),
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Deck supports absent native surfaces and replaces the rail by identity',
    (tester) async {
      await tester.pumpWidget(_page(native: false, rail: 'first'));
      final first = tester.state<ScrollableState>(find.byType(Scrollable));
      await tester.pumpWidget(_page(native: false, rail: 'second'));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        isNot(same(first)),
      );
      expect(find.byType(_Surface), findsNothing);
      expect(find.byKey(const ValueKey('art')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

HomeDeckGeometry _geometry(double width, double height, double labelHeight) =>
    HomeDeckGeometry(
      boardW: width,
      boardH: height,
      railBoxH: 120,
      labelHeight: labelHeight,
      labelGap: 10,
    );

Widget _page({
  double width = 800,
  double height = 600,
  double labelHeight = 27,
  bool theater = false,
  bool native = true,
  String rail = 'stable',
  FocusNode? node,
  List<String>? initialized,
  List<int>? built,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: buildHomeDeckLayout(
        geometry: _geometry(width, height, labelHeight),
        theater: theater,
        railKey: rail,
        itemCount: 100,
        borderColor: Colors.white,
        peeks: const SizedBox(),
        artwork: const SizedBox.expand(key: ValueKey('art')),
        trailer: native
            ? _Surface(name: 'trailer', initialized: initialized!)
            : null,
        live: native ? _Surface(name: 'live', initialized: initialized!) : null,
        identity: const SizedBox(width: 100, height: 100),
        railLabel: SizedBox(key: const ValueKey('label'), height: labelHeight),
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

class _Surface extends StatefulWidget {
  _Surface({required this.name, required this.initialized})
    : super(key: ValueKey(name));
  final String name;
  final List<String> initialized;
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
}
