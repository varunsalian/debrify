import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/episodes_screen.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A cached service client resolves the fixture in the request's live zone.
final _episodesFixtureZoneKey = Object();

class EpisodesPanelFixture {
  EpisodesPanelFixture(this.caseName, int identity) {
    id = 'tt98${identity.toString().padLeft(5, '0')}';
    show = StremioMeta(
      id: id,
      imdbId: id,
      type: 'series',
      name: 'Original Episodes',
      year: '2026',
    );
    addon = StremioAddon(
      id: 'episodes-original-$caseName',
      name: 'Original',
      baseUrl: 'https://episodes-original.invalid',
      manifestUrl: 'https://episodes-original.invalid/manifest.json',
      resources: const ['meta'],
      types: const ['series'],
    );
  }
  final String caseName;
  late String id;
  late StremioMeta show;
  late StremioAddon addon;
  final key = GlobalKey<EpisodesPanelState>();
  final navigator = GlobalKey<NavigatorState>();
  final requests = <http.Request>[];
  final calls = <String>[];
  final selections = <AdvancedSearchSelection>[];
  final quickSelections = <AdvancedSearchSelection>[];
  final played = <TraktEpisode>[];
  final nextEmissions = <({EpisodeResumeTarget target, bool mutation})>[];
  final completionEmissions = <bool>[];
  final sourceItems = <StremioMeta>[];
  EpisodesPanelView? latest;
  EpisodesPanelView get view => latest!;
  bool television = false, compact = false, chrome = false, custom = true;
  bool hasItem = true, hasQuick = true, hasPlay = false, direct = false;
  bool hasLeft = true;
  bool failMeta = false, hasSourcePicker = false, scopeError = false;
  int? initialSeason, initialEpisode;
  int sourceCount = 0;
  bool traktSource = false, mdblistSource = false;
  bool simklFails = false, mdblistFails = false;
  int? initialRating;
  bool remotelyWatched = false;
  ({int season, int episode})? trackerNext;
  Map<String, double> progress = {};
  Map<String, double> traktPlayback = {}, simklPlayback = {};
  Map<String, double> mdblistPlayback = {};
  Future<Map<String, double>> Function()? progressLoader;
  Future<List<TraktSeason>> Function()? injectedSeasons;
  Future<void> Function(StremioMeta)? sourcePicker;
  Future<http.Response?> Function(http.Request)? onRequest;
  List<Map<String, Object?>>? videosOverride;
  List<Map<String, Object?>> get videos =>
      videosOverride ??
      [
        for (final season in [1, 2])
          for (final number in [1, 2])
            {
              'id': '$id:$season:$number',
              'season': season,
              'episode': number,
              'title': season == 1 && number == 1
                  ? 'Pilot'
                  : 'Episode $season.$number',
              'overview': 'An original episode.',
              'released': '2026-01-01T00:00:00Z',
              'imdbRating': 7.5,
            },
      ];
  List<TraktSeason> get directSeasons => [
    for (final season in [1, 2])
      TraktSeason(
        number: season,
        episodeCount: 2,
        episodes: [
          for (final number in [1, 2])
            TraktEpisode(
              season: season,
              number: number,
              title: number == 1 ? 'Pilot' : 'Second',
              playbackUrl: 'https://direct.invalid/$season/$number',
            ),
        ],
      ),
  ];
  String requestIdentity(http.Request r) =>
      '${r.method} ${r.url.host}${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}';
  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    final override = await onRequest?.call(r);
    if (override != null) return override;
    Object? body = [];
    var status = 200;
    if (r.url.host == 'episodes-original.invalid') {
      status = failMeta ? 500 : 200;
      body = failMeta
          ? {}
          : {
              'meta': {'videos': videos},
            };
    } else if (r.url.host == 'api.tvmaze.com') {
      status = r.url.path == '/shows/1' ? 200 : 404;
      body = r.url.path == '/shows/1' ? {'id': 1} : {};
    } else if (r.url.host == 'api.trakt.tv') {
      if (r.url.path.endsWith('/seasons')) {
        status = failMeta ? 500 : 200;
        body = [];
      } else if (r.url.path.contains('/progress/watched')) {
        body = {
          'seasons': [
            {
              'number': 1,
              'episodes': [
                {'number': 1, 'completed': remotelyWatched},
                {'number': 2, 'completed': false},
              ],
            },
          ],
          if (trackerNext != null)
            'next_episode': {
              'season': trackerNext!.season,
              'number': trackerNext!.episode,
            },
        };
      } else if (r.url.path == '/sync/playback/episodes') {
        body = [
          for (final entry in traktPlayback.entries)
            {
              'id': 101,
              'progress': entry.value,
              'show': {
                'ids': {'imdb': id},
              },
              'episode': {
                'season': int.parse(entry.key.split('-').first),
                'number': int.parse(entry.key.split('-').last),
              },
            },
        ];
      } else if (r.url.path.startsWith('/search/')) {
        body = [
          {
            'type': 'show',
            'show': {
              'ids': {'imdb': id, 'trakt': 991},
              'title': show.name,
            },
          },
        ];
      }
    } else if (r.url.host == 'api.simkl.com') {
      if (r.url.path == '/sync/watched') {
        body = [
          {
            'result': true,
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  if (remotelyWatched) {'number': 1, 'watched': true},
                ],
              },
            ],
          },
        ];
      } else if (r.url.path == '/sync/all-items/all/all') {
        body = {
          'shows': [
            {
              'show': {
                'title': show.name,
                'ids': id.startsWith('tmdb:')
                    ? {'tmdb': int.parse(id.split(':').last)}
                    : {'imdb': id},
              },
              'status': 'watching',
            },
          ],
        };
      } else if (r.url.path == '/sync/playback/episodes') {
        body = [
          for (final entry in simklPlayback.entries)
            {
              'id': 981,
              'progress': entry.value,
              'show': {
                'ids': {'imdb': id},
              },
              'episode': {
                'season': int.parse(entry.key.split('-').first),
                'number': int.parse(entry.key.split('-').last),
              },
            },
        ];
      } else if (r.url.path == '/sync/playback/981') {
        status = 204;
        body = null;
      } else if (r.url.path.startsWith('/sync/history')) {
        status = simklFails ? 500 : 200;
        body = {
          'added': {'episodes': simklFails ? 0 : 1},
          'deleted': {'episodes': simklFails ? 0 : 1},
        };
      }
    } else if (r.url.host == 'api.mdblist.com') {
      if (r.url.path == '/sync/ratings' && r.method == 'GET') {
        body = [
          if (initialRating != null)
            {
              'show_ids': {'imdb': id},
              'season': 1,
              'episode': 1,
              'rating': initialRating,
            },
        ];
      } else if (r.url.path.startsWith('/sync/') && r.method == 'POST') {
        status = mdblistFails ? 500 : 200;
        body = {'success': true};
      } else if (r.url.path == '/sync/playback') {
        body = [
          for (final entry in mdblistPlayback.entries)
            {
              'id': 992,
              'type': 'episode',
              'progress': entry.value,
              'show': {
                'ids': {'imdb': id},
              },
              'episode': {
                'season': int.parse(entry.key.split('-').first),
                'number': int.parse(entry.key.split('-').last),
              },
            },
        ];
      } else if (r.url.path.contains('/sync/history/show/')) {
        body = {
          'plays': [
            if (remotelyWatched) {'season_num': 1, 'episode_num': 1},
          ],
        };
      } else if (r.url.path.startsWith('/show/')) {
        body = {
          'ids': {'imdb': id, 'tmdb': 991},
          'title': show.name,
        };
      }
    }
    return http.Response(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        if (r.url.host == 'api.trakt.tv' &&
            r.url.path == '/sync/playback/episodes')
          'x-pagination-page-count': '1',
      },
    );
  }

  Future<void> rememberCanonical() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'catalog_progress_identity_v1:${addon.portableConfigurationKey}:${show.id}',
      show.effectiveImdbId ?? show.id,
    );
  }

  Future<void> authenticate(Set<TrackingSource> sources) async {
    if (sources.contains(TrackingSource.trakt)) {
      await TraktStorage.setTraktAccessToken('episodes-test-trakt');
      await TraktStorage.setTraktTokenExpiry(
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
    }
    if (sources.contains(TrackingSource.simkl)) {
      await SimklStorage.setSimklAccessToken('episodes-test-simkl');
    }
    if (sources.contains(TrackingSource.mdblist)) {
      await MdblistStorage.saveMdblistApiKey('episodes-test-mdblist');
    }
  }

  EpisodesPanel panel() => EpisodesPanel(
    key: key,
    show: show,
    addon: addon,
    initialSeason: initialSeason,
    initialEpisode: initialEpisode,
    isTelevision: television,
    showChrome: chrome,
    compact: compact,
    isTraktSource: traktSource,
    isMdblistSource: mdblistSource,
    onItemSelected: hasItem
        ? (s) {
            calls.add('item');
            selections.add(s);
          }
        : null,
    onQuickPlay: hasQuick
        ? (s) {
            calls.add('quick');
            quickSelections.add(s);
          }
        : null,
    onPlayEpisode: hasPlay
        ? (e) {
            calls.add('directPlay');
            played.add(e);
          }
        : null,
    onBeforeTerminalDispatch: () => calls.add('before'),
    onBack: () => calls.add('back'),
    onFocusLeftEdge: hasLeft ? () => calls.add('left') : null,
    boundSourceCount: (s) {
      sourceItems.add(s);
      return sourceCount;
    },
    onSelectSource: hasSourcePicker
        ? (s) async {
            calls.add('selectSource');
            sourceItems.add(s);
            await sourcePicker?.call(s);
          }
        : null,
    seasonsLoader: direct
        ? () async {
            calls.add('seasons');
            return injectedSeasons == null
                ? directSeasons
                : await injectedSeasons!();
          }
        : null,
    watchProgressLoader:
        progressLoader ??
        (direct
            ? () async {
                calls.add('progress');
                return progress;
              }
            : null),
    onNextEpisodeChanged: (target, {mutation = false}) =>
        nextEmissions.add((target: target, mutation: mutation)),
    onSeriesCompletedChanged: completionEmissions.add,
    contentBuilder: custom
        ? (context, v) {
            latest = v;
            return Column(
              children: [
                Text('season:${v.selectedSeasonNumber} loading:${v.loading}'),
                for (final e in v.episodes)
                  Text('${e.title}: ${v.progressOf(e)}'),
              ],
            );
          }
        : null,
  );
  Widget shell(Widget child) => RepaintBoundary(
    key: const ValueKey('episodes-application-canvas'),
    child: MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppThemeScope(
        theme: AppThemes.legacy,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
      ),
      home: RepaintBoundary(
        key: const ValueKey('episodes-canvas'),
        child: Scaffold(body: child),
      ),
    ),
  );
  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(900, 1200),
    bool wait = true,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    PlatformUtil.debugSetAndroidTvCached(television);
    if (failMeta && !scopeError) await t.runAsync(rememberCanonical);
    await t.pumpWidget(shell(panel()));
    if (wait) await finish(t);
  }

  Future<void> mountScreen(
    WidgetTester t, {
    Size size = const Size(390, 844),
    bool pushed = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    PlatformUtil.debugSetAndroidTvCached(television);
    final screen = EpisodesScreen(
      show: show,
      addon: addon,
      isTelevision: television,
      onItemSelected: (s) {
        calls.add('item:${navigator.currentState!.canPop()}');
        selections.add(s);
      },
      onQuickPlay: (s) {
        calls.add('quick');
        quickSelections.add(s);
      },
      boundSourceCount: (_) => sourceCount,
      onSelectSource: hasSourcePicker ? sourcePicker ?? (_) async {} : null,
    );
    if (failMeta && !scopeError) await t.runAsync(rememberCanonical);
    await t.pumpWidget(shell(pushed ? const Text('Host') : screen));
    if (pushed) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kCatalogDetailRouteName),
          builder: (_) => const Scaffold(body: Text('Catalog')),
        ),
      );
      await t.pump();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kEpisodesRouteName),
          builder: (_) => screen,
        ),
      );
      await t.pump();
    }
    await finish(t);
  }

  Future<void> finish(WidgetTester t) async {
    await until(
      t,
      () => custom && key.currentState != null
          ? latest != null &&
                !view.loading &&
                (view.unavailable || view.episodes.isNotEmpty)
          : find.textContaining('Pilot').evaluate().isNotEmpty ||
                (failMeta &&
                    requests.any(
                      (r) =>
                          r.url.host == 'api.trakt.tv' &&
                          r.url.path.endsWith('/seasons'),
                    )),
    );
    for (var frame = 0; frame < 20; frame++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
  }

  Future<void> until(
    WidgetTester t,
    bool Function() ready, {
    Duration frame = Duration.zero,
  }) async {
    for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(frame);
    }
    expect(ready(), isTrue, reason: 'Original panel fixture did not finish');
  }

  Future<void> sheet(WidgetTester t) async {
    view.options(view.episodes.first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Play'), findsOneWidget);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    t.view.reset();
    PlatformUtil.debugSetAndroidTvCached(null);
    expect(t.takeException(), isNull);
  }
}

Future<void> episodesPanelCase(
  WidgetTester t,
  String name,
  int identity,
  Future<void> Function(EpisodesPanelFixture) body, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'episodes-original');
  TraktService.instance.resetProfileScope();
  SimklService.instance.resetProfileScope();
  final fixture = EpisodesPanelFixture(name, identity);
  try {
    await runZoned(
      () => http.runWithClient(
        () async {
          MdblistService.instance.resetProfileScope();
          try {
            await t.runAsync(TVMazeService.clearCache);
            await body(fixture);
          } finally {
            await fixture.close(t);
            await t.runAsync(TVMazeService.clearCache);
          }
        },
        () => MockClient((request) {
          final current =
              Zone.current[_episodesFixtureZoneKey] as EpisodesPanelFixture;
          return current.respond(request);
        }),
      ),
      zoneValues: {_episodesFixtureZoneKey: fixture},
    );
  } finally {
    ProfileRuntime.debugReset();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    SecretVault.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
  }
}
