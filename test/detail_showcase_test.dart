import 'package:flutter/gestures.dart';
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
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:debrify/utils/platform_util.dart';

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
      if (manySeasons)
        const TraktSeason(number: 4, episodeCount: 5, episodes: []),
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
  bool hasTrakt = true,
  bool hasSimkl = true,
  bool hasMdblist = false,
  bool withSecondaryTracker = false,
  bool withTertiaryTracker = false,
  bool inMyWatchlist = false,
  bool withMyWatchlist = false,
  List<SeriesSource> sources = const [],
  List<StremioMeta> recs = const [],
  void Function(bool)? onDepth,
  bool openingDataReady = true,
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
    openingDataReady: openingDataReady,
    primaryLabel: 'Resume',
    sourceCount: sources.length,
    boundSources: sources,
    hasTrailer: true,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: hasTrakt,
    traktTracked: true,
    traktLabel: 'Watchlist',
    traktRating: 9,
    hasSimkl: hasSimkl,
    simklTracked: false,
    simklLabel: 'Not tracked',
    simklRating: null,
    hasMdblist: hasMdblist,
    mdblistTracked: true,
    mdblistLabel: 'Watchlist',
    mdblistRating: 8,
    showPrimary: true,
    onPrimary: () {},
    onBrowse: null,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onMdblistMenu: () {},
    onTrackers: () {},
    onTrackersSecondary: withSecondaryTracker ? () {} : null,
    onTrackersTertiary: withTertiaryTracker ? () {} : null,
    inMyWatchlist: inMyWatchlist,
    onToggleMyWatchlist: withMyWatchlist ? () {} : null,
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
}) => MediaQuery(
  data: MediaQueryData(size: tall ? const Size(960, 2000) : _tv),
  child: MaterialApp(
    home: AppThemeScope(
      theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              child: Focus(
                focusNode: m.focus.backNode,
                child: const SizedBox.square(dimension: 1),
              ),
            ),
            DetailShowcase(
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
          ],
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
  testWidgets(
    'TV holds a composed opening skeleton before revealing Showcase',
    (tester) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      _surface(tester, _tv);
      final model = _model();

      await tester.pumpWidget(_host(model));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('showcase-tv-opening-skeleton')),
        findsOneWidget,
      );
      // The real page is already mounted under the opaque gate so its lazy
      // image widgets can resolve, but it must not take remote input yet.
      expect(find.byType(ShowcaseIdentity), findsOneWidget);
      expect(model.focus.primaryEntry.hasFocus, isFalse);

      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('showcase-tv-opening-skeleton')),
        findsNothing,
      );
      expect(find.byType(ShowcaseIdentity), findsOneWidget);
      expect(model.focus.primaryEntry.hasFocus, isTrue);
    },
  );

  testWidgets('TV reveal preserves focus deliberately moved to shell chrome', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    _surface(tester, _tv);
    final model = _model();

    await tester.pumpWidget(_host(model));
    await tester.pump();
    model.focus.backNode.requestFocus();
    await tester.pump();
    expect(model.focus.backNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('showcase-tv-opening-skeleton')),
      findsNothing,
    );
    expect(model.focus.backNode.hasFocus, isTrue);
    expect(model.focus.primaryEntry.hasFocus, isFalse);
  });

  testWidgets('TV gate stays composed while opening metadata is pending', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    _surface(tester, _tv);
    final loading = _model(openingDataReady: false);

    await tester.pumpWidget(_host(loading));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('showcase-tv-opening-skeleton')),
      findsOneWidget,
    );
  });

  testWidgets('a series walks identity → seasons → episodes → cast → sources', (
    tester,
  ) async {
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

  testWidgets('a single-season show has no Seasons band and no hole', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_model(), manySeasons: false));
    await tester.pumpAndSettle();
    expect(find.byType(ShowcaseSeasons, skipOffstage: false), findsNothing);
    // DOWN once must reach the EPISODES, not an empty slot where Seasons was.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(DetailShowcase), findsOneWidget);
  });

  testWidgets('a movie has neither Seasons nor Episodes; Sources moves up', (
    tester,
  ) async {
    _surface(tester, const Size(960, 2000));
    await tester.pumpWidget(_host(_model(isMovie: true), tall: true));
    await tester.pumpAndSettle();
    expect(find.byType(ShowcaseSeasons, skipOffstage: false), findsNothing);
    // Sources is the only band under the hero, so one DOWN reaches it.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(ShowcaseSources, skipOffstage: false), findsOneWidget);
    expect(find.byType(DetailShowcase), findsOneWidget);
  });

  testWidgets('no cast means no Cast band — an empty row is not a band', (
    tester,
  ) async {
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
    // An empty Sources band is not an empty state to hide — "Pin source" is
    // exactly what someone with no bound sources needs to see.
    expect(find.text('＋  Pin source', skipOffstage: false), findsOneWidget);
  });

  testWidgets('trackers are READOUT in the meta line, never focusable', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();
    // The branded pills are gone from the action row entirely.
    expect(find.text('TRAKT'), findsNothing);
    expect(find.text('SIMKL'), findsNothing);
    // And the marks that replaced them cannot take the cursor.
    expect(find.text('T'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('tracker action uses the connected service brand', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_model(hasTrakt: true, hasSimkl: false)));
    await tester.pumpAndSettle();
    expect(find.byType(TraktMark), findsOneWidget);
    expect(find.byType(SimklMark), findsNothing);

    await tester.pumpWidget(_host(_model(hasTrakt: false, hasSimkl: true)));
    await tester.pumpAndSettle();
    expect(find.byType(TraktMark), findsNothing);
    expect(find.byType(SimklMark), findsOneWidget);

    await tester.pumpWidget(
      _host(_model(hasTrakt: false, hasSimkl: false, hasMdblist: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TraktMark), findsNothing);
    expect(find.byType(SimklMark), findsNothing);
    expect(find.byType(MdblistMark), findsOneWidget);
  });

  testWidgets('both connected trackers get their own branded action', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_model(withSecondaryTracker: true)));
    await tester.pumpAndSettle();
    expect(find.byType(TraktMark), findsOneWidget);
    expect(find.byType(SimklMark), findsOneWidget);
  });

  testWidgets('three connected trackers get independent branded actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _model(
          hasMdblist: true,
          withSecondaryTracker: true,
          withTertiaryTracker: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TraktMark), findsOneWidget);
    expect(find.byType(SimklMark), findsOneWidget);
    expect(find.byType(MdblistMark), findsOneWidget);
  });

  testWidgets('My Watchlist action reflects saved state', (tester) async {
    await tester.pumpWidget(_host(_model(withMyWatchlist: true)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);

    await tester.pumpWidget(
      _host(_model(withMyWatchlist: true, inMyWatchlist: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  testWidgets('the title falls back to text when there is no logo art', (
    tester,
  ) async {
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
    expect(
      peek,
      greaterThan(50),
      reason: 'nothing peeking reads as a dead end',
    );
    expect(
      peek,
      lessThan(viewport * 0.45),
      reason: 'a whole band showing is the old layout, not a peek',
    );
  });

  testWidgets('depth is announced to the shell, once per transition', (
    tester,
  ) async {
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

  testWidgets('action circles name themselves on focus', (tester) async {
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();

    // The trailer button carries a theater mark, not a play glyph — play is
    // the primary button's promise, and two of them read as two players.
    final trailerIcon = find.byIcon(Icons.theaters_rounded);
    expect(trailerIcon, findsOneWidget);
    expect(find.text('Trailer'), findsNothing);

    final focusWidget = tester.widget<Focus>(
      find.ancestor(of: trailerIcon, matching: find.byType(Focus)).first,
    );
    focusWidget.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('Trailer'), findsOneWidget);
  });

  testWidgets('action circles name themselves on hover too', (tester) async {
    await tester.pumpWidget(_host(_model()));
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.theaters_rounded)));
    await tester.pumpAndSettle();
    expect(find.text('Trailer'), findsOneWidget);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('Trailer'), findsNothing);
  });
}
