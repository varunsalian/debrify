import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';

/// Spotlight's hero, which is the piece that changes Home's focus topology
/// rather than its paint.
///
/// The properties worth pinning are the ones that are wrong by default: the
/// hero must **park by item id** (the reel re-orders as tracker data lands, so
/// an index points at a different title), and LEFT at column 0 must **fall
/// through** rather than be swallowed, because falling through is the only way
/// the sidebar ever opens.
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

SpotlightShelf _section(String title, List<StremioMeta> items,
        {List<FocusNode>? nodes}) =>
    SpotlightShelf(
      title: title,
      nodes: nodes ?? _rowNodes(items.length),
      items: [
        for (final m in items)
          SpotlightCard(image: m.poster, title: m.name, onOpen: () {}),
      ],
    );

List<FocusNode> _rowNodes(int n) =>
    [for (var i = 0; i < n; i++) FocusNode(debugLabel: 'cell$i')];

void _noop() {}

void main() {
  late FocusNode hero;
  late List<List<FocusNode>> rows;

  setUp(() {
    hero = FocusNode(debugLabel: 'hero');
    rows = [
      [FocusNode(debugLabel: 'r0c0'), FocusNode(debugLabel: 'r0c1')],
    ];
  });

  tearDown(() {
    hero.dispose();
    for (final r in rows) {
      for (final n in r) {
        n.dispose();
      }
    }
  });

  Widget host(List<StremioMeta> heroItems, List<SpotlightShelf> sections) =>
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: SpotlightBoard(
              hero: heroItems,
              sections: sections,
              heroNode: hero,
              heroAddon: _addon,
              onHeroOpen: (_, __) {},
            ),
          ),
        ),
      );

  testWidgets('the hero parks by ITEM ID across a reel re-order',
      (tester) async {
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    final c = _meta('tt3', 'Charlie');

    await tester.pumpWidget(host([a, b, c], [_section('Top', [a, b, c])]));
    await tester.pumpAndSettle();

    // Page to Bravo.
    hero.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Bravo'), findsWidgets);

    // The reel re-orders — exactly what happens when tracker rows arrive and
    // shift the sections. An index would now point at Charlie.
    await tester.pumpWidget(host([c, a, b], [_section('Top', [c, a, b])]));
    await tester.pumpAndSettle();
    expect(find.text('Bravo'), findsWidgets,
        reason: 'the parked title must survive the re-order');
  });

  testWidgets('a dropped hero item falls back to the head, not a stale index',
      (tester) async {
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    await tester.pumpWidget(host([a, b], [_section('Top', [a, b])]));
    await tester.pumpAndSettle();
    hero.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Bravo disappears from the catalog entirely.
    await tester.pumpWidget(host([a], [_section('Top', [a])]));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsWidgets);
  });

  testWidgets('LEFT at column 0 falls through — the sidebar is the only way out',
      (tester) async {
    final a = _meta('tt1', 'Alpha');
    var sawLeft = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Focus(
            // Stands in for the shell's directional handler, which is what
            // actually opens the sidebar. If the board swallowed LEFT this
            // would never fire and the sidebar would be unreachable.
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                sawLeft = true;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              body: SpotlightBoard(
                hero: [a],
                sections: [_section('Top', [a], nodes: rows[0])],
                heroNode: hero,
                heroAddon: _addon,
                onHeroOpen: (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    rows[0][0].requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(sawLeft, isTrue);
  });

  testWidgets('the reel NEVER advances on its own — only a deliberate move '
      'pages it', (tester) async {
    // This pins the removal of auto-advance (user call, every device): the
    // reel used to page itself after the art dwell when trailers were off,
    // and a carousel that moves under you takes the choice away. The cadence
    // timer's one remaining job is the trailer dwell.
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    await tester.pumpWidget(host([a, b], [_section('Top', [a, b])]));
    await tester.pumpAndSettle();
    expect(find.text('About Alpha.'), findsOneWidget);

    // Unfocused: parked.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('About Alpha.'), findsOneWidget);

    // FOCUSED and idle: still parked — this is the behaviour that changed.
    hero.requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('About Alpha.'), findsOneWidget,
        reason: 'the reel must hold still until a deliberate move');
    expect(find.text('About Bravo.'), findsNothing);

    // A deliberate move still pages it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('About Bravo.'), findsOneWidget);
  });

  testWidgets('the TV dwell asks for a trailer without paging, and re-arms '
      'after a deliberate move', (tester) async {
    // The cadence's one remaining job on TV: focus rests on the hero, the
    // art dwell elapses, the host is told — and the reel does NOT move.
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
              trailersEnabled: true,
              onDwell: (m) => dwelled.add(m.id),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unfocused: no dwell — the clock is armed by hero focus.
    await tester.pump(const Duration(seconds: 5));
    expect(dwelled, isEmpty);

    hero.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(dwelled, ['tt1'], reason: 'focused: one dwell after the art rest');
    expect(find.text('About Alpha.'), findsOneWidget,
        reason: 'and the reel has not paged');

    // RIGHT pages, tears the roll down, and re-arms for the new slide.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('About Bravo.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(dwelled, ['tt1', 'tt2']);
  });

  testWidgets('a shrinking board does not strand the cursor past the end',
      (tester) async {
    // A board reload can shrink or reorder the shelves under a parked cursor.
    // `_row` is positional, so an unclamped one indexes past the end of
    // rowNodes on the next arrow key and throws.
    final a = _meta('tt1', 'Alpha');
    rows = [
      [FocusNode(debugLabel: 'r0c0')],
      [FocusNode(debugLabel: 'r1c0')],
    ];
    await tester.pumpWidget(host([a], [
      _section('One', [a], nodes: rows[0]),
      _section('Two', [a], nodes: rows[1]),
    ]));
    await tester.pumpAndSettle();

    hero.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // The second shelf goes away.
    rows = [
      [FocusNode(debugLabel: 'r0c0')],
    ];
    await tester.pumpWidget(host([a], [_section('One', [a], nodes: rows[0])]));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Continue Watching shelf draws progress; a catalog one does not',
      (tester) async {
    // The whole point of the shelf descriptor: the board renders progress
    // without knowing what Continue Watching IS. A shelf that returns null for
    // every item simply draws no bars.
    final a = _meta('tt1', 'Alpha');
    await tester.pumpWidget(host([a], [
      SpotlightShelf(
        title: 'Continue Watching',
        nodes: _rowNodes(1),
        items: [
          SpotlightCard(
            image: a.poster,
            title: a.name,
            progress: 40,
            onOpen: () {},
          ),
        ],
      ),
      _section('Popular', [a]),
    ]));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a rolling trailer stops the reel — it must not cut away',
      (tester) async {
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    var dwelt = 0;
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
              trailersEnabled: true,
              onDwell: (_) => dwelt++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hero.requestFocus();
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(dwelt, 1, reason: 'the dwell must start a trailer');

    // Long past any cap: cutting away from something the user is watching to
    // show the next poster is the opposite of what the dwell is for.
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsWidgets,
        reason: 'a rolling trailer must hold the reel');
  });

  testWidgets('LEFT from mid-row is consumed, not leaked to the shell',
      (tester) async {
    // The bug: `_col` drifting from real focus made LEFT fall through while
    // the cursor sat mid-row. The shell then ran a geometric search and jumped
    // to another row, which is what made the sidebar hard to reach.
    final a = _meta('tt1', 'Alpha');
    var leaked = 0;
    rows = [
      [FocusNode(debugLabel: 'c0'), FocusNode(debugLabel: 'c1')],
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Focus(
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                leaked++;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              body: SpotlightBoard(
                hero: [a],
                sections: [
                  _section('Top', [a, _meta('tt2', 'Bravo')], nodes: rows[0]),
                ],
                heroNode: hero,
                heroAddon: _addon,
                onHeroOpen: (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Focus the SECOND cell directly, without going through _walk — exactly
    // the drift that used to break this.
    rows[0][1].requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(leaked, 0, reason: 'mid-row LEFT belongs to the row');

    // At column 0 it must fall through, or the sidebar is unreachable.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(leaked, 1);
  });

  testWidgets('the trailer layer follows the HOST, not the board\'s own flag',
      (tester) async {
    // The crash this pins: gating the trailer widget on the board's `_rolling`
    // kept a media_kit engine mounted after the host had torn the trailer down
    // for playback. Two VideoOutputs is SIGABRT on tvOS.
    //
    // So: supplied by the host means mounted; withdrawn means gone. The
    // board's cadence state must not appear in that decision.
    final a = _meta('tt1', 'Alpha');
    const marker = Key('trailer-layer');

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: SpotlightBoard(
              hero: [a],
              sections: [_section('Top', [a])],
              heroNode: hero,
              heroAddon: _addon,
              onHeroOpen: (_, __) {},
              trailer: const SizedBox(key: marker),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Mounted immediately — no dwell, no rolling state.
    expect(find.byKey(marker), findsOneWidget);

    // Withdrawn by the host: gone at once, engine released.
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: SpotlightBoard(
              hero: [a],
              sections: [_section('Top', [a])],
              heroNode: hero,
              heroAddon: _addon,
              onHeroOpen: (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(marker), findsNothing);
  });

  testWidgets('a channel tile CONTAINS its logo; a poster fills', (tester) async {
    // The reason the card model generalised at all: a channel logo is a wide,
    // often transparent mark. A 2:3 crop cuts the wordmark in half, so channel
    // cards are square and contain their art on a plate.
    final a = _meta('tt1', 'Alpha');
    await tester.pumpWidget(host([a], [
      SpotlightShelf(
        title: 'IPTV Favourites',
        nodes: _rowNodes(1),
        items: const [
          SpotlightCard(
            title: 'A Channel',
            subtitle: 'LIVE',
            shape: SpotlightCardShape.channel,
            onOpen: _noop,
          ),
        ],
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('A Channel'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(SpotlightCardShape.channel.fit, BoxFit.contain);
    expect(SpotlightCardShape.poster.fit, BoxFit.cover);
    // Square, so the mark is not cropped to a portrait slot.
    expect(SpotlightCardShape.channel.aspect, 1);
  });

  testWidgets('a single-item reel shows no dots', (tester) async {
    final a = _meta('tt1', 'Alpha');
    await tester.pumpWidget(host([a], [_section('Top', [a])]));
    await tester.pumpAndSettle();
    // One page is not a carousel; dots there are chrome that says nothing.
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  testWidgets('the card draws at the poster ratio, not the row viewport\'s',
      (tester) async {
    // The bug this pins: the row reserved the lift by making its own viewport
    // `posterH * 1.10 + 24` tall. A horizontal ListView constrains children to
    // the viewport height TIGHTLY, so every card was stretched to that while
    // its width was still derived from `posterH` — a 2:3 poster drawn at
    // 0.53:1, about 26% too tall. It was reported three times as "the cards
    // are too big" and twice mis-diagnosed as the 260×390 ratio being wrong.
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    await tester.pumpWidget(host([a], [_section('Top', [a, b])]));
    await tester.pumpAndSettle();

    final board = tester.getSize(find.byType(SpotlightBoard)).width;
    final posterH = board * (260 / 1920) * (390 / 260);

    // The caption lives inside the card, so its enclosing ClipRRect IS the
    // card box.
    final box = tester
        .getSize(find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(ClipRRect),
        ).first);

    expect(box.height, closeTo(posterH, 0.5),
        reason: 'the card must be its own height, not the viewport\'s');
    expect(box.width / box.height, closeTo(2 / 3, 0.005),
        reason: 'a poster is 2:3 — anything else means it was stretched');
  });

  testWidgets('LEFT on the FIRST hero slide falls through to the sidebar',
      (tester) async {
    // The reel used to wrap modulo its length, so LEFT at slide 0 jumped to
    // the last slide. Since LEFT is the only gesture that opens the sidebar,
    // that made the hero a loop with no way out.
    final a = _meta('tt1', 'Alpha');
    final b = _meta('tt2', 'Bravo');
    var sawLeft = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Focus(
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                sawLeft = true;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              body: SpotlightBoard(
                hero: [a, b],
                sections: [_section('Top', [a, b])],
                heroNode: hero,
                heroAddon: _addon,
                onHeroOpen: (_, __) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    hero.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sawLeft, isTrue, reason: 'the shell must get the key');
    expect(find.text('Alpha'), findsWidgets,
        reason: 'and the reel must not have paged anywhere');

    // RIGHT then LEFT still walks the reel — only the first slide falls out.
    sawLeft = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sawLeft, isFalse);
    expect(find.text('Alpha'), findsWidgets);
  });

  testWidgets('the hero is a FRACTION of the board, not a pixel count',
      (tester) async {
    // `_heroHeight` was 540 logical pixels flat. Logical size differs per
    // device, so that one constant made the hero ~89% of the screen on an
    // Android TV box and ~40% on an Apple TV — and on the latter the trailer
    // played in a slot half its intended height, which is why `cover` threw
    // away half the frame.
    //
    // Measured through the first shelf's title, which sits directly under the
    // hero: its offset as a SHARE of the board is the hero's share, and that
    // share must not move when the panel does.
    final a = _meta('tt1', 'Alpha');
    addTearDown(tester.view.reset);

    Future<double> heroShare(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(host([a], [_section('Shelf', [a])]));
      await tester.pumpAndSettle();
      final board = tester.getSize(find.byType(SpotlightBoard)).height;
      final titleTop = tester.getTopLeft(find.text('Shelf')).dy;
      return titleTop / board;
    }

    final short = await heroShare(const Size(1280, 720));
    final tall = await heroShare(const Size(1280, 1440));
    expect(tall, closeTo(short, 0.03),
        reason: 'the hero must occupy the same share of every panel');
    // And the artwork must reach the bottom of the screen, with the shelf over
    // it — the first shelf title sits inside the hero's lower portion, not
    // below its end. A share of 1.0 would mean the cards start off-screen; the
    // overlap is what brings them up onto the art.
    expect(short, greaterThan(0.6));
    expect(short, lessThan(0.92),
        reason: 'the first shelf must ride ON the artwork, not sit under it');
  });

  testWidgets('a card is never the same colour as the page it sits on',
      (tester) async {
    // The channel plate used to DARKEN off the ground, to give light-on-
    // transparent logos a dark backing. On a black ground that is degenerate —
    // `lerp(black, black)` is black — and an entire row of channels went
    // invisible while still being painted. Any ground the theme can produce
    // must leave a card distinguishable from the page.
    final a = _meta('tt1', 'Alpha');
    await tester.pumpWidget(host([a], [
      SpotlightShelf(
        title: 'Channels',
        nodes: _rowNodes(1),
        items: [
          SpotlightCard(
            title: 'CH 1',
            onOpen: () {},
            shape: SpotlightCardShape.channel,
          ),
        ],
      ),
    ]));
    await tester.pumpAndSettle();

    final ground = SpotlightBoard.groundOf(
      AppTheme.fromDetail(DetailThemes.byId('signal')),
    );
    final plate = tester
        .widgetList<ColoredBox>(find.descendant(
          of: find.byType(ClipRRect),
          matching: find.byType(ColoredBox),
        ))
        .first;
    expect(plate.color, isNot(ground),
        reason: 'a card the colour of the page is an invisible card');
  });
}
