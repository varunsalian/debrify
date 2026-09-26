import 'dart:async';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/features/sources/application/source_cache_dependencies.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'fixtures/sources_screen_factory.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes/fake_source_cache_repository.dart';

Torrent row(String hash) => Torrent(
  rowid: 0,
  infohash: hash,
  name: 'Fixture $hash',
  sizeBytes: 100,
  createdUnix: 0,
  seeders: 1,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

class ReadySettings implements SourceSettingsRepository {
  @override
  bool get isCurrent => true;
  @override
  Future<SourcePrioritySettings> loadPriority() async =>
      SourcePrioritySettings();
  @override
  Future<({bool text, bool logos})> loadAppearance() async =>
      (text: false, logos: false);
}

void main() {
  testWidgets(
    'late cache configuration sweeps visible rows and badges preserve focus/order',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = FakeSourceCacheRepository();
      final cache = FakeSourceCacheSession();
      final searched = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => ReadySettings(),
            ),
            sourceCacheRepositoryProvider.overrideWith(
              (ref, key) => repository,
            ),
          ],
          child: MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: '',
                  title: 'Fixture',
                  isSeries: false,
                ),
                meta: const PlaybackMeta(),
                search: (onBatch) async {
                  searched.complete();
                  return {
                    'torrents': [row('a'), row('b')],
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(searched.isCompleted, isTrue);
      expect(find.byType(SourceRow), findsNWidgets(2));
      final focus = FocusManager.instance.primaryFocus;
      expect(focus?.debugLabel, 'src_0');
      final names = tester
          .widgetList<SourceRow>(find.byType(SourceRow))
          .map((widget) => widget.title)
          .toList();
      repository.opens.single.complete(cache);
      await tester.pump();
      expect(cache.tb.single.$1, ['a', 'b']);
      cache.tb.single.$2.complete({'a'});
      await tester.pump();
      expect(cache.pm.single.$1, ['a', 'b']);
      cache.pm.single.$2.complete([true, false]);
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<SourceRow>(find.byType(SourceRow))
          .toList();
      expect(rows.map((widget) => widget.cacheLabel), ['TB | PM', null]);
      expect(rows.map((widget) => widget.title), names);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
