import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/screens/settings/quick_play_settings_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const QuickPlaySettingsPage(),
        ),
      ),
    );
    // _load awaits several independent preference/service reads. Pump their
    // microtask turns even when no frame has been scheduled yet.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows tabs, the torrent switch, and the priority section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Prefer torrents'), findsOneWidget);
    expect(find.text('Addon priority'), findsOneWidget);
    // Movies tab never shows the packs switch.
    expect(find.text('Prefer season packs'), findsNothing);
    // The old preset cards are gone.
    expect(find.text('Debrify default'), findsNothing);
    expect(find.text('Follow addon order'), findsNothing);
  });

  testWidgets('series tab adds the season packs switch, default on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Prefer season packs'), findsOneWidget);

    final rules = await StorageService.getQuickPlayRules(isMovie: false);
    expect(rules.preferSeriesPacks, isTrue);
  });

  testWidgets('prefer torrents off persists the addon-first source mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();

    final movie = await StorageService.getQuickPlayRules(isMovie: true);
    expect(movie.sourceMode, QuickPlaySourceMode.addonsThenTorrents);
    // Series tab untouched.
    final show = await StorageService.getQuickPlayRules(isMovie: false);
    expect(show.sourceMode, QuickPlaySourceMode.torrentsThenAddons);

    // Toggling back restores the exact shipped default (not a custom copy).
    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();
    final restored = await StorageService.getQuickPlayRules(isMovie: true);
    expect(restored.matchesDebrifyDefault(isMovie: true), isTrue);
  });

  testWidgets('series pack switch off persists and clears exact-only trap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A legacy profile stuck on exactEpisodeOnly must not defeat the switch.
    await StorageService.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
        preset: QuickPlayPreset.custom,
        preferSeriesPacks: false,
        packPreference: QuickPlayPackPreference.exactEpisodeOnly,
      ),
      isMovie: false,
    );
    await pumpPage(tester);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer season packs'));
    await tester.pumpAndSettle();

    final rules = await StorageService.getQuickPlayRules(isMovie: false);
    expect(rules.preferSeriesPacks, isTrue);
    expect(rules.packPreference, isNot(QuickPlayPackPreference.exactEpisodeOnly));
  });

  testWidgets('legacy advanced knobs are gone from the UI but still load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        maxAttempts: 2,
        ranking: QuickPlayRanking.smallest,
      ),
      isMovie: true,
    );
    await pumpPage(tester);

    // No advanced section, no ranking/attempt controls anywhere.
    expect(find.text('Advanced control'), findsNothing);
    expect(find.textContaining('Try up to'), findsNothing);

    // The stored customization survives an unrelated edit untouched.
    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();
    final rules = await StorageService.getQuickPlayRules(isMovie: true);
    expect(rules.maxAttempts, 2);
    expect(rules.ranking, QuickPlayRanking.smallest);
    expect(rules.sourceMode, QuickPlaySourceMode.addonsThenTorrents);
  });

  testWidgets('restore defaults resets both tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        sourceMode: QuickPlaySourceMode.addonsThenTorrents,
        sourcePriority: const ['engine:a', 'stremio:b'],
      ),
      isMovie: true,
    );
    await pumpPage(tester);

    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();

    final movie = await StorageService.getQuickPlayRules(isMovie: true);
    expect(movie.matchesDebrifyDefault(isMovie: true), isTrue);
    expect(movie.sourcePriority, isEmpty);
  });
}
