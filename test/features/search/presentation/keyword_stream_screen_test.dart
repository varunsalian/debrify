import 'package:debrify/features/search/application/keyword_appearance_dependencies.dart';
import 'package:debrify/models/source_appearance.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/features/home/application/home_default_view_dependencies.dart';
import 'package:debrify/features/search/application/keyword_defaults_dependencies.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import '../fakes/fake_keyword_defaults_repository.dart';
import 'dart:async';

import 'package:debrify/features/search/application/keyword_cache_dependencies.dart';
import 'package:debrify/features/search/application/keyword_search_dependencies.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
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
import '../fakes/fake_keyword_search_repository.dart';
import '../keyword_torrent_fixture.dart';

void main() {
  late FakeKeywordSearchRepository repository;
  late FakeKeywordCacheRepository cache;
  late FakeKeywordDefaultsRepository defaults;
  late MockClient client;
  var homeDefaultReads = 0;
  SourceAppearanceReader? appearanceReader;

  setUp(() {
    homeDefaultReads = 0;
    appearanceReader = null;
    disableRuntimeFonts();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    SharedPreferences.setMockInitialValues({});
    MainPageBridge.setActiveTab('search');
    StremioService.instance.invalidateCache();
    repository = FakeKeywordSearchRepository();
    cache = FakeKeywordCacheRepository();
    defaults = FakeKeywordDefaultsRepository()..delayed = false;
    cache.session.torboxEnabled = false;
    client = MockClient((_) async => http.Response('{}', 404));
  });
  tearDown(() {
    for (final request in repository.requests) {
      if (!request.completion.isCompleted) request.complete([]);
    }
    MainPageBridge.setActiveTab(null);
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
    client.close();
  });

  Future<void> drive(
    WidgetTester tester,
    FutureOr<void> Function() action,
  ) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, () => client),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> submit(WidgetTester tester, String query) => drive(tester, () {
    final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
    field.controller.text = query;
    field.onSubmitted!(query);
  });

  Widget application({bool home = false}) => ProviderScope(
    overrides: [
      if (appearanceReader != null)
        keywordAppearanceReaderProvider.overrideWith(
          (ref, session) => appearanceReader!,
        ),
      homeDefaultViewReaderProvider.overrideWithValue(() async {
        homeDefaultReads++;
        return 'keyword';
      }),
      keywordDefaultsRepositoryProvider.overrideWith(
        (ref, session) => defaults,
      ),
      keywordSearchRepositoryProvider.overrideWith(
        (ref, session) => repository,
      ),
      keywordCacheRepositoryProvider.overrideWith((ref, session) => cache),
    ],
    child: MaterialApp(home: SearchScreen(searchMode: !home)),
  );

  Future<void> mount(WidgetTester tester, {bool home = false}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await drive(tester, () => tester.pumpWidget(application(home: home)));
    await tester.tap(find.text('Keyword'));
    await tester.pump();
    await submit(tester, 'query');
    expect(repository.requests.single.query, 'query');
  }

  CinemaSourcesLayout layout(WidgetTester tester) =>
      tester.widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout));

  testWidgets(
    'keyword row appearance refresh preserves results and rejects late startup',
    (tester) async {
      final startup = Completer<SourceAppearance>();
      var reads = 0;
      appearanceReader = () => ++reads == 1
          ? startup.future
          : Future.value((text: true, logos: false));
      await mount(tester, home: true);
      final row = Torrent.fromJson({
        ...keywordTorrent('Appearance fixture').toJson(),
        'stream_label': 'Addon title',
        'stream_description': 'Addon description',
        'addon_display_name': 'Addon name',
      });
      await drive(tester, () => repository.requests.single.complete([row]));
      SourceRow rendered() =>
          tester.widget<SourceRow>(find.byType(SourceRow).first);
      expect(rendered().addonText, isNull);
      expect(rendered().addonName, isNull);
      await drive(tester, MainPageBridge.notifyHomeSettingsChanged);
      expect(rendered().addonText, row.addonPresentation);
      expect(rendered().addonText, isNotNull);
      expect(rendered().addonName, isNull);
      await drive(tester, () => startup.complete((text: false, logos: true)));
      expect(rendered().addonText, row.addonPresentation);
      expect(rendered().addonName, isNull);
      expect(reads, 2);
      expect(repository.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'frozen final snapshot retains authoritative raw rows and legacy displayed rows',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      final old = keywordTorrent('Old row', source: 'one');
      final added = keywordTorrent('Added row', source: 'two');
      await drive(tester, () => request.onBatch('first', [old]));
      layout(tester).onFocusResults();
      await tester.pump();
      expect(layout(tester).isSourceFocused(), isTrue);
      await drive(tester, () => request.complete([old, added]));
      expect(layout(tester).resultCount, 1);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await drive(tester, () => tester.pumpWidget(application()));
      expect(layout(tester).resultCount, 1);
      expect(layout(tester).providers.first.count, 2);
      expect(layout(tester).providersEnabled, isTrue);
      expect(layout(tester).searching, isFalse);
      expect(repository.requests, hasLength(1));
      expect(defaults.reads, hasLength(1));
      await tester.tap(find.textContaining('Sort ·'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Relevance'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(layout(tester).resultCount, 2);
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'late defaults filter fast rows and restore without another read or search',
    (tester) async {
      defaults.delayed = true;
      await mount(tester);
      expect(defaults.reads, hasLength(1));
      final request = repository.requests.single;
      final hd = keywordTorrent('Result.1080p');
      final uhd = keywordTorrent('Result.2160p');
      await drive(tester, () => request.onBatch('first', [hd, uhd]));
      expect(layout(tester).resultCount, 2);
      await drive(
        tester,
        () => defaults.reads.single.complete(
          TorrentFilterState(qualities: {QualityTier.fullHd}),
        ),
      );
      expect(layout(tester).resultCount, 1);
      await drive(tester, () => request.complete([hd, uhd]));
      expect(layout(tester).resultCount, 1);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await drive(tester, () => tester.pumpWidget(application()));
      expect(layout(tester).resultCount, 1);
      expect(defaults.reads, hasLength(1));
      expect(repository.requests, hasLength(1));
      expect(
        tester
            .widget<TvTextField>(find.byType(TvTextField).first)
            .controller
            .text,
        'query',
      );
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('Home keyword return skips the saved-default read', (
    tester,
  ) async {
    await mount(tester, home: true);
    expect(homeDefaultReads, 1);
    final request = repository.requests.single;
    await drive(
      tester,
      () => request.complete([keywordTorrent('Saved.1080p')]),
    );
    expect(layout(tester).resultCount, 1);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
    await drive(tester, () => tester.pumpWidget(application(home: true)));
    expect(layout(tester).resultCount, 1);
    expect(repository.requests, hasLength(1));
    expect(homeDefaultReads, 1);
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
    'open provider dialog clears outgoing choices and rejects retained callbacks',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      await drive(
        tester,
        () => request.onBatch('first', [
          keywordTorrent('Private A', source: 'one'),
          keywordTorrent('Private B', source: 'two'),
        ]),
      );
      await tester.tap(find.text('Providers'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      final staleChoice = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile).first,
      );
      await drive(tester, () {
        repository.isCurrent = false;
        ProfileRuntime.initializeCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 2,
          ),
        );
      });
      expect(find.byType(CheckboxListTile), findsNothing);
      staleChoice.onChanged!(false);
      await tester.pump();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(repository.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'provider dialog, sort and bulk actions use current immutable choices',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      final first = keywordTorrent('Zebra', source: 'one');
      final second = keywordTorrent('Zulu', source: 'two');
      final added = keywordTorrent('Alpha', source: 'three');
      await drive(tester, () => request.onBatch('first', [first, second]));
      await tester.tap(find.text('Providers'));
      await tester.pump(const Duration(milliseconds: 300));
      var choices = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(choices.map((choice) => choice.value), [true, true]);
      choices.first.onChanged!(false);
      await tester.pump();
      expect(layout(tester).resultCount, 1);
      choices = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(choices.map((choice) => choice.value), [false, true]);
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(layout(tester).resultCount, 2);
      await tester.tap(find.text('None'));
      await tester.pump();
      expect(layout(tester).resultCount, 0);
      choices = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      choices.last.onChanged!(true);
      await tester.pump();
      await drive(tester, () => request.complete([first, second, added]));
      expect(
        layout(tester).resultCount,
        1,
      ); // dialog keeps the displayed set frozen
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Sort ·'));
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // sort opens over adopted pending arrivals
      await tester.tap(find.text('Name'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        layout(tester).resultCount,
        2,
      ); // new provider selected; untick retained
      expect(find.text('Zebra'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu')).dy),
      );
      await tester.ensureVisible(find.text('Select'));
      await tester.pump();
      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.text('Add · 2'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Select'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'first batch paints; frozen arrivals adopt without losing row identity',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      final old = keywordTorrent('Original result', source: 'z', seeders: 1);
      final added = keywordTorrent('New result', source: 'a', seeders: 20);
      await drive(tester, () => request.onBatch('z', [old]));
      expect(layout(tester).resultCount, 1);
      expect(layout(tester).searching, isTrue);
      layout(tester).onFocusResults();
      await tester.pump();
      expect(
        layout(tester).isSourceFocused(),
        isTrue,
      ); // real interaction freezes
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'kw_0');
      await drive(tester, () => request.onBatch('a', [added]));
      expect(layout(tester).resultCount, 1);
      expect(layout(tester).providers.map((provider) => provider.id), [
        null,
        'a',
        'z',
      ]);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'kw_0');
      await drive(tester, () => request.complete([added, old]));
      expect(layout(tester).resultCount, 1);
      expect(layout(tester).searching, isFalse);
      layout(tester).onProviderSelected(null); // explicit action adopts pending
      await tester.pump();
      await tester.pump();
      expect(layout(tester).resultCount, 2);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'kw_1');
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      // The existing loader uses uncancellable delayed 3s/7s messages. Let its
      // mounted guards run after disposal; this slice does not change it.
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'completion invalidates vanished source against full pending results',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      final a = keywordTorrent('Result A', source: 'a');
      final b = keywordTorrent('Result B', source: 'b');
      await drive(tester, () => request.onBatch('first', [a, b]));
      layout(tester).onProviderSelected('b');
      await tester.pump();
      expect(layout(tester).selectedProvider, 'b');
      expect(layout(tester).resultCount, 1);
      await drive(tester, () => request.complete([a]));
      expect(layout(tester).selectedProvider, isNull);
      // Frozen displayed rows remain until explicit adoption, but the invalid
      // source filter is removed immediately so All and its rows agree.
      expect(layout(tester).resultCount, 2);
      expect(layout(tester).providers.map((provider) => provider.id), [
        null,
        'a',
      ]);
      layout(tester).onProviderSelected(null);
      await tester.pump();
      expect(layout(tester).resultCount, 1);
      expect(find.text('Result B'), findsNothing);
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      // The existing loader uses uncancellable delayed 3s/7s messages. Let its
      // mounted guards run after disposal; this slice does not change it.
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('new query keeps late old batch and completion off screen', (
    tester,
  ) async {
    await mount(tester);
    final old = repository.requests.single;
    await submit(tester, 'new query');
    await drive(tester, () {
      old.onBatch('late', [keywordTorrent('Old result')]);
      old.complete([keywordTorrent('Old result')]);
    });
    expect(find.text('Old result'), findsNothing);
    expect(find.byType(CinemaSourcesLayout), findsNothing);
    await drive(
      tester,
      () => repository.requests.last.complete([keywordTorrent('New result')]),
    );
    expect(layout(tester).resultCount, 1);
    expect(layout(tester).searching, isFalse);
    expect(find.text('Old result'), findsNothing);
    expect(cache.opens, 2);
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
    // The existing loader uses uncancellable delayed 3s/7s messages. Let its
    // mounted guards run after disposal; this slice does not change it.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
    'profile handoff clears streamed rows and rejects outstanding completion',
    (tester) async {
      await mount(tester);
      final request = repository.requests.single;
      await drive(
        tester,
        () => request.onBatch('first', [keywordTorrent('Private result')]),
      );
      expect(layout(tester).resultCount, 1);
      await drive(tester, () {
        repository.isCurrent = false;
        ProfileRuntime.initializeCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 2,
          ),
        );
      });
      await drive(tester, () {
        request.onBatch('late', [keywordTorrent('Late private result')]);
        request.complete([keywordTorrent('Private result')]);
      });
      expect(find.text('Private result'), findsNothing);
      expect(find.text('Late private result'), findsNothing);
      expect(
        tester
            .widget<TvTextField>(find.byType(TvTextField).first)
            .controller
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
      // The existing loader uses uncancellable delayed 3s/7s messages. Let its
      // mounted guards run after disposal; this slice does not change it.
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
