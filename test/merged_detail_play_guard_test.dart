import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSeriesDetail(
    WidgetTester tester, {
    required Map<String, double> progress,
    void Function(({bool started, int season, int episode})? promised)?
    onPromise,
    Future<void> Function(({bool started, int season, int episode})? promised)?
    onBrowsePrimaryEpisodeSources,
    void Function(TraktItemMenuAction action)? onTraktAction,
    bool preferSeriesPacks = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!preferSeriesPacks) {
      await StorageService.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(
          isMovie: false,
        ).copyWith(preferSeriesPacks: false),
        isMovie: false,
      );
    }
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
          onResume: (promised) async => onPromise?.call(promised),
          onBrowsePrimaryEpisodeSources: onBrowsePrimaryEpisodeSources,
          resumeInfoLoader: () async =>
              (started: false, season: null, episode: null),
          traktMenuOptions: onTraktAction == null
              ? const []
              : const [
                  TraktMenuOption(
                    action: TraktItemMenuAction.searchPacks,
                    icon: Icons.inventory_2_rounded,
                    color: Colors.amber,
                    label: 'Search Season Packs',
                    caption: 'Packs',
                  ),
                ],
          onTraktAction: onTraktAction == null
              ? null
              : (action) async => onTraktAction(action),
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

  // The bug this pins: the label is resolved by this screen's episode engine
  // (which advances off watched state) while the host re-derived the episode
  // from resume positions alone, so Play launched S01E01 under a "Resume · S1E2"
  // button. The promise is what keeps the two in lock-step — assert it against
  // the rendered label so they cannot drift apart again.
  testWidgets('the promised target is the episode the label shows', (
    tester,
  ) async {
    ({bool started, int season, int episode})? captured;
    var pressed = false;
    await pumpSeriesDetail(
      tester,
      progress: const {'1-1': 25},
      onPromise: (p) {
        captured = p;
        pressed = true;
      },
    );

    // Engine-derived: the loader stub reports started:false, so a label reading
    // "Resume" can only have come from the watch-progress engine — exactly the
    // source the host cannot see.
    expect(find.text('Resume · S1E1'), findsOneWidget);

    await tester.tap(find.text('Resume · S1E1'));
    await tester.pump();

    expect(pressed, isTrue);
    expect(captured, isNotNull);
    expect(captured!.season, 1);
    expect(captured!.episode, 1);
    expect(captured!.started, isTrue);
  });

  testWidgets('an untouched show promises nothing', (tester) async {
    ({bool started, int season, int episode})? captured;
    var pressed = false;
    await pumpSeriesDetail(
      tester,
      progress: const {},
      onPromise: (p) {
        captured = p;
        pressed = true;
      },
    );

    // S01E01 with no evidence behind it: forwarding that would override the
    // host's own (possibly better-informed) answer with a bare coordinate.
    expect(find.text('Start Watching'), findsOneWidget);

    await tester.tap(find.text('Start Watching'));
    await tester.pump();

    expect(pressed, isTrue);
    expect(captured, isNull);
  });

  testWidgets('series Play hold offers packs and the promised episode', (
    tester,
  ) async {
    ({bool started, int season, int episode})? captured;
    var plays = 0;
    await pumpSeriesDetail(
      tester,
      progress: const {'1-1': 25},
      onPromise: (_) => plays++,
      onBrowsePrimaryEpisodeSources: (promised) async {
        captured = promised;
      },
      onTraktAction: (_) {},
    );

    await tester.longPress(find.text('Resume · S1E1'));
    await tester.pumpAndSettle();

    expect(find.text('Season pack sources'), findsOneWidget);
    expect(find.text('Episode sources'), findsOneWidget);
    expect(plays, 0, reason: 'a hold must never also activate Play');

    await tester.tap(find.text('Episode sources'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.season, 1);
    expect(captured!.episode, 1);
    expect(captured!.started, isTrue);
    expect(plays, 0);
  });

  testWidgets('series Play hold reuses the More-menu season-pack action', (
    tester,
  ) async {
    TraktItemMenuAction? captured;
    var episodeSourceOpens = 0;
    await pumpSeriesDetail(
      tester,
      progress: const {},
      onBrowsePrimaryEpisodeSources: (_) async => episodeSourceOpens++,
      onTraktAction: (action) => captured = action,
    );

    await tester.longPress(find.text('Start Watching'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season pack sources'));
    await tester.pumpAndSettle();

    expect(captured, TraktItemMenuAction.searchPacks);
    expect(episodeSourceOpens, 0);
  });

  testWidgets(
    'packs off sends a series Play hold straight to episode sources',
    (tester) async {
      var sourceOpens = 0;
      var plays = 0;
      await pumpSeriesDetail(
        tester,
        progress: const {},
        preferSeriesPacks: false,
        onPromise: (_) => plays++,
        onBrowsePrimaryEpisodeSources: (_) async => sourceOpens++,
        onTraktAction: (_) {},
      );

      await tester.longPress(find.text('Start Watching'));
      await tester.pumpAndSettle();

      expect(find.text('Choose sources'), findsNothing);
      expect(sourceOpens, 1);
      expect(plays, 0);
    },
  );

  testWidgets('movie Play hold opens the existing movie Sources action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var sourceOpens = 0;
    var plays = 0;
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'movie-hold',
            type: 'movie',
            name: 'Movie Hold',
          ),
          addon: StremioAddon(
            id: 'test-addon',
            name: 'Test Addon',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: (_) async => plays++,
          onBrowse: () => sourceOpens++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Play'));
    await tester.pump();

    expect(sourceOpens, 1);
    expect(plays, 0);
    expect(haptics, 1, reason: 'InkWell owns the long-press feedback');
  });

  testWidgets('held TV OK opens Sources without firing Play on release', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var sourceOpens = 0;
    var plays = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'movie-tv-hold',
            type: 'movie',
            name: 'Movie TV Hold',
          ),
          addon: StremioAddon(
            id: 'test-addon',
            name: 'Test Addon',
            manifestUrl: '',
            baseUrl: '',
          ),
          isTelevision: true,
          onResume: (_) async => plays++,
          onBrowse: () => sourceOpens++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 650));
    expect(sourceOpens, 1);
    expect(plays, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sourceOpens, 1);
    expect(plays, 0);
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
          onResume: (_) {
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
