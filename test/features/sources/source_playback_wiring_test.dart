import 'dart:async';

import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/presentation/source_playback_bridge.dart';
import 'package:debrify/features/sources/presentation/source_provider_strip.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/dialog_tap_guard.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings implements SourceSettingsRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SourcePrioritySettings> loadPriority() async =>
      SourcePrioritySettings();
  @override
  Future<({bool text, bool logos})> loadAppearance() async =>
      (text: false, logos: false);
}

class Saved implements SavedSourcesRepository {
  var loads = 0;
  @override
  bool get isCurrent => true;
  @override
  Future<SavedSourcesState> load() async {
    loads++;
    return SavedSourcesState();
  }

  @override
  Future<bool> save(SeriesSource source) async => true;
  @override
  Future<bool> remove(SeriesSource source) async => true;
}

class Playback extends SourcePlaybackBridge {
  final completion = Completer<void>();
  final requests =
      <
        ({
          Torrent torrent,
          bool force,
          PlaybackMeta meta,
          List<Torrent> sources,
          int index,
          String keyword,
        })
      >[];
  final downloads = <Torrent>[];
  bool downloadable = true;

  @override
  Future<void> play(
    BuildContext context,
    Torrent torrent, {
    required bool forcePlay,
    required PlaybackMeta meta,
    required List<Torrent> sources,
    required int sourceIndex,
    required String searchKeyword,
  }) {
    expect(context.mounted, isTrue);
    requests.add((
      torrent: torrent,
      force: forcePlay,
      meta: meta,
      sources: sources,
      index: sourceIndex,
      keyword: searchKeyword,
    ));
    return completion.future;
  }

  @override
  bool supportsDownload(Torrent torrent) => downloadable;
  @override
  Future<void> download(BuildContext context, Torrent torrent) async {
    expect(context.mounted, isTrue);
    downloads.add(torrent);
  }
}

Torrent source(String provider, int id) => Torrent(
  rowid: id,
  infohash: 'url:$id',
  name: 'Source $id',
  source: provider,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  hasRealInfoHash: false,
  streamType: StreamType.directUrl,
  directUrl: 'https://example.com/$id',
);

void main() {
  for (final scenario in [
    'row',
    'force',
    'menu',
    'filtered',
    'disposed',
    'download',
    'unsupported_download',
  ]) {
    testWidgets('Sources preserves playback dispatch: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      // The existing guard uses wall-clock time, independent of widget pumps.
      if (DialogTapGuard.shouldIgnoreTap()) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 310)),
        );
      }
      await tester.binding.setSurfaceSize(
        Size(scenario == 'filtered' ? 390 : 640, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final playback = Playback()
        ..downloadable = scenario != 'unsupported_download';
      final saved = Saved();
      final first = source('alpha', 1);
      final second = source('beta', 2);
      const meta = PlaybackMeta(
        imdbId: 'tt-playback',
        title: 'Metadata fixture',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourcePlaybackBridgeProvider.overrideWithValue(playback),
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => Settings(),
            ),
            savedSourcesRepositoryProvider.overrideWith((ref, key) => saved),
          ],
          child: MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                forcePlayOnTap: scenario == 'force',
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt-playback',
                  title: 'Search fixture',
                  isSeries: false,
                ),
                meta: meta,
                search: (_) async => {
                  'torrents': [first, second],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scenario == 'filtered') {
        tester
            .widget<SourceProviderStrip>(find.byType(SourceProviderStrip))
            .onSelect('engine:beta');
        await tester.pumpAndSettle();
      }
      final rows = tester
          .widgetList<SourceRow>(find.byType(SourceRow))
          .toList();
      expect(rows.length, scenario == 'filtered' ? 1 : 2);
      final selectedRow = rows.last;
      final initialLoads = saved.loads;
      if (scenario == 'download' || scenario == 'unsupported_download') {
        selectedRow.onLongPress!();
        await tester.pumpAndSettle();
        if (scenario == 'download') {
          await tester.tap(find.text('Download to device'));
          await tester.pumpAndSettle();
          expect(playback.downloads, [same(second)]);
        } else {
          expect(find.text('Download to device'), findsNothing);
          expect(playback.downloads, isEmpty);
        }
        expect(playback.requests, isEmpty);
        expect(saved.loads, initialLoads);
      } else {
        if (scenario == 'menu') {
          selectedRow.onLongPress!();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Play now'));
          await tester.pumpAndSettle();
        } else {
          selectedRow.onTap();
          await tester.pump();
        }
        expect(playback.requests, hasLength(1));
        final request = playback.requests.single;
        expect(request.torrent, same(second));
        expect(request.force, scenario == 'force');
        expect(request.meta, same(meta));
        expect(request.keyword, 'Search fixture');
        expect(
          request.sources,
          scenario == 'filtered' ? [second] : [first, second],
        );
        expect(request.index, scenario == 'filtered' ? 0 : 1);
        expect(saved.loads, initialLoads);
        // A duplicate SELECT emitted by a closing dialog remains suppressed.
        DialogTapGuard.markKeyAction();
        selectedRow.onTap();
        expect(playback.requests, hasLength(1));
        if (scenario == 'disposed') {
          await tester.pumpWidget(const SizedBox());
        }
        playback.completion.complete();
        await tester.pumpAndSettle();
        expect(saved.loads, initialLoads + (scenario == 'disposed' ? 0 : 1));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
