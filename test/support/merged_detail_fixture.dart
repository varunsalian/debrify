import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef MergedResume = ({bool started, int? season, int? episode});
typedef MergedPromise = ({bool started, int season, int episode});

class MergedObserver extends NavigatorObserver {
  final events = <String>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('push:${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop:${route.settings.name}');
  }
}

class MergedDetailFixture {
  final key = GlobalKey<State<MergedDetailScreen>>();
  final navigator = GlobalKey<NavigatorState>();
  final observer = MergedObserver();
  final calls = <String>[];
  final promises = <MergedPromise?>[];
  final quickSelections = <AdvancedSearchSelection>[];
  final directEpisodes = <TraktEpisode>[];
  final selections = <AdvancedSearchSelection>[];
  final requests = <http.Request>[];
  final sourceItems = <StremioMeta>[];
  StremioMeta item = const StremioMeta(
    id: 'merged-original-series',
    type: 'series',
    name: 'Original Series',
    description: 'A fixed original-code characterization fixture.',
    year: '2026',
    genres: ['Drama'],
    runtime: '42 min',
  );
  StremioAddon addon = StremioAddon(
    id: 'merged-original',
    name: 'Original',
    manifestUrl: '',
    baseUrl: '',
  );
  MergedResume resume = (started: false, season: null, episode: null);
  Completer<MergedResume>? heldResume;
  Completer<void>? heldLaunch;
  Completer<List<StremioMeta>>? heldRecommendations;
  List<StremioMeta> recommendations = [];
  final openedRecommendations = <StremioMeta>[];
  bool failResume = false;
  bool xtream = false, television = false, restart = true, quick = true;
  int count = 2;
  bool paused = false;
  bool menus = false, showPrimary = true, canSelectSource = true;
  TraktTitleStatus? traktStatus;
  SimklTitleStatus? simklStatus;
  MdblistTitleStatus? mdblistStatus;
  Completer<TraktTitleStatus?>? heldTraktStatus;
  Completer<SimklTitleStatus?>? heldSimklStatus;
  Completer<MdblistTitleStatus?>? heldMdblistStatus;
  Future<void> Function(StremioMeta)? onSelectSource;
  Future<void> Function(String)? onAction;
  Future<void> Function()? onRestart;

  Map<String, double> progress = {};
  Future<http.Response> Function(http.Request)? onRequest;
  final episodes = [
    TraktEpisode(season: 1, number: 1, title: 'Pilot'),
    TraktEpisode(season: 1, number: 2, title: 'Second'),
  ];
  Map<String, Object?> get access => mergedDetailTestAccess(key.currentState!);
  DetailModel get model => (access['model'] as DetailModel Function())();
  EpisodesPanel get panel =>
      find.byType(EpisodesPanel).evaluate().single.widget as EpisodesPanel;
  void next(EpisodeResumeTarget target, {bool mutation = false}) =>
      (access['nextEpisode']
          as void Function(EpisodeResumeTarget, {bool mutation}))(
        target,
        mutation: mutation,
      );
  Future<void> loadResume() =>
      (access['loadResume'] as Future<void> Function())();
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    if (onRequest != null) return onRequest!(request);
    return http.Response(jsonEncode({}), 404);
  }

  Future<MergedResume> resumeLoader() async {
    calls.add('resume');
    if (failResume) throw StateError('Original loader failure');
    return heldResume?.future ?? resume;
  }

  Future<List<TraktSeason>> seasonsLoader() async {
    calls.add('seasons');
    return [TraktSeason(number: 1, episodeCount: 2, episodes: episodes)];
  }

  Future<Map<String, double>> progressLoader() async {
    calls.add('progress');
    return progress;
  }

  int sourceCount(StremioMeta value) {
    sourceItems.add(value);
    return count;
  }

  Future<void> selectSource(StremioMeta value) async {
    calls.add('selectSource');
    sourceItems.add(value);
    await onSelectSource?.call(value);
  }

  List<TraktMenuOption> traktOptions(TraktTitleStatus? status) => [
    ...buildTraktAddOnlyMenuOptions(
      isMovie: item.type == 'movie',
      isSeries: item.type == 'series',
      status: status,
    ),
    if (paused)
      const TraktMenuOption(
        action: TraktItemMenuAction.removeFromTraktPlayback,
        icon: Icons.delete_outline,
        color: Colors.red,
        label: 'Remove from Trakt Continue Watching',
        caption: 'Remove playback',
        isTrakt: true,
      ),
  ];
  Future<void> action(String value) async {
    calls.add(value);
    await onAction?.call(value);
  }

  Future<void> mount(
    WidgetTester t, {
    String style = 'classic',
    Size size = const Size(1200, 900),
    bool wait = true,
    bool pushed = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    PlatformUtil.debugSetAndroidTvCached(television);
    await DetailPageStorage.setDetailPageStyle(style);
    final screen = MergedDetailScreen(
      key: key,
      item: item,
      addon: addon,
      isTelevision: television,
      showQuickPlay: showPrimary,
      onResume: (promise) async {
        calls.add('resumePlay');
        promises.add(promise);
        await heldLaunch?.future;
      },
      onRewatch: restart
          ? () async {
              calls.add('restart');
              await onRestart?.call();
            }
          : null,
      resumeInfoLoader: resumeLoader,
      recommendationsLoader: () async {
        calls.add('recommendations');
        return heldRecommendations?.future ?? recommendations;
      },
      onRecommendationTap: openedRecommendations.add,
      onBrowse: () => calls.add('movieBrowse'),
      onBrowsePrimaryEpisodeSources: (promise) async {
        calls.add('episodeBrowse');
        promises.add(promise);
      },
      onQuickPlay: quick
          ? (selection) async {
              calls.add('quickPlay');
              quickSelections.add(selection);
            }
          : null,
      onItemSelected: (selection) {
        calls.add('itemSelected');
        selections.add(selection);
      },
      boundSourceCount: sourceCount,
      onSelectSource: canSelectSource ? selectSource : null,
      traktStatusLoader: () async {
        calls.add('trakt');
        return heldTraktStatus?.future ?? traktStatus;
      },
      simklStatusLoader: () async {
        calls.add('simkl');
        return heldSimklStatus?.future ?? simklStatus;
      },
      mdblistStatusLoader: () async {
        calls.add('mdblist');
        return heldMdblistStatus?.future ?? mdblistStatus;
      },
      traktMenuOptions: menus ? traktOptions(traktStatus) : const [],
      traktMenuBuilder: menus ? traktOptions : null,
      simklMenuOptions: menus
          ? buildSimklMenuOptions(
              inContinueWatching: paused,
              isSimklAuthenticated: true,
              isSeries: item.type == 'series',
              status: simklStatus,
            )
          : const [],
      simklMenuBuilder: menus
          ? (status) => buildSimklMenuOptions(
              inContinueWatching: paused,
              isSimklAuthenticated: true,
              isSeries: item.type == 'series',
              status: status,
            )
          : null,
      mdblistMenuOptions: menus
          ? buildMdblistMenuOptions(
              authenticated: true,
              isSeries: item.type == 'series',
              status: mdblistStatus,
            )
          : const [],
      mdblistMenuBuilder: menus
          ? (status) => buildMdblistMenuOptions(
              authenticated: true,
              isSeries: item.type == 'series',
              status: status,
            )
          : null,
      onTraktAction: menus ? (a) => action('traktAction:${a.name}') : null,
      onSimklAction: menus ? (a) => action('simklAction:${a.name}') : null,
      onMdblistAction: menus ? (a) => action('mdblistAction:${a.name}') : null,
      seasonsLoader: xtream ? seasonsLoader : null,
      onPlayEpisode: xtream
          ? (episode) async {
              calls.add('directPlay');
              directEpisodes.add(episode);
            }
          : null,
      watchProgressLoader: xtream ? progressLoader : null,
    );
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver, observer],
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
        home: pushed
            ? const Scaffold(body: Text('Host'))
            : RepaintBoundary(
                key: const ValueKey('merged-canvas'),
                child: screen,
              ),
      ),
    );
    if (pushed) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kCatalogDetailRouteName),
          builder: (_) => screen,
        ),
      );
      await t.pump();
    }
    if (wait) await finishOpening(t);
  }

  Future<void> finishOpening(WidgetTester t) async {
    await until(t, () => model.openingDataReady && calls.contains('mdblist'));
    // The post-frame callback does not request a frame. Fixed bounded pumps
    // explicitly paint the completed fake futures and finish reveal delays.
    for (var frame = 0; frame < 12; frame++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    expect(ready(), isTrue, reason: 'Original merged action did not finish');
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 13));
    await t.pump();
    t.view.reset();
    PlatformUtil.debugSetAndroidTvCached(null);
    expect(t.takeException(), isNull);
  }
}

Future<void> mergedDetailCase(
  WidgetTester t,
  Future<void> Function(MergedDetailFixture) body, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'detail_trailer_autoplay_enabled': false,
    ...preferences,
  });
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'merged-original');
  TraktService.instance.resetProfileScope();
  SimklService.instance.resetProfileScope();
  MdblistService.instance.resetProfileScope();
  final fixture = MergedDetailFixture();
  try {
    await http.runWithClient(() async {
      try {
        await body(fixture);
      } finally {
        await fixture.close(t);
      }
    }, () => MockClient(fixture.respond));
  } finally {
    ProfileRuntime.debugReset();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    SecretVault.debugReset();
  }
}
