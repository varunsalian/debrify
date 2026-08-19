import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/section_reveal.dart';

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

DetailModel _model({
  void Function(bool)? onDepth,
  bool isMovie = false,
  VoidCallback? onBrowse,
  ImdbEnrichment? extra,
  ParentsGuideResult? guide,
  void Function(StremioMeta)? onRecommendationTap,
}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: isMovie ? 'movie' : 'series',
    name: 'A Show',
    description: 'A synopsis long enough to be clamped on a phone, where two '
        'lines is all the identity affords before MORE.',
    year: '2008',
    genres: const ['Crime', 'Drama'],
  );
  return DetailModel(
    item: item,
    isMovie: isMovie,
    isTelevision: false,
    accent: const Color(0xFFABA124),
    imdbExtra: extra ??
        const ImdbEnrichment(
          cast: [
            CastMember(name: 'A Person', character: 'Someone'),
            CastMember(name: 'B Person', character: 'Someone Else'),
          ],
        ),
    parentsGuide: guide,
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
    onBrowse: onBrowse,
    onTrailer: () {},
    onSelectSource: () {},
    onAppMenu: () {},
    onTraktMenu: () {},
    onSimklMenu: () {},
    onTrackers: () {},
    onManageSources: () {},
    onRecommendationTap: onRecommendationTap ?? (_) {},
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
  // The band reveal is token-driven, and `fromDetail` carries no entrance —
  // so a test that wants one has to say so, the way `ThemeSpec` does for the
  // Looks that ship it (Spotlight is `fadeUp`).
  EntranceStyle? entrance,
  AppTheme? theme,
}) =>
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: AppThemeScope(
          theme: theme ??
              AppTheme.fromDetail(
                DetailThemes.byId('signal'),
                motion: entrance == null
                    ? null
                    : MotionTokens.of(MotionCharacter.settle)
                        .copyWith(entrance: entrance),
              ),
          child: Scaffold(
            body: DetailShowcase(
              model: m,
              dpad: dpad,
              episodesHost: m.isMovie
                  ? null
                  : (builder) => Builder(
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

  testWidgets('a movie mounts the source BROWSE — identity circle and band '
      'card — and both fire onBrowse', (tester) async {
    _surface(tester, _phone);
    var browsed = 0;
    await tester.pumpWidget(_host(
      _model(isMovie: true, onBrowse: () => browsed++),
      dpad: false,
      size: _phone,
    ));
    await tester.pumpAndSettle();

    // The identity's layers circle (Showcase shipped without ANY route to
    // the movie source list — the band's cards go to the BINDING manager).
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.layers_rounded));
    expect(browsed, 1);

    // And the band's labelled entry beside "Pin source".
    await tester.drag(find.byType(DetailShowcase), const Offset(0, -900));
    await tester.pumpAndSettle();
    final browseCard = find.text('⌕  Browse all', skipOffstage: false);
    expect(browseCard, findsOneWidget);
    await tester.ensureVisible(browseCard);
    await tester.pumpAndSettle();
    await tester.tap(browseCard, warnIfMissed: false);
    expect(browsed, 2);
  });

  testWidgets('a series mounts the browse under pack wording — it opens the '
      'season-pack search, not "all sources"', (tester) async {
    _surface(tester, _phone);
    var browsed = 0;
    await tester.pumpWidget(_host(
      _model(onBrowse: () => browsed++),
      dpad: false,
      size: _phone,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.layers_rounded));
    expect(browsed, 1);

    await tester.drag(find.byType(DetailShowcase), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('⌕  Browse all', skipOffstage: false), findsNothing);
    final packCard = find.text('⌕  Season packs', skipOffstage: false);
    expect(packCard, findsOneWidget);
    await tester.ensureVisible(packCard);
    await tester.pumpAndSettle();
    await tester.tap(packCard, warnIfMissed: false);
    expect(browsed, 2);
  });

  testWidgets('a series whose host offers no pack search mounts NO browse',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(_host(
      _model(),
      dpad: false,
      size: _phone,
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.layers_rounded), findsNothing);
    expect(find.text('⌕  Browse all', skipOffstage: false), findsNothing);
    expect(find.text('⌕  Season packs', skipOffstage: false), findsNothing);
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

  // ── IMDb enrichment: honors chips, Parents Guide, Universe, Did You Know ─

  const honorsExtra = ImdbEnrichment(
    top250Rank: 1,
    meterRank: 21,
    meterDelta: -1,
  );

  ParentsGuideResult pg() => const ParentsGuideResult(categories: [
        ParentsGuideCategory(
          id: 'violence',
          label: 'Violence & Gore',
          severity: 'Moderate',
          severityVotes: 204,
          totalVotes: 262,
          items: [
            ParentsGuideItem(text: 'Several fist fights.'),
            ParentsGuideItem(text: 'A death near the end.', isSpoiler: true),
          ],
        ),
        ParentsGuideCategory(
          id: 'profanity',
          label: 'Profanity',
          severity: 'Severe',
          severityVotes: 231,
          totalVotes: 258,
          items: [ParentsGuideItem(text: 'Frequent strong language.')],
        ),
      ]);

  const uniExtra = ImdbEnrichment(universe: [
    UniverseTitle(
      imdbId: 'tt3032476',
      name: 'Better Call Saul',
      relation: 'Followed by',
      year: 2015,
      endYear: 2022,
      isSeries: true,
    ),
    UniverseTitle(
      imdbId: 'tt9243946',
      name: 'El Camino',
      relation: 'Followed by',
      year: 2019,
    ),
  ]);

  const dykExtra = ImdbEnrichment(
    didYouKnow: [
      DidYouKnowEntry(kind: 'Trivia', text: 'A fact about the production.'),
      DidYouKnowEntry(kind: 'Quote', text: 'I am the one who knocks!'),
    ],
    triviaTotal: 15,
    goofsTotal: 3,
    quotesTotal: 2,
  );

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('honors chips render on both tiers, and only when ranked',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(
        _host(_model(extra: honorsExtra), dpad: false, size: _phone));
    await tester.pumpAndSettle();
    expect(find.text('№1'), findsOneWidget);
    expect(find.text('№21'), findsOneWidget);
    expect(find.text(' ▾1'), findsOneWidget,
        reason: 'a falling meter shows its drift');

    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(), dpad: true, size: _tv));
    await tester.pumpAndSettle();
    expect(find.textContaining('TOP 250'), findsNothing,
        reason: 'no rank → no chip, no reserved space');
  });

  testWidgets('the guide band renders cards whose plate follows the tap',
      (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(
        _host(_model(guide: pg()), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    final cards = find.text('Violence & Gore', skipOffstage: false);
    expect(cards, findsNWidgets(2),
        reason: 'the category card plus the plate header');
    expect(find.text('Several fist fights.', skipOffstage: false),
        findsOneWidget);
    expect(find.text('A death near the end.', skipOffstage: false),
        findsNothing,
        reason: 'spoiler entries are withheld, not rendered');
    expect(
        find.text('1 spoiler entry hidden', skipOffstage: false),
        findsOneWidget);

    await reveal(
        tester, find.text('Profanity', skipOffstage: false).first);
    await tester.tap(find.text('Profanity').first);
    await tester.pumpAndSettle();
    expect(find.text('Frequent strong language.', skipOffstage: false),
        findsOneWidget,
        reason: 'the plate follows the selected card');
  });

  testWidgets('the wide plate SHOW pill reveals spoilers', (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(
        _host(_model(guide: pg()), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('SHOW', skipOffstage: false));
    await tester.tap(find.text('SHOW'));
    await tester.pumpAndSettle();
    expect(find.text('A death near the end.', skipOffstage: false),
        findsOneWidget);
    expect(find.text('HIDE'), findsOneWidget);
  });

  testWidgets('compact guide is an accordion: closed rows, tap to open',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(
        _host(_model(guide: pg()), dpad: false, size: _phone));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Violence & Gore', skipOffstage: false));
    expect(find.text('Several fist fights.'), findsNothing,
        reason: 'rows start collapsed');
    await tester.tap(find.text('Violence & Gore'));
    await tester.pumpAndSettle();
    expect(find.text('Several fist fights.'), findsOneWidget);
    // Its spoiler stays withheld until this row's own SHOW.
    expect(find.text('A death near the end.'), findsNothing);
    await tester.tap(find.text('SHOW'));
    await tester.pumpAndSettle();
    expect(find.text('A death near the end.'), findsOneWidget);
  });

  testWidgets('a universe card opens through the recommendation door with a '
      'synthesized meta', (tester) async {
    final opened = <StremioMeta>[];
    _surface(tester, _tv);
    await tester.pumpWidget(_host(
      _model(isMovie: true, extra: uniExtra, onRecommendationTap: opened.add),
      dpad: true,
      size: _tv,
    ));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Better Call Saul', skipOffstage: false));
    expect(find.text('FOLLOWED BY', skipOffstage: false), findsNWidgets(2));
    expect(find.text('2015–2022', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Better Call Saul'));
    expect(opened, hasLength(1));
    expect(opened.single.imdbId, 'tt3032476');
    expect(opened.single.type, 'series');

    await tester.tap(find.text('El Camino'));
    expect(opened, hasLength(2));
    expect(opened.last.type, 'movie');
  });

  testWidgets('did you know renders mixed cards, the count line, and the +N '
      'terminal card', (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(
      _model(isMovie: true, extra: dykExtra),
      dpad: true,
      size: _tv,
    ));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Did You Know', skipOffstage: false));
    expect(find.text('15 trivia · 3 goofs · 2 quotes'), findsOneWidget);
    expect(find.text('TRIVIA', skipOffstage: false), findsOneWidget);
    expect(find.text('“I am the one who knocks!”', skipOffstage: false),
        findsOneWidget, reason: 'quotes are set in quotation marks');
    expect(find.text('+18', skipOffstage: false), findsOneWidget,
        reason: '20 total, 2 mounted — the rest live on IMDb');
  });

  testWidgets('absent data mounts none of the new surfaces', (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(), dpad: true, size: _tv));
    await tester.pumpAndSettle();

    expect(find.text('Parents Guide', skipOffstage: false), findsNothing);
    expect(find.text('Universe', skipOffstage: false), findsNothing);
    expect(find.text('Did You Know', skipOffstage: false), findsNothing);
  });

  // ── the band reveal ───────────────────────────────────────────────────────
  //
  // Touch has no band cursor: nothing lifts, nothing parks, and the only thing
  // that moves is the page. So each band arrives as it crosses into the
  // viewport. The property that matters most is the failure DIRECTION — a band
  // that never gets its trigger must end up visible, not stranded at opacity 0
  // with the page apparently missing its content. `section_reveal_test.dart`
  // owns that guarantee at the widget level; these cover the page's wiring.

  testWidgets('a band below the fold waits, then arrives on scroll',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(_host(_model(),
        dpad: false, size: _phone, entrance: EntranceStyle.fadeUp));
    await tester.pumpAndSettle();

    // The hero deliberately stops short of a full screenful to leave the next
    // band PEEKING, so Seasons is already on screen — and a band you can see
    // has arrived, rather than waiting for a scroll that may never come.
    expect(_bandOpacity(tester, 'seasons'), 1,
        reason: 'the peek band is visible at rest, so it has already arrived');

    // Cast sits a screenful further down. Mounted — `cacheExtent` builds well
    // past the fold — but not yet arrived, which is exactly the case a
    // mount-triggered reveal gets wrong.
    expect(_bandOpacity(tester, 'cast'), 0,
        reason: 'built ahead of the fold, but not revealed');

    await tester.drag(find.byType(DetailShowcase), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(_bandOpacity(tester, 'cast'), 1);
  });

  testWidgets('stepping the ladder into a band snaps it to rest first',
      (tester) async {
    _surface(tester, _phone);
    await tester.pumpWidget(_host(_model(),
        dpad: false, size: _phone, entrance: EntranceStyle.fadeUp));
    await tester.pumpAndSettle();
    expect(_bandOpacity(tester, 'cast'), 0);

    // dpad:false pages still receive arrow keys from real keyboards, and the
    // ladder parks the band it steps into with `Scrollable.ensureVisible` —
    // which composes the paint transforms of every ancestor. Measuring a band
    // through a half-played entrance parks it off its `rest` alignment, so
    // the band is snapped to rest BEFORE the scroll is computed.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    expect(_bandOpacity(tester, 'cast'), 1,
        reason: 'the band the cursor stepped into is at rest, not mid-reveal');
  });

  testWidgets('a look with no entrance token shows its bands outright',
      (tester) async {
    _surface(tester, _phone);
    // No `entrance:` — the default `EntranceStyle.none`, which must mean the
    // band is simply there rather than a band that waits for a trigger the
    // look never intends to fire.
    await tester.pumpWidget(_host(_model(), dpad: false, size: _phone));
    await tester.pumpAndSettle();

    expect(_revealWrappers(tester, 'seasons'), 0,
        reason: 'no entrance means no reveal wrapper at all, not opacity 0');
  });

  testWidgets('DPAD keeps its own choreography — no reveal wrapper',
      (tester) async {
    _surface(tester, _tv);
    await tester.pumpWidget(_host(_model(),
        dpad: true, size: _tv, entrance: EntranceStyle.fadeUp));
    await tester.pumpAndSettle();

    // An entrance here would animate against `_reveal`'s parking scroll, which
    // is what puts a band on screen when the remote steps into it.
    expect(find.byKey(const ValueKey('showcase-band-seasons'),
        skipOffstage: false), findsNothing);
    expect(find.byType(SectionReveal, skipOffstage: false), findsNothing);
  });
}

/// The reveal's own [FadeTransition] — the outermost one under the band's key,
/// which is [SectionReveal]'s, not any fade a cell paints inside itself.
///
/// `skipOffstage: false` on EVERY finder here, the inner one included: the
/// band that matters most is one built ahead of the fold, and a sliver's cache
/// region counts as offstage — so a default `byType` finds nothing inside it
/// however the descendant finder is configured.
double _bandOpacity(WidgetTester t, String id) => t
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byKey(ValueKey('showcase-band-$id'), skipOffstage: false),
        matching: find.byType(FadeTransition, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .first
    .opacity
    .value;

/// How many reveal wrappers the band actually mounted.
///
/// Counts [SectionReveal.activeKey] rather than a widget TYPE: asserting that
/// no `FadeTransition` exists anywhere under the band would also fail the day
/// a season pill or a poster gains a cross-fade of its own, sending the next
/// maintainer to the reveal to debug a change they made elsewhere.
int _revealWrappers(WidgetTester t, String id) => find
    .descendant(
      of: find.byKey(ValueKey('showcase-band-$id'), skipOffstage: false),
      matching: find.byKey(SectionReveal.activeKey, skipOffstage: false),
      skipOffstage: false,
    )
    .evaluate()
    .length;
