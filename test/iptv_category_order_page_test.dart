import 'dart:async';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/iptv_category_order_page.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  const catalogKey = 'm3u|http://example/list.m3u';
  final playlist = IptvPlaylist(
    id: 'source-1',
    name: 'Example playlist',
    url: 'http://example/list.m3u',
    addedAt: DateTime(2026),
  );

  Future<void> drainAsync(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('category_order_page_test');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: catalogKey,
      channels: [
        IptvChannel(
          name: 'News One',
          url: 'http://h/1',
          group: 'News',
          duration: -1,
        ),
        IptvChannel(
          name: 'Sports One',
          url: 'http://h/2',
          group: 'Sports',
          duration: -1,
        ),
        IptvChannel(
          name: 'Kids One',
          url: 'http://h/3',
          group: 'Kids',
          duration: -1,
        ),
      ],
      categories: const ['News', 'Sports', 'Kids'],
    );
    IptvCatalogDb.setGroupHidden(catalogKey, 'Kids', true);
    PlatformUtil.debugSetAndroidTvCached(true);
  });

  tearDown(() async {
    PlatformUtil.debugSetAndroidTvCached(null);
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  testWidgets(
    'TV reorder saves category ranks and provider reset clears them',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget app() => AppThemeScope(
        theme: AppThemes.legacy,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IptvCategoryOrderPage(playlist: playlist),
                  ),
                ),
                child: const Text('Open category order'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app());
      await tester.tap(find.text('Open category order'));
      await drainAsync(tester);

      expect(find.text('News'), findsOneWidget);
      expect(find.text('Sports'), findsOneWidget);
      expect(find.text('Kids'), findsOneWidget);
      expect(find.text('1 channel · Hidden'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('iptv-category-order-'),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Moving…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      await tester.tap(find.text('Done'));
      await drainAsync(tester);
      expect(IptvCatalogDb.savedCategoryOrder(catalogKey), [
        'Sports',
        'News',
        'Kids',
      ]);

      expect(find.text('Open category order'), findsOneWidget);
      await tester.tap(find.text('Open category order'));
      await drainAsync(tester);
      final sportsTop = tester.getTopLeft(find.text('Sports')).dy;
      final newsTop = tester.getTopLeft(find.text('News')).dy;
      expect(sportsTop, lessThan(newsTop));

      await tester.tap(find.text('Provider order'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await drainAsync(tester);
      expect(IptvCatalogDb.savedCategoryOrder(catalogKey), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving freezes the submitted category-order snapshot', (
    tester,
  ) async {
    final saveStarted = Completer<void>();
    final releaseSave = Completer<void>();
    List<String>? submitted;
    Widget app() => AppThemeScope(
      theme: AppThemes.legacy,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => IptvCategoryOrderPage(
                    playlist: playlist,
                    debugSaveCategoryOrder: (_, ordered) async {
                      submitted = ordered.toList(growable: false);
                      saveStarted.complete();
                      await releaseSave.future;
                    },
                  ),
                ),
              ),
              child: const Text('Open category order'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.tap(find.text('Open category order'));
    await drainAsync(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(saveStarted.isCompleted, isTrue);
    expect(find.text('Saving…'), findsOneWidget);
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Provider order'),
    );
    expect(reset.onPressed, isNull);

    await tester.tap(find.text('Provider order'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Sports')).dy,
      lessThan(tester.getTopLeft(find.text('News')).dy),
    );

    releaseSave.complete();
    await drainAsync(tester);
    expect(submitted, ['Sports', 'News', 'Kids']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile switch closes the editor without saving stale keys', (
    tester,
  ) async {
    final profileSetup = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'category_order_profile_guard_test',
      );
      final registry = await ProfileRegistry.open(
        path: p.join(directory.path, 'profiles.db'),
      );
      final first = await registry.createProfile(
        name: 'First',
        role: UserProfileRole.admin,
      );
      final second = await registry.createProfile(
        name: 'Second',
        role: UserProfileRole.admin,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: first.id, dataGeneration: 1, sessionEpoch: 1),
      );
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.iptv,
      );
      return (
        directory: directory,
        registry: registry,
        second: second,
        authorization: authorization,
      );
    }))!;
    addTearDown(() async {
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      await profileSetup.registry.close();
      await profileSetup.directory.delete(recursive: true);
    });

    await tester.pumpWidget(
      AppThemeScope(
        theme: AppThemes.legacy,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IptvCategoryOrderPage(
                      playlist: playlist,
                      authorization: profileSetup.authorization,
                    ),
                  ),
                ),
                child: const Text('Open category order'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open category order'));
    await drainAsync(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    ProfileRuntime.publish(
      ProfileScope(
        profileId: profileSetup.second.id,
        dataGeneration: 1,
        sessionEpoch: 2,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Open category order'), findsOneWidget);
    expect(
      find.text('The active profile changed. Nothing was saved.'),
      findsAtLeastNWidgets(1),
    );
    expect(IptvCatalogDb.savedCategoryOrder(catalogKey), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imported-file categories load without catalog rows', (
    tester,
  ) async {
    final local = IptvPlaylist(
      id: 'local-1',
      name: 'Imported file',
      url: '',
      content: '''
#EXTM3U
#EXTINF:-1 group-title="Local News",One
http://h/one
#EXTINF:-1 group-title="Local Sports",Two
http://h/two
''',
      addedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: IptvCategoryOrderPage(playlist: local),
        ),
      ),
    );
    await drainAsync(tester);

    expect(find.text('Local News'), findsOneWidget);
    expect(find.text('Local Sports'), findsOneWidget);
    expect(find.textContaining('Open this source in IPTV once'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('imported-file order reopens the catalog DB before reading', () async {
    const playlistId = 'local-closed-db';
    await IptvCatalogDb.setCategoryOrder(
      IptvCatalogKey.forLocalCategoryOrder(playlistId),
      const ['Local Sports', 'Local News'],
    );
    await IptvCatalogDb.closeScope();
    expect(IptvCatalogDb.isOpen, isFalse);

    final ordered = await IptvResultsViewState.applyStoredLocalCategoryOrder(
      playlistId,
      const ['Local News', 'Local Sports'],
    );

    expect(IptvCatalogDb.isOpen, isTrue);
    expect(ordered, const ['Local Sports', 'Local News']);
  });

  test(
    'catalog DB failure leaves imported-file playback in provider order',
    () async {
      await IptvCatalogDb.closeScope();
      final notDirectory = File(p.join(dir.path, 'not-a-directory'));
      await notDirectory.writeAsString('blocked');
      IptvCatalogDb.debugDirectoryOverride = notDirectory.path;

      final ordered = await IptvResultsViewState.applyStoredLocalCategoryOrder(
        'local-unavailable-db',
        const ['Local News', 'Local Sports'],
      );

      expect(ordered, const ['Local News', 'Local Sports']);
      expect(IptvCatalogDb.isOpen, isFalse);
      IptvCatalogDb.debugDirectoryOverride = dir.path;
    },
  );
}
