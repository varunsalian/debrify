import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_layout_stage.dart';
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

DetailModel _model({required bool isMovie, bool isTelevision = false}) {
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
    accent: const Color(0xFFABA124),
    imdbExtra: null,
    parentsGuide: null,
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
  _ => DetailConsole(model: m, episodesHost: m.isMovie ? null : _host),
};

Future<void> _pump(
  WidgetTester tester,
  String layoutId,
  DetailTheme theme, {
  required bool isMovie,
  required Size size,
  required bool isTelevision,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, devicePixelRatio: 1.0),
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
  const layouts = ['marquee', 'dossier', 'stage', 'console'];

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
