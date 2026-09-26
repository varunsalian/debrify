import 'dart:async';

import 'package:debrify/features/sources/application/source_link_dependencies.dart';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/source_link_copier.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
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

Torrent episode({String? url}) => Torrent(
  rowid: 1,
  infohash: 'iptv:fixture',
  name: 'Fixture S01E02',
  source: 'iptv:fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  hasRealInfoHash: false,
  streamType: StreamType.directUrl,
  directUrl: url,
  iptvCatalogType: 'series',
  iptvEntryKey: 'series:12',
  seasonNumber: 1,
  episodeIdentifier: 'S01E02',
);

void main() {
  for (final scenario in [
    'active',
    'profile_retired',
    'disposed',
    'missing',
    'unavailable',
  ]) {
    testWidgets('Sources owns deferred copy completion: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ProfileSessionMemory.debugReset);
      final pending = Completer<IptvEpisodeResolution>();
      final copied = <String>[];
      var resolutions = 0;
      final copier = SourceLinkCopier(
        isDeferredEpisode: IptvSourceSearch.isDeferredXtreamSeries,
        resolveEpisode: (_) {
          resolutions++;
          return pending.future;
        },
        writeText: (text) async => copied.add(text),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceLinkCopierProvider.overrideWithValue(copier),
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => Settings(),
            ),
          ],
          child: MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt-copy-episode',
                  title: 'Fixture',
                  isSeries: true,
                  season: 1,
                  episode: 2,
                ),
                meta: const PlaybackMeta(),
                search: (_) async => {
                  'torrents': [episode()],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = tester.widget<SourceRow>(find.byType(SourceRow).first);
      expect(row.onCopy, isNotNull);
      row.onCopy!();
      await tester.pump();
      expect(resolutions, 1);
      expect(copied, isEmpty);
      expect(find.text('Finding this IPTV episode…'), findsOneWidget);
      if (scenario == 'profile_retired') ProfileSessionMemory.clearAll();
      if (scenario == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      }
      pending.complete(
        scenario == 'missing'
            ? const IptvEpisodeResolution(IptvEpisodeResolutionStatus.missing)
            : scenario == 'unavailable'
            ? const IptvEpisodeResolution(
                IptvEpisodeResolutionStatus.unavailable,
              )
            : IptvEpisodeResolution(
                IptvEpisodeResolutionStatus.resolved,
                episode(url: 'https://example.com/episode'),
              ),
      );
      await tester.pumpAndSettle();
      // Let the initial progress snackbar retire and its queued outcome appear.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        copied,
        scenario == 'active' ? ['https://example.com/episode'] : [],
      );
      expect(
        find.text('Link copied to clipboard'),
        scenario == 'active' ? findsOneWidget : findsNothing,
      );
      if (scenario == 'missing') {
        expect(
          find.text('S01E02 is not available in this IPTV series.'),
          findsOneWidget,
        );
      } else if (scenario == 'unavailable') {
        expect(
          find.text('Could not check this IPTV series. Try again.'),
          findsOneWidget,
        );
      }
      expect(resolutions, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
