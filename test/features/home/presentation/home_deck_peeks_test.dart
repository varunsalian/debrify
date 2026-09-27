import 'dart:convert';
import 'dart:io' as io;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/home/presentation/home_deck_peeks.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../home_mdblist_continuation_screen_test.dart' show FixtureImages;

void main() {
  late io.Directory images;
  setUpAll(() async {
    images = await io.Directory.systemTemp.createTemp('home_deck_peeks_');
    final file = await io.File('${images.path}/image.png').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ),
    );
    CachedNetworkImageProvider.defaultCacheManager = FixtureImages(file);
  });
  tearDownAll(() => images.delete(recursive: true));

  testWidgets(
    'Deck paints the far preview first with bounded decode and original transforms',
    (tester) async {
      await tester.pumpWidget(_host(_items()));
      final cards = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .toList();
      expect(cards.map((c) => c.imageUrl), [
        'https://art.invalid/2',
        'https://art.invalid/1',
      ]);
      expect(cards.map((c) => c.key), [
        const ValueKey('deck-peek-2-https://art.invalid/2'),
        const ValueKey('deck-peek-1-https://art.invalid/1'),
      ]);
      for (final card in cards) {
        expect(card.memCacheWidth, 480);
        expect(card.fit, BoxFit.cover);
        expect(card.fadeInDuration, Duration.zero);
        expect(card.fadeOutDuration, Duration.zero);
      }
      expect(
        tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .map((w) => w.opacity),
        [.30, .52],
      );
      expect(
        tester
            .widgetList<AnimatedSlide>(find.byType(AnimatedSlide))
            .map((w) => w.offset),
        [const Offset(.19, 0), const Offset(.10, 0)],
      );
      for (final slide in tester.widgetList<AnimatedSlide>(
        find.byType(AnimatedSlide),
      )) {
        expect(slide.duration, const Duration(milliseconds: 260));
        expect(slide.curve, Curves.easeOutCubic);
      }
      final transforms = tester
          .widgetList<Transform>(find.byType(Transform))
          .where((w) => w.child is ClipRRect)
          .toList();
      expect(transforms.map((w) => w.transform.entry(0, 0)), [.87, .94]);
      for (final positioned in tester.widgetList<Positioned>(
        find.byType(Positioned),
      )) {
        expect(positioned.left, 100);
        expect(positioned.top, 40);
        expect(positioned.width, 320);
        expect(positioned.height, 180);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deck bounds focus, skips missing art and never searches past the next two titles',
    (tester) async {
      final items = [
        _item('current'),
        _item('missing'),
        _item('poster', poster: 'https://art.invalid/poster'),
        _item('later', background: 'https://art.invalid/later'),
      ];
      await tester.pumpWidget(_host(items, focused: -5));
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        'https://art.invalid/poster',
      );
      await tester.pumpWidget(_host(items, focused: 1));
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((w) => w.imageUrl),
        ['https://art.invalid/later', 'https://art.invalid/poster'],
      );
      await tester.pumpWidget(_host(items, focused: 99));
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(_host(items, favourite: true));
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(_host([]));
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus updates only preview content and preview artwork cannot intercept taps',
    (tester) async {
      final focus = ValueNotifier(0);
      addTearDown(focus.dispose);
      var backgroundBuilds = 0;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Builder(
                builder: (_) {
                  backgroundBuilds++;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(),
                  );
                },
              ),
              ValueListenableBuilder<int>(
                valueListenable: focus,
                builder: (_, value, _) =>
                    Stack(children: _peeks(_items(), focused: value)),
              ),
            ],
          ),
        ),
      );
      final before = backgroundBuilds;
      focus.value = 1;
      await tester.pump();
      expect(backgroundBuilds, before);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((w) => w.imageUrl),
        ['https://art.invalid/3', 'https://art.invalid/2'],
      );
      await tester.tapAt(const Offset(300, 120));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

List<StremioMeta> _items() =>
    List.generate(4, (i) => _item('$i', background: 'https://art.invalid/$i'));
StremioMeta _item(String id, {String? background, String? poster}) =>
    StremioMeta(
      id: id,
      type: 'movie',
      name: id,
      background: background,
      poster: poster,
    );
List<Widget> _peeks(
  List<StremioMeta> items, {
  int focused = 0,
  bool favourite = false,
}) => buildHomeDeckPeeks(
  items: items,
  favRail: favourite,
  focused: focused,
  left: 100,
  top: 40,
  width: 320,
  height: 180,
);
Widget _host(
  List<StremioMeta> items, {
  int focused = 0,
  bool favourite = false,
}) => MaterialApp(
  home: Stack(
    children: _peeks(items, focused: focused, favourite: favourite),
  ),
);
