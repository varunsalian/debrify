import 'dart:async';
import 'dart:io';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/torrent_service.dart';
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
