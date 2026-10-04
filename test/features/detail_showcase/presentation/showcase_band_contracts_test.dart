import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

void main() {
  test('wide touch scale and scope notification preserve all input axes', () {
    expect(const ShowcaseMetrics(1280, touch: true).k, closeTo(4 / 3, 0.00001));
    expect(const ShowcaseMetrics(1920, touch: true).k, 1.5);
    expect(const ShowcaseMetrics(1280).k, 1);
    expect(const ShowcaseMetrics(1280, compact: true, touch: true).k, 1);
    const old = ShowcaseMetricsScope(
      metrics: ShowcaseMetrics(960),
      child: SizedBox(),
    );
    expect(
      const ShowcaseMetricsScope(
        metrics: ShowcaseMetrics(960),
        child: SizedBox(),
      ).updateShouldNotify(old),
      isFalse,
    );
    expect(
      const ShowcaseMetricsScope(
        metrics: ShowcaseMetrics(960, compact: true),
        child: SizedBox(),
      ).updateShouldNotify(old),
      isTrue,
    );
    expect(
      const ShowcaseMetricsScope(
        metrics: ShowcaseMetrics(960, touch: true),
        child: SizedBox(),
      ).updateShouldNotify(old),
      isTrue,
    );
    expect(
      const ShowcaseMetricsScope(
        metrics: ShowcaseMetrics(961),
        child: SizedBox(),
      ).updateShouldNotify(old),
      isTrue,
    );
  });

  testWidgets(
    'metrics prefer scope; fallback subtracts horizontal safe padding',
    (t) async {
      ShowcaseMetrics? observed;
      Widget read() => Builder(
        builder: (c) {
          observed = ShowcaseMetrics.of(c);
          return const SizedBox();
        },
      );
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1000, 600),
            padding: EdgeInsets.symmetric(horizontal: 20),
          ),
          child: read(),
        ),
      );
      expect(observed!.w, 960);
      expect(observed!.touch, isFalse);
      await t.pumpWidget(
        ShowcaseMetricsScope(
          metrics: const ShowcaseMetrics(720, touch: true),
          child: read(),
        ),
      );
      expect(observed!.w, 720);
      expect(observed!.touch, isTrue);
    },
  );

  testWidgets(
    'sources browse term mounts its third node and dispatches callbacks',
    (t) async {
      await showcaseCase(t, (f) async {
        final nodes = f.nodes(3, 'sources');
        Widget host(bool browse) => f.host(
          ShowcaseSources(
            sources: const [],
            nodes: nodes,
            onOpen: () => f.calls.add('open'),
            onBrowseAll: browse ? () => f.calls.add('browse') : null,
          ),
        );
        await t.pumpWidget(host(true));
        await showcasePump(t);
        expect(nodes[2].context, isNotNull);
        expect(find.text('⌕  Browse all'), findsOneWidget);
        await t.tap(find.text('⌕  Browse all'));
        expect(f.calls, ['browse']);
        nodes[1].requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        expect(f.calls, ['browse', 'open']);
        await t.pumpWidget(host(false));
        await showcasePump(t);
        expect(nodes[2].context?.mounted ?? false, isFalse);
        expect(find.text('⌕  Browse all'), findsNothing);
      });
    },
  );

  testWidgets(
    'compact season pill uses first borrowed node and popup selects season',
    (t) async {
      await showcaseCase(t, (f) async {
        final nodes = f.nodes(2, 'seasons');
        await t.pumpWidget(
          f.host(
            ShowcaseSeasons(view: f.view(), nodes: nodes),
            size: const Size(390, 844),
            compact: true,
            touch: true,
          ),
        );
        await showcasePump(t);
        expect(nodes.first.context, isNotNull);
        expect(nodes.last.context, isNull);
        expect(find.text('Season 2'), findsOneWidget);
        expect(find.text('Season 1'), findsNothing);
        await t.tap(find.text('Season 2'));
        await showcasePump(t);
        await t.tap(find.text('Season 1'));
        await showcasePump(t);
        expect(f.calls, ['season:1']);
      }, size: const Size(390, 844));
    },
  );

  testWidgets(
    'Did You Know has one borrowed node per entry plus the remainder',
    (t) async {
      await showcaseCase(t, (f) async {
        final nodes = f.nodes(3, 'dyk');
        await t.pumpWidget(
          f.host(
            ShowcaseDidYouKnow(
              entries: const [
                DidYouKnowEntry(kind: 'Trivia', text: 'A fact.'),
                DidYouKnowEntry(kind: 'Quote', text: 'A quote.'),
              ],
              total: 7,
              countLine: null,
              nodes: nodes,
            ),
          ),
        );
        await showcasePump(t);
        expect(find.text('+5'), findsOneWidget);
        expect(nodes.every((n) => n.context != null), isTrue);
      });
    },
  );

  testWidgets(
    'band note retry dispatches pointer and all remote activate keys; details render',
    (t) async {
      await showcaseCase(t, (f) async {
        final retry = f.node('retry');
        await t.pumpWidget(
          f.host(
            Column(
              children: [
                ShowcaseBandNote(
                  text: 'Load failed',
                  actionLabel: 'Retry',
                  actionNode: retry,
                  onAction: () => f.calls.add('action'),
                ),
                const ShowcaseDetails(
                  rows: [('Country', 'India')],
                  awards: 'An award',
                ),
              ],
            ),
          ),
        );
        await showcasePump(t);
        expect(find.text('Country'), findsOneWidget);
        expect(find.text('India'), findsOneWidget);
        expect(find.text('An award'), findsOneWidget);
        await t.tap(find.text('Retry'));
        retry.requestFocus();
        await t.pump();
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.gameButtonA,
        ]) {
          await t.sendKeyEvent(key);
        }
        expect(f.calls, List.filled(5, 'action'));
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(f.calls, hasLength(5));
      });
    },
  );

  testWidgets(
    'sticky logo and ambient visibility and scrim gradients preserve transitions',
    (t) async {
      await showcaseCase(t, (f) async {
        Widget host(bool visible, bool thinned) => f.host(
          Stack(
            children: [
              ShowcaseAmbient(url: null, visible: visible),
              ShowcaseBackdropScrim(visible: visible, thinned: thinned),
              ShowcaseStickyLogo(
                url: null,
                name: 'Original Movie',
                visible: visible,
              ),
            ],
          ),
        );
        await t.pumpWidget(host(false, false));
        await showcasePump(t);
        final before = t
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((w) => w.decoration)
            .toList();
        expect(
          t
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((w) => w.opacity == 0),
          isTrue,
        );
        await t.pumpWidget(host(true, true));
        await showcasePump(t);
        expect(
          t
              .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
              .every((w) => w.opacity == 1),
          isTrue,
        );
        final after = t
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((w) => w.decoration)
            .toList();
        expect(after, isNot(equals(before)));
      });
    },
  );
}
