import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/browse_screen.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_keyboard.dart';
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
import 'package:debrify/widgets/iptv/spotlight/spotlight_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  for (final favorites in [true, false]) {
    testWidgets(
      'Spotlight ${favorites ? 'Favorites' : 'custom list'} uses guide navigation',
      (tester) async {
        tester.view.physicalSize = const Size(896, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late String listId;
        await tester.runAsync(() async {
          listId = favorites
              ? StorageService.iptvFavoritesListId
              : await StorageService.createIptvList('Mixed shelf');
          for (var i = 0; i < 2; i++) {
            await StorageService.setIptvChannelInList(
              listId,
              'https://example.com/saved/$i.ts',
              true,
              channelName: 'Saved channel $i',
              playlistId: i == 0 ? 'local-guide' : 'another-provider',
              contentType: i == 0 ? 'live' : 'vod',
            );
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: IptvResultsView(searchQuery: '', isTelevision: true),
            ),
          ),
        );
        Future<void> settleShelf() async {
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await settleShelf();
        await tester.tap(
          find.byKey(
            ValueKey<String>(
              'spotlight-rail-tile-playlist-${favorites ? 'iptv-favorites' : 'iptv-list-$listId'}',
            ),
          ),
        );
        await settleShelf();
        final timeline = tester.widget<SpotlightLiveTimeline>(
          find.byType(SpotlightLiveTimeline),
        );
        expect(timeline.channels.map((c) => c.name), [
          'Saved channel 0',
          'Saved channel 1',
        ]);
        expect(timeline.controller!.focusChannelAt(0), isTrue);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'spotlight-live-timeline',
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Saved channel 1, On demand' &&
                widget.properties.selected == true,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('Spotlight source rail Left opens the app sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sidebar = FocusNode(debugLabel: 'review-sidebar');
    addTearDown(sidebar.dispose);
    final previousSidebarCallback = MainPageBridge.focusTvSidebar;
    addTearDown(() => MainPageBridge.focusTvSidebar = previousSidebarCallback);
    MainPageBridge.focusTvSidebar = sidebar.requestFocus;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 72,
                child: TextButton(
                  focusNode: sidebar,
                  onPressed: () {},
                  child: const Text('Home'),
                ),
              ),
              const Expanded(
                child: IptvResultsView(searchQuery: '', isTelevision: true),
              ),
            ],
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
    final timeline = tester.widget<SpotlightLiveTimeline>(
      find.byType(SpotlightLiveTimeline),
    );
    expect(timeline.controller!.focusFirstChannel(), isTrue);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
      'iptv-spotlight-sources',
    );
    final shell = find.byType(SpotlightShell);
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isTrue);
    final heroRect = tester.getRect(
      find.byKey(const ValueKey('spotlight-hero')),
    );
    final heroElement = tester.element(
      find.byKey(const ValueKey('spotlight-hero')),
    );
    final expandedContent = tester.getRect(find.byType(SpotlightLiveTimeline));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isFalse);
    expect(timeline.controller!.hasFocus, isTrue);
    expect(tester.getRect(find.byType(SpotlightLiveTimeline)), expandedContent);
    expect(
      tester.getRect(find.byKey(const ValueKey('spotlight-hero'))),
      heroRect,
    );
    expect(
      tester.element(find.byKey(const ValueKey('spotlight-hero'))),
      same(heroElement),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(sidebar.hasPrimaryFocus, isFalse);
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    final sourceNode = FocusManager.instance.primaryFocus!;
    Focus.of(tester.element(find.text('Manage sources'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
      isNot('iptv-spotlight-sources'),
    );
    sourceNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(sidebar.hasPrimaryFocus, isTrue);
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isFalse);
    sourceNode.requestFocus();
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isTrue);
    await tester.tap(find.byKey(const ValueKey('spotlight-sources-toggle')));
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isFalse);
    expect(timeline.controller!.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('spotlight-sources-toggle')));
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isTrue);
    await tester.tapAt(expandedContent.centerRight - const Offset(20, 0));
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isFalse);
    expect(timeline.controller!.hasFocus, isTrue);
    // The app's existing Back flow also opens its sidebar through this bridge.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    MainPageBridge.notifyTvSidebarFocusChanged(true);
    sidebar.requestFocus();
    await tester.pump();
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isFalse);
    MainPageBridge.notifyTvSidebarFocusChanged(false);
    final results = tester.state<IptvResultsViewState>(
      find.byType(IptvResultsView),
    );
    results.focusFirstFilter();
    await tester.pump();
    Focus.of(tester.element(find.text('Manage sources'))).requestFocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    final rememberedSource = FocusManager.instance.primaryFocus!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sidebar.hasPrimaryFocus, isTrue);
    // Exercise BrowseScreen's actual app-sidebar return callback.
    results.focusFirstFilter();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus, same(rememberedSource));
    expect(tester.widget<SpotlightShell>(shell).sourcesExpanded, isTrue);
    final panel = tester.getRect(
      find.byKey(const ValueKey('spotlight-sources-panel')),
    );
    expect(
      panel.contains(tester.getCenter(find.text('Manage sources'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Spotlight traverses wrapped hero actions before leaving the panel',
    (tester) async {
      await tester.runAsync(() => StorageService.createIptvList('Review list'));
      tester.view.physicalSize = const Size(896, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var upExits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: IptvResultsView(
              searchQuery: '',
              isTelevision: true,
              onUpArrowFromFilters: () => upExits++,
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
      tester
          .widget<SpotlightLiveTimeline>(find.byType(SpotlightLiveTimeline))
          .controller!
          .focusFirstChannel();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      final watch = find.widgetWithText(FilledButton, 'Watch');
      final favorite = find.byTooltip('Add to Favorites');
      expect(
        tester.getTopLeft(favorite).dy,
        greaterThan(tester.getTopLeft(watch).dy),
      );
      final watchNode = tester.widget<FilledButton>(watch).focusNode!;
      expect(watchNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final lowerAction = FocusManager.instance.primaryFocus!;
      expect(lowerAction.nearestScope?.debugLabel, 'iptv-spotlight-hero');
      expect(lowerAction.rect.top, greaterThan(watchNode.rect.top));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus!.rect.top,
        lessThan(lowerAction.rect.top),
      );
      expect(upExits, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(upExits, 1);
      lowerAction.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-category-filter',
      );
      Focus.of(
        tester.element(
          find.descendant(
            of: find.byTooltip('More channel actions'),
            matching: find.byIcon(Icons.more_horiz_rounded),
          ),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        isNot('iptv-spotlight-hero'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [800.0, 896.0]) {
    testWidgets('Spotlight DPAD connects sources, guide and hero at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: IptvResultsView(searchQuery: '', isTelevision: true),
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
      await tester.tap(find.byKey(const ValueKey('spotlight-category-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All channels'));
      await tester.pumpAndSettle();
      final timeline = tester.widget<SpotlightLiveTimeline>(
        find.byType(SpotlightLiveTimeline),
      );
      expect(timeline.controller!.focusChannelAt(1), isTrue);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(timeline.controller!.hasFocus, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-playlist-filter',
      );
      if (width >= 860) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      } else {
        // The source trigger opens a sheet on compact canvases; dismissing it
        // must restore the trigger before returning to content.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-playlist-filter',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'iptv-spotlight-primary-action',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pump();
      expect(timeline.controller!.hasFocus, isTrue);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label?.contains(timeline.channels[1].name) ??
                  false) &&
              w.properties.selected == true,
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-category-filter',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-spotlight-primary-action',
      );
      expect(find.text('Watch'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.text('Add to Favorites'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'iptv-category-filter',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(timeline.controller!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Spotlight preview actions fit the minimum and desktop canvases',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 480);
      addTearDown(tester.view.reset);
      final surface = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: surface,
              child: const IptvResultsView(searchQuery: '', isTelevision: true),
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
      for (final size in [
        const Size(800, 480),
        const Size(896, 480),
        const Size(1200, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        final timeline = tester.widget<SpotlightLiveTimeline>(
          find.byType(SpotlightLiveTimeline),
        );
        timeline.controller!.focusFirstChannel();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        final actions = tester.getRect(
          find.byKey(const ValueKey('spotlight-hero-actions-slot')),
        );
        final hero = tester.getRect(
          find.byKey(const ValueKey('spotlight-hero')),
        );
        expect(hero.contains(actions.topLeft), isTrue);
        expect(hero.contains(actions.bottomRight - const Offset(1, 1)), isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
    expect(find.byTooltip('Expand sources'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spotlight-category-control')),
      findsOneWidget,
    );
    expect(find.text('Living room TV'), findsWidgets);
    expect(
      find.byType(BrowseSearchHeader, skipOffstage: false),
      findsOneWidget,
    );
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
    expect(
      find.byType(BrowseSearchHeader, skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar search keeps TV keyboard open and submits into results',
    (tester) async {
      tester.view.physicalSize = const Size(896, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PlatformUtil.debugSetAndroidTvCached(true);
      final previousKeyboard = StorageService.tvKeyboardEnabledCached;
      StorageService.tvKeyboardEnabledCached = true;
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        StorageService.tvKeyboardEnabledCached = previousKeyboard;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: BrowseScreen(
              tabIndex: 13,
              hintText: 'Search channels',
              submitOnly: false,
              isTelevision: true,
              embedSearchHeaderInView: true,
              viewBuilder: (args) => IptvResultsView(
                key: args.resultKey,
                searchQuery: args.query,
                isTelevision: args.isTelevision,
                searchHeader: args.searchHeader,
                onUpArrowFromFilters: args.onUpArrowToSearch,
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, find.byType(SpotlightLiveTimeline));
      bool expanded() => tester
          .widget<SpotlightShell>(find.byType(SpotlightShell))
          .sourcesExpanded;
      final initialChannels = tester
          .widget<SpotlightLiveTimeline>(find.byType(SpotlightLiveTimeline))
          .channels
          .map((c) => c.name)
          .toList();
      final hero = find.byKey(const ValueKey('spotlight-hero'));
      final heroRect = tester.getRect(hero);
      final heroElement = tester.element(hero);
      expect(heroRect.height, greaterThan(225));
      expect(find.byType(BrowseSearchHeader), findsNothing);
      final hiddenSearch = tester.widget<BrowseSearchHeader>(
        find.byType(BrowseSearchHeader, skipOffstage: false),
      );
      expect(hiddenSearch.focusNode.canRequestFocus, isFalse);

      await tester.tap(find.byTooltip('Search channels'));
      await tester.pumpAndSettle();
      expect(expanded(), isTrue);
      expect(hiddenSearch.focusNode.hasFocus, isTrue);
      expect(tester.getRect(hero), heroRect);
      expect(tester.element(hero), same(heroElement));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TvKeyboardPanel), findsOneWidget);
      expect(expanded(), isTrue);
      var keyboard = tester
          .widget<TvKeyboardPanel>(find.byType(TvKeyboardPanel))
          .controller;
      keyboard.onInsert('Kids');
      await tester.pump();
      // Submit before the live-filter debounce fires.
      keyboard.onSubmit();
      await tester.pumpAndSettle();
      expect(find.byType(TvKeyboardPanel), findsNothing);
      expect(expanded(), isFalse);
      var timeline = tester.widget<SpotlightLiveTimeline>(
        find.byType(SpotlightLiveTimeline),
      );
      expect(timeline.channels.map((channel) => channel.name), ['Kids Two']);
      expect(timeline.controller!.hasFocus, isTrue);

      // Guide -> sources -> Up reaches Search. Opening the keyboard keeps the
      // field mounted; a query with no matches stays editable after submission.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(hiddenSearch.focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      keyboard = tester
          .widget<TvKeyboardPanel>(find.byType(TvKeyboardPanel))
          .controller;
      keyboard.onClear();
      keyboard.onInsert('No matching channel');
      await tester.pump();
      keyboard.onSubmit();
      await tester.pumpAndSettle();
      expect(expanded(), isTrue);
      expect(hiddenSearch.focusNode.hasFocus, isTrue);
      expect(find.byType(TvKeyboardPanel), findsNothing);
      final search = tester.widget<BrowseSearchHeader>(
        find.byType(BrowseSearchHeader),
      );
      search.onClear();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      timeline = tester.widget<SpotlightLiveTimeline>(
        find.byType(SpotlightLiveTimeline),
      );
      expect(timeline.channels.map((c) => c.name), initialChannels);
      expect(timeline.controller!.hasFocus, isTrue);
      expect(expanded(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search spans categories and clearing restores the browse category',
    (tester) async {
      tester.view.physicalSize = const Size(896, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final query = ValueNotifier<String>('');
      addTearDown(query.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: query,
              builder: (context, value, _) =>
                  IptvResultsView(searchQuery: value, isTelevision: true),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, find.byType(SpotlightLiveTimeline));
      await tester.tap(
        find.byKey(const ValueKey<String>('spotlight-category-pill')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SpotlightLiveTimeline>(find.byType(SpotlightLiveTimeline))
            .channels
            .map((c) => c.name),
        ['News One'],
      );
      query.value = 'Kids';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SpotlightLiveTimeline>(find.byType(SpotlightLiveTimeline))
            .channels
            .map((c) => c.name),
        ['Kids Two'],
      );
      query.value = '';
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SpotlightLiveTimeline>(find.byType(SpotlightLiveTimeline))
            .channels
            .map((c) => c.name),
        ['News One'],
      );
      expect(tester.takeException(), isNull);
    },
  );

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
