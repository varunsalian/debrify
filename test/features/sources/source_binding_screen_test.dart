import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/data/stored_saved_sources_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
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

class SavingRepository implements SavedSourcesRepository {
  SavingRepository(this.delegate, this.onSave);
  final StoredSavedSourcesRepository delegate;
  final void Function() onSave;
  @override
  bool get isCurrent => delegate.isCurrent;
  @override
  Future<SavedSourcesState> load() => delegate.load();
  @override
  Future<bool> remove(SeriesSource source) => delegate.remove(source);
  @override
  Future<bool> save(SeriesSource source) {
    onSave();
    return delegate.save(source);
  }
}

void main() {
  testWidgets(
    'Sources direct pin reloads the row binding and unpin removes it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var repositorySaves = 0;
      final torrent = Torrent(
        rowid: 0,
        infohash: 'url:1',
        name: 'Direct fixture',
        source: 'stremio:test',
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        streamType: StreamType.directUrl,
        hasRealInfoHash: false,
        directUrl: 'https://example.com/temporary-signed-url',
        stremioAddonId: 'test.addon',
        stremioAddonKey: 'configuration',
        stremioStreamKey: 'profile',
        stremioStreamIndex: 3,
      );
      await SeriesSourceService.setSources('tt-fixture', []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedSourcesRepositoryProvider.overrideWith(
              (ref, session) => SavingRepository(
                StoredSavedSourcesRepository(session),
                () => repositorySaves++,
              ),
            ),
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => Settings(),
            ),
          ],
          child: MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt-fixture',
                  title: 'Fixture',
                  isSeries: false,
                ),
                meta: const PlaybackMeta(),
                search: (onBatch) async {
                  return {
                    'torrents': [torrent],
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<SourceRow>(find.byType(SourceRow).first).onLongPress!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin as source'));
      await tester.pumpAndSettle();
      final sources = await SeriesSourceService.getSources('tt-fixture');
      expect(sources, hasLength(1));
      expect(repositorySaves, 1);
      expect(sources.single.isAddonDirect, isTrue);
      expect(sources.single.addonKey, 'configuration');
      expect(sources.single.streamIndex, 3);
      expect(
        sources.single.toJson().toString(),
        isNot(contains(torrent.directUrl!)),
      );
      tester.widget<SourceRow>(find.byType(SourceRow).first).onLongPress!();
      await tester.pumpAndSettle();
      expect(find.text('Unpin source'), findsOneWidget);
      await tester.tap(find.text('Unpin source'));
      await tester.pumpAndSettle();
      expect(await SeriesSourceService.getSources('tt-fixture'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
