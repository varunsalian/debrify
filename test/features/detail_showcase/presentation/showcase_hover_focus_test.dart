import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

Finder privateType(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

void main() {
  for (final type in [
    '_SourceCard',
    '_GuideCard',
    '_Poster',
    '_UniverseCard',
    '_DykCard',
    '_DykMoreCard',
  ]) {
    testWidgets('hover and focus share the $type lift without pointer focus', (
      t,
    ) async {
      await showcaseCase(t, (f) async {
        final node = f.node(type);
        final child = switch (type) {
          '_SourceCard' => ShowcaseSources(
            sources: const [],
            nodes: [node, f.node('add')],
            onOpen: () {},
          ),
          '_GuideCard' => ShowcaseGuide(
            guide: showcaseGuide(),
            nodes: [node, ...f.nodes(2, 'guide')],
            accent: Colors.yellow,
          ),
          '_Poster' => ShowcaseRecs(
            items: const [
              StremioMeta(id: 'tt-rec', type: 'movie', name: 'Original rec'),
            ],
            nodes: [node],
            onTap: (_) {},
          ),
          '_UniverseCard' => ShowcaseUniverse(
            items: const [
              UniverseTitle(
                imdbId: 'tt-u',
                name: 'Original universe',
                relation: 'Related',
                year: 2026,
              ),
            ],
            nodes: [node],
            onOpen: (_) {},
          ),
          _ => ShowcaseDidYouKnow(
            entries: const [
              DidYouKnowEntry(kind: 'Trivia', text: 'Original fact'),
            ],
            total: 2,
            countLine: null,
            nodes: type == '_DykCard'
                ? [node, f.node('more')]
                : [f.node('fact'), node],
          ),
        };
        await t.pumpWidget(f.host(child));
        await showcasePump(t);
        final card = privateType(type).first;
        final lift = find.descendant(
          of: card,
          matching: find.byType(ParallaxFocus),
        );
        expect(lift, findsOneWidget);
        bool lit() => t.widget<ParallaxFocus>(lift).focused;
        expect(lit(), isFalse);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(950, 530));
        await mouse.moveTo(t.getCenter(lift));
        await t.pump();
        expect(lit(), isTrue);
        expect(node.hasFocus, isFalse);
        await mouse.moveTo(const Offset(950, 530));
        await t.pump();
        expect(lit(), isFalse);
        node.requestFocus();
        await showcasePump(t);
        expect(lit(), isTrue);
        await mouse.removePointer();
      });
    });
  }

  for (final television in [false, true]) {
    testWidgets('Hover gates MouseRegion on television $television', (t) async {
      await showcaseCase(t, (f) async {
        await t.pumpWidget(
          f.host(
            ShowcaseCast(
              cast: const [CastMember(name: 'Actor')],
              nodes: f.nodes(1, 'cast'),
            ),
          ),
        );
        await showcasePump(t);
        final hover = privateType('_Hover');
        expect(hover, findsOneWidget);
        expect(
          find.descendant(of: hover, matching: find.byType(MouseRegion)),
          television ? findsNothing : findsOneWidget,
        );
      }, television: television);
    });
  }

  testWidgets('hover and focus share the cast lift; hovering does not focus', (
    t,
  ) async {
    await showcaseCase(t, (f) async {
      final nodes = f.nodes(1, 'cast');
      await t.pumpWidget(
        f.host(
          ShowcaseCast(
            cast: const [CastMember(name: 'Actor')],
            nodes: nodes,
          ),
        ),
      );
      await showcasePump(t);
      bool lit() => t.widget<ParallaxFocus>(find.byType(ParallaxFocus)).focused;
      expect(lit(), isFalse);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(950, 530));
      await mouse.moveTo(t.getCenter(find.byType(ClipOval)));
      await t.pump();
      expect(lit(), isTrue);
      expect(nodes.single.hasFocus, isFalse);
      await mouse.moveTo(const Offset(950, 530));
      await t.pump();
      expect(lit(), isFalse);
      nodes.single.requestFocus();
      await showcasePump(t);
      expect(lit(), isTrue);
      await mouse.removePointer();
    });
  });

  testWidgets('rail focus scrolls only the nearest horizontal rail', (t) async {
    await showcaseCase(t, (f) async {
      final nodes = f.nodes(8, 'cast');
      await t.pumpWidget(
        f.host(
          SingleChildScrollView(
            controller: f.scroll,
            child: Column(
              children: [
                const SizedBox(height: 250),
                ShowcaseCast(
                  cast: [
                    for (var i = 0; i < 8; i++) CastMember(name: 'Actor $i'),
                  ],
                  nodes: nodes,
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      await showcasePump(t);
      final rail = t.state<ScrollableState>(
        find.descendant(
          of: find.byType(ShowcaseCast),
          matching: find.byType(Scrollable),
        ),
      );
      expect(rail.position.pixels, 0);
      expect(nodes[6].context, isNotNull);
      nodes[6].requestFocus();
      await showcasePump(t);
      expect(rail.position.pixels, greaterThan(0));
      expect(f.scroll.offset, 0);
    });
  });

  testWidgets(
    'identity circles retain their MouseRegion on TV and never scroll the page',
    (t) async {
      await showcaseCase(t, (f) async {
        await t.pumpWidget(
          f.host(
            SingleChildScrollView(
              controller: f.scroll,
              child: Column(
                children: [
                  f.identity(height: 640),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        );
        await showcasePump(t);
        expect(
          find.descendant(
            of: privateType('_Circle'),
            matching: find.byType(MouseRegion),
          ),
          findsOneWidget,
        );
        f.actions.first.requestFocus();
        await showcasePump(t);
        expect(f.scroll.offset, 0);
      }, television: true);
    },
  );
}
