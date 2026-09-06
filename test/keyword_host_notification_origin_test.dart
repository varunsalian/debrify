import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/screens/search/keyword_search_controller.dart';
import 'package:debrify/screens/search/keyword_search_screen.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/search_loading_animation.dart';
import 'package:debrify/widgets/torrent_filters_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'discover_screen_origin_test.dart'
    show prepareDiscoverHydration, mountDiscover, discoverSource, discoverSourceFinder,
        DiscoverManifestHold;
import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites;

// PREP ONLY. Origin main545f18c0. Defaults cases explicitly re-invoke the
// public controller after real results; neither is natural-startup evidence.
// Eight tests separate lifetimes within the six approved scenario groups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('origin held submission mounts toolbar; notification builds both',
      (tester) async {
    await _prepare(tester);
    final transport = _SearchTransport();
    await _withSearch(tester, transport, () async {
      await _mountKeyword(tester);
      final c = _controller(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      await _submit(tester);
      expect(transport.entered.isCompleted, isTrue);
      expect(find.byType(SearchLoadingAnimation), findsOneWidget);
      expect(c.kwToolbarVisible, isFalse);
      field.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      transport.finish();
      await _drain(tester);
      expect(c.kwToolbarVisible, isTrue);
      expect(c.kwToolbarNodes.first.context?.mounted, isTrue);
      expect(c.kwToolbarNodes.first.hasFocus, isTrue);
      expect(find.text('Alpha Fixture 720p'), findsOneWidget);
      c.enterSelection(); // Existing public controller API, not gesture proof.
      await _drain(tester);
      final node = c.kwToolbarNodes.first;
      node.requestFocus();
      await tester.pump();
      var host = 0;
      var child = 0;
      var notifications = 0;
      void notified() => notifications++;
      final previous = debugOnRebuildDirtyWidget;
      c.addListener(notified);
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is SearchScreenHost) host++;
        if (element.widget is KeywordSearchScreen) child++;
      };
      try {
        c.toggleSelection(c.kwResults.first);
        expect(notifications, 1);
        await tester.pump();
        expect(host, 1); // Origin, NOT the future retirement expectation.
        expect(child, 1);
        expect(find.text('Add · 1'), findsOneWidget);
        expect(node.hasFocus, isTrue);
        expect(c.kwToolbarNodes.first, same(node));
        await tester.pump(const Duration(milliseconds: 16));
        expect(host, 1);
        expect(child, 1);
        expect(transport.requests, hasLength(1));
      } finally {
        debugOnRebuildDirtyWidget = previous;
        c.removeListener(notified);
      }
    });
  });

  testWidgets('origin error is not empty-query Sources focus', (tester) async {
    await _prepare(tester, engine: false);
    final transport = _SearchTransport();
    await _withSearch(tester, transport, () async {
      await _mountKeyword(tester);
      final c = _controller(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.kwSourcesBtnFocus.hasFocus, isTrue);
      await _submit(tester);
      await _drain(tester);
      expect(find.text('Search failed'), findsOneWidget);
      expect(c.kwSourcesButtonVisible, isFalse);
      field.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '');
      await _drain(tester);
      expect(find.text('Search failed'), findsNothing);
      expect(c.kwSourcesButtonVisible, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.kwSourcesBtnFocus.hasFocus, isTrue);
      expect(transport.requests, isEmpty);
    });
  });

  testWidgets('origin mode away permits held result then returns same controller',
      (tester) async {
    await _prepare(tester);
    final transport = _SearchTransport();
    await _withSearch(tester, transport, () async {
      await _mountKeyword(tester);
      final c = _controller(tester);
      await _submit(tester);
      expect(transport.entered.isCompleted, isTrue);
      await tester.tap(find.text('Catalog'));
      await tester.pump();
      expect(find.byType(KeywordSearchScreen), findsNothing);
      transport.finish();
      await _drain(tester);
      expect(c.kwResults, hasLength(2));
      await tester.tap(find.text('Keyword'));
      await _drain(tester);
      expect(_controller(tester), same(c));
      expect(find.text('Alpha Fixture 720p'), findsOneWidget);
      expect(c.kwSelectionMode, isFalse);
      expect(transport.requests, hasLength(1));
    });
  });

  testWidgets('origin public Back invalidates held keyword before late arrival',
      (tester) async {
    await _prepare(tester);
    final transport = _SearchTransport();
    await _withSearch(tester, transport, () async {
      await _mountKeyword(tester);
      final c = _controller(tester);
      await _submit(tester);
      expect(transport.entered.isCompleted, isTrue);
      final oldToken = c.kwSearchToken;
      MainPageBridge.setActiveTab('search');
      try {
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        // Observe synchronous reset before completing the actual request.
        expect(c.kwSearchToken, greaterThan(oldToken));
        expect(c.kwQuery, isEmpty);
        expect(tester.widget<EditableText>(find.byType(EditableText))
            .controller.text, isEmpty);
        transport.finish();
        await _drain(tester);
        expect(find.byType(KeywordSearchScreen), findsNothing);
        expect(find.text('Alpha Fixture 720p'), findsNothing);
        expect(c.kwResults, isEmpty);
      } finally {
        MainPageBridge.setActiveTab(null);
      }
    });
  });

  for (final userChoice in [false, true]) {
    testWidgets('origin explicit defaults reload after results: user=$userChoice',
        (tester) async {
      await _prepare(tester);
      final transport = _SearchTransport()..finish();
      await _withSearch(tester, transport, () async {
        await _mountKeyword(tester);
        await _submit(tester);
        await _drain(tester);
        final c = _controller(tester);
        expect(c.kwSearching, isFalse);
        expect(c.kwAll, hasLength(2));
        expect(c.kwResults, hasLength(2));
        expect(c.kwFilters.qualities, isEmpty);
        final profile = ProfileRuntime.scope.value;
        final profileMode = ProfileRuntime.mode;
        final prefs = await SharedPreferences.getInstance();
        final physical = <String, Object>{
          for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
          'flutter.default_filter_qualities_v1': '["fullHd"]',
        };
        final oldStore = SharedPreferencesStorePlatform.instance;
        final held = _HeldWholePreferences(physical);
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = held;
        var finished = false;
        final loading = c.loadDefaultFilters().then((_) => finished = true);
        try {
          await tester.pump();
          expect(held.entered.isCompleted, isTrue);
          expect(held.reads, 1);
          expect(finished, isFalse);
          expect(c.kwFilters.qualities, isEmpty);
          if (userChoice) {
            await tester.tap(find.text('Filters'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(TorrentFiltersSheet), findsOneWidget);
            final qualityChip = find.descendant(
              of: find.byType(TorrentFiltersSheet),
              matching: find.text('720p'),
            );
            expect(qualityChip, findsOneWidget);
            await tester.tap(qualityChip);
            await tester.pump();
            await tester.ensureVisible(find.text('Apply Filters'));
            await tester.tap(find.text('Apply Filters'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            // If UI waits for the held SDK this assertion fails: no private
            // filter mutation, hook or early release is permitted instead.
            expect(c.kwFilters.qualities, {QualityTier.hd});
            expect(finished, isFalse);
          }
          held.release.complete();
          await loading;
          await _drain(tester);
          expect(_controller(tester), same(c));
          expect(ProfileRuntime.scope.value, profile);
          expect(ProfileRuntime.mode, profileMode);
          expect(c.kwFilters.qualities,
              {userChoice ? QualityTier.hd : QualityTier.fullHd});
          expect(c.kwResults.map((t) => t.name),
              [userChoice ? 'Alpha Fixture 720p' : 'Zulu Fixture 1080p']);
          expect(find.text(userChoice ? 'Alpha Fixture 720p' : 'Zulu Fixture 1080p'),
              findsOneWidget);
          expect(await held.snapshot(), physical);
          expect(held.reads, 1);
          expect(transport.requests, hasLength(1));
        } finally {
          if (!held.release.isCompleted) held.release.complete();
          try {
            await loading;
          } finally {
            SharedPreferencesStorePlatform.instance = oldStore;
            SharedPreferences.resetStatic();
          }
        }
      });
    });
  }

  for (final disposeFirst in [false, true]) {
    testWidgets('origin Discover external hydration: disposed=$disposeFirst',
        (tester) async {
      final hold = await prepareDiscoverHydration(tester);
      final fetcher = StremioService.instance.debugManifestFetcher!;
      final unknownManifests = <String>[];
      StremioService.instance.debugManifestFetcher = (url) {
        if (url != DiscoverManifestHold.url) {
          unknownManifests.add(url);
          throw StateError('Unexpected Discover manifest');
        }
        return fetcher(url);
      };
      await StorageService.setDiscoverDefaultSource('cw');
      await StorageService.setDiscoverLastSource('cw');
      try {
        await mountDiscover(tester, tv: true);
        expect(hold.requested, isNotEmpty);
        expect(hold.requested.toSet(), {DiscoverManifestHold.url});
        final source = discoverSource(tester);
        final node = source.focusNode!;
        node.requestFocus();
        await tester.pump();
        expect(node.hasFocus, isTrue);
        expect(source.options.map((o) => o.value), isNot(contains(hold.source)));
        if (disposeFirst) await tester.pumpWidget(const SizedBox.shrink());
        hold.complete();
        await pumpFavourites(tester);
        if (disposeFirst) {
          expect(find.byType(SearchScreenHost), findsNothing);
          expect(discoverSourceFinder(), findsNothing);
          expect(await StorageService.getDiscoverLastSource(), 'cw');
        } else {
          expect(discoverSource(tester).options.map((o) => o.value),
              contains(hold.source));
          expect(discoverSource(tester).value, 'cw');
          expect(discoverSource(tester).focusNode, same(node));
          expect(node.hasFocus, isTrue);
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (!hold.release.isCompleted) hold.complete();
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpFavourites(tester);
        } finally {
          StremioService.instance.debugManifestFetcher = fetcher;
        }
      }
      expect(unknownManifests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _prepare(WidgetTester tester, {bool engine = true}) async {
  await prepareFavourites(tester);
  LocalEngineStorage.instance.resetProfileScope();
  EngineRegistry.instance.invalidateProfileScope();
  addTearDown(() {
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
  });
  await tester.runAsync(() async {
    await EngineRegistry.instance.initialize();
    if (engine) {
      await LocalEngineStorage.instance.saveEngine(
        engineId: 'notification_fixture', fileName: 'notification_fixture.yaml',
        yamlContent: _engine, displayName: 'Notification Fixture',
      );
      await EngineRegistry.instance.reload();
    }
  });
  expect(EngineRegistry.instance.getEngineIds(),
      engine ? ['notification_fixture'] : isEmpty);
}

Future<void> _mountKeyword(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: SearchScreen(searchMode: true, isTelevision: true),
  ));
  await _drain(tester);
  await tester.tap(find.text('Keyword'));
  await _drain(tester);
  expect(find.byType(KeywordSearchScreen), findsOneWidget);
}

KeywordSearchController _controller(WidgetTester tester) =>
    tester.widget<KeywordSearchScreen>(find.byType(KeywordSearchScreen)).controller;

Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'notification fixture');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _drain(tester);
}

// Finite frame allowance, not pumpAndSettle on a held loading animation.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _withSearch(WidgetTester tester, _SearchTransport transport,
    Future<void> Function() body) async {
  await http.runWithClient(() async {
    try {
      await body();
      expect(transport.unknown, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      transport.finish();
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        expect(find.byType(SearchLoadingAnimation), findsNothing);
        // Existing loader has unretained 3s/7s delayed callbacks. Discharge
        // them only after unmount; this does not exercise mounted tiers.
        await tester.pump(const Duration(seconds: 7));
        await _drain(tester);
      } finally {
        transport.client.close();
      }
    }
    expect(transport.unknown, isEmpty);
    expect(tester.takeException(), isNull);
  }, () => transport.client);
}

class _SearchTransport {
  final entered = Completer<void>();
  final release = Completer<void>();
  final requests = <Uri>[];
  final unknown = <String>[];
  late final client = MockClient((request) async {
    if (request.method != 'GET' || request.url !=
        Uri.parse('https://notification-fixture.invalid/search?q=notification+fixture')) {
      unknown.add('${request.method} ${request.url}');
      throw StateError('Unexpected fixture HTTP');
    }
    requests.add(request.url);
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return http.Response(jsonEncode({'results': [
      {'infohash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
       'name': 'Alpha Fixture 720p', 'seeders': 12, 'size_bytes': 1000000000},
      {'infohash': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
       'name': 'Zulu Fixture 1080p', 'seeders': 20, 'size_bytes': 2000000000},
    ]}), 200, headers: {'content-type': 'application/json'});
  });
  void finish() { if (!release.isCompleted) release.complete(); }
}

class _HeldWholePreferences extends InMemorySharedPreferencesStore {
  _HeldWholePreferences(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  int reads = 0;
  Future<Map<String, Object>> snapshot() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) async {
    reads++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.getAllWithParameters(parameters);
  }
}

const _engine = '''
id: notification_fixture
display_name: Notification Fixture
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://notification-fixture.invalid/search
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
