import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/storage/storage_profile_caches.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Original view running against a real temporary catalog and profile store.
/// Fixture channels have no logo/guide URL, so golden paint never makes a
/// provider request or reaches an uninjected service wall clock.
class IptvResultsFixture {
  IptvResultsFixture._(this.directory, this.playlist, this.channels);

  final Directory directory;
  final IptvPlaylist playlist;
  final List<IptvChannel> channels;
  final key = GlobalKey<IptvResultsViewState>();
  static final clock = DateTime(2030, 1, 1, 10);

  String get catalogKey => IptvCatalogKey.forPlaylist(playlist, 'live')!;
  IptvResultsViewState get state => key.currentState!;

  static Future<IptvResultsFixture> create({
    String style = 'command',
    bool numbered = true,
  }) async {
    MainPageBridge.cancelIptvStartupChannel();
    MainPageBridge.cancelIptvStartup = null;
    SharedPreferences.setMockInitialValues({
      IptvCatalogRefreshService.intervalKey: 0,
    });
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    resetStorageProfileCaches();
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'iptv-view-contract',
    );
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
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
    IptvCatalogDb.debugDirectoryOverride = directory.path;
    await IptvCatalogDb.open();
    await IptvAppearanceStorage.setIptvChannelPreviewEnabled(false);
    await IptvAppearanceStorage.setIptvStyle(style);
    final playlist = IptvPlaylist(
      id: 'characterization-provider',
      name: 'Characterization TV',
      url: 'https://example.test/characterization.m3u',
      addedAt: DateTime(2026),
    );
    final channels = [
      for (var index = 0; index < 12; index++)
        IptvChannel(
          name: 'Channel ${index + 1}',
          url: 'https://example.test/live/${index + 1}.ts',
          group: ['News', 'Kids', 'Culture'][index % 3],
          contentType: 'live',
          duration: -1,
          attributes: {'tvg-id': 'contract-${index + 1}'},
          httpHeaders: const {'User-Agent': 'contract-client'},
        ),
    ];
    final fixture = IptvResultsFixture._(directory, playlist, channels);
    fixture.ingest(channels, numbered: numbered);
    await IptvPlaylistStorage.setIptvPlaylists([playlist]);
    return fixture;
  }

  CatalogSnapshot ingest(
    List<IptvChannel> rows, {
    bool numbered = true,
    List<String> categories = const ['News', 'Kids', 'Culture'],
  }) {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: catalogKey,
      channels: rows,
      categories: categories,
      numberingSourceKey: numbered ? catalogKey : null,
    );
    return IptvCatalogDb.snapshot(catalogKey)!;
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    bool television = true,
    String query = '',
    FocusNode? externalFocus,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Column(
            children: [
              if (externalFocus != null)
                Focus(
                  focusNode: externalFocus,
                  child: const SizedBox(height: 20),
                ),
              Expanded(
                child: RepaintBoundary(
                  key: const ValueKey('iptv-characterization-canvas'),
                  child: IptvResultsView(
                    key: key,
                    searchQuery: query,
                    isTelevision: television,
                    debugSpotlightNow: () => clock,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await until(
      tester,
      () =>
          key.currentState != null &&
          iptvResultsViewTestAccess(state).snapshot != null &&
          iptvResultsViewTestAccess(state).filteredChannels.isNotEmpty,
    );
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      ready(),
      isTrue,
      reason: 'SQL view did not finish the expected action',
    );
    expect(tester.takeException(), isNull);
  }

  Future<void> notifyRefresh(
    WidgetTester tester,
    CatalogSnapshot expected,
  ) async {
    IptvCatalogRefreshService.instance.revision.value++;
    await until(
      tester,
      () =>
          iptvResultsViewTestAccess(state).snapshot?.generation ==
          expected.generation,
    );
    // Refresh may publish its snapshot before focus cleanup and shelf reads.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Complete the existing maintenance delay after unmount, when its mounted
    // guard rejects the work, before closing the catalog it borrowed.
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() async {
      await IptvCatalogRefreshService.instance.debugSettle();
      MainPageBridge.cancelIptvStartupChannel();
      MainPageBridge.cancelIptvStartup = null;
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      await DebrifyTvDatabase.debugDatabaseOverride?.close();
      DebrifyTvDatabase.debugDatabaseOverride = null;
      IptvMediaStore.debugResetMigration();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      await directory.delete(recursive: true);
    });
  }
}

/// Cleanup happens inside the test body, before Flutter checks pending timers.
Future<void> iptvResultsCase(
  WidgetTester tester,
  Future<void> Function(IptvResultsFixture) body, {
  bool numbered = true,
  String style = 'command',
}) async {
  final fixture = (await tester.runAsync(
    () => IptvResultsFixture.create(numbered: numbered, style: style),
  ))!;
  try {
    await body(fixture);
  } finally {
    await fixture.close(tester);
  }
}
