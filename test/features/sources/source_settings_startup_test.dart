import 'dart:async';

import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/source_settings_repository.dart';
import 'package:debrify/features/sources/models/source_presentation_settings.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'fixtures/sources_screen_factory.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupSettings implements SourceSettingsRepository {
  final priority = Completer<SourcePrioritySettings>();
  final appearance = Completer<({bool text, bool logos})>();
  @override
  bool isCurrent = true;
  @override
  Future<SourcePrioritySettings> loadPriority() => priority.future;
  @override
  Future<({bool text, bool logos})> loadAppearance() => appearance.future;
}

void main() {
  for (final retire in [false, true]) {
    testWidgets('Sources waits for settings before search; retired: $retire', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = StartupSettings();
      var searches = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, session) => settings,
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
                  return {'torrents': []};
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      settings.appearance.complete((text: true, logos: true));
      await tester.pump();
      expect(searches, 0);
      if (retire) {
        settings.isCurrent = false;
        ProfileSessionMemory.clearAll();
      }
      settings.priority.complete(SourcePrioritySettings());
      // A retired route remains loading until the profile handoff removes it.
      // Flush completion without waiting for its repeating spinner to stop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(searches, retire ? 0 : 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
