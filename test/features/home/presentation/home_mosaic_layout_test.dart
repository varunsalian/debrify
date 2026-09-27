import 'package:debrify/features/home/presentation/home_mosaic_layout.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  for (final c in [
    (1280.0, 720.0, 2 / 3, 0.0, 7, 1088 / 7, 1632 / 7),
    (1280.0, 720.0, 2 / 3, 45.0, 7, 1088 / 7, 1632 / 7 + 45),
    (1280.0, 720.0, 16 / 9, 0.0, 3, 384.0, 216.0),
    (90.0, 400.0, 2 / 3, 45.0, 1, 1.0, 46.5),
    (4000.0, 100.0, 2 / 3, 0.0, 8, 474.0, 711.0),
  ]) {
    test(
      'Mosaic fits ${c.$5} columns for ${c.$1}x${c.$2}, aspect ${c.$3}, caption ${c.$4}',
      () {
        final geometry = HomeMosaicGeometry(
          boardW: c.$1,
          boardH: c.$2,
          cellAspect: c.$3,
          captionBandHeight: c.$4,
        );
        expect(geometry.perRow, c.$5);
        expect(geometry.cellW, closeTo(c.$6, .0001));
        expect(geometry.extent, closeTo(c.$7, .0001));
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Mosaic reserves scaled header clearance at $scale and builds lazily',
      (tester) async {
        final channel = ObservedValue<IptvChannel?>(null);
        addTearDown(channel.dispose);
        final built = <int>[];
        await tester.pumpWidget(_page(channel, scale: scale, built: built));
        expect(
          tester.getTopLeft(find.byType(GridView)).dy,
          scale == 1 ? 153 : 196,
        );
        expect(tester.getTopLeft(find.byType(GridView)).dx, 48);
        expect(tester.getSize(find.byType(GridView)).width, 704);
        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 5);
        expect(delegate.mainAxisExtent, 192);
        expect(grid.padding, const EdgeInsets.only(bottom: 24));
        expect(built, contains(0));
        expect(built.length, lessThan(50));
        expect(find.text('HOLD ▲▼ TO CHANGE ROW'), findsOneWidget);
        await tester.pumpWidget(_page(channel, scale: scale, showHint: false));
        expect(find.text('HOLD ▲▼ TO CHANGE ROW'), findsNothing);
        expect(
          tester.getTopLeft(find.byType(GridView)).dy,
          scale == 1 ? 153 : 196,
        );
        await tester.pumpWidget(const SizedBox());
        expect(channel.isObserved, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'live shading updates without rebuilding cells; resize keeps focus, scroll and surface state',
    (tester) async {
      final channel = ObservedValue<IptvChannel?>(null);
      final node = FocusNode();
      addTearDown(channel.dispose);
      addTearDown(node.dispose);
      final built = <int>[];
      final initialized = <String>[];
      Widget page({double width = 800, String rail = 'first'}) => _page(
        channel,
        width: width,
        rail: rail,
        node: node,
        built: built,
        live: _Live(initialized: initialized),
      );
      await tester.pumpWidget(page());
      final stack = tester
          .widgetList<Stack>(find.byType(Stack))
          .singleWhere((s) => s.children.first.key == const ValueKey('art'));
      expect(stack.children[2], isA<_Live>());
      expect(_colors(tester), contains(const Color(0xDE0D0B1A)));
      expect(_colors(tester), isNot(contains(const Color(0x8C0D0B1A))));
      final builtBefore = List<int>.of(built);
      channel.value = IptvChannel(
        name: 'Live',
        url: 'https://example.invalid/live',
      );
      await tester.pump();
      expect(built, builtBefore);
      expect(
        _colors(tester),
        containsAll([const Color(0x9E0D0B1A), const Color(0x8C0D0B1A)]),
      );
      expect(_colors(tester), isNot(contains(const Color(0xDE0D0B1A))));
      node.requestFocus();
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(80);
      await tester.pump();
      await tester.pumpWidget(page(width: 700));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        same(scroll),
      );
      expect(scroll.position.pixels, 80);
      expect(node.hasFocus, isTrue);
      expect(initialized, ['live']);
      await tester.pumpWidget(page(width: 700, rail: 'second'));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        isNot(same(scroll)),
      );
      expect(initialized, ['live']);
      await tester.pumpWidget(const SizedBox());
      expect(channel.isObserved, isFalse);
      // Borrowed signal remains usable after the layout releases its listeners.
      channel.value = null;
      expect(tester.takeException(), isNull);
    },
  );
}

Iterable<Color?> _colors(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((box) => (box.decoration as BoxDecoration).color);

Widget _page(
  ValueNotifier<IptvChannel?> channel, {
  double width = 800,
  double scale = 1,
  bool showHint = true,
  String rail = 'first',
  FocusNode? node,
  List<int>? built,
  Widget? live,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 600,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Builder(
          builder: (context) => buildHomeMosaicLayout(
            context: context,
            geometry: HomeMosaicGeometry(
              boardW: width,
              boardH: 600,
              cellAspect: 2 / 3,
              captionBandHeight: 0,
            ),
            railKey: rail,
            itemCount: 100,
            artwork: const SizedBox.expand(key: ValueKey('art')),
            liveSurface: live,
            liveChannel: channel,
            identity: const SizedBox(),
            railLabel: const SizedBox(height: 27),
            showRailHint: showHint,
            hintColor: Colors.white,
            itemBuilder: (_, index) {
              built?.add(index);
              return index == 0
                  ? Focus(focusNode: node, child: const SizedBox.expand())
                  : const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  ),
);

class _Live extends StatefulWidget {
  const _Live({required this.initialized});
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
