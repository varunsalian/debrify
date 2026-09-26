import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/search/application/keyword_cache_dependencies.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/cinema_sources_layout.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/golden_harness.dart' show disableRuntimeFonts;
import '../fakes/fake_keyword_cache_repository.dart';

const cachedHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const otherHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory directory;
  late MockClient client;
  late FakeKeywordCacheRepository repository;
  late Completer<Set<String>> cache;
  late int requests;

  setUp(() async {
    disableRuntimeFonts();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('keyword-cache-screen-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    await LocalEngineStorage.instance.saveEngine(
      engineId: 'fixture',
      fileName: 'fixture.yaml',
      displayName: 'Fixture engine',
      yamlContent: jsonEncode({
        'id': 'fixture',
        'display_name': 'Fixture engine',
        'capabilities': {'keyword_search': true},
        'api': {'base_url': 'https://keyword.invalid/search', 'method': 'GET'},
        'query_params': {'type': 'query_params', 'param_name': 'query'},
        'response_format': {'type': 'direct_json', 'results_path': 'results'},
        'field_mappings': {
          'infohash': {'source': 'hash'},
          'name': {'source': 'title'},
        },
        'settings': [
          {'id': 'enabled', 'default': true},
        ],
      }),
    );
    MainPageBridge.setActiveTab('search');
    StremioService.instance.invalidateCache();
    repository = FakeKeywordCacheRepository();
    cache = Completer<Set<String>>();
    repository.session.tb = (_) => cache.future;
    requests = 0;
    client = MockClient((request) async {
      if (request.url.host != 'keyword.invalid') {
        return http.Response('{}', 404);
      }
      requests++;
      return http.Response(
        jsonEncode({
          'results': [
            {'hash': cachedHash, 'title': 'Cached result'},
            {'hash': otherHash, 'title': 'Uncached result'},
          ],
        }),
        200,
      );
    });
  });

  tearDown(() async {
    if (!cache.isCompleted) cache.complete({});
    client.close();
    MainPageBridge.setActiveTab(null);
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
    ProfileSessionMemory.clearAll();
    AppStorage.debugReset();
    await directory.delete(recursive: true);
  });

  Future<void> drive(
    WidgetTester tester,
    FutureOr<void> Function() action,
  ) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }, () => client),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> search(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await drive(
      tester,
      () => tester.pumpWidget(
        ProviderScope(
          overrides: [
            keywordCacheRepositoryProvider.overrideWith(
              (ref, session) => repository,
            ),
          ],
          child: const MaterialApp(home: SearchScreen(searchMode: true)),
        ),
      ),
    );
    await tester.tap(find.text('Keyword'));
    await tester.pump();
    await drive(tester, () {
      final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
      field.controller.text = 'Result';
      field.onSubmitted!('Result');
    });
    expect(requests, 1);
    expect(repository.opens, 1);
    expect(repository.session.torboxCalls, [
      [cachedHash, otherHash],
    ]);
    expect(
      tester
          .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
          .resultCount,
      2,
    );
  }

  for (final otherProvider in [false, true]) {
    testWidgets(
      'production keyword cache completion preserves focus: other=$otherProvider',
      (tester) async {
        repository.session.otherProviderActive = otherProvider;
        await search(tester);
        final layout = tester.widget<CinemaSourcesLayout>(
          find.byType(CinemaSourcesLayout),
        );
        layout.onFocusResults();
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        expect(focused?.debugLabel, 'kw_0');
        await drive(tester, () => cache.complete({cachedHash}));
        expect(
          tester
              .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
              .resultCount,
          otherProvider ? 2 : 1,
        );
        expect(FocusManager.instance.primaryFocus, same(focused));
        expect(repository.session.torboxCalls, hasLength(1));
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await drive(tester, () => tester.pumpWidget(const SizedBox()));
      },
    );
  }

  testWidgets(
    'profile handoff clears keyword rows and rejects late cache completion',
    (tester) async {
      await search(tester);
      await drive(
        tester,
        () => ProfileRuntime.initializeCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 2,
          ),
        ),
      );
      await drive(tester, () => cache.complete({cachedHash}));
      expect(find.text('Cached result'), findsNothing);
      expect(find.text('Uncached result'), findsNothing);
      final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
      expect(field.controller.text, isEmpty);
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
    },
  );
  testWidgets(
    'a fresh screen restores completed cache state without new requests',
    (tester) async {
      await search(tester);
      await drive(tester, () => cache.complete({cachedHash}));
      expect(
        tester
            .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
            .resultCount,
        1,
      );
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await drive(
        tester,
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              keywordCacheRepositoryProvider.overrideWith(
                (ref, session) => repository,
              ),
            ],
            child: const MaterialApp(home: SearchScreen(searchMode: true)),
          ),
        ),
      );
      expect(
        tester
            .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
            .resultCount,
        1,
      );
      expect(
        tester
            .widget<TvTextField>(find.byType(TvTextField).first)
            .controller
            .text,
        'Result',
      );
      expect(repository.opens, 1);
      expect(repository.session.torboxCalls.length, 1);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
    },
  );
}
