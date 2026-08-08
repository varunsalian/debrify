import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_layout_premium.dart';
import 'package:debrify/widgets/detail/detail_layout_stage.dart';
import 'package:debrify/widgets/detail/detail_episode_cells.dart';
import 'package:debrify/widgets/detail/detail_identity.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/episodes_panel.dart';

/// Renders every layout under every theme, at TV and phone size.
///
/// Deliberately NOT a golden suite — this repo has no golden harness and a
/// full-route golden cannot even be built (a fake `seasonsLoader` forces the
/// screen back to Classic). What this proves instead is the thing §2a of the
/// plan warns about: a theme is not "paint only". Display sizes run 18→31px and
/// families change, which moves text wrapping and therefore focus rectangles.
/// An overflow here is a traversal bug, not just an ugly frame.
///
/// The episode engine is bypassed entirely: `EpisodesPanelView` is a plain
/// value object, so a synthetic one renders a layout with no network and no
/// state machine.

const _tv = Size(960, 540);
const _phone = Size(390, 844);

TraktEpisode _ep(int n) => TraktEpisode(
  season: 5,
  number: n,
  title: 'Episode $n With A Reasonably Long Title',
  overview:
      'A synopsis long enough to wrap on a narrow column and short '
      'enough to stay believable.',
  rating: 8.3,
  firstAired: '2012-07-${n.toString().padLeft(2, '0')}',
  runtime: 47,
);

final _episodes = [for (var i = 1; i <= 8; i++) _ep(i)];

EpisodesPanelView _view({bool loading = false, bool unavailable = false}) =>
    EpisodesPanelView(
      seasons: [
        const TraktSeason(number: 4, episodeCount: 8, episodes: []),
        TraktSeason(number: 5, episodeCount: 8, episodes: _episodes),
      ],
      selectedSeasonNumber: 5,
      episodes: loading || unavailable ? const [] : _episodes,
      loading: loading,
      unavailable: unavailable,
      showImageUrl: null,
      generation: 1,
      landing: loading || unavailable ? null : _episodes[2],
      focusIntent: EpisodeFocusIntent.none,
      progressOf: (e) => e.number == 1
          ? 100
          : e.number == 3
          ? 38
          : null,
      isNext: (e) => e.number == 3,
      play: (_) {},
      options: (_) {},
      stepSeason: (_) {},
      selectSeason: (_) {},
      onLeftEdge: null,
      onRetry: () {},
      onSearchForSources: () {},
    );

DetailModel _model({
  required bool isMovie,
  bool isTelevision = false,
  bool withParentsGuide = false,
  ParentsGuideResult? parentsGuide,
  Color accent = const Color(0xFFABA124),
}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: isMovie ? 'movie' : 'series',
    name: 'A Title Long Enough To Wrap On Narrow Columns',
    poster: null,
    background: null,
    description:
        'A synopsis with enough words in it that a serif face at 31px and a '
        'mono face at 18px produce visibly different wrapping.',
    year: '2008–2013',
    genres: const ['Crime', 'Drama', 'Thriller'],
  );
  return DetailModel(
    item: item,
    isMovie: isMovie,
    isTelevision: isTelevision,
    accent: accent,
    imdbExtra: null,
    parentsGuide:
        parentsGuide ??
        (withParentsGuide
            ? const ParentsGuideResult(
                categories: [
                  ParentsGuideCategory(
                    id: 'violence',
                    label: 'Violence & Gore',
                    severity: 'Moderate',
                    severityVotes: 12,
                    totalVotes: 18,
                    items: [
                      ParentsGuideItem(text: 'Some stylized action violence.'),
                    ],
                  ),
                ],
              )
            : null),
    recommendations: isMovie ? [item, item, item, item] : const [],
    primaryLabel: 'Resume · S5E3',
    sourceCount: 2,
    hasTrailer: true,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: true,
    traktTracked: true,
    traktLabel: 'Watchlist',
    traktRating: 9,
    hasSimkl: true,
    simklTracked: true,
    simklLabel: 'Watching',
    simklRating: null,
    showPrimary: true,
    onPrimary: () {},
    onBrowse: isMovie ? () {} : null,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onRecommendationTap: (_) {},
    onAmbientStill: (_) {},
    focus: DetailFocusCoordinator(
      backNode: FocusNode(debugLabel: 'test-back'),
      primaryEntry: FocusNode(debugLabel: 'test-primary'),
    ),
  );
}

Widget _host(Widget Function(BuildContext, EpisodesPanelView) builder) =>
    Builder(builder: (context) => builder(context, _view()));

Widget _layout(String id, DetailModel m) => switch (id) {
  'marquee' => DetailMarquee(model: m, episodesHost: m.isMovie ? null : _host),
  'dossier' => DetailDossier(model: m, episodesHost: m.isMovie ? null : _host),
  'stage' => DetailStage(model: m, episodesHost: m.isMovie ? null : _host),
  'vista' => DetailPremium(
    kind: PremiumDetailKind.vista,
    model: m,
    episodesHost: m.isMovie ? null : _host,
  ),
  'monolith' => DetailPremium(
    kind: PremiumDetailKind.monolith,
    model: m,
    episodesHost: m.isMovie ? null : _host,
  ),
  'mosaic' => DetailPremium(
    kind: PremiumDetailKind.mosaic,
    model: m,
    episodesHost: m.isMovie ? null : _host,
  ),
  'halo' => DetailPremium(
    kind: PremiumDetailKind.halo,
    model: m,
    episodesHost: m.isMovie ? null : _host,
  ),
  'premiere' => DetailPremium(
    kind: PremiumDetailKind.premiere,
    model: m,
    episodesHost: m.isMovie ? null : _host,
  ),
  _ => DetailConsole(model: m, episodesHost: m.isMovie ? null : _host),
};

Future<void> _pump(
  WidgetTester tester,
  String layoutId,
  DetailTheme theme, {
  required bool isMovie,
  required Size size,
  required bool isTelevision,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: 1.0,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: theme.ground,
            body: DetailThemeScope(
              theme: theme,
              child: _layout(
                layoutId,
                _model(isMovie: isMovie, isTelevision: isTelevision),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  const layouts = [
    'marquee',
    'dossier',
    'stage',
    'console',
    'vista',
    'monolith',
    'mosaic',
    'halo',
    'premiere',
  ];

  group('every theme renders every layout without overflowing', () {
    for (final theme in DetailThemes.all) {
      for (final id in layouts) {
        for (final movie in [false, true]) {
          final kind = movie ? 'movie' : 'series';

          testWidgets('${theme.id} · $id · $kind · tv', (tester) async {
            await _pump(
              tester,
              id,
              theme,
              isMovie: movie,
              size: _tv,
              isTelevision: true,
            );
            expect(tester.takeException(), isNull);
          });

          testWidgets('${theme.id} · $id · $kind · phone', (tester) async {
            await _pump(
              tester,
              id,
              theme,
              isMovie: movie,
              size: _phone,
              isTelevision: false,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('the cursor survives every theme', () {
    // Every layout, not just Dossier: a theme that leaves one of them without
    // a focusable element is a page the remote cannot drive at all.
    for (final theme in DetailThemes.all) {
      for (final id in layouts) {
        testWidgets('${theme.id} · $id keeps a focusable body', (tester) async {
          await _pump(
            tester,
            id,
            theme,
            isMovie: false,
            size: _tv,
            isTelevision: true,
          );
          // Something must be able to hold the DPAD cursor, or the page is a
          // dead end however good it looks.
          final focusables = tester
              .widgetList<Focus>(find.byType(Focus))
              .where((f) => f.canRequestFocus)
              .length;
          expect(focusables, greaterThan(0), reason: '${theme.id} · $id');
        });
      }
    }
  });

  group('premium layouts expose the themed parents guide', () {
    for (final id in const [
      'vista',
      'monolith',
      'mosaic',
      'halo',
      'premiere',
    ]) {
      testWidgets('$id opens Parents Guide without leaving the theme', (
        tester,
      ) async {
        tester.view.physicalSize = _tv;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final theme = DetailThemes.vault;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: theme.ground,
                body: DetailThemeScope(
                  theme: theme,
                  child: _layout(
                    id,
                    _model(
                      isMovie: false,
                      isTelevision: true,
                      withParentsGuide: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Parents Guide'), findsOneWidget);

        await tester.tap(find.text('Parents Guide'));
        await tester.pumpAndSettle();
        expect(find.text('PARENTS GUIDE'), findsOneWidget);
        expect(find.text('Violence & Gore'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('premium layouts retain their responsive and DPAD contracts', () {
    const premium = ['vista', 'monolith', 'mosaic', 'halo', 'premiere'];

    for (final id in premium) {
      testWidgets('$id fits a landscape phone', (tester) async {
        for (final isMovie in [false, true]) {
          await _pump(
            tester,
            id,
            DetailThemes.vault,
            isMovie: isMovie,
            size: const Size(800, 400),
            isTelevision: false,
          );
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('$id fits a short portrait phone', (tester) async {
        for (final isMovie in [false, true]) {
          await _pump(
            tester,
            id,
            DetailThemes.vault,
            isMovie: isMovie,
            size: const Size(390, 600),
            isTelevision: false,
          );
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('$id fits enlarged text on TV and phone', (tester) async {
        for (final isMovie in [false, true]) {
          await _pump(
            tester,
            id,
            DetailThemes.vault,
            isMovie: isMovie,
            size: _tv,
            isTelevision: true,
            textScale: 1.8,
          );
          expect(tester.takeException(), isNull);

          await _pump(
            tester,
            id,
            DetailThemes.vault,
            isMovie: isMovie,
            size: _phone,
            isTelevision: false,
            textScale: 1.8,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }

    for (final id in const ['vista', 'mosaic', 'halo']) {
      testWidgets('$id contains the first horizontal rail edge', (
        tester,
      ) async {
        final model = _model(isMovie: false, isTelevision: true);
        tester.view.physicalSize = _tv;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DetailThemeScope(
                theme: DetailThemes.signal,
                child: _layout(id, model),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final firstCard = tester.widget<DetailEpisodeCard>(
          find.byType(DetailEpisodeCard).first,
        );
        firstCard.focusNode.requestFocus();
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(firstCard.focusNode.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        final season = tester.widget<DetailSeasonControl>(
          find.byType(DetailSeasonControl),
        );
        expect(season.focusNode!.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(model.focus.primaryEntry.hasFocus, isTrue);
      });
    }

    testWidgets('Halo uses the resolved artwork accent', (tester) async {
      const artworkAccent = Color(0xFF31D17C);
      final model = _model(
        isMovie: false,
        isTelevision: true,
        accent: artworkAccent,
      );
      tester.view.physicalSize = _tv;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailThemeScope(
              theme: DetailThemes.signal,
              child: _layout('halo', model),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final mark = tester.widget<Icon>(
        find.byIcon(Icons.radio_button_checked_rounded),
      );
      expect(mark.color, artworkAccent);
    });

    testWidgets('adaptive actions reveal every DPAD target', (tester) async {
      await _pump(
        tester,
        'vista',
        DetailThemes.vault,
        isMovie: false,
        size: _tv,
        isTelevision: true,
        textScale: 1.8,
      );
      final primary = tester.widget<DetailPrimaryButton>(
        find.byType(DetailPrimaryButton),
      );
      primary.focusNode!.requestFocus();
      await tester.pump();

      final horizontalScroll = find.ancestor(
        of: find.byType(DetailActionRow),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontalScroll, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(horizontalScroll);
      expect(scrollState.position.pixels, lessThan(2));

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(scrollState.position.pixels, greaterThan(0));

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      expect(scrollState.position.pixels, lessThan(2));
    });

    testWidgets('an expanded Parents Guide scrolls with the TV DPAD', (
      tester,
    ) async {
      final longGuide = ParentsGuideResult(
        categories: [
          ParentsGuideCategory(
            id: 'violence',
            label: 'Violence & Gore',
            severity: 'Moderate',
            severityVotes: 12,
            totalVotes: 18,
            items: [
              ParentsGuideItem(
                text: List.filled(
                  45,
                  'A detailed non-spoiler description of the scene.',
                ).join(' '),
              ),
            ],
          ),
        ],
      );
      final model = _model(
        isMovie: false,
        isTelevision: true,
        parentsGuide: longGuide,
      );
      tester.view.physicalSize = _tv;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailThemeScope(
              theme: DetailThemes.vault,
              child: _layout('vista', model),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Parents Guide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Violence & Gore'));
      await tester.pumpAndSettle();

      final categoryContext = tester.element(find.text('Violence & Gore'));
      Focus.of(categoryContext).requestFocus();
      await tester.pump();
      final dialogScroll = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Scrollable),
      );
      expect(dialogScroll, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(dialogScroll);
      expect(scrollState.position.maxScrollExtent, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(scrollState.position.pixels, greaterThan(0));
    });

    testWidgets('a desktop mouse wheel scrolls the horizontal episode rail', (
      tester,
    ) async {
      await _pump(
        tester,
        'halo',
        DetailThemes.vault,
        isMovie: false,
        size: const Size(1280, 800),
        isTelevision: false,
      );
      final episodeCard = find.byType(DetailEpisodeCard).first;
      final horizontalScroll = find.ancestor(
        of: episodeCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontalScroll, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(horizontalScroll);
      expect(scrollState.position.pixels, 0);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      final railPosition = tester.getCenter(episodeCard);
      await pointer.addPointer(location: railPosition);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: railPosition,
          scrollDelta: const Offset(0, 240),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();

      expect(scrollState.position.pixels, greaterThan(0));
    });

    testWidgets('Marquee maps a desktop mouse wheel onto its episode rail', (
      tester,
    ) async {
      await _pump(
        tester,
        'marquee',
        DetailThemes.vault,
        isMovie: false,
        size: const Size(1280, 800),
        isTelevision: false,
      );
      final episodeCard = find.byType(DetailEpisodeCard).first;
      final horizontalScroll = find.ancestor(
        of: episodeCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontalScroll, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(horizontalScroll);
      expect(scrollState.position.pixels, 0);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      final railPosition = tester.getCenter(episodeCard);
      await pointer.addPointer(location: railPosition);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: railPosition,
          scrollDelta: const Offset(0, 240),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();

      expect(scrollState.position.pixels, greaterThan(0));
    });

    testWidgets('Mosaic keeps its utilities above a full-width episode rail', (
      tester,
    ) async {
      await _pump(
        tester,
        'mosaic',
        DetailThemes.vault,
        isMovie: false,
        size: const Size(1600, 900),
        isTelevision: false,
      );

      final hero = tester.getRect(find.byKey(const Key('mosaic-hero')));
      final feature = tester.getRect(find.byKey(const Key('mosaic-feature')));
      final rail = tester.getRect(find.byKey(const Key('mosaic-bottom-rail')));
      expect(hero.left, lessThan(feature.left));
      expect(hero.bottom, lessThanOrEqualTo(rail.top));
      expect(feature.bottom, lessThanOrEqualTo(rail.top));
      expect(rail.left, closeTo(hero.left, 1));
      expect(rail.right, closeTo(feature.right, 1));
      expect(rail.width, greaterThan(1500));

      final episodeCard = find.byType(DetailEpisodeCard).first;
      final horizontalScroll = find.ancestor(
        of: episodeCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontalScroll, findsOneWidget);
      final scrollState = tester.state<ScrollableState>(horizontalScroll);
      expect(scrollState.position.pixels, 0);
    });
  });

  group('degenerate states do not throw under any theme', () {
    for (final theme in [
      DetailThemes.signal,
      DetailThemes.broadsheet, // light
      DetailThemes.concrete, // light + offset shadows
      DetailThemes.vault, // 1px focus, huge serif
      DetailThemes.cinemascope, // grain + wide tracking
      DetailThemes.frost, // translucent everything
    ]) {
      testWidgets('${theme.id} · loading', (tester) async {
        tester.view.physicalSize = _tv;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MaterialApp(
                home: Scaffold(
                  body: DetailThemeScope(
                    theme: theme,
                    child: DetailDossier(
                      model: _model(isMovie: false, isTelevision: true),
                      episodesHost: (b) =>
                          Builder(builder: (c) => b(c, _view(loading: true))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${theme.id} · unavailable', (tester) async {
        tester.view.physicalSize = _tv;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MaterialApp(
                home: Scaffold(
                  body: DetailThemeScope(
                    theme: theme,
                    child: DetailDossier(
                      model: _model(isMovie: false, isTelevision: true),
                      episodesHost: (b) => Builder(
                        builder: (c) => b(c, _view(unavailable: true)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
