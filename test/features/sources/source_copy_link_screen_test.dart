import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

void main() {
  for (final kind in ['direct', 'magnet', 'unavailable', 'retired']) {
    testWidgets('Sources copies the rendered $kind link', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ProfileSessionMemory.debugReset);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final torrent = Torrent(
        rowid: 1,
        infohash: kind == 'magnet' ? 'abcdef' : 'url:fixture',
        name: 'Copy fixture',
        source: 'fixture',
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        hasRealInfoHash: kind == 'magnet',
        streamType: kind == 'magnet'
            ? StreamType.torrent
            : StreamType.directUrl,
        directUrl: kind == 'direct' || kind == 'retired'
            ? 'https://example.com/movie'
            : null,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => Settings(),
            ),
          ],
          child: MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: sourcesScreenForTesting(
                selection: const AdvancedSearchSelection(
                  imdbId: 'tt-copy-fixture',
                  title: 'Copy fixture',
                  isSeries: false,
                ),
                meta: const PlaybackMeta(),
                search: (_) async => {
                  'torrents': [torrent],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = tester.widget<SourceRow>(find.byType(SourceRow).first);
      if (kind == 'retired') {
        ProfileSessionMemory.clearAll();
        row.onCopy!();
        await tester.pumpAndSettle();
        expect(copied, isEmpty);
        expect(find.text('Link copied to clipboard'), findsNothing);
      } else if (kind == 'unavailable') {
        expect(row.onCopy, isNull);
        row.onLongPress!();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(copied, isEmpty);
        expect(find.text('No link available for this source.'), findsOneWidget);
      } else {
        expect(row.onCopy, isNotNull);
        row.onCopy!();
        await tester.pumpAndSettle();
        expect(copied, [torrent.copyLink]);
        expect(find.text('Link copied to clipboard'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
