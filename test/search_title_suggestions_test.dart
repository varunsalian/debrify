import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/tmdb_title_search.dart';
import 'package:debrify/widgets/app_tab_switcher.dart';
import 'package:debrify/widgets/text_field_suggestions.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    MainPageBridge.setActiveTab('search');
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StremioService.instance.invalidateCache();
  });
  tearDown(() {
    MainPageBridge.setActiveTab(null);
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
  });

  Future<void> drive(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        // A settings reload schedules its debounce in this real async zone.
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }, () => MockClient((_) async => http.Response('{}', 404))),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<({TmdbTitleSearch search, List<http.Request> requests})> mount(
    WidgetTester tester, {
    Future<StremioMeta> Function(StremioMeta)? resolve,
    Widget Function(Widget)? wrap,
  }) async {
    final requests = <http.Request>[];
    final search = TmdbTitleSearch(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'media_type': 'movie',
                  'id': 841,
                  'title': 'Dune',
                  'release_date': '1984-12-14',
                },
                {
                  'media_type': 'movie',
                  'id': 438631,
                  'title': 'Dune',
                  'release_date': '2021-09-15',
                },
              ],
            }),
            200,
          );
        }),
      ),
    );
    await drive(
      tester,
      () => tester.pumpWidget(
        MaterialApp(
          home: (wrap ?? (Widget child) => child)(
            SearchScreen(
              searchMode: true,
              titleSearch: search,
              suggestedTitleResolver: resolve,
            ),
          ),
        ),
      ),
    );
    return (search: search, requests: requests);
  }

  testWidgets(
    'Navbar Search shows distinct title choices and ordinary search',
    (tester) async {
      final fixture = await mount(tester);
      await tester.enterText(find.byType(TextField).first, 'Dune');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Movie · 1984'), findsOneWidget);
      expect(find.text('Movie · 2021'), findsOneWidget);
      expect(find.text('Search for “Dune”'), findsOneWidget);
      expect(fixture.requests, hasLength(1));
      await drive(
        tester,
        () => tester.testTextInput.receiveAction(TextInputAction.search),
      );
      expect(fixture.search.value, isEmpty);
      expect(find.byType(TextFieldSuggestions), findsNothing);
      // Caret-only notifications after submit must not restart title lookup.
      final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
      field.controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.search.value, isEmpty);
      await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  testWidgets(
    'Keyword gets title suggestions while pasted links bypass lookup',
    (tester) async {
      final fixture = await mount(tester);
      await drive(tester, () => tester.tap(find.text('Keyword')));
      await tester.enterText(find.byType(TextField).first, 'Dune');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('Search torrents'), findsOneWidget);
      expect(find.text('Movie · 2021'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/private',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.search.value, isEmpty);
      expect(fixture.requests, hasLength(1));
      await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  testWidgets(
    'metadata preference changes cancel choices and apply the new language',
    (tester) async {
      final fixture = await mount(tester);
      await tester.enterText(find.byType(TextField).first, 'Dune');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(fixture.search.value, hasLength(2));
      await drive(
        tester,
        () =>
            MetadataPreferencesService.save(MetadataPreferences(features: {})),
      );
      expect(fixture.search.value, isEmpty);
      await drive(
        tester,
        () => MetadataPreferencesService.save(
          MetadataPreferences(language: 'hi-IN'),
        ),
      );
      expect(fixture.requests.last.url.queryParameters['language'], 'hi-IN');
      expect(fixture.search.value, hasLength(2));
      await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  testWidgets('choosing a remake opens its existing detail route by identity', (
    tester,
  ) async {
    final fixture = await mount(tester);
    await tester.enterText(find.byType(TextField).first, 'Dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await drive(tester, () => tester.tap(find.text('Movie · 2021')));
    final detail = tester.widget<MergedDetailScreen>(
      find.byType(MergedDetailScreen),
    );
    expect(detail.item.id, 'tmdb:438631');
    expect(detail.item.year, '2021');
    expect(fixture.search.value, isEmpty);
    await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
  });

  testWidgets('Back cancels a title open without unlocking a newer selection', (
    tester,
  ) async {
    final oldLookup = Completer<StremioMeta>();
    final newLookup = Completer<StremioMeta>();
    final resolved = <StremioMeta>[];
    await mount(
      tester,
      resolve: (item) {
        resolved.add(item);
        return item.id == 'tmdb:841' ? oldLookup.future : newLookup.future;
      },
    );
    await tester.enterText(find.byType(TextField).first, 'Dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.text('Movie · 1984'));
    await tester.pump();
    expect(resolved, hasLength(1));
    expect(find.text('Loading title…'), findsOneWidget);

    MainPageBridge.setActiveTab('search');
    expect(MainPageBridge.handleBackNavigation(), isTrue);
    await tester.pump();
    final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
    expect(field.controller.text, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'Dune');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    final newerChoice = field.suggestions!.value.firstWhere(
      (item) => item.id == 'movie:tmdb:438631',
    );
    await tester.tap(find.text('Movie · 2021'));
    await tester.pump();
    expect(resolved, hasLength(2));

    oldLookup.complete(resolved.first);
    await tester.pump();
    expect(find.byType(MergedDetailScreen), findsNothing);
    // The older lookup's finally block must not release the newer open's lock.
    newerChoice.onSelected();
    expect(resolved, hasLength(2));

    await drive(tester, () async => newLookup.complete(resolved.last));
    final detail = tester.widget<MergedDetailScreen>(
      find.byType(MergedDetailScreen),
    );
    expect(detail.item.id, 'tmdb:438631');
    expect(find.byType(MergedDetailScreen), findsOneWidget);
    await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
  });

  testWidgets(
    'editing the query cancels a pending open and resumes suggestions',
    (tester) async {
      final pending = Completer<StremioMeta>();
      StremioMeta? selected;
      final fixture = await mount(
        tester,
        resolve: (item) {
          selected = item;
          return pending.future;
        },
      );
      await tester.enterText(find.byType(TextField).first, 'Dune');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.tap(find.text('Movie · 1984'));
      await tester.pump();
      expect(selected, isNotNull);

      await tester.enterText(find.byType(TextField).first, 'Arrival');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(fixture.requests.last.url.queryParameters['query'], 'Arrival');
      expect(find.byType(TextFieldSuggestions), findsOneWidget);

      pending.complete(selected!);
      await tester.pumpAndSettle();
      expect(find.byType(MergedDetailScreen), findsNothing);
      final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
      expect(field.controller.text, 'Arrival');
      await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
    },
  );

  for (final returnImmediately in [false, true]) {
    testWidgets(
      'switching tabs cancels a pending title open (immediate return: $returnImmediately)',
      (tester) async {
        final pending = Completer<StremioMeta>();
        final tab = ValueNotifier<int>(MainTab.search);
        addTearDown(tab.dispose);
        StremioMeta? selected;
        await mount(
          tester,
          resolve: (item) {
            selected = item;
            return pending.future;
          },
          wrap: (search) => ValueListenableBuilder<int>(
            valueListenable: tab,
            builder: (context, index, _) => AppTabSwitcher(
              selectedIndex: index,
              isTelevision: false,
              entranceAnimation: const AlwaysStoppedAnimation<double>(1),
              child: index == MainTab.search
                  ? search
                  : const Scaffold(body: Text('Home tab')),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField).first, 'Dune');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        await tester.tap(find.text('Movie · 2021'));
        await tester.pump();
        expect(selected, isNotNull);
        final original = tester.state(find.byType(SearchScreen));

        tab.value = MainTab.home;
        MainPageBridge.setActiveTab('home');
        if (returnImmediately) {
          // Both changes happen before a frame: the same Search state stays
          // mounted, but its old selection must remain cancelled.
          tab.value = MainTab.search;
          MainPageBridge.setActiveTab('search');
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.state(find.byType(SearchScreen)), same(original));
        if (!returnImmediately) {
          expect(find.text('Home tab'), findsOneWidget);
        }

        // Complete during the real tab transition, while Search is mounted.
        await drive(tester, () async => pending.complete(selected!));
        expect(find.byType(MergedDetailScreen), findsNothing);
        expect(tester.takeException(), isNull);
        await drive(tester, () => tester.pumpWidget(const SizedBox.shrink()));
      },
    );
  }
}
