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
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/episodes_panel.dart';

/// Drives every detail layout with the DPAD journeys a TV remote actually
/// performs, and asserts the cursor lands where the layout promises.
///
/// The core contract, for every layout that shows episodes:
///   * DOWN from the action row reaches the episode collection.
///   * The episode cells themselves are then reachable (season control is a
///     waypoint, not a wall).
///   * UP from the collection returns to the action row.
///   * A side-pane layout also honors RIGHT into the pane and LEFT back out.

const _tv = Size(960, 540);

TraktEpisode _ep(int n) => TraktEpisode(
  season: 5,
  number: n,
  title: 'Episode $n',
  overview: 'Synopsis for episode $n.',
  rating: 8.1,
  firstAired: '2012-07-${n.toString().padLeft(2, '0')}',
  runtime: 47,
);

final _episodes = [for (var i = 1; i <= 8; i++) _ep(i)];

EpisodesPanelView _view({
  required bool manySeasons,
  int episodeCount = 8,
  int landingNumber = 1,
  EpisodeFocusIntent focusIntent = EpisodeFocusIntent.none,
}) {
  final episodes = episodeCount == 8
      ? _episodes
      : [for (var i = 1; i <= episodeCount; i++) _ep(i)];
  return EpisodesPanelView(
    seasons: [
      if (manySeasons)
        const TraktSeason(number: 4, episodeCount: 8, episodes: []),
      TraktSeason(
        number: 5,
        episodeCount: episodeCount,
        episodes: episodes,
      ),
    ],
    selectedSeasonNumber: 5,
    episodes: episodes,
    loading: false,
    unavailable: false,
    showImageUrl: null,
    generation: 1,
    landing: episodes[landingNumber - 1],
    focusIntent: focusIntent,
    progressOf: (_) => null,
    isNext: (e) => e.number == landingNumber,
    play: (_) {},
    options: (_) {},
    stepSeason: (_) {},
    selectSeason: (_) {},
    onLeftEdge: null,
    onRetry: () {},
    onSearchForSources: () {},
  );
}

DetailModel _model({bool withParentsGuide = false}) {
  final item = StremioMeta(
    id: 'tt0903747',
    imdbId: 'tt0903747',
    type: 'series',
    name: 'A Show',
    poster: null,
    background: null,
    description: 'A synopsis.',
    year: '2008',
    genres: const ['Crime', 'Drama'],
  );
  return DetailModel(
    item: item,
    isMovie: false,
    isTelevision: true,
    accent: const Color(0xFFABA124),
    imdbExtra: null,
    parentsGuide: withParentsGuide
        ? const ParentsGuideResult(
            categories: [
              ParentsGuideCategory(
                id: 'violence',
                label: 'Violence & Gore',
                severity: 'Moderate',
                severityVotes: 12,
                totalVotes: 18,
                items: [ParentsGuideItem(text: 'Some action violence.')],
              ),
            ],
          )
        : null,
    recommendations: const [],
    primaryLabel: 'Resume',
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
    onBrowse: null,
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

Widget _layout(
  String id,
  DetailModel m, {
  required bool manySeasons,
  int episodeCount = 8,
  int landingNumber = 1,
  EpisodeFocusIntent focusIntent = EpisodeFocusIntent.none,
}) {
  Widget host(Widget Function(BuildContext, EpisodesPanelView) b) => Builder(
    builder: (c) => b(
      c,
      _view(
        manySeasons: manySeasons,
        episodeCount: episodeCount,
        landingNumber: landingNumber,
        focusIntent: focusIntent,
      ),
    ),
  );
  return switch (id) {
    'marquee' => DetailMarquee(model: m, episodesHost: host),
    'dossier' => DetailDossier(model: m, episodesHost: host),
    'stage' => DetailStage(model: m, episodesHost: host),
    'console' => DetailConsole(model: m, episodesHost: host),
    'vista' => DetailPremium(
      kind: PremiumDetailKind.vista,
      model: m,
      episodesHost: host,
    ),
    'monolith' => DetailPremium(
      kind: PremiumDetailKind.monolith,
      model: m,
      episodesHost: host,
    ),
    'mosaic' => DetailPremium(
      kind: PremiumDetailKind.mosaic,
      model: m,
      episodesHost: host,
    ),
    'halo' => DetailPremium(
      kind: PremiumDetailKind.halo,
      model: m,
      episodesHost: host,
    ),
    'premiere' => DetailPremium(
      kind: PremiumDetailKind.premiere,
      model: m,
      episodesHost: host,
    ),
    _ => throw ArgumentError(id),
  };
}

Future<DetailModel> _pump(
  WidgetTester tester,
  String layoutId, {
  required bool manySeasons,
  bool withParentsGuide = false,
  int episodeCount = 8,
  int landingNumber = 1,
  EpisodeFocusIntent focusIntent = EpisodeFocusIntent.none,
}) async {
  tester.view.physicalSize = _tv;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final model = _model(withParentsGuide: withParentsGuide);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: DetailThemes.signal.ground,
          body: DetailThemeScope(
            theme: DetailThemes.signal,
            child: _layout(
              layoutId,
              model,
              manySeasons: manySeasons,
              episodeCount: episodeCount,
              landingNumber: landingNumber,
              focusIntent: focusIntent,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  return model;
}

String _focusLabel() =>
    FocusManager.instance.primaryFocus?.debugLabel ?? '<none>';

bool _onEpisodeCell() => _focusLabel().contains(':5-');

Future<void> _key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pump();
  // Post-frame focus hand-offs (requestFocus in a callback) settle next frame.
  await tester.pump();
}

/// Presses DOWN up to [max] times, returning after the first press that lands
/// on an episode cell. Returns the number of presses used, or -1.
Future<int> _downToEpisodes(WidgetTester tester, {int max = 4}) async {
  for (var i = 1; i <= max; i++) {
    await _key(tester, LogicalKeyboardKey.arrowDown);
    if (_onEpisodeCell()) return i;
  }
  return -1;
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

  group('DOWN from Play reaches the episodes (multi-season)', () {
    for (final id in layouts) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id, manySeasons: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        if (id == 'dossier') {
          // Dossier crosses panes with RIGHT, by design.
          await _key(tester, LogicalKeyboardKey.arrowRight);
          expect(
            _onEpisodeCell() || _focusLabel() == 'dossier-season',
            isTrue,
            reason: 'RIGHT landed on ${_focusLabel()}',
          );
          if (!_onEpisodeCell()) {
            await _key(tester, LogicalKeyboardKey.arrowDown);
            expect(_onEpisodeCell(), isTrue,
                reason: 'DOWN from season landed on ${_focusLabel()}');
          }
          return;
        }
        final presses = await _downToEpisodes(tester);
        expect(presses, greaterThan(0),
            reason: 'never reached an episode cell; stuck on ${_focusLabel()}');
      });
    }
  });

  group('DOWN from Play reaches the episodes (single season)', () {
    for (final id in layouts) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id, manySeasons: false);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        if (id == 'dossier') {
          await _key(tester, LogicalKeyboardKey.arrowRight);
          expect(_onEpisodeCell(), isTrue,
              reason: 'RIGHT landed on ${_focusLabel()}');
          return;
        }
        final presses = await _downToEpisodes(tester);
        expect(presses, greaterThan(0),
            reason: 'never reached an episode cell; stuck on ${_focusLabel()}');
      });
    }
  });

  group('episodes stay reachable after a Continue Watching landing reveal', () {
    // The engine lands a resumed series deep in the season (S5E18 of 24) and
    // the layout scrolls the list there before the user touches the remote.
    // That unmounts the earliest cells — but their FocusNodes keep a STALE
    // context (detach never clears it), so a `context != null` "mounted" check
    // returns a dead node and the hand-off into the collection becomes a dead
    // key. This is the on-device bug the 8-episode fixtures could never hit.
    Future<void> settleReveal(WidgetTester tester) async {
      // revealDetailLanding converges over up to 8 post-frame retries.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    for (final manySeasons in [true, false]) {
      final label = manySeasons ? 'multi-season' : 'single season';
      for (final id in layouts) {
        testWidgets('$id ($label)', (tester) async {
          final m = await _pump(
            tester,
            id,
            manySeasons: manySeasons,
            episodeCount: 24,
            landingNumber: 18,
            focusIntent: EpisodeFocusIntent.landing,
          );
          await settleReveal(tester);
          m.focus.primaryEntry.requestFocus();
          await tester.pump();
          if (id == 'dossier') {
            await _key(tester, LogicalKeyboardKey.arrowRight);
            if (!_onEpisodeCell()) {
              await _key(tester, LogicalKeyboardKey.arrowDown);
            }
            expect(_onEpisodeCell(), isTrue,
                reason: 'RIGHT/DOWN landed on ${_focusLabel()}');
            return;
          }
          final presses = await _downToEpisodes(tester);
          expect(presses, greaterThan(0),
              reason:
                  'never reached an episode cell; stuck on ${_focusLabel()}');
        });
      }
    }

    for (final id in ['monolith', 'premiere']) {
      testWidgets('$id: RIGHT still crosses into the scrolled pane',
          (tester) async {
        final m = await _pump(
          tester,
          id,
          manySeasons: false,
          episodeCount: 24,
          landingNumber: 18,
          focusIntent: EpisodeFocusIntent.landing,
        );
        await settleReveal(tester);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        // Walk the action line; onRightEdge fires at its end and must cross
        // into the pane even though the pane has scrolled deep.
        var crossed = false;
        for (var i = 0; i < 8 && !crossed; i++) {
          await _key(tester, LogicalKeyboardKey.arrowRight);
          crossed = _onEpisodeCell();
        }
        expect(crossed, isTrue, reason: 'RIGHT landed on ${_focusLabel()}');
      });
    }
  });

  group('DOWN from Play still reaches episodes with a Parents Guide', () {
    for (final id in layouts.where((l) => l != 'dossier')) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id,
            manySeasons: true, withParentsGuide: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        final presses = await _downToEpisodes(tester, max: 5);
        expect(presses, greaterThan(0),
            reason: 'never reached an episode cell; stuck on ${_focusLabel()}');
      });
    }
  });

  group('UP from the first episode returns toward the actions', () {
    for (final id in layouts) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id, manySeasons: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        if (id == 'dossier') {
          await _key(tester, LogicalKeyboardKey.arrowRight);
        } else {
          await _downToEpisodes(tester);
        }
        if (!_onEpisodeCell()) return; // covered by the reach tests above
        // UP as many times as it takes (season control is a legal waypoint).
        for (var i = 0; i < 4; i++) {
          await _key(tester, LogicalKeyboardKey.arrowUp);
          if (m.focus.primaryEntry.hasFocus || m.focus.backNode.hasFocus) {
            return;
          }
        }
        // Stage parks on the tab strip, which is its sanctioned waypoint.
        if (id == 'stage') {
          expect(_focusLabel(), startsWith('stage-tab-'),
              reason: 'UP stranded on ${_focusLabel()}');
          return;
        }
        fail('UP never returned to the actions; stuck on ${_focusLabel()}');
      });
    }
  });

  group('side-pane layouts honor RIGHT into the episodes', () {
    for (final id in const ['monolith', 'premiere']) {
      for (final guide in const [false, true]) {
        testWidgets('$id${guide ? ' with guide' : ''}', (tester) async {
          final m = await _pump(tester, id,
              manySeasons: true, withParentsGuide: guide);
          m.focus.primaryEntry.requestFocus();
          await tester.pump();
          // RIGHT walks the action row to its end, then must cross straight
          // into the pane — never dead-stop, never detour through the guide.
          var crossed = false;
          for (var i = 0; i < 10; i++) {
            await _key(tester, LogicalKeyboardKey.arrowRight);
            if (_onEpisodeCell() || _focusLabel() == 'premium-season') {
              crossed = true;
              break;
            }
          }
          expect(crossed, isTrue,
              reason: 'RIGHT never crossed; stuck on ${_focusLabel()}');
        });
      }
    }
  });

  group('LEFT from a vertical episode list returns to the actions', () {
    for (final id in const ['monolith', 'premiere', 'dossier']) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id, manySeasons: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        if (id == 'dossier') {
          await _key(tester, LogicalKeyboardKey.arrowRight);
          if (!_onEpisodeCell()) {
            await _key(tester, LogicalKeyboardKey.arrowDown);
          }
        } else {
          await _downToEpisodes(tester);
        }
        if (!_onEpisodeCell()) return;
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(m.focus.primaryEntry.hasFocus, isTrue,
            reason: 'LEFT landed on ${_focusLabel()}');
      });
    }
  });

  group('walking the collection stays on episode cells', () {
    // Rails advance with RIGHT; vertical lists and the console grid with DOWN.
    const walkKey = {
      'marquee': LogicalKeyboardKey.arrowRight,
      'vista': LogicalKeyboardKey.arrowRight,
      'halo': LogicalKeyboardKey.arrowRight,
      'mosaic': LogicalKeyboardKey.arrowRight,
      'monolith': LogicalKeyboardKey.arrowDown,
      'premiere': LogicalKeyboardKey.arrowDown,
      'dossier': LogicalKeyboardKey.arrowDown,
      'stage': LogicalKeyboardKey.arrowDown,
      'console': LogicalKeyboardKey.arrowRight,
    };
    for (final id in layouts) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id, manySeasons: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        if (id == 'dossier') {
          await _key(tester, LogicalKeyboardKey.arrowRight);
          if (!_onEpisodeCell()) {
            await _key(tester, LogicalKeyboardKey.arrowDown);
          }
        } else {
          await _downToEpisodes(tester);
        }
        expect(_onEpisodeCell(), isTrue,
            reason: 'never entered; stuck on ${_focusLabel()}');
        for (var i = 0; i < 3; i++) {
          await _key(tester, walkKey[id]!);
          expect(_onEpisodeCell(), isTrue,
              reason: 'walk step ${i + 1} escaped to ${_focusLabel()}');
        }
      });
    }
  });

  group('the Parents Guide button is reachable when a guide exists', () {
    // vista/halo reach it by walking RIGHT along the action row; the
    // side-pane layouts by walking DOWN (RIGHT is their pane crossing);
    // mosaic through the feature tile into the facts tile.
    const route = {
      'vista': LogicalKeyboardKey.arrowRight,
      'halo': LogicalKeyboardKey.arrowRight,
      'monolith': LogicalKeyboardKey.arrowDown,
      'premiere': LogicalKeyboardKey.arrowDown,
    };
    for (final id in const ['vista', 'monolith', 'halo', 'premiere']) {
      testWidgets(id, (tester) async {
        final m = await _pump(tester, id,
            manySeasons: true, withParentsGuide: true);
        m.focus.primaryEntry.requestFocus();
        await tester.pump();
        var reached = false;
        for (var i = 0; i < 6; i++) {
          await _key(tester, route[id]!);
          if (_focusLabel() == 'premium-guide') {
            reached = true;
            break;
          }
        }
        expect(reached, isTrue,
            reason: 'guide unreachable; last stop ${_focusLabel()}');
      });
    }

    testWidgets('mosaic', (tester) async {
      final m = await _pump(tester, 'mosaic',
          manySeasons: true, withParentsGuide: true);
      m.focus.primaryEntry.requestFocus();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await _key(tester, LogicalKeyboardKey.arrowRight);
        if (_focusLabel() == 'premium-continue') break;
      }
      expect(_focusLabel(), 'premium-continue',
          reason: 'feature tile unreachable');
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusLabel(), 'premium-guide',
          reason: 'DOWN from feature landed on ${_focusLabel()}');
    });
  });

  group('the cursor survives dynamic view swaps', () {
    // The real EpisodesPanel swaps the view on load completion and on season
    // change; both bump the generation, which retires every episode FocusNode.
    // These journeys prove the cursor lands correctly across those swaps.

    EpisodesPanelView seasonView(
      int seasonNumber,
      int generation,
      EpisodeFocusIntent intent,
      void Function(int) stepTo, {
      bool loading = false,
    }) {
      final eps = [
        for (var i = 1; i <= 8; i++)
          TraktEpisode(
            season: seasonNumber,
            number: i,
            title: 'S$seasonNumber E$i',
            overview: '',
            rating: 8.0,
            firstAired: '2012-07-${i.toString().padLeft(2, '0')}',
            runtime: 47,
          ),
      ];
      return EpisodesPanelView(
        seasons: [
          TraktSeason(number: 4, episodeCount: 8, episodes: const []),
          TraktSeason(number: 5, episodeCount: 8, episodes: const []),
        ],
        selectedSeasonNumber: seasonNumber,
        episodes: loading ? const [] : eps,
        loading: loading,
        unavailable: false,
        showImageUrl: null,
        generation: generation,
        landing: loading ? null : eps.first,
        focusIntent: intent,
        progressOf: (_) => null,
        isNext: (_) => false,
        play: (_) {},
        options: (_) {},
        stepSeason: (d) => stepTo(seasonNumber + d),
        selectSeason: stepTo,
        onLeftEdge: null,
        onRetry: () {},
        onSearchForSources: () {},
      );
    }

    for (final id in const ['vista', 'premiere', 'marquee', 'console']) {
      testWidgets('$id · season step keeps the season control focused',
          (tester) async {
        tester.view.physicalSize = _tv;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final model = _model();
        final viewState = ValueNotifier<(int, int, EpisodeFocusIntent)>(
          (5, 1, EpisodeFocusIntent.none),
        );
        addTearDown(viewState.dispose);
        void stepTo(int season) {
          viewState.value = (
            season,
            viewState.value.$2 + 1,
            EpisodeFocusIntent.seasonControl,
          );
        }

        Widget host(Widget Function(BuildContext, EpisodesPanelView) b) =>
            ValueListenableBuilder<(int, int, EpisodeFocusIntent)>(
              valueListenable: viewState,
              builder: (context, s, _) =>
                  b(context, seasonView(s.$1, s.$2, s.$3, stepTo)),
            );
        Widget layout = switch (id) {
          'marquee' => DetailMarquee(model: model, episodesHost: host),
          'console' => DetailConsole(model: model, episodesHost: host),
          'vista' => DetailPremium(
            kind: PremiumDetailKind.vista,
            model: model,
            episodesHost: host,
          ),
          _ => DetailPremium(
            kind: PremiumDetailKind.premiere,
            model: model,
            episodesHost: host,
          ),
        };
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: DetailThemes.signal.ground,
                body: DetailThemeScope(
                  theme: DetailThemes.signal,
                  child: layout,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        model.focus.primaryEntry.requestFocus();
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await _key(tester, LogicalKeyboardKey.arrowDown);
          if (_focusLabel().endsWith('-season')) break;
        }
        expect(_focusLabel(), endsWith('-season'),
            reason: 'never reached season control; on ${_focusLabel()}');

        // LEFT steps to season 4 — a full view swap with a new generation.
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 50));
        expect(viewState.value.$1, 4, reason: 'stepSeason did not fire');
        expect(_focusLabel(), endsWith('-season'),
            reason: 'season swap dropped the cursor to ${_focusLabel()}');

        // DOWN now enters the NEW season's cells.
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(_focusLabel(), contains(':4-'),
            reason: 'DOWN after swap landed on ${_focusLabel()}');
      });
    }

    testWidgets('vista · DOWN works right after loading finishes',
        (tester) async {
      tester.view.physicalSize = _tv;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final model = _model();
      final loading = ValueNotifier<bool>(true);
      addTearDown(loading.dispose);
      Widget host(Widget Function(BuildContext, EpisodesPanelView) b) =>
          ValueListenableBuilder<bool>(
            valueListenable: loading,
            builder: (context, isLoading, _) => b(
              context,
              seasonView(
                5,
                isLoading ? 1 : 2,
                isLoading
                    ? EpisodeFocusIntent.none
                    : EpisodeFocusIntent.landing,
                (_) {},
                loading: isLoading,
              ),
            ),
          );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: _tv, devicePixelRatio: 1.0),
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: DetailThemes.signal.ground,
              body: DetailThemeScope(
                theme: DetailThemes.signal,
                child: DetailPremium(
                  kind: PremiumDetailKind.vista,
                  model: model,
                  episodesHost: host,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      model.focus.primaryEntry.requestFocus();
      await tester.pump();

      // DOWN while loading may walk the action row's wrapped lines, but must
      // never strand the cursor (a bare scope with nothing focused).
      for (var i = 0; i < 3; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
        final primary = FocusManager.instance.primaryFocus;
        expect(primary, isNotNull, reason: 'press ${i + 1} killed focus');
        expect(primary, isNot(isA<FocusScopeNode>()),
            reason: 'press ${i + 1} stranded focus on a bare scope');
      }

      loading.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      model.focus.primaryEntry.requestFocus();
      await tester.pump();
      final presses = await _downToEpisodes(tester);
      expect(presses, greaterThan(0),
          reason: 'DOWN after load never reached episodes; on ${_focusLabel()}');
    });
  });

  group('mosaic feature tile routes', () {
    testWidgets('RIGHT from actions reaches the feature tile and DOWN leaves it',
        (tester) async {
      final m = await _pump(tester, 'mosaic', manySeasons: true);
      m.focus.primaryEntry.requestFocus();
      await tester.pump();
      var onFeature = false;
      for (var i = 0; i < 8; i++) {
        await _key(tester, LogicalKeyboardKey.arrowRight);
        if (_focusLabel() == 'premium-continue') {
          onFeature = true;
          break;
        }
      }
      expect(onFeature, isTrue,
          reason: 'feature tile unreachable; stuck on ${_focusLabel()}');
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(
        _onEpisodeCell() ||
            _focusLabel() == 'premium-season' ||
            _focusLabel() == 'premium-guide',
        isTrue,
        reason: 'DOWN from feature landed on ${_focusLabel()}',
      );
    });
  });
}
