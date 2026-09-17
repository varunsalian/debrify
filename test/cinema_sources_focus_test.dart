import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'dart:io';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/cinema_sources_layout.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/torrent_filters_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final returned in [false, true, null]) {
    testWidgets('cached current episode card: returned=$returned', (
      tester,
    ) async {
      final addon = StremioAddon(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://addon.test/manifest.json',
        baseUrl: 'https://addon.test',
        types: const ['series'],
        resources: const ['stream'],
      );
      final pin = SeriesSource(
        torrentHash: '',
        torrentName: 'Cached episode',
        debridService: SeriesSource.addonDirectService,
        debridTorrentId: '',
        boundAt: 1,
        addonId: 'test',
        addonKey: addon.sourceBindingKey,
        streamKey: 'profile',
        streamIndex: 0,
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
        'series_source_tt123': jsonEncode([pin.toJson()]),
      });
      SecretVault.debugReset(deviceIdOverride: 'picker-cache-test');
      StremioService.instance.invalidateCache();
      addTearDown(StremioService.instance.invalidateCache);
      final cached = Torrent.fromJson({
        ..._torrent('Cached episode', 'stremio:Test').toJson(),
        'stream_type': 'directUrl',
        'direct_url': 'https://cdn.test/episode3',
        'stremio_addon_id': 'test',
        'stremio_addon_key': addon.sourceBindingKey,
        'stremio_stream_key': 'profile',
        'stremio_stream_index': 0,
        'stremio_video_id': 'tt123:1:3',
      });
      final finished = Completer<Map<String, dynamic>>();
      final early = _torrent('Early source', 'torrentio');
      await tester.runAsync(() async {
        await TorrentService.ensureInitialized();
        await ResolvedPlaybackLinkCache.save(
          id: 'tt123',
          type: 'series',
          season: 1,
          episode: 3,
          source: cached,
        );
      });
      await tester.runAsync(() async {
        final searched = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt123',
                  isSeries: true,
                  title: 'Show',
                  season: 1,
                  episode: 3,
                ),
                meta: const PlaybackMeta(contentType: 'series'),
                search: (onBatch) async {
                  searched.complete();
                  if (returned == null) {
                    onBatch('torrentio', [early]);
                    return finished.future;
                  }
                  return {
                    'torrents': [if (returned == true) cached],
                  };
                },
              ),
            ),
          ),
        );
        await searched.future.timeout(const Duration(seconds: 5));
      });
      if (returned == null) {
        await tester.pump();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        // No new network rows: the cached fallback must alone expose the pill.
        finished.complete({
          'torrents': [early],
        });
        await tester.pumpAndSettle();
        expect(find.text('Cached episode'), findsNothing);
        expect(find.text('1 new source'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, same(focused));
        await tester.tap(find.text('1 new source'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Cached episode'), findsOneWidget);
      expect(
        find.textContaining('Not returned by the latest search'),
        returned == true ? findsNothing : findsOneWidget,
      );
      expect(
        tester
            .widget<SourceRow>(
              find.byWidgetPredicate(
                (w) => w is SourceRow && w.title == 'Cached episode',
              ),
            )
            .isCurrentSource,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  late Directory storage;
  setUpAll(() {
    storage = Directory.systemTemp.createTempSync('cinema-sources-focus-');
    AppStorage.debugOverride(
      documents: storage,
      support: storage,
      cache: storage,
    );
  });
  tearDownAll(() {
    AppStorage.debugReset();
    storage.deleteSync(recursive: true);
  });

  testWidgets(
    'selected direct source is revealed and stays marked after navigation',
    (tester) async {
      const pin = SeriesSource(
        torrentHash: '',
        torrentName: 'Previous episode',
        debridService: SeriesSource.addonDirectService,
        debridTorrentId: '',
        boundAt: 1,
        addonId: 'addon',
        addonKey: 'configuration',
        streamKey: 'preferred',
        bingeGroup: 'group',
        streamIndex: 30,
      );
      SharedPreferences.setMockInitialValues({
        'series_source_tt123': jsonEncode([pin.toJson()]),
      });
      await tester.runAsync(TorrentService.ensureInitialized);
      expect((await SeriesSourceService.getSources('tt123')).length, 1);
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final results = List.generate(
        40,
        (i) => Torrent(
          rowid: i,
          infohash: 'direct_$i',
          hasRealInfoHash: false,
          name: 'Episode source $i',
          sizeBytes: 1000000,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'stremio:Test',
          streamType: StreamType.directUrl,
          directUrl: 'https://example.com/episode/$i',
          stremioAddonId: 'addon',
          stremioAddonKey: 'configuration',
          stremioStreamKey: i == 30 ? 'preferred' : 'profile$i',
          stremioBingeGroup: i >= 29 && i <= 31 ? 'group' : 'group$i',
          stremioStreamIndex: i,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: sourcesScreenForTesting(
              selection: const AdvancedSearchSelection(
                imdbId: 'tt123',
                isSeries: true,
                title: 'Show',
                season: 1,
                episode: 2,
              ),
              meta: const PlaybackMeta(),
              search: (_) async => {'torrents': results},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_30');
      final selected = find.byWidgetPredicate(
        (w) => w is SourceRow && w.isCurrentSource,
      );
      expect(selected, findsOneWidget);
      expect(tester.widget<SourceRow>(selected).title, 'Episode source 30');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              w.icon == Icons.check_circle_rounded &&
              w.semanticLabel == 'Selected source',
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(selected).overlaps(const Rect.fromLTWH(0, 0, 960, 540)),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_31');
      expect(selected, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final railFocus = FocusManager.instance.primaryFocus;
      expect(railFocus?.debugLabel, 'cinema-provider-all');
      await tester.tap(find.text('Test').first);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(railFocus));
      expect(selected, findsOneWidget);
      expect(
        tester.getRect(selected).overlaps(const Rect.fromLTWH(0, 0, 960, 540)),
        isTrue,
      );
      await tester.tap(find.text('All sources'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(railFocus));
      expect(
        tester.getRect(selected).overlaps(const Rect.fromLTWH(0, 0, 960, 540)),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_30');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('D-pad reaches and opens Filter and Sort from the first source', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(TorrentService.ensureInitialized);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: sourcesScreenForTesting(
            selection: const AdvancedSearchSelection(
              imdbId: '',
              isSeries: false,
              title: 'Movie',
            ),
            meta: const PlaybackMeta(),
            search: (_) async => {
              'torrents': [_torrent('Movie', 'torrentio')],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_0');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_filter');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(TorrentFiltersSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TorrentFiltersSheet), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_filter');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(PopupMenuItem<String>, 'Addon order'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(PopupMenuItem<String>, 'Seeders'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_filter');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching providers after scrolling can return to results', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(TorrentService.ensureInitialized);
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: sourcesScreenForTesting(
            selection: const AdvancedSearchSelection(
              imdbId: '',
              isSeries: false,
              title: 'Movie',
            ),
            meta: const PlaybackMeta(),
            search: (_) async => {
              'torrents': [
                for (var i = 0; i < 100; i++)
                  _torrent('Movie A $i', 'torrentio'),
                for (var i = 0; i < 100; i++) _torrent('Movie B $i', 'jackett'),
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byKey(const ValueKey('cinema-sources-results')),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -4000));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<SourceRow>(find.byType(SourceRow)).toList();
    final row = rows.firstWhere((row) => row.focusNode.debugLabel != 'src_0');
    row.focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'cinema-provider-all',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('cinema-provider-'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (back, earlyBatch) in [
    (false, true),
    (true, true),
    (true, false),
  ]) {
    testWidgets(
      'search completion preserves ${back ? 'back' : 'provider'} focus '
      '(early batch: $earlyBatch)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.runAsync(TorrentService.ensureInitialized);
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final finished = Completer<Map<String, dynamic>>();
        SearchBatchCallback? onBatch;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: '',
                  isSeries: false,
                  title: 'Movie',
                ),
                meta: const PlaybackMeta(),
                search: (callback) {
                  onBatch = callback;
                  return finished.future;
                },
              ),
            ),
          ),
        );
        await tester.pump();
        expect(onBatch, isNotNull);
        final early = _torrent('Early source', 'torrentio');
        final late = _torrent('Late source', 'jackett');
        if (earlyBatch) {
          onBatch!('torrentio', [early]);
          await tester.pump();
          await tester.pump();
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'src_0');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        } else {
          tester
              .state<CinemaSourcesLayoutState>(find.byType(CinemaSourcesLayout))
              .focusSelectedProvider();
        }
        await tester.pump();
        await tester.sendKeyEvent(
          back ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
        );
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        expect(
          focused?.debugLabel,
          back ? 'cinema-sources-back' : 'cinema-provider-engine:torrentio',
        );

        onBatch!('jackett', [late]);
        finished.complete({
          'torrents': [early, late],
        });
        await tester.pumpAndSettle();
        expect(find.text('Search complete'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, same(focused));
        expect(
          find.byType(SourceRow),
          findsNWidgets(earlyBatch ? 1 : 2),
          reason: 'leaving an early row freezes later sources behind the pill',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Torrent _torrent(String name, String source) => Torrent(
  rowid: 0,
  infohash: name.hashCode.toRadixString(16).padLeft(40, '0'),
  name: name,
  sizeBytes: 1000000,
  createdUnix: 0,
  seeders: 10,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
);
