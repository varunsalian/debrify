import 'dart:async';
import 'dart:io';

import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_detail_http_transport.dart';

typedef CatalogResume = ({bool started, int? season, int? episode});

/// Observes only the mounted view, host callbacks, stores and HTTP. There is
/// deliberately no State accessor and no production seam.
class CatalogDetailFixture {
  static int _serial = 0;
  final String imdb = 'tt${(9100000 + ++_serial).toString()}';
  final navigator = GlobalKey<NavigatorState>();
  final calls = <String>[];
  final artwork = <PlayLoaderArt>[];
  final requests = <http.Request>[];
  final opened = <StremioMeta>[];
  final traktActions = <TraktItemMenuAction>[];
  final simklActions = <SimklItemMenuAction>[];
  final mdblistActions = <MdblistItemMenuAction>[];
  late StremioMeta item = meta();
  bool television = true, quick = true, restart = true, hold = true;
  bool episodeSources = true, resumeEnabled = true, simklEnabled = true;
  bool failResume = false;
  CatalogResume resume = (started: false, season: null, episode: null);
  Completer<CatalogResume>? heldResume;
  Completer<List<StremioMeta>>? heldRecommendations;
  List<StremioMeta> recommendations = [];
  List<TraktMenuOption> traktOptions = [];
  List<SimklMenuOption> simklOptions = [];
  List<MdblistMenuOption> mdblistOptions = [];
  Future<StremioMeta?> Function(String, String)? enricher;
  Future<void> Function()? onRestart;
  Future<http.Response> Function(http.Request)? onRequest;
  int closed = 0;

  StremioMeta meta({
    String type = 'movie',
    bool rich = true,
    String? background,
    String? poster,
    String? name,
    String? description,
    String? id,
  }) => StremioMeta(
    id: id ?? imdb,
    imdbId: id == null ? imdb : null,
    type: type,
    name: name ?? 'Original Catalog',
    description:
        description ?? (rich ? 'A fixed original-code catalog fixture.' : null),
    year: rich ? '2026' : null,
    genres: rich ? const ['Drama'] : null,
    runtime: rich ? '104 min' : null,
    background: background,
    poster: poster,
  );

  Future<http.Response> respond(http.Request r) async {
    requests.add(r);
    if (r.url.host == 'catalog-fixture.invalid') {
      return http.Response.bytes(
        File('test/goldens/catalog_detail/artwork.png').readAsBytesSync(),
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    return onRequest == null ? http.Response('{}', 404) : await onRequest!(r);
  }

  Future<CatalogResume> loadResume() async {
    calls.add('resume');
    if (failResume) throw StateError('Original resume failure');
    return heldResume?.future ?? resume;
  }

  CatalogItemDetailScreen screen() => CatalogItemDetailScreen(
    item: item,
    isTelevision: television,
    showQuickPlay: quick,
    hasBoundSource: false,
    enablePrimarySourcesHold: hold,
    onPlay: () => calls.add('play'),
    onRewatch: restart
        ? () {
            calls.add('restart');
            unawaited(onRestart?.call());
          }
        : null,
    onBrowse: () => calls.add('browse'),
    onBrowsePrimaryEpisodeSources: episodeSources
        ? () async {
            calls.add('episode');
          }
        : null,
    resumeInfoLoader: resumeEnabled ? loadResume : null,
    simklStatusLoader: simklEnabled
        ? () async {
            calls.add('simkl');
            return null;
          }
        : null,
    recommendationsLoader: () async {
      calls.add('recommendations');
      return heldRecommendations?.future ?? recommendations;
    },
    onRecommendationTap: opened.add,
    metaEnricher: enricher,
    onLoaderArt: (a) {
      calls.add('art');
      artwork.add(a);
    },
    traktMenuOptions: traktOptions,
    onTraktAction: traktActions.add,
    simklMenuOptions: simklOptions,
    onSimklAction: simklActions.add,
    mdblistMenuOptions: mdblistOptions,
    onMdblistAction: mdblistActions.add,
  );

  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(1200, 900),
    bool wait = true,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    PlatformUtil.debugSetAndroidTvCached(television);
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver],
        locale: const Locale('en', 'US'),
        builder: (c, child) => AppThemeScope(
          theme: AppThemes.legacy,
          child: MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
        ),
        home: RepaintBoundary(
          key: const ValueKey('catalog-canvas'),
          child: screen(),
        ),
      ),
    );
    if (wait) await finish(t);
  }

  Future<void> finish(WidgetTester t) async {
    // Drain real asynchronous preferences/HTTP without changing fake time.
    for (var i = 0; i < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    // All ordinary captures use this exact 1.2 s fake-clock reveal timeline.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    expect(ready(), true, reason: 'Original catalog observable did not finish');
  }

  Future<void> tap(WidgetTester t, String text) async {
    final target = find.text(text).first;
    await t.ensureVisible(target);
    await t.pump();
    await t.tap(target);
    await t.pump();
  }

  Future<void> cover(WidgetTester t) async {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> uncover(WidgetTester t) async {
    navigator.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await until(t, () => calls.contains('resume'));
  }

  Future<void> close(WidgetTester t) async {
    if (closed++ == 0) {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 13));
      await t.pump();
      t.view.reset();
      PlatformUtil.debugSetAndroidTvCached(null);
      expect(t.takeException(), isNull);
    }
  }
}

Future<void> catalogDetailCase(
  WidgetTester t,
  Future<void> Function(CatalogDetailFixture) body, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  SecretVault.debugReset(deviceIdOverride: 'catalog-original');
  TraktService.instance.resetProfileScope();
  SimklService.instance.resetProfileScope();
  MdblistService.instance.resetProfileScope();
  final f = CatalogDetailFixture();
  try {
    await http.runWithClient(
      () => HttpOverrides.runZoned(() async {
        try {
          await body(f);
        } finally {
          await f.close(t);
        }
      }, createHttpClient: (_) => CatalogFixtureHttpClient()),
      () => MockClient(f.respond),
    );
  } finally {
    ProfileRuntime.debugReset();
    TraktService.instance.resetProfileScope();
    SimklService.instance.resetProfileScope();
    MdblistService.instance.resetProfileScope();
    SecretVault.debugReset();
  }
}
