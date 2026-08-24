import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSeriesDetail(
    WidgetTester tester, {
    required Map<String, double> progress,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'brand-new-series',
            type: 'series',
            name: 'Brand New Series',
          ),
          addon: StremioAddon(
            id: 'direct-test',
            name: 'Direct Test',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: () async {},
          resumeInfoLoader: () async =>
              (started: false, season: null, episode: null),
          seasonsLoader: () async => [
            TraktSeason(
              number: 1,
              episodeCount: 1,
              episodes: [TraktEpisode(season: 1, number: 1, title: 'Pilot')],
            ),
          ],
          watchProgressLoader: () async => progress,
          onPlayEpisode: (_) async {},
        ),
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('brand-new S1E1 remains Start Watching', (tester) async {
    await pumpSeriesDetail(tester, progress: const {});

    expect(find.text('Start Watching'), findsOneWidget);
    expect(find.text('Resume · S1E1'), findsNothing);
  });

  testWidgets('real S1E1 progress renders Resume', (tester) async {
    await pumpSeriesDetail(tester, progress: const {'1-1': 25});

    expect(find.text('Resume · S1E1'), findsOneWidget);
  });

  testWidgets('merged detail admits only one playback launch at a time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousStyle = StorageService.detailPageStyleCached;
    StorageService.detailPageStyleCached = 'showcase';
    addTearDown(() => StorageService.detailPageStyleCached = previousStyle);
    final firstLaunch = Completer<void>();
    var launches = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppThemeScope(
          theme: AppThemes.legacy,
          // Keep the test off the network: autoplay still becomes enabled,
          // but reduced motion prevents resolving the synthetic trailer ID.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'movie-without-external-lookups',
            type: 'movie',
            name: 'Guarded Movie',
            trailerYtId: 'synthetic-trailer',
          ),
          addon: StremioAddon(
            id: 'test-addon',
            name: 'Test Addon',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: () {
            launches++;
            return launches == 1 ? firstLaunch.future : Future<void>.value();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    HeroTrailerBackdrop trailer() =>
        tester.widget<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop));
    expect(trailer().enabled, isTrue);
    expect(trailer().startDelay, Duration.zero);

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(trailer().enabled, isFalse);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(launches, 1);

    firstLaunch.complete();
    await tester.pump();
    expect(trailer().enabled, isTrue);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(launches, 2);
  });
}
