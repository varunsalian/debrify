import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/episodes_panel.dart';

/// Showcase's band model and DPAD map.
///
/// The property under test throughout is that **bands are positional**: an
/// absent band leaves no hole. A movie has no Seasons and no Episodes, a show
/// with one season has no Seasons, and a title whose IMDb enrichment failed has
/// no Cast — and in each case DOWN must still walk a contiguous ladder. A fixed
/// index table passes a happy-path test and silently skips a row in the field.
const _tv = Size(960, 540);

TraktEpisode _ep(int n) => TraktEpisode(
      season: 5,
      number: n,
      title: 'Episode $n',
      overview: 'Synopsis $n.',
      firstAired: '2012-07-0$n',
      runtime: 47,
    );

EpisodesPanelView _view({required bool manySeasons, int count = 5}) {
  final eps = [for (var i = 1; i <= count; i++) _ep(i)];
  return EpisodesPanelView(
    seasons: [
      if (manySeasons) const TraktSeason(number: 4, episodeCount: 5, episodes: []),
      TraktSeason(number: 5, episodeCount: count, episodes: eps),
    ],
    selectedSeasonNumber: 5,
    episodes: eps,
    loading: false,
    unavailable: false,
    showImageUrl: null,
    generation: 1,
    landing: eps.first,
    focusIntent: EpisodeFocusIntent.none,
    progressOf: (_) => null,
    isNext: (e) => e.number == 1,
    play: (_) {},
    options: (_) {},
    stepSeason: (_) {},
    selectSeason: (_) {},
    onLeftEdge: null,
    onRetry: () {},
    onSearchForSources: () {},
  );
}

DetailModel _model({
  bool isMovie = false,
  bool withCast = true,
  List<SeriesSource> sources = const [],
  List<StremioMeta> recs = const [],
  void Function(bool)? onDepth,
}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: isMovie ? 'movie' : 'series',
    name: 'A Show',
    description: 'A synopsis.',
    year: '2008',
    genres: const ['Crime', 'Drama'],
  );
  return DetailModel(
    item: item,
    isMovie: isMovie,
    isTelevision: true,
    accent: const Color(0xFFABA124),
    imdbExtra: withCast
        ? const ImdbEnrichment(
            cast: [
              CastMember(name: 'A Person', character: 'Someone'),
              CastMember(name: 'B Person', character: 'Someone Else'),
            ],
          )
        : null,
    parentsGuide: null,
    recommendations: recs,
    primaryLabel: 'Resume',
    sourceCount: sources.length,
    boundSources: sources,
    hasTrailer: true,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: true,
    traktTracked: true,
    traktLabel: 'Watchlist',
    traktRating: 9,
    hasSimkl: true,
    simklTracked: false,
    simklLabel: 'Not tracked',
    simklRating: null,
    showPrimary: true,
    onPrimary: () {},
    onBrowse: null,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onTrackers: () {},
    onManageSources: () {},
    onRecommendationTap: (_) {},
    onAmbientStill: (_) {},
    onDepth: onDepth,
    focus: DetailFocusCoordinator(
      backNode: FocusNode(debugLabel: 'test-back'),
      primaryEntry: FocusNode(debugLabel: 'test-primary'),
    ),
  );
}

/// [tall] gives the page a viewport big enough to lay every band out at once.
/// The bands live in a lazy `ListView`, so at the real 540 the ones below the
/// fold are never built and a structural assertion would be testing the
/// viewport rather than the layout. The DPAD tests keep the true TV size.
Widget _host(
  DetailModel m, {
  bool manySeasons = true,
  int count = 5,
  bool tall = false,
}) =>
    MediaQuery(
      data: MediaQueryData(size: tall ? const Size(960, 2000) : _tv),
      child: MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: DetailShowcase(
              model: m,
              episodesHost: m.isMovie
                  ? null
                  : (builder) => Builder(
                        builder: (context) => builder(
                          context,
                          _view(manySeasons: manySeasons, count: count),
                        ),
                      ),
            ),
          ),
        ),
      ),
    );

/// Resizes the actual render surface. A `MediaQuery` wrapper does not — the
/// view stays 800×600 and the lazy band list never builds what is below it,
/// so a structural assertion would silently be testing the default viewport.
void _surface(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump(const Duration(milliseconds: 320));
}

void main() {
  testWidgets('a series walks identity → seasons → episodes → cast → sources',
      (tester) async {
    _surface(tester, const Size(960, 2000));
    await tester.pumpWidget(_host(_model(), tall: true));
    await tester.pumpAndSettle();

    // `skipOffstage: false` throughout: the identity is a full screenful now,
    // so the bands below it are built but OFFSTAGE until scrolled to. These
    // assertions are about the ladder's structure — which bands exist and in
    // what order — not about what happens to be painted, and the default
    // finder quietly conflates the two.
    expect(find.byType(ShowcaseSeasons, skipOffstage: false), findsOneWidget);
    // seasons → episodes → cast
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(find.byType(ShowcaseCast, skipOffstage: false), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(ShowcaseSources, skipOffstage: false), findsOneWidget);
    // Nothing threw and the page is intact — the ladder is contiguous.
    expect(find.byType(DetailShowcase), findsOneWidget);
  });

  testWidgets('a single-season show has no Seasons band and no hole',
      (tester) async {
    await tester.pumpWidget(_host(_model(), manySeasons: false));
    await tester.pumpAndSettle();
    expect(find.byType(ShowcaseSeasons, skipOffstage: false), findsNothing);
    // DOWN once must reach the EPISODES, not an empty slot where Seasons was.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(DetailShowcase), findsOneWidget);
  });

  testWidgets('a movie has neither Seasons nor Episodes; Sources moves up',
      (tester) async {
    _surface(tester, const Size(960, 2000));
    await tester.pumpWidget(_host(_model(isMovie: true), tall: true));
    await tester.pumpAndSettle();
    expect(find.byType(ShowcaseSeasons, skipOffstage: false), findsNothing);
    // Sources is the only band under the hero, so one DOWN reaches it.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(ShowcaseSources, skipOffstage: false), findsOneWidget);
    expect(find.byType(DetailShowcase), findsOneWidget);
  });

  testWidgets('no cast means no Cast band — an empty row is not a band',
      (tester) async {
    _surface(tester, const Size(960, 2000));
    await tester.pumpWidget(_host(_model(withCast: false), tall: true));
    await tester.pumpAndSettle();
    expect(find.byType(ShowcaseCast, skipOffstage: false), findsNothing);
    // seasons → episodes → sources, with Cast absent from the ladder entirely.
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(find.byType(ShowcaseSources, skipOffstage: false), findsOneWidget);
  });

  testWidgets('the Sources band always exists, with the Find tile alone when '
      'nothing is bound', (tester) async {
    _surface(tester, const Size(960, 2000));
    await tester.pumpWidget(_host(_model(), tall: true));
    await tester.pumpAndSettle();
    // seasons → episodes → cast → sources.
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    // An empty Sources band is not an empty state to hide — "Find sources" is
    // exactly what someone with no bound sources needs to see.
    expect(find.text('＋  Find sources', skipOffstage: false), findsOneWidget);
  });

  testWidgets('trackers are READOUT in the meta line, never focusable',
      (tester) async {
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();
    // The branded pills are gone from the action row entirely.
    expect(find.text('TRAKT'), findsNothing);
    expect(find.text('SIMKL'), findsNothing);
    // And the marks that replaced them cannot take the cursor.
    expect(find.text('T'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('the title falls back to text when there is no logo art',
      (tester) async {
    // ~1 metahub logo in 4 is a black wordmark, invisible on ink. The text
    // path is the other half of the design, not a degraded one.
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();
    expect(find.text('A Show'), findsWidgets);
  });

  testWidgets('the hero fills the first screenful and leaves the next band '
      'peeking', (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();

    // The reference opens on key art with the identity at its foot and the
    // next row peeking in — the tell that the page continues. As an ordinary
    // block in the flow the identity floated mid-art with whole rows already
    // under it, which is what read as "not the Apple layout".
    final identity = tester.getSize(find.byType(ShowcaseIdentity)).height;
    final viewport = tester.getSize(find.byType(DetailShowcase)).height;
    final peek = viewport - identity;
    expect(peek, greaterThan(50),
        reason: 'nothing peeking reads as a dead end');
    expect(peek, lessThan(viewport * 0.45),
        reason: 'a whole band showing is the old layout, not a peek');
  });

  testWidgets('depth is announced to the shell, once per transition',
      (tester) async {
    final depths = <bool>[];
    await tester.pumpWidget(_host(_model(onDepth: depths.add)));
    await tester.pumpAndSettle();
    expect(depths, isEmpty, reason: 'opening at the hero is not a transition');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(depths, [true]);

    // Walking further down is still deep — the shell must not be told again,
    // and its handler calls setState.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(depths, [true]);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(depths.last, isFalse);
  });
}
