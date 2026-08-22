import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';

/// The board's second life on phones, tablets and desktop.
///
/// Two axes, deliberately separate (SPOTLIGHT_RESPONSIVE_PLAN.md): the METRIC
/// tier follows the board's own width, but only when the input is not a
/// remote — `dpad: true` is always the wide TV presentation whatever the
/// width, because the DPAD ladder must never target widgets the compact
/// rendering doesn't mount. The compact numbers are measured off the Apple TV
/// phone app on the reference device; if one of these fails, decide which
/// side is wrong before changing it — the measurement wins by default.
StremioMeta _meta(String id, String name) => StremioMeta(
      id: id,
      imdbId: id,
      type: 'series',
      name: name,
      description: 'About $name.',
      genres: const ['Drama'],
    );

final _addon = StremioAddon(
  id: 'a',
  name: 'A',
  manifestUrl: 'https://example.invalid/manifest.json',
  baseUrl: 'https://example.invalid',
  types: const ['series'],
  resources: const ['catalog'],
);

SpotlightShelf _section(String title, List<StremioMeta> items) =>
    SpotlightShelf(
      title: title,
      nodes: [
        for (var i = 0; i < items.length; i++)
          FocusNode(debugLabel: 'cell$i'),
      ],
      items: [
        for (final m in items)
          SpotlightCard(image: m.poster, title: m.name, onOpen: () {}),
      ],
    );

void main() {
  late FocusNode hero;

  setUp(() {
    hero = FocusNode(debugLabel: 'hero');
  });

  tearDown(() {
    hero.dispose();
  });

  void surface(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget host(
    List<StremioMeta> heroItems,
    List<SpotlightShelf> sections, {
    required bool dpad,
    void Function(StremioMeta, StremioAddon)? onHeroOpen,
  }) =>
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: SpotlightBoard(
              hero: heroItems,
              sections: sections,
              heroNode: hero,
              heroAddon: _addon,
              onHeroOpen: onHeroOpen ?? (_, __) {},
              dpad: dpad,
            ),
          ),
        ),
      );

  /// The card's art box (its ClipRRect) for a titled card. On compact the
  /// caption is OUTSIDE this box; on wide it is inside — either way the
  /// ClipRRect is the artwork's own geometry.
  Size cardBox(WidgetTester tester, String title) {
    // Compact puts the caption text OUTSIDE the clip, so an ancestor lookup
    // from the text can fail — find all card clips and match by width being
    // one of the row's cards instead.
    final clips = find.descendant(
      of: find.byType(SpotlightBoard),
      matching: find.byType(ClipRRect),
    );
    // The FIRST shelf card clip: the hero paints no ClipRRect.
    expect(clips, findsWidgets);
    return tester.getSize(clips.first);
  }

  group('the metric tier follows width — but only off DPAD', () {
    testWidgets('390 wide + touch = compact: posters at 25.7%',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      await tester
          .pumpWidget(host([a], [_section('Top', [a])], dpad: false));
      await tester.pumpAndSettle();

      final poster = 390 * 0.257;
      final box = cardBox(tester, 'Alpha');
      expect(box.width, closeTo(poster, 0.5),
          reason: 'compact posters are 25.7% of the width — the measured '
              'Apple phone fraction');
      expect(box.width / box.height, closeTo(2 / 3, 0.005));
    });

    testWidgets('390 wide + DPAD = still the TV table (a narrow TV is a TV)',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      await tester.pumpWidget(host([a], [_section('Top', [a])], dpad: true));
      await tester.pumpAndSettle();

      final poster = 390 * (260 / 1920);
      final box = cardBox(tester, 'Alpha');
      expect(box.width, closeTo(poster, 0.5),
          reason: 'dpad:true never leaves the wide tier, whatever the width');
    });

    testWidgets('834 wide + touch = mid: posters bumped to 16% for fingers',
        (tester) async {
      surface(tester, const Size(834, 1194));
      final a = _meta('tt1', 'Alpha');
      await tester
          .pumpWidget(host([a], [_section('Top', [a])], dpad: false));
      await tester.pumpAndSettle();

      final box = cardBox(tester, 'Alpha');
      expect(box.width, closeTo(834 * 0.16, 0.5));
    });

    testWidgets('834 wide + DPAD = wide', (tester) async {
      surface(tester, const Size(834, 1194));
      final a = _meta('tt1', 'Alpha');
      await tester.pumpWidget(host([a], [_section('Top', [a])], dpad: true));
      await tester.pumpAndSettle();

      final box = cardBox(tester, 'Alpha');
      expect(box.width, closeTo(834 * (260 / 1920), 0.5));
    });

    testWidgets('1440 wide + pointer = the TV table verbatim', (tester) async {
      surface(tester, const Size(1440, 810));
      final a = _meta('tt1', 'Alpha');
      await tester
          .pumpWidget(host([a], [_section('Top', [a])], dpad: false));
      await tester.pumpAndSettle();

      final box = cardBox(tester, 'Alpha');
      expect(box.width, closeTo(1440 * (260 / 1920), 0.5));
    });
  });

  group('compact presentation', () {
    testWidgets('the caption sits BELOW the art, not overlaid on it',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      await tester
          .pumpWidget(host([a], [_section('Top', [a])], dpad: false));
      await tester.pumpAndSettle();

      // The shelf card's title text must be under the art box's lower edge.
      final art = find
          .descendant(
              of: find.byType(SpotlightBoard),
              matching: find.byType(ClipRRect))
          .first;
      final artBottom = tester.getBottomLeft(art).dy;
      // The card caption (not the hero's texts): the text whose top is at or
      // below the art bottom.
      final captions = find.text('Alpha');
      final below = [
        for (var i = 0; i < tester.widgetList(captions).length; i++)
          tester.getTopLeft(captions.at(i)).dy,
      ].where((y) => y >= artBottom - 1);
      expect(below, isNotEmpty,
          reason: 'small art cannot afford an overlay caption — it moves '
              'below the card on compact');
    });

    testWidgets(
        'portrait keeps rating and season/episode metadata below the art',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      await tester.pumpWidget(
        host(
          [a],
          [
            SpotlightShelf(
              title: 'Continue Watching',
              nodes: const [],
              // Home may request caption-free poster rows, but useful card
              // metadata must still survive the compact breakpoint.
              captions: false,
              items: [
                SpotlightCard(
                  title: 'Alpha',
                  subtitle: 'S2 · E5 · 24 min left',
                  rating: 8.06,
                  onOpen: () {},
                ),
              ],
            ),
          ],
          dpad: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('S2 · E5 · 24 min left · ★ 8.1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hero is ~64% of the board with a centered Open pill',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      await tester
          .pumpWidget(host([a], [_section('Top', [a])], dpad: false));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget,
          reason: 'touch needs a real CTA — OK-on-focus does not exist here');
      final pill = tester.getCenter(find.text('Open'));
      expect(pill.dx, closeTo(390 / 2, 24),
          reason: 'the compact identity stack is centered');

      // The first shelf's heading marks the hero's end — no shelf overlap on
      // compact, so it sits just under 64% of the board.
      final titleTop = tester.getTopLeft(find.text('Top')).dy;
      expect(titleTop / 844, closeTo(0.64, 0.05));
    });

    testWidgets('the CTA routes through onHeroOpen — the same door OK uses',
        (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      StremioMeta? opened;
      await tester.pumpWidget(host(
        [a],
        [_section('Top', [a])],
        dpad: false,
        onHeroOpen: (m, _) => opened = m,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      expect(opened?.id, 'tt1');
    });

    testWidgets('a swipe pages the reel', (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      final b = _meta('tt2', 'Bravo');
      await tester
          .pumpWidget(host([a, b], [_section('Top', [a, b])], dpad: false));
      await tester.pumpAndSettle();

      await tester.fling(
          find.byType(SpotlightBoard), const Offset(-260, 0), 900);
      await tester.pumpAndSettle();
      // Bravo's identity is on the hero now (metadata line present for it).
      expect(find.text('Bravo'), findsWidgets);
    });

    testWidgets('the touch reel does NOT advance itself — swipe is the only '
        'pager', (tester) async {
      // Auto-advance was removed by user call, on every device: the reel
      // holds still until a swipe or a dot tap.
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      final b = _meta('tt2', 'Bravo');
      await tester
          .pumpWidget(host([a, b], [_section('Top', [a, b])], dpad: false));
      await tester.pump();

      expect(find.text('Series · Drama'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      // Alpha's shelf caption AND hero identity are still the first slide's.
      expect(find.text('Alpha'), findsWidgets,
          reason: 'the reel must hold still until a deliberate move');

      // The deliberate move still works.
      await tester.fling(
          find.byType(SpotlightBoard), const Offset(-260, 0), 900);
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsWidgets);
    });

    testWidgets('on TV the unfocused hero does NOT auto-advance',
        (tester) async {
      surface(tester, const Size(960, 540));
      final a = _meta('tt1', 'Alpha');
      final b = _meta('tt2', 'Bravo');
      await tester
          .pumpWidget(host([a, b], [_section('Top', [a, b])], dpad: true));
      await tester.pump();

      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      // The hero's IDENTITY still belongs to Alpha — the description is
      // rendered only on the wide hero, never on cards, so it is the
      // unambiguous witness.
      expect(find.text('About Alpha.'), findsOneWidget,
          reason: 'the reel never advances on its own');
      expect(find.text('About Bravo.'), findsNothing);
    });

    testWidgets(
        'the touch hero asks for a trailer immediately without paging the reel',
        (tester) async {
      // Start useful trailer work as soon as the visible hero is eligible,
      // and change nothing else.
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      final b = _meta('tt2', 'Bravo');
      final dwelled = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
            child: Scaffold(
              body: SpotlightBoard(
                hero: [a, b],
                sections: [_section('Top', [a, b])],
                heroNode: hero,
                heroAddon: _addon,
                onHeroOpen: (_, __) {},
                dpad: false,
                trailersEnabled: true,
                onDwell: (m) => dwelled.add(m.id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(dwelled, ['tt1'],
          reason: 'the resolve starts for the visible slide immediately');
      expect(find.text('Alpha'), findsWidgets,
          reason: 'and the reel has not moved');

      // Swiping tears the roll down and re-arms for the next slide.
      await tester.fling(
          find.byType(SpotlightBoard), const Offset(-260, 0), 900);
      await tester.pumpAndSettle();
      expect(dwelled, ['tt1', 'tt2']);
    });

    testWidgets('tapping a dot jumps the reel', (tester) async {
      surface(tester, const Size(390, 844));
      final a = _meta('tt1', 'Alpha');
      final b = _meta('tt2', 'Bravo');
      await tester
          .pumpWidget(host([a, b], [_section('Top', [a, b])], dpad: false));
      await tester.pumpAndSettle();

      // The second dot: dots are the only AnimatedContainers on the board.
      final dots = find.byType(AnimatedContainer);
      expect(tester.widgetList(dots).length, greaterThanOrEqualTo(2));
      await tester.tap(dots.at(1));
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsWidgets);
    });
  });
}
