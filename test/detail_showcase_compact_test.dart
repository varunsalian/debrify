import 'package:flutter/material.dart';
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

/// Showcase's compact (phone) presentation and touch drivers.
///
/// The contract under test: `dpad:false` under 600 wide renders the compact
/// widgets (integrated episode card, season pill + anchored popup, kebab) and
/// drives the ambient dissolve from SCROLL; `dpad:true` at the TV size renders
/// byte-for-byte what shipped, whatever the width. The band topology always
/// matches the rendering — compact's seasons band carries exactly one node.
TraktEpisode _ep(int n) => TraktEpisode(
      season: 5,
      number: n,
      title: 'Episode $n',
      overview: 'Synopsis $n.',
      firstAired: '2012-07-0$n',
      runtime: 47,
    );

EpisodesPanelView _view({
  required bool manySeasons,
  int count = 5,
  void Function(TraktEpisode)? options,
  void Function(int)? selectSeason,
}) {
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
    options: options ?? (_) {},
    stepSeason: (_) {},
    selectSeason: selectSeason ?? (_) {},
    onLeftEdge: null,
    onRetry: () {},
    onSearchForSources: () {},
  );
}

DetailModel _model({void Function(bool)? onDepth}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: 'series',
    name: 'A Show',
    description: 'A synopsis long enough to be clamped on a phone, where two '
        'lines is all the identity affords before MORE.',
    year: '2008',
    genres: const ['Crime', 'Drama'],
  );
  return DetailModel(
    item: item,
    isMovie: false,
    isTelevision: false,
    accent: const Color(0xFFABA124),
    imdbExtra: const ImdbEnrichment(
      cast: [
        CastMember(name: 'A Person', character: 'Someone'),
        CastMember(name: 'B Person', character: 'Someone Else'),
      ],
    ),
    parentsGuide: null,
    recommendations: const [],
    primaryLabel: 'Resume',
    sourceCount: 0,
    boundSources: const [],
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

void _surface(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _host(
  DetailModel m, {
  required bool dpad,
  required Size size,
  bool manySeasons = true,
  void Function(TraktEpisode)? options,
  void Function(int)? selectSeason,
}) =>
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: Scaffold(
            body: DetailShowcase(
              model: m,
              dpad: dpad,
              episodesHost: (builder) => Builder(
                builder: (context) => builder(
                  context,
                  _view(
                    manySeasons: manySeasons,
                    options: options,
                    selectSeason: selectSeason,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

const _phone = Size(390, 844);
const _tv = Size(960, 540);

void main() {
  testWidgets('compact renders the integrated episode card', (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(_host(_model(), dpad: false, size: _phone));
    await tester.pumpAndSettle();

    expect(
      find.byType(ShowcaseEpisodeCardCompact, skipOffstage: false),
      findsWidgets,
      reason: 'under 600 wide with touch, the cell is one integrated card',
    );
    expect(find.byType(ShowcaseEpisodeCell, skipOffstage: false), findsNothing);

    // Its geometry is the measured one: 62% of the width.
    final card = find
        .byType(ShowcaseEpisodeCardCompact, skipOffstage: false)
        .first;
    expect(tester.getSize(card).width, closeTo(390 * 0.62, 0.5));
  });

  testWidgets('on TV nothing changes — the wide cell, no kebab',
      (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    expect(
        find.byType(ShowcaseEpisodeCell, skipOffstage: false), findsWidgets);
    expect(find.byType(ShowcaseEpisodeCardCompact, skipOffstage: false),
        findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded, skipOffstage: false),
        findsNothing,
        reason: 'hold-OK is the TV options gesture; the kebab is touch-only');
  });

  testWidgets('the compact kebab fires options', (tester) async {
    _surface(tester, _phone);
    TraktEpisode? optioned;
    await tester.pumpWidget(_host(
      _model(),
      dpad: false,
      size: _phone,
      options: (e) => optioned = e,
    ));
    await tester.pumpAndSettle();

    // Bring the episode band on screen.
    await tester.drag(
        find.byType(DetailShowcase), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byIcon(Icons.more_vert_rounded).first, warnIfMissed: false);
    expect(optioned, isNotNull);
    expect(optioned!.number, 1);
  });

  testWidgets('compact seasons are a pill whose popup selects',
      (tester) async {
    _surface(tester, _phone);
    int? selected;
    await tester.pumpWidget(_host(
      _model(),
      dpad: false,
      size: _phone,
      selectSeason: (n) => selected = n,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(DetailShowcase), const Offset(0, -500));
    await tester.pumpAndSettle();

    // The pill, not the chip rail.
    final pill = find.text('Season 5');
    expect(pill, findsOneWidget);
    // Chips would render one control per season; the pill renders one total.
    expect(find.text('Season 4'), findsNothing);

    await tester.tap(pill);
    await tester.pumpAndSettle();
    // The anchored popup lists both seasons now.
    expect(find.text('Season 4'), findsOneWidget);

    await tester.tap(find.text('Season 4'));
    await tester.pumpAndSettle();
    expect(selected, 4);
  });

  testWidgets('the popup dismisses on an outside tap, selecting nothing',
      (tester) async {
    _surface(tester, _phone);
    int? selected;
    await tester.pumpWidget(_host(
      _model(),
      dpad: false,
      size: _phone,
      selectSeason: (n) => selected = n,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(DetailShowcase), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 5'));
    await tester.pumpAndSettle();
    expect(find.text('Season 4'), findsOneWidget);

    await tester.tapAt(const Offset(370, 830));
    await tester.pumpAndSettle();
    expect(find.text('Season 4'), findsNothing);
    expect(selected, isNull);
  });

  testWidgets('TV keeps the chip rail — one control per season',
      (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    expect(find.text('Season 4', skipOffstage: false), findsOneWidget);
    expect(find.text('Season 5', skipOffstage: false), findsOneWidget);
  });

  testWidgets('scroll drives the dissolve on touch, with hysteresis',
      (tester) async {
    _surface(tester, _phone);
    final depths = <bool>[];
    await tester.pumpWidget(_host(
      _model(onDepth: depths.add),
      dpad: false,
      size: _phone,
    ));
    await tester.pumpAndSettle();

    ShowcaseAmbient ambient() =>
        tester.widget<ShowcaseAmbient>(find.byType(ShowcaseAmbient));

    expect(ambient().visible, isFalse,
        reason: 'the page opens on sharp key art');

    // Deep: past 40% of the viewport.
    await tester.drag(find.byType(DetailShowcase), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(ambient().visible, isTrue,
        reason: 'touch has no band focus — the scroll is the depth driver');
    expect(depths.last, isTrue,
        reason: 'the parent swaps its backdrop off this signal');

    // A wiggle around the boundary must not flap: back up to ~35% (inside
    // the 30–40% hysteresis window) stays deep…
    await tester.drag(find.byType(DetailShowcase), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(ambient().visible, isTrue,
        reason: 'between 30% and 40% the previous state holds');

    // …and only dropping under 30% goes shallow again.
    await tester.drag(find.byType(DetailShowcase), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(ambient().visible, isFalse);
    expect(depths.last, isFalse);
  });

  testWidgets('on TV the dissolve stays band-driven — scroll alone moves it '
      'nowhere', (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(DetailShowcase), const Offset(0, -600));
    await tester.pumpAndSettle();
    final ambient =
        tester.widget<ShowcaseAmbient>(find.byType(ShowcaseAmbient));
    expect(ambient.visible, isFalse,
        reason: 'the DPAD page answers depth with the band cursor, and the '
            'cursor never left the identity');
  });

  testWidgets('the compact identity is centered with a MORE expander',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(_host(_model(), dpad: false, size: _phone));
    await tester.pumpAndSettle();

    expect(find.text('MORE'), findsOneWidget);
    await tester.tap(find.text('MORE'));
    await tester.pumpAndSettle();
    expect(find.text('LESS'), findsOneWidget,
        reason: 'the synopsis expands in place and can be re-collapsed');
  });
}
