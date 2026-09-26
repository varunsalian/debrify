import 'dart:async';
import 'package:debrify/features/sources/application/source_settings_dependencies.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/cinema_sources_layout.dart';
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

Torrent row(String name, String source) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  source: source,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

void main() {
  testWidgets(
    'addon retry updates status and buffers rows without stealing rail focus',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final result = Completer<List<Torrent>>();
      var retries = 0;
      var searches = 0;
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
                  imdbId: '',
                  title: 'Fixture',
                  isSeries: false,
                ),
                meta: const PlaybackMeta(),
                search: (onBatch) async {
                  searches++;
                  final rows = [row('Original', 'engine:base')];
                  onBatch('base', rows);
                  return {
                    'torrents': rows,
                    'addonStatuses': [
                      const AddonSearchStatus(
                        addonId: 'broken',
                        addonKey: 'exact-config',
                        name: 'Broken',
                        sourceKey: 'stremio:broken',
                        count: 0,
                        error: 'timeout',
                      ),
                    ],
                  };
                },
                retry:
                    ({
                      required addonId,
                      required type,
                      required imdbId,
                      season,
                      episode,
                      required timeout,
                      required preserveOrder,
                      originVideoId,
                    }) {
                      expect(addonId, 'exact-config');
                      retries++;
                      return result.future;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<Focus>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Focus &&
                  widget.focusNode?.debugLabel ==
                      'cinema-provider-stremio:broken',
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(retries, 1);
      final focus = FocusManager.instance.primaryFocus;
      expect(focus?.debugLabel, 'cinema-provider-stremio:broken');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(retries, 1);
      expect(
        tester
            .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
            .providers
            .singleWhere((provider) => provider.id == 'stremio:broken')
            .loading,
        isTrue,
      );
      result.complete([row('Recovered', 'stremio:broken')]);
      await tester.pumpAndSettle();
      expect(searches, 1);
      expect(retries, 1);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(find.text('1 new source'), findsOneWidget);
      expect(find.text('Recovered'), findsNothing);
      final provider = tester
          .widget<CinemaSourcesLayout>(find.byType(CinemaSourcesLayout))
          .providers
          .singleWhere((provider) => provider.id == 'stremio:broken');
      expect(provider.failed, isFalse);
      expect(provider.loading, isFalse);
      await tester.tap(find.text('1 new source'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SourceRow>(find.byType(SourceRow))
            .map((row) => row.title),
        ['Recovered'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
