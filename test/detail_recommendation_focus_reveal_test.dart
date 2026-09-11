import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final layout in ['marquee', 'dossier', 'console']) {
    testWidgets(
      '$layout reveals a cached recommendation focused programmatically',
      (tester) async {
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final back = FocusNode();
        final primary = FocusNode();
        addTearDown(back.dispose);
        addTearDown(primary.dispose);
        final model = DetailModel(
          item: const StremioMeta(
            id: 'movie',
            type: 'movie',
            name: 'Movie',
            description: 'Movie synopsis for the reference pane.',
          ),
          isMovie: true,
          isTelevision: true,
          accent: Colors.amber,
          imdbExtra: null,
          parentsGuide: null,
          recommendations: [
            for (var i = 0; i < 30; i++)
              StremioMeta(id: 'rec-$i', type: 'movie', name: 'Title $i'),
          ],
          primaryLabel: 'Play',
          sourceCount: 0,
          hasTrailer: false,
          trailerBusy: false,
          trailerPlaying: false,
          hasTrakt: false,
          traktTracked: false,
          traktLabel: '',
          traktRating: null,
          hasSimkl: false,
          simklTracked: false,
          simklLabel: '',
          simklRating: null,
          showPrimary: true,
          onPrimary: () {},
          onBrowse: null,
          onTrailer: () {},
          onSelectSource: () {},
          onAppMenu: () {},
          onTraktMenu: () {},
          onSimklMenu: () {},
          onRecommendationTap: (_) {},
          onAmbientStill: (_) {},
          focus: DetailFocusCoordinator(backNode: back, primaryEntry: primary),
        );
        final body = switch (layout) {
          'marquee' => DetailMarquee(model: model, episodesHost: null),
          'dossier' => DetailDossier(model: model, episodesHost: null),
          _ => DetailConsole(model: model, episodesHost: null),
        };
        await tester.pumpWidget(
          MaterialApp(
            home: DetailThemeScope(
              theme: DetailThemes.signal,
              child: Scaffold(body: body),
            ),
          ),
        );
        await tester.pump();
        final list = layout == 'console'
            ? find.byType(GridView).first
            : find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is ListView &&
                        widget.scrollDirection == Axis.horizontal,
                  )
                  .first;
        final viewport = tester.getRect(list);
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        final cards = find.descendant(of: list, matching: find.byType(InkWell));
        final element = tester.element(cards.last);
        final card = find.byElementPredicate((e) => identical(e, element));
        final before = tester.getRect(card);
        expect(
          layout == 'console'
              ? before.bottom > viewport.bottom
              : before.right > viewport.right,
          isTrue,
          reason:
              'The target must start beyond the visible viewport, in the lazy cache.',
        );
        final focus = find
            .descendant(of: card, matching: find.byType(Focus))
            .last;
        final child = tester.widget<Focus>(focus).child;
        final node = Focus.of(tester.element(find.byWidget(child)));
        node.requestFocus();
        await tester.pump();
        await tester.pump();
        expect(node.hasFocus, isTrue);
        expect(scroll.position.pixels, greaterThan(0));
        final after = tester.getRect(card);
        if (layout == 'console') {
          expect(after.top, greaterThanOrEqualTo(viewport.top - 1));
          expect(after.bottom, lessThanOrEqualTo(viewport.bottom + 1));
        } else {
          expect(after.left, greaterThanOrEqualTo(viewport.left - 1));
          expect(after.right, lessThanOrEqualTo(viewport.right + 1));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
