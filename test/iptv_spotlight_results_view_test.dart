import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/browse/browse_search_header.dart';
import 'package:debrify/widgets/iptv/iptv_filters.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory catalogDirectory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    MainPageBridge.cancelIptvStartupChannel();
    MainPageBridge.cancelIptvStartup = null;
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    catalogDirectory = await Directory.systemTemp.createTemp(
      'spotlight-results-view-test',
    );
    AppStorage.debugOverride(
      documents: catalogDirectory,
      support: catalogDirectory,
      cache: catalogDirectory,
    );
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
    IptvCatalogDb.debugDirectoryOverride = catalogDirectory.path;
    await IptvCatalogDb.open();
    await StorageService.setIptvStyle('spotlight');
    await StorageService.setIptvChannelPreviewEnabled(false);
    await StorageService.setIptvPlaylists([
      IptvPlaylist(
        id: 'local-guide',
        name: 'Living room TV',
        url: '',
        content: '''#EXTM3U
#EXTINF:-1 tvg-id="one" group-title="News",News One
https://example.com/live/one.ts
#EXTINF:-1 tvg-id="two" group-title="Kids",Kids Two
https://example.com/live/two.ts
''',
        addedAt: DateTime(2026),
      ),
    ]);
  });

  tearDown(() async {
    MainPageBridge.cancelIptvStartupChannel();
    MainPageBridge.cancelIptvStartup = null;
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await catalogDirectory.delete(recursive: true);
  });

  testWidgets('selected Spotlight style renders the complete TV shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(896, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = TextEditingController();
    final searchFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(searchFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: IptvResultsView(
            searchQuery: '',
            isTelevision: true,
            searchHeader: BrowseSearchHeader(
              controller: controller,
              focusNode: searchFocus,
              hintText: 'Search channels',
              onClear: controller.clear,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(SpotlightLiveTimeline).evaluate().isNotEmpty) break;
    }

    expect(
      find.byKey(const ValueKey<String>('spotlight-shell-wide')),
      findsOneWidget,
    );
    expect(find.text('Debrify'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('Living room TV'), findsWidgets);
    expect(find.byType(BrowseSearchHeader), findsOneWidget);
    expect(find.byType(SpotlightLiveTimeline), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('spotlight-category-pill')),
    );
    await tester.pumpAndSettle();
    expect(find.text('All channels'), findsWidgets);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('Kids'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(800, 540);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('spotlight-shell-compact')),
      findsOneWidget,
    );
    expect(find.byType(SpotlightLiveTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(896, 540);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('spotlight-shell-wide')),
      findsOneWidget,
    );
    expect(find.byType(SpotlightLiveTimeline), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A short canvas deliberately uses the useful existing single-pane page.
    tester.view.physicalSize = const Size(760, 479);
    await tester.pumpAndSettle();
    expect(find.byType(SpotlightLiveTimeline), findsNothing);
    expect(find.byType(IptvFiltersBar), findsOneWidget);
    expect(find.byType(BrowseSearchHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Spotlight category picker lazily builds a bounded list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(896, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final content = StringBuffer('#EXTM3U\n');
    for (var index = 0; index < 400; index++) {
      final category = 'Category ${index.toString().padLeft(3, '0')}';
      content
        ..writeln('#EXTINF:-1 group-title="$category",Channel $index')
        ..writeln('https://example.com/live/$index.ts');
    }
    await tester.runAsync(
      () => StorageService.setIptvPlaylists([
        IptvPlaylist(
          id: 'local-guide',
          name: 'Large provider',
          url: '',
          content: content.toString(),
          addedAt: DateTime(2026),
        ),
      ]),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IptvResultsView(searchQuery: '', isTelevision: true),
        ),
      ),
    );
    await _pumpUntil(tester, find.byType(SpotlightLiveTimeline));

    await tester.tap(
      find.byKey(const ValueKey<String>('spotlight-category-pill')),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byKey(
      const ValueKey<String>('spotlight-category-list'),
    );
    expect(listFinder, findsOneWidget);
    final list = tester.widget<ListView>(listFinder);
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(
      find
          .descendant(of: listFinder, matching: find.byType(ListTile))
          .evaluate()
          .length,
      lessThan(30),
    );
    expect(find.text('Category 399'), findsNothing);

    final categoryScrollable = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Category 399'),
      1000,
      scrollable: categoryScrollable,
    );
    await tester.tap(find.text('Category 399'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('spotlight-category-pill')),
    );
    await tester.pumpAndSettle();

    final selectedTileFinder = find.byKey(
      const ValueKey<String>('spotlight-selected-category-tile'),
    );
    expect(selectedTileFinder, findsOneWidget);
    expect(
      find.descendant(
        of: selectedTileFinder,
        matching: find.text('Category 399'),
      ),
      findsOneWidget,
    );
    final selectedTile = tester.widget<ListTile>(selectedTileFinder);
    expect(selectedTile.focusNode, isNotNull);
    expect(selectedTile.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy two-pane height uses the body below search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => StorageService.setIptvStyle('command'));
    final height = ValueNotifier<double>(439);
    addTearDown(height.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (context, value, _) => SizedBox(
                width: 900,
                height: value,
                child: const IptvResultsView(
                  searchQuery: '',
                  isTelevision: true,
                  searchHeader: SizedBox(
                    key: ValueKey<String>('fixed-search'),
                    height: 60,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, find.byType(IptvFiltersBar));
    expect(find.byKey(const ValueKey<String>('iptv-cockpit')), findsNothing);

    height.value = 440;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('iptv-cockpit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch-tablet gate uses 499/500px body below search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.runAsync(() => StorageService.setIptvStyle('command'));
    final height = ValueNotifier<double>(559);
    addTearDown(height.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (context, value, _) => SizedBox(
                width: 900,
                height: value,
                child: const IptvResultsView(
                  searchQuery: '',
                  searchHeader: SizedBox(height: 60),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('iptv-cockpit')),
    );
    expect(
      find.byKey(const ValueKey<String>('iptv-tablet-two-pane')),
      findsNothing,
    );

    height.value = 560;
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('iptv-tablet-two-pane')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Spotlight startup hands a nonzero row to the timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(896, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final content = StringBuffer('#EXTM3U\n');
    for (var index = 0; index < 24; index++) {
      content
        ..writeln('#EXTINF:-1 group-title="News",Startup $index')
        ..writeln('https://example.com/startup/$index.ts');
    }
    await tester.runAsync(
      () => StorageService.setIptvPlaylists([
        IptvPlaylist(
          id: 'local-guide',
          name: 'Startup provider',
          url: '',
          content: content.toString(),
          addedAt: DateTime(2026),
        ),
      ]),
    );
    MainPageBridge.setIptvStartupChannel({
      'playlistId': 'local-guide',
      'url': 'https://example.com/startup/17.ts',
      'name': 'Startup 17',
    });
    final handedIndices = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvResultsView(
            searchQuery: '',
            isTelevision: true,
            debugOnSpotlightStartupFocus: (index) {
              handedIndices.add(index);
              MainPageBridge.cancelIptvStartupChannel();
            },
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 80 && handedIndices.isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(handedIndices, [17]);
    expect(find.text('Startup 17'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}
