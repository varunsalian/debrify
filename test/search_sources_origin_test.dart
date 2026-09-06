import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart' show buildSearchSources;
import 'package:debrify/screens/search_screen.dart' show SearchScreen;
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites;

// Real a94a5196 factory/UI/TPS/store. Only HTTP and the physical preference
// transport are held. No provider, player, caller-refresh or rollback proof.
const _id = 'tt1234567';
const _key = 'series_source_$_id';
const _physicalKey = 'flutter.$_key';
const _signedUrl =
    'https://video.invalid/movie.mp4?synthetic-signature=expired';
const _limit = Duration(seconds: 20);

class _HeldStore extends InMemorySharedPreferencesStore {
  _HeldStore(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();
  final writes = <(String, String, Object)>[];
  bool? result;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _physicalKey) return super.setValue(type, key, value);
    writes.add((type, key, value));
    if (!entered.isCompleted) entered.complete();
    await release.future.timeout(_limit);
    result = await super.setValue(type, key, value);
    if (!completed.isCompleted) completed.complete();
    return result!;
  }

  Future<Map<String, Object>> physical() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

class _Routes extends NavigatorObserver {
  final pops = <Route<dynamic>>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops.add(route);
    super.didPop(route, previousRoute);
  }
}

Future<void> _case(
  WidgetTester tester, {
  required bool holdHttp,
  required bool userPop,
}) async {
  await prepareFavourites(tester);
  final previousStore = SharedPreferencesStorePlatform.instance;
  final service = StremioService.instance;
  final previousClient = service.debugStreamHttpClientFactory;
  final requests = <Uri>[];
  final unexpected = <Uri>[];
  final httpEntered = Completer<void>();
  final httpRelease = Completer<void>();
  final httpCompleted = Completer<void>();
  final routes = _Routes();
  final navigator = GlobalKey<NavigatorState>();
  final addon = StremioAddon(
    id: 'sources.origin',
    name: 'Origin source',
    manifestUrl: 'https://sources.invalid/manifest.json',
    baseUrl: 'https://sources.invalid',
    resources: ['stream'],
    types: ['movie'],
  );
  final seeded = await SharedPreferences.getInstance();
  await seeded.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
  await seeded.setString('sources_origin_sentinel', 'unchanged');
  final backend = _HeldStore({
    for (final key in seeded.getKeys()) 'flutter.$key': seeded.get(key)!,
  });
  final initial = await backend.physical();
  var routeCompleted = 0;
  Map<String, Object>? finalPhysical;
  List<SeriesSource>? finalPublic;
  final client = MockClient((request) async {
    requests.add(request.url);
    if (request.method != 'GET' ||
        request.url.toString() !=
            'https://sources.invalid/stream/movie/$_id.json') {
      unexpected.add(request.url);
      throw StateError('Unexpected Sources fixture HTTP transport');
    }
    if (!httpEntered.isCompleted) httpEntered.complete();
    if (holdHttp) await httpRelease.future.timeout(_limit);
    if (!httpCompleted.isCompleted) httpCompleted.complete();
    return http.Response(
      jsonEncode({
        'streams': [
          {
            'name': 'Origin source',
            'description': 'Origin movie 1080p',
            'url': _signedUrl,
          },
        ],
      }),
      200,
    );
  });
  try {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    service.invalidateCache();
    service.debugStreamHttpClientFactory = () => client;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await tester.runAsync(() => EngineRegistry.instance.initialize());
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          home: const Scaffold(body: Text('Sources origin parent')),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => buildSearchSources(
          selection: const AdvancedSearchSelection(
            imdbId: _id,
            isSeries: false,
            title: 'Origin movie',
            contentType: 'movie',
          ),
          meta: const PlaybackMeta(
            imdbId: _id,
            title: 'Origin movie',
            contentType: 'movie',
          ),
          isTelevision: false,
          bindMode: !holdHttp,
        ),
      );
      unawaited(
        navigator.currentState!.push(route).then((_) {
          routeCompleted++;
        }),
      );
      await pumpFavourites(tester);
      expect(httpEntered.isCompleted, isTrue);
      expect(unexpected, isEmpty);
      expect(requests, [
        Uri.parse('https://sources.invalid/stream/movie/$_id.json'),
      ]);
      if (holdHttp) {
        expect(find.byType(SourceRow), findsNothing);
        navigator.currentState!.pop();
        await pumpFavourites(tester);
        expect(routes.pops, [route]);
        expect(routeCompleted, 1);
        httpRelease.complete();
        await pumpFavourites(tester);
        expect(httpCompleted.isCompleted, isTrue);
        expect(find.byType(SourceRow), findsNothing);
        expect(backend.writes, isEmpty);
      } else {
        expect(find.byType(SourceRow), findsOneWidget);
        await tester.tap(find.byType(SourceRow));
        await tester.pump();
        await tester.tap(find.byType(SourceRow));
        await tester.pump();
        expect(backend.entered.isCompleted, isTrue);
        expect(backend.writes, hasLength(1));
        expect(backend.writes.single.$1, 'String');
        expect(backend.writes.single.$2, _physicalKey);
        expect(await backend.physical(), initial);
        // SDK cache is optimistic; it is not evidence of a durable write.
        final cached = await SharedPreferences.getInstance();
        expect(cached.getString(_key), backend.writes.single.$3);
        expect(routes.pops, isEmpty);
        expect(routeCompleted, 0);
        if (userPop) {
          navigator.currentState!.pop();
          await pumpFavourites(tester);
          expect(routes.pops, [route]);
          expect(routeCompleted, 1);
          expect(await backend.physical(), initial);
        }
        backend.release.complete();
        await pumpFavourites(tester);
        expect(backend.completed.isCompleted, isTrue);
        expect(backend.result, isTrue);
        finalPhysical = await backend.physical();
        finalPublic = await SeriesSourceService.getSources(_id);
        expect(routes.pops, [route]);
        expect(routeCompleted, 1);
        expect(find.byType(SourceRow), findsNothing);
      }
      expect(find.text('Sources origin parent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!httpRelease.isCompleted) httpRelease.complete();
      if (!backend.release.isCompleted) backend.release.complete();
      await pumpFavourites(tester);
    } finally {
      service.debugStreamHttpClientFactory = previousClient;
      service.invalidateCache();
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      EngineRegistry.instance.invalidateProfileScope();
      LocalEngineStorage.instance.resetProfileScope();
      client.close();
    }
  }
  // Global transport hooks are restored even if earlier assertions failed.
  expect(service.debugStreamHttpClientFactory, same(previousClient));
  expect(SharedPreferencesStorePlatform.instance, same(previousStore));
  expect(unexpected, isEmpty);
  expect(tester.takeException(), isNull);
  if (!holdHttp) {
    expect(backend.writes, hasLength(1));
    expect(finalPhysical![_physicalKey], backend.writes.single.$3);
    expect({...finalPhysical!}..remove(_physicalKey), initial);
    final raw = finalPhysical![_physicalKey] as String;
    expect(raw, isNot(contains(_signedUrl)));
    expect(raw, isNot(contains('synthetic-signature')));
    final descriptor = (jsonDecode(raw) as List).single as Map;
    expect(descriptor['debridService'], SeriesSource.addonDirectService);
    expect(descriptor['addonId'], addon.id);
    expect(descriptor['addonKey'], addon.sourceBindingKey);
    expect(descriptor['streamIndex'], 0);
    expect(
      descriptor['streamKey'],
      isA<String>().having((v) => v.isNotEmpty, 'nonempty', true),
    );
    expect(finalPublic, hasLength(1));
    expect(finalPublic!.single.toJson(), descriptor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'origin Sources held addon completes after public route pop without late UI',
    (tester) => _case(tester, holdHttp: true, userPop: true),
  );
  testWidgets(
    'origin Sources double tap holds one physical movie bind before one pop',
    (tester) => _case(tester, holdHttp: false, userPop: false),
  );
  testWidgets(
    'origin Sources user pop while binding permits late persistence without another pop',
    (tester) => _case(tester, holdHttp: false, userPop: true),
  );
  testWidgets('origin Sources false physical write keeps old durable binding but pops',
    (tester) => _faultCase(tester, throws: false));
  testWidgets('origin Sources thrown write escapes and finally permits another bind',
    (tester) => _faultCase(tester, throws: true));
  testWidgets('origin public catalog Sources persists eligible addon toggle across reopen',
    (tester) => _catalogRoundtrip(tester));
  testWidgets('origin public Keyword Sources honors defaults and persists indexer toggle',
    (tester) => _keywordRoundtrip(tester));
}

// Additional finite fault outcomes. The accepted three-case helper above stays
// unchanged; false physical persistence is not a false TPS bind result.
class _FaultStore extends InMemorySharedPreferencesStore {
  _FaultStore(super.data, {required this.throws}) : super.withData();
  final bool throws;
  final failure = StateError('synthetic Sources physical write failure');
  final release = Completer<void>();
  final entered = Completer<void>();
  final writes = <(String, String, Object)>[];
  final unrelatedWrites = <String>[];
  bool? firstResult;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _physicalKey) {
      unrelatedWrites.add(key);
      return super.setValue(type, key, value);
    }
    writes.add((type, key, value));
    if (writes.length == 1) {
      entered.complete();
      await release.future.timeout(_limit);
      if (throws) throw failure;
      firstResult = false;
      return false;
    }
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> physical() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

Future<void> _faultCase(WidgetTester tester, {required bool throws}) async {
  await prepareFavourites(tester);
  final previousStore = SharedPreferencesStorePlatform.instance;
  final service = StremioService.instance;
  final previousClient = service.debugStreamHttpClientFactory;
  final routes = _Routes();
  final navigator = GlobalKey<NavigatorState>();
  final requests = <Uri>[];
  final unexpected = <Uri>[];
  final addon = StremioAddon(
    id: 'sources.origin', name: 'Origin source',
    manifestUrl: 'https://sources.invalid/manifest.json',
    baseUrl: 'https://sources.invalid', resources: ['stream'], types: ['movie'],
  );
  const old = SeriesSource(
    torrentHash: '', torrentName: 'OLD durable movie',
    debridService: SeriesSource.addonDirectService, debridTorrentId: '',
    boundAt: 1, addonId: 'old.addon', addonKey: 'old-addon-key',
    streamKey: 'old-stream', streamIndex: 3,
  );
  final oldRaw = jsonEncode([old.toJson()]);
  final seeded = await SharedPreferences.getInstance();
  await seeded.setString('stremio_addons_v1', jsonEncode([addon.toJson()]));
  await seeded.setString(_key, oldRaw);
  await seeded.setString('sources_origin_sentinel', 'unchanged');
  final backend = _FaultStore({
    for (final key in seeded.getKeys()) 'flutter.$key': seeded.get(key)!,
  }, throws: throws);
  final initial = await backend.physical();
  final parentZone = Zone.current;
  // Created in the parent error zone; no async test body crosses the child zone.
  final observed = Completer<void>();
  final errors = <Object>[];
  final stacks = <StackTrace>[];
  final callbackZone = parentZone.fork(specification: ZoneSpecification(
    handleUncaughtError: (self, parent, zone, error, stack) {
      if (identical(error, backend.failure) && errors.isEmpty) {
        errors.add(error);
        stacks.add(stack);
        observed.complete();
      } else {
        // Includes a duplicate of the synthetic failure. Never recurse through
        // Zone.current and never consume errors just because their type matches.
        parentZone.handleUncaughtError(error, stack);
      }
    },
  ));
  var routeCompleted = 0;
  Map<String, Object>? finalPhysical;
  final client = MockClient((request) async {
    requests.add(request.url);
    if (request.method != 'GET' || request.url.toString() !=
        'https://sources.invalid/stream/movie/$_id.json') {
      unexpected.add(request.url);
      throw StateError('Unexpected Sources fault fixture HTTP transport');
    }
    return http.Response(jsonEncode({'streams': [
      {'name': 'Origin source', 'description': 'Origin movie 1080p', 'url': _signedUrl},
    ]}), 200);
  });
  try {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    service.invalidateCache();
    service.debugStreamHttpClientFactory = () => client;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await tester.runAsync(() => EngineRegistry.instance.initialize());
    expect((await SeriesSourceService.getSources(_id)).single.toJson(), old.toJson());
    expect((await backend.physical())[_physicalKey], oldRaw);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, navigatorObservers: [routes],
        home: const Scaffold(body: Text('Sources fault parent')),
      ));
      final route = MaterialPageRoute<void>(builder: (_) => buildSearchSources(
        selection: const AdvancedSearchSelection(imdbId: _id, isSeries: false,
          title: 'Origin movie', contentType: 'movie'),
        meta: const PlaybackMeta(imdbId: _id, title: 'Origin movie', contentType: 'movie'),
        isTelevision: false, bindMode: true,
      ));
      unawaited(navigator.currentState!.push(route).then((_) { routeCompleted++; }));
      await pumpFavourites(tester);
      expect(find.byType(SourceRow), findsOneWidget);
      expect(tester.widget<SourceRow>(find.byType(SourceRow)).isSelected, isFalse);
      expect(requests, [Uri.parse('https://sources.invalid/stream/movie/$_id.json')]);
      expect(unexpected, isEmpty);
      // Only the synchronous public row callback executes in the error zone.
      void tap() => callbackZone.run<void>(
        tester.widget<SourceRow>(find.byType(SourceRow)).onTap,
      );
      tap();
      await tester.pump();
      tap();
      await tester.pump();
      expect(backend.entered.isCompleted, isTrue);
      expect(backend.writes, hasLength(1));
      expect(backend.writes.single.$1, 'String');
      expect(backend.writes.single.$2, _physicalKey);
      final attempted = backend.writes.single.$3 as String;
      expect(attempted, isNot(oldRaw));
      expect(attempted, isNot(contains(_signedUrl)));
      expect(attempted, isNot(contains('synthetic-signature')));
      final attemptedDescriptor = (jsonDecode(attempted) as List).single as Map;
      expect(attemptedDescriptor['addonId'], addon.id);
      expect(attemptedDescriptor['addonKey'], addon.sourceBindingKey);
      final cached = await SharedPreferences.getInstance();
      expect(cached.getString(_key), attempted);
      expect(await backend.physical(), initial);
      expect(routes.pops, isEmpty);
      expect(routeCompleted, 0);
      backend.release.complete();
      await pumpFavourites(tester);
      // Both outcomes leave the previous physical binding untouched.
      expect(await backend.physical(), initial);
      expect(cached.getString(_key), attempted);
      expect((await SeriesSourceService.getSources(_id)).single.toJson(), attemptedDescriptor);
      if (throws) {
        await observed.future.timeout(_limit);
        expect(errors, [same(backend.failure)]);
        expect(stacks.single.toString(), isNotEmpty);
        expect(routes.pops, isEmpty);
        expect(routeCompleted, 0);
        expect(find.text('Direct source pinned for fresh-link playback.'), findsNothing);
        expect(find.byType(SourceRow), findsOneWidget);
        expect(tester.widget<SourceRow>(find.byType(SourceRow)).isSelected, isFalse);
        // The initial failed bind has not reloaded the UI. A new public tap
        // now reaching the transport proves the finally-reset latch.
        expect((await backend.physical())[_physicalKey], oldRaw);
        tap();
        await pumpFavourites(tester);
        expect(backend.writes, hasLength(2));
        finalPhysical = await backend.physical();
        expect(finalPhysical![_physicalKey], backend.writes.last.$3);
        expect((jsonDecode(finalPhysical![_physicalKey] as String) as List).single,
          (await SeriesSourceService.getSources(_id)).single.toJson());
        expect(errors, [same(backend.failure)]);
      } else {
        expect(backend.firstResult, isFalse);
        expect(backend.writes, hasLength(1));
        expect(errors, isEmpty);
        finalPhysical = await backend.physical();
        expect(finalPhysical, initial);
      }
      expect(routes.pops, [route]);
      expect(routeCompleted, 1);
      expect(find.byType(SourceRow), findsNothing);
      expect(find.text('Sources fault parent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!backend.release.isCompleted) backend.release.complete();
      await pumpFavourites(tester);
    } finally {
      service.debugStreamHttpClientFactory = previousClient;
      service.invalidateCache();
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      EngineRegistry.instance.invalidateProfileScope();
      LocalEngineStorage.instance.resetProfileScope();
      client.close();
    }
  }
  expect(service.debugStreamHttpClientFactory, same(previousClient));
  expect(SharedPreferencesStorePlatform.instance, same(previousStore));
  expect(unexpected, isEmpty);
  expect(errors, throws ? [same(backend.failure)] : isEmpty);
  expect(tester.takeException(), isNull);
  expect({...finalPhysical!}..remove(_physicalKey), {...initial}..remove(_physicalKey));
}

const _catalogPhysicalKey = 'flutter.catalog_search_disabled_addons_v1';

class _CatalogStore extends InMemorySharedPreferencesStore {
  _CatalogStore(super.data) : super.withData();
  final writes = <(String, String, Object)>[];
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == _catalogPhysicalKey) writes.add((type, key, value));
    return super.setValue(type, key, value);
  }
  Future<Map<String, Object>> physical() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

Future<void> _catalogRoundtrip(WidgetTester tester) async {
  await prepareFavourites(tester);
  final previousStore = SharedPreferencesStorePlatform.instance;
  final service = StremioService.instance;
  final previousClient = service.debugStreamHttpClientFactory;
  final unexpected = <Uri>[];
  final client = MockClient((request) async {
    unexpected.add(request.url);
    throw StateError('Unexpected empty-query catalog fixture HTTP');
  });
  final eligible = StremioAddon(
    id: 'catalog.eligible', name: 'Eligible catalog origin',
    manifestUrl: 'https://eligible.invalid/manifest.json',
    baseUrl: 'https://eligible.invalid', resources: ['catalog'], types: ['movie'],
    catalogs: const [StremioAddonCatalog(id: 'search', type: 'movie',
      name: 'Search', extraSupported: ['search'],
      extras: [StremioExtraParam(name: 'search', isRequired: true)])],
  );
  final ineligible = StremioAddon(
    id: 'catalog.ineligible', name: 'Nonsearchable catalog origin',
    manifestUrl: 'https://ineligible.invalid/manifest.json',
    baseUrl: 'https://ineligible.invalid', resources: ['catalog'], types: ['movie'],
    catalogs: const [StremioAddonCatalog(id: 'browse', type: 'movie', name: 'Browse')],
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('stremio_addons_v1', jsonEncode([
    eligible.toJson(), ineligible.toJson(),
  ]));
  await prefs.setString('catalog_origin_sentinel', 'unchanged');
  final backend = _CatalogStore({
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
  });
  final initial = await backend.physical();
  try {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    service.invalidateCache();
    service.debugStreamHttpClientFactory = () => client;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SearchScreen(searchMode: true)));
      await pumpFavourites(tester);
      expect(find.text('Search movies & shows'), findsOneWidget);
      expect(initial.containsKey(_catalogPhysicalKey), isFalse);
      await tester.tap(find.text('Sources'));
      await pumpFavourites(tester);
      final dialog = find.byType(Dialog);
      Finder inside(Finder child) => find.descendant(of: dialog, matching: child);
      expect(dialog, findsOneWidget);
      expect(inside(find.text('Eligible catalog origin')), findsOneWidget);
      expect(inside(find.text('Nonsearchable catalog origin')), findsNothing);
      expect(inside(find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
      expect(inside(find.byIcon(Icons.block_rounded)), findsNothing);
      expect(backend.writes, isEmpty);
      await tester.tap(inside(find.text('Eligible catalog origin')));
      await pumpFavourites(tester);
      expect(dialog, findsOneWidget);
      expect(inside(find.byIcon(Icons.block_rounded)), findsOneWidget);
      expect(backend.writes, hasLength(1));
      expect(backend.writes.single.$1, 'String');
      expect(backend.writes.single.$2, _catalogPhysicalKey);
      expect(backend.writes.single.$3, '["catalog.eligible"]');
      final physical = await backend.physical();
      expect(physical[_catalogPhysicalKey], '["catalog.eligible"]');
      expect(physical['flutter.stremio_addons_v1'], initial['flutter.stremio_addons_v1']);
      expect(physical['flutter.catalog_origin_sentinel'], 'unchanged');
      await tester.tap(inside(find.text('Done')));
      await pumpFavourites(tester);
      expect(dialog, findsNothing);
      expect(find.text('Search movies & shows'), findsOneWidget);
      // Discard the optimistic SDK instance before reopening the actual dialog.
      SharedPreferences.resetStatic();
      await tester.tap(find.text('Sources'));
      await pumpFavourites(tester);
      expect(dialog, findsOneWidget);
      expect(inside(find.text('Eligible catalog origin')), findsOneWidget);
      expect(inside(find.text('Nonsearchable catalog origin')), findsNothing);
      expect(inside(find.byIcon(Icons.block_rounded)), findsOneWidget);
      expect(inside(find.byIcon(Icons.check_circle_rounded)), findsNothing);
      expect(backend.writes, hasLength(1));
      expect((await backend.physical())[_catalogPhysicalKey], '["catalog.eligible"]');
      await tester.tap(inside(find.text('Done')));
      await pumpFavourites(tester);
      expect(tester.takeException(), isNull);
    }, () => client);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFavourites(tester);
    } finally {
      service.debugStreamHttpClientFactory = previousClient;
      service.invalidateCache();
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      client.close();
    }
  }
  expect(service.debugStreamHttpClientFactory, same(previousClient));
  expect(SharedPreferencesStorePlatform.instance, same(previousStore));
  expect(unexpected, isEmpty);
  expect(tester.takeException(), isNull);
  // Empty query only: no nonempty-query restart or keyword-dialog claim.
}

const _keywordPhysicalKey = 'flutter.engine_indexer_manager_origin_indexer_case_a_enabled';
class _KeywordStore extends InMemorySharedPreferencesStore {
  _KeywordStore(super.data) : super.withData();
  final writes = <(String, String, Object)>[];
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == _keywordPhysicalKey) writes.add((type, key, value));
    return super.setValue(type, key, value);
  }
  Future<Map<String, Object>> physical() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

Future<void> _keywordRoundtrip(WidgetTester tester) async {
  await prepareFavourites(tester);
  final previousStore = SharedPreferencesStorePlatform.instance;
  final service = StremioService.instance;
  final previousClient = service.debugStreamHttpClientFactory;
  final unexpected = <Uri>[];
  final client = MockClient((request) async {
    unexpected.add(request.url);
    throw StateError('Unexpected empty-query keyword fixture HTTP');
  });
  const config = IndexerManagerConfig(id: 'Case-A', name: 'Origin Indexer',
    type: IndexerManagerType.jackett, baseUrl: 'https://indexer.invalid',
    apiKey: 'synthetic-only', enabled: false);
  await StorageService.setIndexerManagerConfigs([config]);
  final prefs = await SharedPreferences.getInstance();
  final backend = _KeywordStore({
    for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
  });
  final initial = await backend.physical();
  try {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = backend;
    service.invalidateCache();
    service.debugStreamHttpClientFactory = () => client;
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await tester.runAsync(() async {
      await LocalEngineStorage.instance.saveEngine(engineId: 'origin_fixture',
        fileName: 'origin_fixture.yaml', yamlContent: _keywordOriginYaml,
        displayName: 'Origin Fixture');
      await EngineRegistry.instance.reload();
    });
    final registryEngine = EngineRegistry.instance.getEngine('origin_fixture');
    expect(EngineRegistry.instance.getEngineIds(), ['origin_fixture']);
    expect(initial.containsKey(_keywordPhysicalKey), isFalse);
    expect(initial.containsKey('flutter.engine_origin_fixture_enabled'), isFalse);
    final beforeConfig = await StorageService.getIndexerManagerConfigs();
    expect(beforeConfig.single.enabled, isFalse);
    expect(beforeConfig.single.engineId, 'indexer_manager_origin_indexer_Case-A');
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SearchScreen(searchMode: true)));
      await pumpFavourites(tester);
      await tester.tap(find.text('Keyword'));
      await pumpFavourites(tester);
      expect(find.text('Keyword torrent search'), findsOneWidget);
      await tester.tap(find.text('Sources'));
      await pumpFavourites(tester);
      final dialog = find.byType(Dialog);
      Finder inside(Finder child) => find.descendant(of: dialog, matching: child);
      expect(dialog, findsOneWidget);
      expect(inside(find.text('Origin Fixture')), findsOneWidget);
      expect(inside(find.text('Origin Indexer')), findsOneWidget);
      Finder row(String name) => find.ancestor(of: inside(find.text(name)),
        matching: find.byType(GestureDetector)).first;
      expect(find.descendant(of: row('Origin Fixture'),
        matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
      expect(find.descendant(of: row('Origin Indexer'),
        matching: find.byIcon(Icons.block_rounded)), findsOneWidget);
      expect(backend.writes, isEmpty);
      await tester.tap(inside(find.text('Origin Indexer')));
      await pumpFavourites(tester);
      expect(dialog, findsOneWidget);
      expect(backend.writes, hasLength(1));
      expect(backend.writes.single.$1, 'Bool');
      expect(backend.writes.single.$2, _keywordPhysicalKey);
      expect(backend.writes.single.$3, true);
      expect((await backend.physical())[_keywordPhysicalKey], true);
      expect(inside(find.byIcon(Icons.check_circle_rounded)), findsNWidgets(2));
      await tester.tap(inside(find.text('Done')));
      await pumpFavourites(tester);
      SharedPreferences.resetStatic();
      await tester.tap(find.text('Sources'));
      await pumpFavourites(tester);
      expect(dialog, findsOneWidget);
      expect(inside(find.text('Origin Fixture')), findsOneWidget);
      expect(inside(find.text('Origin Indexer')), findsOneWidget);
      expect(inside(find.byIcon(Icons.check_circle_rounded)), findsNWidgets(2));
      expect(inside(find.byIcon(Icons.block_rounded)), findsNothing);
      expect(backend.writes, hasLength(1));
      expect((await backend.physical())[_keywordPhysicalKey], true);
      expect(EngineRegistry.instance.getEngine('origin_fixture'), same(registryEngine));
      expect(EngineRegistry.instance.getEngineIds(), ['origin_fixture']);
      final afterConfig = await StorageService.getIndexerManagerConfigs();
      // Compare without printing any credential-bearing config on failure.
      expect(jsonEncode(afterConfig.single.toJson()) == jsonEncode(beforeConfig.single.toJson()), isTrue);
      expect(afterConfig.single.enabled, isFalse);
      final physical = await backend.physical();
      expect(physical['flutter.indexer_manager_configs_v1'] == initial['flutter.indexer_manager_configs_v1'], isTrue);
      expect(physical.containsKey('flutter.engine_origin_fixture_enabled'), isFalse);
      await tester.tap(inside(find.text('Done')));
      await pumpFavourites(tester);
      expect(tester.takeException(), isNull);
    }, () => client);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFavourites(tester);
    } finally {
      service.debugStreamHttpClientFactory = previousClient;
      service.invalidateCache();
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      EngineRegistry.instance.invalidateProfileScope();
      LocalEngineStorage.instance.resetProfileScope();
      client.close();
    }
  }
  expect(service.debugStreamHttpClientFactory, same(previousClient));
  expect(SharedPreferencesStorePlatform.instance, same(previousStore));
  expect(unexpected, isEmpty);
  expect(tester.takeException(), isNull);
  // Empty query: no query execution, canonical authority or native proof.
}

const _keywordOriginYaml = '''
id: origin_fixture
display_name: Origin Fixture
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://origin-fixture.invalid/search
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
field_mappings:
  infohash: infohash
  name: name
  seeders: seeders
  size_bytes: size_bytes
''';
