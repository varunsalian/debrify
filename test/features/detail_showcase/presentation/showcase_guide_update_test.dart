import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

void main() {
  testWidgets('same guide retains selected category and wide spoiler reveal', (
    t,
  ) async {
    await showcaseCase(t, (f) async {
      final g = showcaseGuide();
      final nodes = f.nodes(3, 'guide');
      Widget host() =>
          f.host(ShowcaseGuide(guide: g, nodes: nodes, accent: Colors.yellow));
      await t.pumpWidget(host());
      await showcasePump(t);
      nodes[2].requestFocus();
      await showcasePump(t);
      expect(find.text('Plain 2'), findsOneWidget);
      await t.tap(find.text('SHOW'));
      await t.pump();
      expect(find.text('Spoiler 2'), findsOneWidget);
      await t.pumpWidget(host());
      await t.pump();
      expect(find.text('Plain 2'), findsOneWidget);
      expect(find.text('Spoiler 2'), findsOneWidget);
    });
  });

  testWidgets(
    'new guide re-seats selection from live focus and hides spoilers',
    (t) async {
      await showcaseCase(t, (f) async {
        final nodes = f.nodes(3, 'guide');
        Widget host(String prefix) => f.host(
          ShowcaseGuide(
            guide: showcaseGuide(prefix: prefix),
            nodes: nodes,
            accent: Colors.yellow,
          ),
        );
        await t.pumpWidget(host(''));
        await showcasePump(t);
        nodes[2].requestFocus();
        await showcasePump(t);
        await t.tap(find.text('Category 0').first);
        await t.pump();
        expect(nodes[2].hasFocus, isTrue);
        expect(find.text('Plain 0'), findsOneWidget);
        await t.tap(find.text('SHOW'));
        await t.pump();
        expect(find.text('Spoiler 0'), findsOneWidget);
        await t.pumpWidget(host('New '));
        await t.pump();
        expect(find.text('New Plain 2'), findsOneWidget);
        expect(find.text('New Spoiler 2'), findsNothing);
        expect(find.text('New Plain 0'), findsNothing);
      });
    },
  );

  testWidgets('new guide without category focus selects zero', (t) async {
    await showcaseCase(t, (f) async {
      final nodes = f.nodes(3, 'guide');
      Widget host(String prefix) => f.host(
        ShowcaseGuide(
          guide: showcaseGuide(prefix: prefix),
          nodes: nodes,
          accent: Colors.yellow,
        ),
      );
      await t.pumpWidget(host(''));
      await showcasePump(t);
      await t.tap(find.text('Category 2').first);
      await t.pump();
      expect(find.text('Plain 2'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
      expect(nodes.any((n) => n.hasFocus), isFalse);
      await t.pumpWidget(host('New '));
      await t.pump();
      expect(find.text('New Plain 0'), findsOneWidget);
    });
  });

  testWidgets(
    'compact same object retains open row; new guide clears row and spoilers',
    (t) async {
      await showcaseCase(t, (f) async {
        final nodes = f.nodes(3, 'guide');
        var guide = showcaseGuide();
        Widget host() => f.host(
          ShowcaseGuide(guide: guide, nodes: nodes, accent: Colors.yellow),
          size: const Size(390, 844),
          compact: true,
          touch: true,
        );
        await t.pumpWidget(host());
        await showcasePump(t);
        await t.tap(find.text('Category 1'));
        await t.pump();
        await t.tap(find.text('SHOW'));
        await t.pump();
        await t.pumpWidget(host());
        await t.pump();
        expect(find.text('Plain 1'), findsOneWidget);
        expect(find.text('Spoiler 1'), findsOneWidget);
        guide = showcaseGuide(prefix: 'New ');
        await t.pumpWidget(host());
        await t.pump();
        expect(find.text('New Plain 1'), findsNothing);
        await t.tap(find.text('New Category 1'));
        await t.pump();
        expect(find.text('New Plain 1'), findsOneWidget);
        expect(find.text('New Spoiler 1'), findsNothing);
      }, size: const Size(390, 844));
    },
  );
}
